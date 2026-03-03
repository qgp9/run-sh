#!/usr/bin/env bash
# post-init.sh - Day-0 bootstrap script
# Scope: tailscale join + ansible user prep + minimal utilities

set -Eeuo pipefail

SCRIPT_USAGE='Usage: curl ... | bash -s -- (--tailscale "<TAILSCALE_AUTH_KEY>" | --tailscale-stdin | --tailscale-prompt) (--sshkey "<SSH_PUBLIC_KEY>" | --skip-ssh-key) [--user <USERNAME>] [--ts-hostname <HOSTNAME>] (--enable-tailscale-ssh | --disable-tailscale-ssh)'
POST_INIT_FLAG="/var/lib/post_init_setup_done"
POST_INIT_LOG="/var/log/post-init.log"
DEFAULT_USERNAME="ansible"

SSH_PUB_KEY=""
TAILSCALE_AUTH_KEY=""
TAILSCALE_AUTH_MODE=""
USERNAME="$DEFAULT_USERNAME"
TAILSCALE_HOSTNAME="$(hostname)"
TAILSCALE_SSH_ENABLED=""
SSH_KEY_MODE_SET="false"
TAILSCALE_SSH_MODE_SET="false"
TAILSCALE_AUTH_MODE_SET="false"
CURRENT_STEP="init"

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

on_error() {
    local line_no="$1"
    log "STEP ${CURRENT_STEP} fail (line=${line_no})"
}

run_step() {
    local step_name="$1"
    shift

    CURRENT_STEP="$step_name"
    log "STEP ${CURRENT_STEP} start"
    "$@"
    log "STEP ${CURRENT_STEP} ok"
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
                if [ "$SSH_KEY_MODE_SET" = "true" ]; then
                    fail "Choose only one SSH key mode: --sshkey or --skip-ssh-key."
                fi
                SSH_PUB_KEY="$2"
                SSH_KEY_MODE_SET="true"
                shift 2
                ;;
            --skip-ssh-key)
                if [ "$SSH_KEY_MODE_SET" = "true" ]; then
                    fail "Choose only one SSH key mode: --sshkey or --skip-ssh-key."
                fi
                SSH_KEY_MODE_SET="true"
                shift
                ;;
            --tailscale)
                require_value "--tailscale" "${2:-}"
                if [ "$TAILSCALE_AUTH_MODE_SET" = "true" ]; then
                    fail "Choose only one Tailscale auth mode: --tailscale, --tailscale-stdin, or --tailscale-prompt."
                fi
                TAILSCALE_AUTH_KEY="$2"
                TAILSCALE_AUTH_MODE="arg"
                TAILSCALE_AUTH_MODE_SET="true"
                shift 2
                ;;
            --tailscale-stdin)
                if [ "$TAILSCALE_AUTH_MODE_SET" = "true" ]; then
                    fail "Choose only one Tailscale auth mode: --tailscale, --tailscale-stdin, or --tailscale-prompt."
                fi
                TAILSCALE_AUTH_MODE="stdin"
                TAILSCALE_AUTH_MODE_SET="true"
                shift
                ;;
            --tailscale-prompt)
                if [ "$TAILSCALE_AUTH_MODE_SET" = "true" ]; then
                    fail "Choose only one Tailscale auth mode: --tailscale, --tailscale-stdin, or --tailscale-prompt."
                fi
                TAILSCALE_AUTH_MODE="prompt"
                TAILSCALE_AUTH_MODE_SET="true"
                shift
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
            --enable-tailscale-ssh)
                if [ "$TAILSCALE_SSH_MODE_SET" = "true" ]; then
                    fail "Choose only one Tailscale SSH mode: --enable-tailscale-ssh or --disable-tailscale-ssh."
                fi
                TAILSCALE_SSH_ENABLED="true"
                TAILSCALE_SSH_MODE_SET="true"
                shift
                ;;
            --disable-tailscale-ssh)
                if [ "$TAILSCALE_SSH_MODE_SET" = "true" ]; then
                    fail "Choose only one Tailscale SSH mode: --enable-tailscale-ssh or --disable-tailscale-ssh."
                fi
                TAILSCALE_SSH_ENABLED="false"
                TAILSCALE_SSH_MODE_SET="true"
                shift
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

    if [ "$TAILSCALE_AUTH_MODE_SET" = "false" ]; then
        fail "Missing Tailscale auth mode: choose --tailscale, --tailscale-stdin, or --tailscale-prompt."
    fi

    if [ "$SSH_KEY_MODE_SET" = "false" ]; then
        fail "Missing SSH key mode: choose --sshkey or --skip-ssh-key."
    fi

    if [ "$TAILSCALE_SSH_MODE_SET" = "false" ]; then
        fail "Missing Tailscale SSH mode: choose --enable-tailscale-ssh or --disable-tailscale-ssh."
    fi

    if [ "$TAILSCALE_SSH_ENABLED" = "false" ] && [ -z "$SSH_PUB_KEY" ]; then
        fail "At least one access path is required: use --sshkey or enable Tailscale SSH."
    fi
}

