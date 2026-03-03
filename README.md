# run-sh

Day-0 bootstrap scripts for hosts where `cloud-init` is unavailable or inconvenient.

## Scope
This repository is intentionally limited to Day-0 provisioning:
- Join a host to tailnet (Tailscale)
- Prepare an Ansible admin account (user, sudo, SSH key)
- Install a minimal utility set (`curl`, `git`, `tmux`, `vim`, etc.)

Out of scope:
- App/service deployment
- Security hardening beyond bootstrap basics
- Monitoring/observability setup

Those belong to Day-1+ configuration (Ansible roles/playbooks).

## Repository layout
- `post-init/post-init.sh`: Day-0 bootstrap script run on the target host.
- `post-init/generate_bootstrap_command.sh`: Local helper to generate a one-shot bootstrap command.
- `post-init/.env-example`: Example environment file for the local helper.

## Quick start
### 1) Prepare local environment
```bash
cd post-init
cp .env-example .env
# Fill in values in .env
```

Required local tools:
- `curl`
- `jq`

Versioning recommendation:
- Pin `POST_INIT_SH_URL` to a release tag instead of `main`.
- Example: `https://cdn.jsdelivr.net/gh/qgp9/run-sh@v0.3.0/post-init/post-init.sh`
- Roll back by switching to an earlier tag.

### 2) Generate a bootstrap command
```bash
./generate_bootstrap_command.sh <target-hostname>
```

This prints a command similar to:
```bash
curl -sSL <POST_INIT_SH_URL> | sudo bash -s -- \
  --sshkey "<SSH_PUBLIC_KEY>" \
  --tailscale "<TAILSCALE_AUTH_KEY>" \
  --user "ansible" \
  --ts-hostname "<target-hostname>"
```

### 3) Run on the target host
Execute the generated command on the target host as root (or with `sudo`).

## `post-init.sh` interface
Required arguments:
- `--sshkey "<SSH_PUBLIC_KEY>"`
- `--tailscale "<TAILSCALE_AUTH_KEY>"`

Optional arguments:
- `--user "<USERNAME>"` (default: `ansible`)
- `--ts-hostname "<HOSTNAME>"` (default: host's current hostname)

## Idempotency behavior
- A completion marker is written to `/var/lib/post_init_setup_done` only after full success.
- If the marker exists, the script exits without re-running Day-0 steps.

## Security notes
- The bootstrap command includes secrets in CLI arguments.
  - Avoid shell history persistence for this command when possible.
  - Use short-lived Tailscale auth keys.
- The script grants `NOPASSWD:ALL` to the bootstrap user for operational convenience.
  - Tighten this in Ansible for production environments.

## Day-1 handoff
After Day-0 finishes and the node appears in tailnet, run your Ansible workflow immediately:
- inventory registration
- baseline hardening
- package/service policy
- monitoring/logging setup
