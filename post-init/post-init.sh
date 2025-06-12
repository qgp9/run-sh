#!/bin/bash
# post-init.sh - The universal bootstrapping script
# setup user, ssh key, tailscale
# usage: curl ... | bash --sshkey "<SSH_PUBLIC_KEY>" --tailscale "<TAILSCALE_AUTH_KEY>" [--user <USERNAME>] [--ts-hostname <HOSTNAME>]

function main() {
    # --- root check ---
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root."
        exit 1
    fi
    
    # --- script idempotency ---
    POST_INIT_FLAG="/var/lib/post_init_setup_done"
    if [ -f "$POST_INIT_FLAG" ]; then
        log "Post-initialization script already completed. Exiting."
        exit 0
    fi
    log "Starting universal post-initialization script..."

    parse_args "$@"
    install_basic_utils
    add_user "$USERNAME"
    grant_sudo_privileges "$USERNAME"
    deploy_ssh_key "$USERNAME" "$SSH_PUB_KEY"
    setup_tailscale

    log "Post-initialization script completed successfully."
    touch "$POST_INIT_FLAG" # Create main script completion flag
}

# logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/post-init.log
}


function parse_args() {
    # --- command line argument parsing ---
    SSH_PUB_KEY=""
    TAILSCALE_AUTH_KEY=""
    USERNAME="ansible" # default value
    TAILSCALE_HOSTNAME="$(hostname)" # default value
    
    while (( "$#" )); do
      case "$1" in
        --sshkey)
          SSH_PUB_KEY="$2"
          shift 2
          ;;
        --tailscale)
          TAILSCALE_AUTH_KEY="$2"
          shift 2
          ;;
        --user)
          USERNAME="$2"
          shift 2
          ;;
        --ts-hostname)
          TAILSCALE_HOSTNAME="$2"
          shift 2
          ;;
        --) # End of arguments
          shift
          break
          ;;
        *) # Unknown option
          log "Error: Unknown option $1"
          exit 1
          ;;
      esac
    done
    
    # argument validation
    if [ -z "$SSH_PUB_KEY" ] || [ -z "$TAILSCALE_AUTH_KEY" ]; then
        log "Error: Missing required arguments --sshkey and --tailscale."
        log "Usage: curl ... | bash --sshkey \"<SSH_PUBLIC_KEY>\" --tailscale \"<TAILSCALE_AUTH_KEY>\" [--user <USERNAME>] [--ts-hostname <HOSTNAME>]"
        exit 1
    fi
}

function install_basic_utils() {
    # Detect package manager and set commands
    if command -v apt-get &>/dev/null; then
        log "Detected Debian/Ubuntu (apt-get)."
        apt-get update
        apt-get install -y curl ca-certificates openssh-server screen vim git
    elif command -v yum &>/dev/null; then
        log "Detected RHEL/CentOS 7 (yum)."
        yum check-update || true
        yum install -y curl ca-certificates openssh-server screen vim git
    elif command -v dnf &>/dev/null; then
        log "Detected RHEL/CentOS 8+/Fedora (dnf)."
        dnf check-update || true
        dnf install -y curl ca-certificates openssh-server screen vim git
    elif command -v zypper &>/dev/null; then
        log "Detected OpenSUSE/SLES (zypper)."
        zypper refresh
        zypper install -y curl ca-certificates openssh-server screen vim git
    else
        log "Error: No supported package manager found. Cannot proceed."
        exit 1
    fi || { log "Package manager installation failed. Cannot proceed."; exit 1; }
}


# --- system basic utils and package manager detection ---


function add_user() {
    local username="$1"
    if id "$username" &>/dev/null; then
        log "User '$username' already exists."
    else
        log "Adding user '$username'..."
        useradd -m -s /bin/bash "$username" || { log "Failed to add user."; exit 1; }
        log "User '$username' created."
    fi
}


function grant_sudo_privileges() {
    local username="$1"
    local sudoers_file="/etc/sudoers.d/90-${username}-user"
    if [ ! -f "$sudoers_file" ]; then
        log "Granting sudo privileges for '$username'..."
        echo "$username ALL=(ALL) NOPASSWD:ALL" | tee "$sudoers_file" || { log "Failed to grant sudo privileges."; exit 1; }
        chmod 0440 "$sudoers_file" || { log "Failed to set sudoers file permissions."; exit 1; }
        log "Sudo privileges granted for '$username'."
    else
        log "Sudoers file '$sudoers_file' already exists."
    fi
}


function deploy_ssh_key() {
    local username="$1"
    local ssh_pub_key="$2"
    local ssh_dir="/home/$username/.ssh"
    local sudo_user="sudo -u $username"

    log "Deploying SSH public key for '$username'..."

    $sudo_user mkdir -p "$ssh_dir" || { log "Failed to create SSH dir for $username."; exit 1; }
    $sudo_user chmod 700 "$ssh_dir" || { log "Failed to set SSH dir permissions."; exit 1; }
    
    # Use overwrite instead of append (tee instead of tee -a)
    echo "$ssh_pub_key" | $sudo_user tee "$ssh_dir/authorized_keys" > /dev/null || { log "Failed to write SSH key."; exit 1; }
    $sudo_user chmod 600 "$ssh_dir/authorized_keys" || { log "Failed to set SSH key permissions."; exit 1; }
    log "SSH public key deployed."
}

function setup_tailscale() {
    log "Installing Tailscale..."
    # Tailscale installation script detects distribution and installs (idempotent)
    if ! command -v tailscale &>/dev/null; then
        curl -fsSL https://tailscale.com/install.sh | sh || { log "Failed to download/install Tailscale."; exit 1; }
    fi

    log "Authenticating Tailscale with provided authkey..."
    run tailscale up --authkey "$TAILSCALE_AUTH_KEY" --hostname "$TAILSCALE_HOSTNAME" --accept-routes --accept-dns || { log "Tailscale initial authentication failed. Check authkey or network."; exit 1; }
    log "Tailscale initial setup completed successfully. Device should appear in your Tailnet."
}

function run() {
    "$@"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log "Error: $@ failed."
        return $exit_code
    fi
}


main "$@"
