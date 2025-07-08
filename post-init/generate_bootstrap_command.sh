#!/bin/bash
# generate_bootstrap_command.sh - Run on local PC to generate bootstrap command
set -u

# --- argument parsing ---
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <TARGET_HOSTNAME>"
    exit 1
fi

source .env

TARGET_HOSTNAME=$1

# --- Generate Tailscale Authkey (One-time with ACL tags) ---
# Call Tailscale API to issue a one-time authkey.
# "One-time" keys are automatically deleted when the device disconnects.
# "ACL Tags" can be pre-assigned to restrict initial access permissions.
# Example: tag:unprovisioned-server (no access anywhere)
#          tag:ssh-inbound-only (SSH access only from specific IPs/ports)
# Tailscale ACLs: https://tailscale.com/kb/1018/acls/
# API docs: https://api.tailscale.com/api/v2/tailnet/<tailnetID>/keys
echo "Generating Tailscale authkey for: $TARGET_HOSTNAME..."
API_RESPONSE=$(curl -s -X POST "https://api.tailscale.com/api/v2/tailnet/${TAILNET_ID}/keys" \
  -H "Authorization: Bearer ${TAILSCALE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-raw '{
    "capabilities": {
      "devices": {
        "create": {
          "reusable": false,
          "ephemeral": false,
          "preauthorized": true,
          "tags": ["tag:unprovisioned-server"]
        }
      }
    },
    "expirySeconds": 3600
  }')

TAILSCALE_AUTH_KEY=$(echo "${API_RESPONSE}" | jq -r '.key')

if [ -z "$TAILSCALE_AUTH_KEY" ] || [ "$TAILSCALE_AUTH_KEY" == "null" ]; then
    echo "Error: Failed to generate Tailscale authkey."
    echo "API Response: ${API_RESPONSE}"
    exit 1
fi
echo "Tailscale authkey generated successfully (Ephemeral): ${TAILSCALE_AUTH_KEY}"

# --- Generate final `curl | bash` command ---
POST_INIT_URL="${POST_INIT_SH_URL}" # Your post-init.sh URL

FINAL_COMMAND="curl -sSL ${POST_INIT_URL} | sudo bash -s -- "
FINAL_COMMAND+=" --sshkey \"${ANSIBLE_SSH_PUB_KEY}\" "
FINAL_COMMAND+=" --tailscale \"${TAILSCALE_AUTH_KEY}\" "
FINAL_COMMAND+=" --user \"${USERNAME}\" "
FINAL_COMMAND+=" --ts-hostname \"${TARGET_HOSTNAME}\""

echo -e "\n\n========================================================"
echo "      COPY AND PASTE THE FOLLOWING COMMAND ON YOUR NEW SERVER"
echo "========================================================"
echo "${FINAL_COMMAND}"
echo "========================================================"
echo -e "\nNOTE: This Tailscale authkey is one-time and/or single-use. "
echo "After authentication, you should see '${TARGET_HOSTNAME}' in your Tailscale admin console."
echo "Remember to update your Tailscale ACLs and Ansible inventory for this server."

# Copy command to clipboard if pbcopy is available
if command -v pbcopy &>/dev/null; then
    echo "${FINAL_COMMAND}" | pbcopy
    echo -e "\n✅ Command has been copied to clipboard!"
fi