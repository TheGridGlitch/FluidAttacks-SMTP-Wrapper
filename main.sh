#!/bin/bash

set -euo pipefail

# ========================
# HELP
# ========================
show_help() {
cat << EOF
Static Analysis Tool (Raw Mode)

Usage:
  ./main.sh --file-path <path> [options]

Options:
  --repo <git_url>
  --file-path <path>
  --email <email>
  --config <file>
  --severity <levels>   (LOW,MEDIUM,HIGH,CRITICAL)
  --retries <num>
  -h, --help
EOF
}

# ========================
# CONFIG
# ========================
DOCKER_IMAGE="fluidattacks/sast:latest"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT_DIR="$BASE_DIR/reports"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RETRIES=3
SEVERITY=""

WORK_TMP="/tmp/sast_clean_$TIMESTAMP"

# ========================
# LOGGING
# ========================
info() { echo "[+] $1"; }
warn() { echo "[!] $1"; }
error_exit() { echo "[❌ ERROR] $1"; exit 1; }

# ========================
# ARGS
# ========================
[[ "$#" -eq 0 ]] && { show_help; exit 0; }

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --repo) REPO_URL="$2"; shift ;;
        --file-path) FILE_PATH="$2"; shift ;;
        --email) EMAIL="$2"; shift ;;
        --config) CONFIG_FILE="$2"; shift ;;
        --severity) SEVERITY="$2"; shift ;;
        --retries) RETRIES="$2"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) error_exit "Unknown param: $1" ;;
    esac
    shift
done

# ========================
# AUTO CONFIG
# ========================
DEFAULT_CONFIG="$BASE_DIR/config/smtp.conf"

if [[ -z "${CONFIG_FILE:-}" && -f "$DEFAULT_CONFIG" ]]; then
    CONFIG_FILE="$DEFAULT_CONFIG"
    info "Using default config: $CONFIG_FILE"
fi

# ========================
# VALIDATION
# ========================
info "Validating inputs..."

[[ -z "${REPO_URL:-}" && -z "${FILE_PATH:-}" ]] && \
    error_exit "Provide --repo or --file-path"

[[ -n "${REPO_URL:-}" && -n "${FILE_PATH:-}" ]] && \
    error_exit "Only one input allowed"

if [[ -n "${EMAIL:-}" && -z "${CONFIG_FILE:-}" ]]; then
    error_exit "--config required when using email"
fi

[[ -n "${CONFIG_FILE:-}" && ! -f "$CONFIG_FILE" ]] && \
    error_exit "SMTP config not found"

[[ -n "${EMAIL:-}" ]] && source "$CONFIG_FILE"

command -v docker >/dev/null || error_exit "Docker missing"
command -v rsync >/dev/null || error_exit "rsync required"
command -v curl >/dev/null || error_exit "curl missing"

mkdir -p "$REPORT_DIR"

OUTPUT_FILE="$REPORT_DIR/sast_$TIMESTAMP.txt"

# ========================
# SEVERITY HANDLING
# ========================
if [[ -z "$SEVERITY" ]]; then
    info "No severity specified → running full scan (ALL severities)"
else
    SEVERITY=$(echo "$SEVERITY" | tr '[:lower:]' '[:upper:]' | tr -d ' ')
    info "Requested severity: $SEVERITY"
fi

# ========================
# RETRY
# ========================
retry() {
    local c=0
    until "$@"; do
        ((c++))
        [[ $c -ge $RETRIES ]] && error_exit "Operation failed"
        warn "Retry $c/$RETRIES..."
        sleep 2
    done
}

# ========================
# PREP SCANNER
# ========================
info "Preparing scanner..."
retry docker pull "$DOCKER_IMAGE"

# ========================
# TARGET
# ========================
if [[ -n "${REPO_URL:-}" ]]; then
    SOURCE_DIR="/tmp/repo_$TIMESTAMP"
    info "Cloning repository..."
    retry git clone "$REPO_URL" "$SOURCE_DIR"
else
    SOURCE_DIR="$FILE_PATH"
    info "Using local directory: $SOURCE_DIR"
fi

# ========================
# SAFE COPY
# ========================
info "Creating isolated scan copy..."

rsync -a \
    --exclude 'venv' \
    --exclude '.venv' \
    --exclude 'node_modules' \
    --exclude '__pycache__' \
    --exclude '.git' \
    "$SOURCE_DIR/" "$WORK_TMP/"

# ========================
# RUN SCAN (RAW OUTPUT)
# ========================
info "Running scan (raw output)..."

retry docker run --rm -v "$WORK_TMP:/scan-dir" "$DOCKER_IMAGE" \
    sast scan /scan-dir > "$OUTPUT_FILE" 2>&1

# ========================
# REPORT STATUS
# ========================
echo "[+] Report saved: $OUTPUT_FILE"

# ========================
# EMAIL (OPTIONAL)
# ========================
if [[ -n "${EMAIL:-}" ]]; then
    info "Sending email..."

    retry bash -c "
    {
    echo \"From: $FROM_EMAIL\"
    echo \"To: $EMAIL\"
    echo \"Subject: Scan Report [$TIMESTAMP]\"
    echo \"\"
    cat \"$OUTPUT_FILE\"
    } | curl --url \"smtp://$SMTP_SERVER:$SMTP_PORT\" \
    --ssl-reqd \
    --mail-from \"$FROM_EMAIL\" \
    --mail-rcpt \"$EMAIL\" \
    --upload-file - \
    --user \"$SMTP_USER:$SMTP_PASS\"
    "

    info "Email sent"
else
    info "Skipping email"
fi

# ========================
# CLEANUP
# ========================
rm -rf "$WORK_TMP" 2>/dev/null || true
[[ -n "${REPO_URL:-}" ]] && rm -rf "$SOURCE_DIR"

# ========================
# FINAL
# ========================
echo "=========================================="
echo " Scan Completed Successfully ✅"
echo "=========================================="
