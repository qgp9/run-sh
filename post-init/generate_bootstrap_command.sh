#!/usr/bin/env bash
# generate_bootstrap_command.sh - Run on local PC to generate bootstrap command
set -eu

# --- argument parsing ---
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <TARGET_HOSTNAME>"
    exit 1
fi

source .env

TARGET_HOSTNAME=$1

parse_bool() {
    local var_name="$1"
    local var_value="${2:-}"

    if [ "$var_value" != "true" ] && [ "$var_value" != "false" ]; then
        echo "Error: ${var_name} must be explicitly set to true or false."
        exit 1
    fi
}

parse_auth_mode() {
    local mode_value="${1:-}"
    if [ "$mode_value" != "arg" ] && [ "$mode_value" != "prompt" ]; then
        echo "Error: TAILSCALE_AUTH_INPUT_MODE must be set to arg or prompt."
        exit 1
    fi
}

parse_positive_int() {
    local var_name="$1"
    local var_value="${2:-}"

    if ! [[ "$var_value" =~ ^[0-9]+$ ]] || [ "$var_value" -le 0 ]; then
        echo "Error: ${var_name} must be a positive integer."
        exit 1
    fi
}

# --- Generate Tailscale Authkey (Ephemeral with ACL tags) ---
# Call Tailscale API to issue a one-time (or Ephemeral) authkey.
# "Ephemeral" keys are automatically deleted when the device disconnects.
# "ACL Tags" can be pre-assigned to restrict initial access permissions.
# Example: tag:unprovisioned-server (no access anywhere)
#          tag:ssh-inbound-only (SSH access only from specific IPs/ports)
# Tailscale ACLs: https://tailscale.com/kb/1018/acls/
# API docs: https://api.tailscale.com/api/v2/tailnet/<tailnetID>/keys
if [ -z "${TAILSCALE_KEY_EXPIRY_SECONDS:-}" ]; then
    echo "Error: TAILSCALE_KEY_EXPIRY_SECONDS must be set in .env."
    exit 1
fi
if [ -z "${TAILSCALE_KEY_REUSABLE:-}" ]; then
    echo "Error: TAILSCALE_KEY_REUSABLE must be set in .env."
    exit 1
fi
if [ -z "${TAILSCALE_KEY_PREAUTHORIZED:-}" ]; then
    echo "Error: TAILSCALE_KEY_PREAUTHORIZED must be set in .env."
    exit 1
fi
if [ -z "${TAILSCALE_KEY_TAGS:-}" ]; then
    echo "Error: TAILSCALE_KEY_TAGS must be set in .env."
    exit 1
fi

parse_positive_int "TAILSCALE_KEY_EXPIRY_SECONDS" "${TAILSCALE_KEY_EXPIRY_SECONDS}"
parse_bool "TAILSCALE_KEY_REUSABLE" "${TAILSCALE_KEY_REUSABLE}"
parse_bool "TAILSCALE_KEY_PREAUTHORIZED" "${TAILSCALE_KEY_PREAUTHORIZED}"

TAILSCALE_KEY_TAGS_JSON=$(printf '%s' "${TAILSCALE_KEY_TAGS}" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length > 0))')
if [ "$(echo "${TAILSCALE_KEY_TAGS_JSON}" | jq 'length')" -eq 0 ]; then
    echo "Error: TAILSCALE_KEY_TAGS must contain at least one non-empty tag."
    exit 1
fi

TAILSCALE_KEY_REQUEST_PAYLOAD=$(jq -n \
  --argjson reusable "${TAILSCALE_KEY_REUSABLE}" \
  --argjson preauthorized "${TAILSCALE_KEY_PREAUTHORIZED}" \
  --argjson tags "${TAILSCALE_KEY_TAGS_JSON}" \
  --argjson expiry_seconds "${TAILSCALE_KEY_EXPIRY_SECONDS}" \
  '{
    capabilities: {
      devices: {
        create: {
          reusable: $reusable,
          ephemeral: false,
          preauthorized: $preauthorized,
          tags: $tags
        }
      }
    },
    expirySeconds: $expiry_seconds
  }')

