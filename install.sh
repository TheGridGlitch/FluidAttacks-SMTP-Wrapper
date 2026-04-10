#!/bin/bash

set -e

echo "=========================================="
echo " 🔧 Installing Static Analysis Tool"
echo "=========================================="
echo ""

# ========================
# HELPERS
# ========================
info() { echo "[+] $1"; }
warn() { echo "[!] $1"; }
error_exit() { echo "[❌ ERROR] $1"; exit 1; }

# ========================
# INSTALL DEPENDENCIES
# ========================
install_pkg() {
    PKG=$1
    if command -v "$PKG" >/dev/null 2>&1; then
        info "$PKG already installed"
    else
        info "Installing $PKG..."
        sudo apt-get update -y >/dev/null 2>&1 || true
        sudo apt-get install -y "$PKG" || error_exit "Failed to install $PKG"
    fi
}

install_pkg docker.io
install_pkg git
install_pkg curl
install_pkg rsync
install_pkg jq

# ========================
# DOCKER SETUP
# ========================
if ! groups $USER | grep -q docker; then
    info "Adding user to docker group..."
    sudo usermod -aG docker $USER || warn "Could not add user to docker group"
    warn "Please log out and log back in for docker access"
fi

if ! systemctl is-active --quiet docker; then
    info "Starting Docker service..."
    sudo systemctl start docker || warn "Could not start Docker"
fi

# ========================
# PROJECT STRUCTURE
# ========================
info "Setting up directories..."
mkdir -p reports
mkdir -p config

# ========================
# SMTP CONFIG (SMART)
# ========================
CONFIG_FILE="config/smtp.conf"

echo ""

if [[ -f "$CONFIG_FILE" ]]; then
    warn "SMTP config already exists"

    read -p "Do you want to update the existing SMTP configuration? [y/N]: " UPDATE_CHOICE

    if [[ ! "$UPDATE_CHOICE" =~ ^[Yy]$ ]]; then
        info "Keeping existing SMTP configuration"
    else
        echo ""
        info "Updating SMTP configuration..."

        read -p "SMTP Server: " SMTP_SERVER
        read -p "SMTP Port: " SMTP_PORT
        read -p "SMTP Username: " SMTP_USER
        read -s -p "SMTP Password: " SMTP_PASS
        echo ""
        read -p "From Email: " FROM_EMAIL

        cat << EOF > "$CONFIG_FILE"
SMTP_SERVER="$SMTP_SERVER"
SMTP_PORT="$SMTP_PORT"
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"
FROM_EMAIL="$FROM_EMAIL"
EOF

        info "SMTP configuration updated"
    fi

else
    read -p "Do you want to configure email (SMTP)? [y/N]: " SMTP_CHOICE

    if [[ "$SMTP_CHOICE" =~ ^[Yy]$ ]]; then
        echo ""
        read -p "SMTP Server: " SMTP_SERVER
        read -p "SMTP Port: " SMTP_PORT
        read -p "SMTP Username: " SMTP_USER
        read -s -p "SMTP Password: " SMTP_PASS
        echo ""
        read -p "From Email: " FROM_EMAIL

        cat << EOF > "$CONFIG_FILE"
SMTP_SERVER="$SMTP_SERVER"
SMTP_PORT="$SMTP_PORT"
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"
FROM_EMAIL="$FROM_EMAIL"
EOF

        info "SMTP configuration saved"
    else
        warn "Skipping SMTP setup"
    fi
fi

# ========================
# MAKE MAIN EXECUTABLE
# ========================
if [[ -f "main.sh" ]]; then
    chmod +x main.sh
    info "main.sh is now executable"
else
    warn "main.sh not found in current directory"
fi

# ========================
# FINAL MESSAGE
# ========================
echo ""
echo "=========================================="
echo " Installation Complete ✅"
echo "=========================================="
echo ""
echo "Use: ./main.sh -h to begin"
echo ""