load_tailscale_auth_key() {
    case "$TAILSCALE_AUTH_MODE" in
        arg)
            if [ -z "$TAILSCALE_AUTH_KEY" ]; then
                fail "--tailscale requires a non-empty auth key."
            fi
            ;;
        stdin)
            if ! IFS= read -r TAILSCALE_AUTH_KEY; then
                fail "Failed to read Tailscale auth key from stdin."
            fi
            if [ -z "$TAILSCALE_AUTH_KEY" ]; then
                fail "Tailscale auth key from stdin is empty."
            fi
            ;;
        prompt)
            if [ ! -r /dev/tty ]; then
                fail "--tailscale-prompt requires an interactive terminal."
            fi
            read -r -s -p "Enter Tailscale auth key: " TAILSCALE_AUTH_KEY < /dev/tty
            echo "" > /dev/tty
            if [ -z "$TAILSCALE_AUTH_KEY" ]; then
                fail "Tailscale auth key from prompt is empty."
            fi
            ;;
        *)
            fail "Invalid Tailscale auth mode."
            ;;
    esac
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
    local ssh_flag="--ssh=true"

    log "Installing Tailscale if needed."

    if ! command -v tailscale >/dev/null 2>&1; then
        curl -fsSL https://tailscale.com/install.sh | sh
    fi

    if [ "$TAILSCALE_SSH_ENABLED" = "false" ]; then
        ssh_flag="--ssh=false"
    fi

    log "Joining tailnet with provided auth key."
    if ! tailscale up --authkey "$TAILSCALE_AUTH_KEY" --hostname "$TAILSCALE_HOSTNAME" --accept-routes --accept-dns "$ssh_flag"; then
        log "Error: tailscale up failed. Check auth key, ACL tags, and network connectivity."
        exit 1
    fi

    log "Tailscale setup completed successfully."
}

main() {
    trap 'on_error $LINENO' ERR

    require_root

    if [ -f "$POST_INIT_FLAG" ]; then
        log "Post-initialization already completed. Exiting."
        exit 0
    fi

    parse_args "$@"
    log "Starting Day-0 post-initialization."
    run_step "load_tailscale_auth_key" load_tailscale_auth_key

    run_step "install_basic_utils" install_basic_utils
    run_step "add_user" add_user "$USERNAME"
    run_step "grant_sudo_privileges" grant_sudo_privileges "$USERNAME"
    if [ -n "$SSH_PUB_KEY" ]; then
        run_step "deploy_ssh_key" deploy_ssh_key "$USERNAME" "$SSH_PUB_KEY"
    else
        log "STEP deploy_ssh_key skip (no --sshkey provided)"
    fi
    run_step "setup_tailscale" setup_tailscale

    mkdir -p "$(dirname "$POST_INIT_FLAG")"
    touch "$POST_INIT_FLAG"
    log "Post-initialization completed successfully."
}

main "$@"