echo "Generating Tailscale authkey for: $TARGET_HOSTNAME..."
API_RESPONSE=$(curl -s -X POST "https://api.tailscale.com/api/v2/tailnet/${TAILNET_ID}/keys" \
  -H "Authorization: Bearer ${TAILSCALE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-raw "${TAILSCALE_KEY_REQUEST_PAYLOAD}")

TAILSCALE_AUTH_KEY=$(echo "${API_RESPONSE}" | jq -r '.key')

if [ -z "$TAILSCALE_AUTH_KEY" ] || [ "$TAILSCALE_AUTH_KEY" == "null" ]; then
    echo "Error: Failed to generate Tailscale authkey."
    echo "API Response: ${API_RESPONSE}"
    exit 1
fi
echo "Tailscale authkey generated successfully (ephemeral)."

# --- Generate final `curl | bash` command ---
POST_INIT_URL="${POST_INIT_SH_URL}" # Your post-init.sh URL

FINAL_COMMAND="curl -sSL ${POST_INIT_URL} | sudo bash -s -- "
FINAL_COMMAND+=" --user \"${USERNAME}\" "
FINAL_COMMAND+=" --ts-hostname \"${TARGET_HOSTNAME}\""

if [ -z "${USE_LEGACY_SSH_KEY:-}" ]; then
    echo "Error: USE_LEGACY_SSH_KEY must be set in .env."
    exit 1
fi
if [ -z "${TAILSCALE_SSH:-}" ]; then
    echo "Error: TAILSCALE_SSH must be set in .env."
    exit 1
fi
if [ -z "${TAILSCALE_AUTH_INPUT_MODE:-}" ]; then
    echo "Error: TAILSCALE_AUTH_INPUT_MODE must be set in .env."
    exit 1
fi

parse_bool "USE_LEGACY_SSH_KEY" "${USE_LEGACY_SSH_KEY}"
parse_bool "TAILSCALE_SSH" "${TAILSCALE_SSH}"
parse_auth_mode "${TAILSCALE_AUTH_INPUT_MODE}"

if [ "${TAILSCALE_AUTH_INPUT_MODE}" = "arg" ]; then
    FINAL_COMMAND+=" --tailscale \"${TAILSCALE_AUTH_KEY}\" "
else
    FINAL_COMMAND+=" --tailscale-prompt "
fi

if [ "${USE_LEGACY_SSH_KEY}" = "true" ]; then
    if [ -z "${ANSIBLE_SSH_PUB_KEY:-}" ]; then
        echo "Error: USE_LEGACY_SSH_KEY is true but ANSIBLE_SSH_PUB_KEY is empty."
        exit 1
    fi
    FINAL_COMMAND+=" --sshkey \"${ANSIBLE_SSH_PUB_KEY}\" "
else
    FINAL_COMMAND+=" --skip-ssh-key "
fi

if [ "${TAILSCALE_SSH}" = "true" ]; then
    FINAL_COMMAND+=" --enable-tailscale-ssh"
else
    FINAL_COMMAND+=" --disable-tailscale-ssh"
fi

if [ "${USE_LEGACY_SSH_KEY}" = "false" ] && [ "${TAILSCALE_SSH}" = "false" ]; then
    echo "Error: invalid access mode. At least one of legacy SSH key or Tailscale SSH must be enabled."
    exit 1
fi

echo -e "\n\n========================================================"
echo "      COPY AND PASTE THE FOLLOWING COMMAND ON YOUR NEW SERVER"
echo "========================================================"
echo "${FINAL_COMMAND}"
echo "========================================================"
echo -e "\nNOTE: This Tailscale auth key is generated with your configured policy."
echo "After authentication, you should see '${TARGET_HOSTNAME}' in your Tailscale admin console."
echo "Remember to update your Tailscale ACLs and Ansible inventory for this server."
echo "Tailscale key policy: expiry=${TAILSCALE_KEY_EXPIRY_SECONDS}s reusable=${TAILSCALE_KEY_REUSABLE} preauthorized=${TAILSCALE_KEY_PREAUTHORIZED} tags=${TAILSCALE_KEY_TAGS}"
if [ "${TAILSCALE_AUTH_INPUT_MODE}" = "prompt" ]; then
    echo "Prompt mode selected: paste the generated Tailscale auth key when prompted on the target host."
    echo "Generated key: ${TAILSCALE_AUTH_KEY}"
fi

# Copy command to clipboard if pbcopy is available
if command -v pbcopy &>/dev/null; then
    echo "${FINAL_COMMAND}" | pbcopy
    echo -e "\n✅ Command has been copied to clipboard!"
fi
