#!/usr/bin/env bash
# sshRemoteSetup.sh
# Automates SSH key-based authentication setup on a remote Linux machine.
# Compatible with Ubuntu/Debian-based and RedHat/CentOS-based distributions.
#
# Usage: ./sshRemoteSetup.sh <IP_ADDRESS> <USERNAME> <PASSWORD> [SSH_PORT] [DISABLE_PASSWORD_AUTH]
# Example: ./sshRemoteSetup.sh 192.168.1.100 ubuntu mypassword 22 true

set -euo pipefail

# ---------------------------------------------------------------------------
# Usage / parameter validation
# ---------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
    echo "Usage: ./sshRemoteSetup.sh <IP_ADDRESS> <USERNAME> <PASSWORD> [SSH_PORT] [DISABLE_PASSWORD_AUTH]"
    echo "Example: ./sshRemoteSetup.sh 192.168.1.100 user password 22 true"
    exit 0
fi

if [[ $# -lt 3 ]]; then
    echo "Error: IP_ADDRESS, USERNAME, and PASSWORD are required."
    echo "Usage: ./sshRemoteSetup.sh <IP_ADDRESS> <USERNAME> <PASSWORD> [SSH_PORT] [DISABLE_PASSWORD_AUTH]"
    exit 1
fi

IP_ADDRESS="$1"
USERNAME="$2"
PASSWORD="$3"
SSH_PORT="${4:-22}"
DISABLE_PASSWORD_AUTH="${5:-false}"

# Validate SSH port is a number
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]]; then
    echo "Invalid value for SSH_PORT. Using default value of 22."
    SSH_PORT=22
fi

# Normalize DISABLE_PASSWORD_AUTH to lowercase
DISABLE_PASSWORD_AUTH="${DISABLE_PASSWORD_AUTH,,}"
if [[ "$DISABLE_PASSWORD_AUTH" != "true" && "$DISABLE_PASSWORD_AUTH" != "false" ]]; then
    echo "Invalid value for DISABLE_PASSWORD_AUTH. Using default value of false."
    DISABLE_PASSWORD_AUTH="false"
fi

echo "Setting up SSH on remote Linux machine..."

# ---------------------------------------------------------------------------
# Ensure sshpass is installed (needed for non-interactive password auth)
# ---------------------------------------------------------------------------
if ! command -v sshpass &>/dev/null; then
    echo "sshpass not found. Attempting to install..."
    if command -v apt-get &>/dev/null; then
        # Debian / Ubuntu
        sudo apt-get update -qq && sudo apt-get install -y -qq sshpass
    elif command -v dnf &>/dev/null; then
        # RHEL 8+ / Fedora / CentOS Stream
        sudo dnf install -y sshpass
    elif command -v yum &>/dev/null; then
        # RHEL 7 / CentOS 7
        sudo yum install -y sshpass
    else
        echo "Error: Could not install sshpass. Please install it manually and re-run this script."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Generate SSH key pair locally
# ---------------------------------------------------------------------------
SSH_DIR="$HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

KEY_PATH="$SSH_DIR/id_ed25519_${IP_ADDRESS}"

if [[ -f "$KEY_PATH" ]]; then
    echo "SSH key already exists at $KEY_PATH. Skipping key generation."
else
    echo "Generating SSH key pair at $KEY_PATH..."
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -q
    echo "SSH key pair generated successfully."
fi

PUBLIC_KEY_PATH="${KEY_PATH}.pub"
PUBLIC_KEY="$(cat "$PUBLIC_KEY_PATH")"

# ---------------------------------------------------------------------------
# Update local ~/.ssh/config
# ---------------------------------------------------------------------------
SSH_CONFIG_PATH="$SSH_DIR/config"
touch "$SSH_CONFIG_PATH"
chmod 600 "$SSH_CONFIG_PATH"

SSH_CONFIG_ENTRY="Host ${IP_ADDRESS}
    IdentityFile ${KEY_PATH}
    User ${USERNAME}
    Port ${SSH_PORT}
"

if grep -q "^Host ${IP_ADDRESS}$" "$SSH_CONFIG_PATH" 2>/dev/null; then
    echo "Host ${IP_ADDRESS} already exists in SSH config."
else
    printf '\n%s\n' "$SSH_CONFIG_ENTRY" >> "$SSH_CONFIG_PATH"
    echo "Updated SSH config at $SSH_CONFIG_PATH"
fi

# ---------------------------------------------------------------------------
# Shared SSH / sshpass options
# ---------------------------------------------------------------------------
SSHPASS_OPTS=(sshpass -p "$PASSWORD")
SSH_OPTS=(-o StrictHostKeyChecking=no -o BatchMode=no -p "$SSH_PORT")

# ---------------------------------------------------------------------------
# Copy public key to remote machine and configure sshd
# ---------------------------------------------------------------------------
echo "Copying public key to remote Linux machine..."

"${SSHPASS_OPTS[@]}" ssh "${SSH_OPTS[@]}" "${USERNAME}@${IP_ADDRESS}" bash <<REMOTE_SCRIPT
set -e

# Create .ssh directory on remote machine if it doesn't exist
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Ensure authorized_keys file exists with proper permissions
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Append public key only if it is not already present
PUBLIC_KEY='${PUBLIC_KEY}'
if ! grep -qF "\$PUBLIC_KEY" ~/.ssh/authorized_keys; then
    printf '%s\n' "\$PUBLIC_KEY" >> ~/.ssh/authorized_keys
    echo "Public key appended to authorized_keys."
else
    echo "Public key already present in authorized_keys."
fi

# Report authorized_keys line count for verification
echo "Authorized keys line count: \$(wc -l < ~/.ssh/authorized_keys)"

# Ensure PubkeyAuthentication is enabled in sshd_config
sudo sed -Ei 's/^#?[[:space:]]*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
echo "PubkeyAuthentication enabled."
REMOTE_SCRIPT

echo "Public key copied to remote Linux machine successfully."

# ---------------------------------------------------------------------------
# Optionally disable password authentication
# ---------------------------------------------------------------------------
if [[ "$DISABLE_PASSWORD_AUTH" == "true" ]]; then
    echo "Disabling password authentication on remote Linux machine..."

    "${SSHPASS_OPTS[@]}" ssh "${SSH_OPTS[@]}" "${USERNAME}@${IP_ADDRESS}" bash <<REMOTE_SCRIPT
set -e

# Backup sshd_config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Disable password authentication
sudo sed -Ei 's/^#?[[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
echo "PasswordAuthentication disabled."

# Restart SSH service (sshd on RHEL/CentOS, ssh on Debian/Ubuntu)
if systemctl list-units --type=service | grep -q 'sshd.service'; then
    sudo systemctl restart sshd
else
    sudo systemctl restart ssh
fi
echo "SSH service restarted."
REMOTE_SCRIPT

    echo "Password authentication disabled on remote Linux machine successfully."
fi

echo "SSH setup completed successfully."
