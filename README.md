# run-sh

A simple helper script collection for server bootstrap automation via curl. Perfect for quick server setup when cloud-init is complex or unavailable.

> ⚠️ **Disclaimer**: This README was mostly written by an LLM (thanks, AI!) and hasn't been thoroughly fact-checked. Proceed with caution and a sense of humor 😄  
> *Even this disclaimer sentence was written by an LLM - we're going full meta here!*

## TL;DR

```bash
# 1. Setup environment
cp post-init/.env-example .env
# Edit .env with your values

# 2. Generate bootstrap command
./post-init/generate_bootstrap_command.sh my-server

# 3. Run on new server (copy-paste the output)
# curl -sSL https://... | sudo bash -s -- --sshkey "..." --tailscale "..." --user "ansible" --ts-hostname "my-server"

# 4. SSH into server
ssh ansible@my-server.your-tailnet.ts.net

# 5. Use Ansible for further automation
ansible-playbook -i inventory.yml playbook.yml
```

## Overview

`run-sh` provides a semi-automated approach to server initialization. Instead of complex cloud-init configurations, you can bootstrap a server with a single curl command after it's created.

## How It Works

1. **Generate bootstrap command** on your local machine
2. **Copy and paste** the generated command on your new server
3. **Wait 1-2 minutes** for automatic setup
4. **SSH into the server** and start using Ansible for further automation

## Features

- 🔧 **One-command setup**: Single curl command to bootstrap any Linux server
- 🔐 **SSH key deployment**: Automatic SSH public key setup for secure access
- 🌐 **Tailscale integration**: Automatic VPN setup for secure remote access
- 👤 **User management**: Creates ansible user with sudo privileges
- 📦 **Package installation**: Installs essential tools (curl, git, vim, screen)
- 🔄 **Idempotent**: Safe to run multiple times
- 🐧 **Multi-distro support**: Works with apt, yum, dnf, zypper package managers

## Quick Start

### Prerequisites

1. Create a `.env` file with your configuration (refer to `post-init/.env-example` for the required variables):

```bash
TAILNET_ID="your-tailnet-id"
TAILSCALE_API_TOKEN="your-api-token"
ANSIBLE_SSH_PUB_KEY="your-ssh-public-key"
USERNAME="ansible"
POST_INIT_SH_URL="https://raw.githubusercontent.com/your-repo/run-sh/main/post-init/post-init.sh"
```

> **Note**: The `POST_INIT_SH_URL` example above is for when you fork the repository. You can also use the default value from `post-init/.env-example` if you prefer.

2. Generate the bootstrap command:

```bash
./post-init/generate_bootstrap_command.sh your-server-hostname
```

3. Copy the generated command and run it on your new server via console.

### Example Workflow

```bash
# 1. Generate bootstrap command
./post-init/generate_bootstrap_command.sh my-new-server

# 2. Copy the output command and run it on your server:
# curl -sSL https://raw.githubusercontent.com/your-repo/run-sh/main/post-init/post-init.sh | sudo bash -s -- --sshkey "ssh-rsa..." --tailscale "tskey..." --user "ansible" --ts-hostname "my-new-server"

# 3. SSH into your server via Tailscale
ssh ansible@<hostname>.<tailnet>.ts.net
```

## Use Cases

- **Quick prototyping**: Set up test servers in seconds
- **Cloud-init alternatives**: When cloud-init is complex or unavailable
- **Existing server setup**: Add configuration to already running servers
- **Development environments**: Consistent setup across team members
- **Emergency access**: Quick VPN setup for remote servers

## Advantages over Cloud-init

| Aspect | Cloud-init | run-sh |
|--------|------------|--------|
| **Complexity** | High (YAML, templates) | Low (single command) |
| **Flexibility** | Limited (pre-configured) | High (run when needed) |
| **Debugging** | Hard (logs only) | Easy (console access) |
| **Setup time** | Instant (at creation) | 1-2 minutes |
| **Learning curve** | Steep | Minimal |

## Tailscale Integration

The script automatically sets up Tailscale VPN for secure remote access:

- **One-time auth keys**: Single-use keys that are automatically revoked after first use
- **ACL tags**: Pre-assigned restrictive permissions (`tag:unprovisioned-server`)
- **Automatic device naming**: Uses the provided hostname for easy identification
- **Route acceptance**: Automatically accepts routes and DNS settings

### Tailscale ACL Configuration

The generated auth keys include `tag:unprovisioned-server` which should be configured in your Tailscale ACLs to restrict initial access. Example ACL configuration:

- Example ACL configuration:

```json
{
  "tagOwners": {
    "tag:unprovisioned-server": ["autogroup:admin"],
  },
  "grants": [
    {
      "src": ["autogroup:admin"],
      "dst": ["*"],
      "ip":  ["*"],
    }
  ],
}
```

## Security Features

- **Secure SSH setup**: Proper file permissions and key deployment
- **Sudo privileges**: Controlled access for automation user

## Requirements

- Linux server with internet access
- Root/sudo access on target server
- Tailscale account and API token
- SSH public key

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Feel free to submit issues and enhancement requests!
