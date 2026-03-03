#!/usr/bin/env bash
# post-init.sh - Day-0 bootstrap script
# Scope: tailscale join + ansible user prep + minimal utilities

set -euo pipefail

SCRIPT_USAGE='Usage: curl ... | bash -s -- --sshkey "<SSH_PUBLIC_KEY>" --tailscale "<TAILSCALE_AUTH_KEY>" [--user <USERNAME>] [--ts-hostname <HOSTNAME>]'
POST_INIT_FLAG="/var/lib/post_init_setup_done"
POST_INIT_LOG="/var/log/post-init.log"
DEFAULT_USERNAME="ansible"

SSH_PUB_KEY=""
TAILSCALE_AUTH_KEY=""
USERNAME="$DEFAULT_USERNAME"
TAILSCALE_HOSTNAME="$(hostname)"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$POST_INIT_LOG"
}

usage() {
    echo "$SCRIPT_USAGE" >&2
}

fail() {
    log "Error: $1"
    usage
    exit 1
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root." >&2
        exit 1
    fi
}

require_value() {
    local option_name="$1"
    local option_value="${2:-}"

    if [ -z "$option_value" ]; then
        fail "${option_name} requires a value."
    fi
}

parse_args() {
    while (( "$#" )); do
        case "$1" in
            --sshkey)
                require_value "--sshkey" "${2:-}"
                SSH_PUB_KEY="$2"
                shift 2
                ;;
            --tailscale)
                require_value "--tailscale" "${2:-}"
                TAILSCALE_AUTH_KEY="$2"
                shift 2
                ;;
            --user)
                require_value "--user" "${2:-}"
                USERNAME="$2"
                shift 2
                ;;
            --ts-hostname)
                require_value "--ts-hostname" "${2:-}"
                TAILSCALE_HOSTNAME="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done

    if [ -z "$SSH_PUB_KEY" ] || [ -z "$TAILSCALE_AUTH_KEY" ]; then
        fail "Missing required arguments --sshkey and --tailscale."
    fi
}

install_basic_utils() {
    if command -v apt-get >/dev/null 2>&1; then
        log "Detected Debian/Ubuntu (apt-get)."
        apt-get update
        apt-get install -y curl ca-certificates openssh-server git tmux vim
    elif command -v yum >/dev/null 2>&1; then
        log "Detected RHEL/CentOS 7 (yum)."
        yum check-update || true
        yum install -y curl ca-certificates openssh-server git tmux vim
    elif command -v dnf >/dev/null 2>&1; then
        log "Detected RHEL/CentOS 8+/Fedora (dnf)."
        dnf check-update || true
        dnf install -y curl ca-certificates openssh-server git tmux vim
    elif command -v zypper >/dev/null 2>&1; then
        log "Detected OpenSUSE/SLES (zypper)."
        zypper refresh
        zypper install -y curl ca-certificates openssh git tmux vim
    else
        fail "No supported package manager found."
    fi
}

add_user() {
    local username="$1"

    if id "$username" >/dev/null 2>&1; then
        log "User '$username' already exists."
        return
    fi

    log "Adding user '$username'."
    useradd -m -s /bin/bash "$username"
}

grant_sudo_privileges() {
    local username="$1"
    local sudoers_file="/etc/sudoers.d/90-${username}-user"

    if [ -f "$sudoers_file" ]; then
        log "Sudoers file '$sudoers_file' already exists."
        return
    fi

    log "Granting sudo privileges for '$username'."
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$username" > "$sudoers_file"
    chmod 0440 "$sudoers_file"
}

deploy_ssh_key() {
    local username="$1"
    local ssh_pub_key="$2"
    local ssh_dir="/home/$username/.ssh"
    local auth_keys_file="$ssh_dir/authorized_keys"

    log "Deploying SSH public key for '$username'."

    install -d -m 0700 -o "$username" -g "$username" "$ssh_dir"
    printf '%s\n' "$ssh_pub_key" > "$auth_keys_file"
    chown "$username:$username" "$auth_keys_file"
    chmod 0600 "$auth_keys_file"
}

setup_tailscale() {
    log "Installing Tailscale if needed."

    if ! command -v tailscale >/dev/null 2>&1; then
        curl -fsSL https://tailscale.com/install.sh | sh
    fi

    log "Joining tailnet with provided auth key."
    if ! tailscale up --authkey "$TAILSCALE_AUTH_KEY" --hostname "$TAILSCALE_HOSTNAME" --accept-routes --accept-dns; then
        log "Error: tailscale up failed. Check auth key, ACL tags, and network connectivity."
        exit 1
    fi

    log "Tailscale setup completed successfully."
}

main() {
    require_root

    if [ -f "$POST_INIT_FLAG" ]; then
        log "Post-initialization already completed. Exiting."
        exit 0
    fi

    parse_args "$@"
    log "Starting Day-0 post-initialization."

    install_basic_utils
    add_user "$USERNAME"
    grant_sudo_privileges "$USERNAME"
    deploy_ssh_key "$USERNAME" "$SSH_PUB_KEY"
    setup_tailscale

    mkdir -p "$(dirname "$POST_INIT_FLAG")"
    touch "$POST_INIT_FLAG"
    log "Post-initialization completed successfully."
}

main "$@"
