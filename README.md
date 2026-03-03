# run-sh
![Built with Codex](https://img.shields.io/badge/Built%20with-Codex-0A7CFF)

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
- `post-init/generate_bootstrap_command.sh`: Local key issuer + validated command builder.
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

The generator does two things:
- Creates a Tailscale auth key via API using policy variables from `.env`
- Builds a bootstrap command with explicit access-mode flags

By default, it also fails fast if the same hostname already exists in tailnet.
To bypass this guard intentionally:
```bash
./generate_bootstrap_command.sh --allow-existing-hostname <target-hostname>
```

This prints a command similar to:
```bash
curl -sSL <POST_INIT_SH_URL> | sudo bash -s -- \
  --tailscale-prompt \
  --user "ansible" \
  --ts-hostname "<target-hostname>" \
  --sshkey "<SSH_PUBLIC_KEY>" \
  --enable-tailscale-ssh
```

### 3) Run on the target host
Execute the generated command on the target host as root (or with `sudo`).

## `post-init.sh` interface
Required arguments:
- One explicit Tailscale auth input mode:
  - `--tailscale "<TAILSCALE_AUTH_KEY>"`, or
  - `--tailscale-stdin`, or
  - `--tailscale-prompt`
- One explicit SSH key mode:
  - `--sshkey "<SSH_PUBLIC_KEY>"`, or
  - `--skip-ssh-key`
- One explicit Tailscale SSH mode:
  - `--enable-tailscale-ssh`, or
  - `--disable-tailscale-ssh`

Optional arguments:
- `--user "<USERNAME>"` (default: `ansible`)
- `--ts-hostname "<HOSTNAME>"` (default: host's current hostname)

## Access mode choices
- Tailscale SSH only:
  - `--tailscale-prompt` (or another explicit auth input mode)
  - `--skip-ssh-key`
  - `--enable-tailscale-ssh`
- Legacy SSH key + Tailscale SSH:
  - `--tailscale-prompt` (or another explicit auth input mode)
  - `--sshkey "<SSH_PUBLIC_KEY>"`
  - `--enable-tailscale-ssh`
- Legacy SSH key only:
  - `--tailscale-prompt` (or another explicit auth input mode)
  - `--sshkey "<SSH_PUBLIC_KEY>"`
  - `--disable-tailscale-ssh`

## Idempotency behavior
- A completion marker is written to `/var/lib/post_init_setup_done` only after full success.
- If the marker exists, the script exits without re-running Day-0 steps.

## Security notes
- Prefer `--tailscale-prompt` to avoid exposing the auth key in shell history and process args.
- If you use `--tailscale "<key>"`, avoid shell history persistence and use short-lived keys.
- The script grants `NOPASSWD:ALL` to the bootstrap user for operational convenience.
  - Tighten this in Ansible for production environments.

## Tailscale key policy variables
Set these in `post-init/.env` for `generate_bootstrap_command.sh`:
- `TAILSCALE_KEY_EXPIRY_SECONDS` (positive integer)
- `TAILSCALE_KEY_REUSABLE` (`true|false`)
- `TAILSCALE_KEY_PREAUTHORIZED` (`true|false`)
- `TAILSCALE_KEY_TAGS` (comma-separated tags, e.g. `tag:unprovisioned-server,tag:ssh-inbound-only`)
- `ALLOW_EXISTING_HOSTNAME` (`true|false`, default recommended: `false`)

## Day-1 handoff
After Day-0 finishes and the node appears in tailnet, run your Ansible workflow immediately:
- inventory registration
- baseline hardening
- package/service policy
- monitoring/logging setup
