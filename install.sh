#!/usr/bin/env bash

# ========================
# ANCHOR TO SCRIPT LOCATION
# ========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo " 🔧 Installing Static Analysis Tool"
echo "=========================================="
echo ""

# ========================
# HELPERS
# ========================
info()       { echo "[+] $1"; }
warn()       { echo "[!] $1"; }
error_exit() { echo "[❌ ERROR] $1"; exit 1; }

# ========================
# OS CHECK
# ========================
command -v apt-get >/dev/null || error_exit "This installer requires a Debian/Ubuntu system"

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

# ========================
# DOCKER SETUP
# ========================
if ! groups "$USER" | grep -q docker; then
  info "Adding user to docker group..."
  sudo usermod -aG docker "$USER" || warn "Could not add user to docker group"
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
mkdir -p "$SCRIPT_DIR/reports"
mkdir -p "$SCRIPT_DIR/config"

# ========================
# SMTP CONFIG
# ========================
CONFIG_FILE="$SCRIPT_DIR/config/smtp.conf"

echo ""

if [ -f "$CONFIG_FILE" ]; then
  warn "SMTP config already exists at: $CONFIG_FILE"
  printf "Do you want to update it? [y/N]: "
  read UPDATE_CHOICE
  if [ "$UPDATE_CHOICE" != "y" ] && [ "$UPDATE_CHOICE" != "Y" ]; then
    info "Keeping existing SMTP configuration"
    SKIP_SMTP=1
  else
    SKIP_SMTP=0
  fi
else
  printf "Do you want to configure email (SMTP)? [y/N]: "
  read SMTP_CHOICE
  if [ "$SMTP_CHOICE" = "y" ] || [ "$SMTP_CHOICE" = "Y" ]; then
    SKIP_SMTP=0
  else
    warn "Skipping SMTP setup"
    SKIP_SMTP=1
  fi
fi

if [ "$SKIP_SMTP" = "0" ]; then
  echo ""

  printf "SMTP Server:   "
  read SMTP_SERVER

  printf "SMTP Port:     "
  read SMTP_PORT

  printf "SMTP Username: "
  read SMTP_USER

  printf "SMTP Password: "
  read SMTP_PASS
  echo ""

  printf "From Email:    "
  read FROM_EMAIL

  # Validate none are empty
  if   [ -z "$SMTP_SERVER" ]; then error_exit "SMTP server cannot be empty"
  elif [ -z "$SMTP_PORT" ];   then error_exit "SMTP port cannot be empty"
  elif [ -z "$SMTP_USER" ];   then error_exit "SMTP username cannot be empty"
  elif [ -z "$SMTP_PASS" ];   then error_exit "SMTP password cannot be empty"
  elif [ -z "$FROM_EMAIL" ];  then error_exit "From email cannot be empty"
  fi

  # Write the config
  {
    echo "SMTP_SERVER=\"$SMTP_SERVER\""
    echo "SMTP_PORT=\"$SMTP_PORT\""
    echo "SMTP_USER=\"$SMTP_USER\""
    echo "SMTP_PASS=\"$SMTP_PASS\""
    echo "FROM_EMAIL=\"$FROM_EMAIL\""
  } > "$CONFIG_FILE"

  # Verify it was written
  if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ]; then
    chmod 600 "$CONFIG_FILE"
    info "SMTP configuration saved to: $CONFIG_FILE"
    info "Permissions set to 600"
  else
    error_exit "Failed to write $CONFIG_FILE — check folder permissions"
  fi
fi

# ========================
# MAKE MAIN EXECUTABLE
# ========================
if [ -f "$SCRIPT_DIR/main.sh" ]; then
  chmod +x "$SCRIPT_DIR/main.sh"
  info "main.sh is now executable"
else
  warn "main.sh not found in the tool directory"
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
