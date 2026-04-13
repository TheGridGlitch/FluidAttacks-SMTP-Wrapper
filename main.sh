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
  --severity <levels>   (LOW,MEDIUM,HIGH,CRITICAL — comma-separated)
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
info()       { echo "[+] $1"; }
warn()       { echo "[!] $1"; }
error_exit() { echo "[❌ ERROR] $1"; exit 1; }

# ========================
# ARGS
# ========================
[[ "$#" -eq 0 ]] && { show_help; exit 0; }

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --repo)      REPO_URL="$2";    shift ;;
    --file-path) FILE_PATH="$2";   shift ;;
    --email)     EMAIL="$2";       shift ;;
    --config)    CONFIG_FILE="$2"; shift ;;
    --severity)  SEVERITY="$2";    shift ;;
    --retries)   RETRIES="$2";     shift ;;
    -h|--help)   show_help; exit 0 ;;
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

if [[ -n "${EMAIL:-}" ]]; then
  [[ "$EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]] || error_exit "Invalid email format: $EMAIL"
fi

if [[ -n "${EMAIL:-}" && -z "${CONFIG_FILE:-}" ]]; then
  error_exit "--config required when using email"
fi

[[ -n "${CONFIG_FILE:-}" && ! -f "$CONFIG_FILE" ]] && \
  error_exit "SMTP config not found"

# ========================
# SAFE CONFIG PARSER
# ========================
if [[ -n "${EMAIL:-}" ]]; then
  while IFS='=' read -r key value; do
    [[ -z "${key// }" || "$key" =~ ^[[:space:]]*# ]] && continue

    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    value="${value:-}"
    value="${value#"${value%%[![:space:]]*}"}"

    if [[ "$value" =~ ^\".*\"$ ]]; then
      value="${value:1:-1}"
    elif [[ "$value" =~ ^\'.*\'$ ]]; then
      value="${value:1:-1}"
    fi

    case "$key" in
      SMTP_SERVER) SMTP_SERVER="$value" ;;
      SMTP_PORT)   SMTP_PORT="$value" ;;
      SMTP_USER)   SMTP_USER="$value" ;;
      SMTP_PASS)   SMTP_PASS="$value" ;;
      FROM_EMAIL)  FROM_EMAIL="$value" ;;
    esac
  done < "$CONFIG_FILE"
fi

command -v docker >/dev/null || error_exit "Docker missing"
command -v rsync  >/dev/null || error_exit "rsync required"
command -v curl   >/dev/null || error_exit "curl missing"
command -v base64 >/dev/null || error_exit "base64 required"

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
    ((c++)) || true
    [[ $c -ge $RETRIES ]] && error_exit "Operation failed after $RETRIES retries"
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
  --exclude 'venv'        \
  --exclude '.venv'       \
  --exclude 'node_modules'\
  --exclude '__pycache__' \
  --exclude '.git'        \
  "$SOURCE_DIR/" "$WORK_TMP/"

# ========================
# RUN SCAN (RAW OUTPUT)
# ========================
info "Running scan (raw output)..."

SEVERITY_FLAG=""
[[ -n "$SEVERITY" ]] && SEVERITY_FLAG="--severity $SEVERITY"

retry docker run --rm -v "$WORK_TMP:/scan-dir" "$DOCKER_IMAGE" \
  sast scan /scan-dir $SEVERITY_FLAG > "$OUTPUT_FILE" 2>&1

# ========================
# REPORT STATUS
# ========================
[[ -s "$OUTPUT_FILE" ]] || warn "Report is empty — scan may have failed silently"
echo "[+] Report saved: $OUTPUT_FILE"

# ========================
# EMAIL (ATTACHMENT - FINAL FIXED)
# ========================
send_email() {
  local subject="Scan Report [$TIMESTAMP]"
  local attachment="$OUTPUT_FILE"

  info "Preparing email with attachment..."

  EMAIL_TMP=$(mktemp)
  BOUNDARY="====BOUNDARY_$(date +%s)===="

  {
    echo "From: $FROM_EMAIL"
    echo "To: $EMAIL"
    echo "Subject: $subject"
    echo "MIME-Version: 1.0"
    echo "Content-Type: multipart/mixed; boundary=\"$BOUNDARY\""
    echo ""

    echo "--$BOUNDARY"
    echo "Content-Type: text/plain; charset=UTF-8"
    echo ""
    echo "Hi,"
    echo ""
    echo "Please find the attached scan report."
    echo ""
    echo "Generated: $TIMESTAMP"
    echo ""

    echo "--$BOUNDARY"
    echo "Content-Type: application/octet-stream; name=\"$(basename "$attachment")\""
    echo "Content-Disposition: attachment; filename=\"$(basename "$attachment")\""
    echo "Content-Transfer-Encoding: base64"
    echo ""

    base64 -w 76 "$attachment"

    echo ""
    echo "--$BOUNDARY--"
  } > "$EMAIL_TMP"

  info "Sending email via SMTP..."

  curl --fail --show-error \
    --url "smtp://$SMTP_SERVER:$SMTP_PORT" \
    --ssl-reqd \
    --mail-from "$FROM_EMAIL" \
    --mail-rcpt "$EMAIL" \
    --upload-file "$EMAIL_TMP" \
    --user "$SMTP_USER:$SMTP_PASS"

  rm -f "$EMAIL_TMP"
}

if [[ -n "${EMAIL:-}" ]]; then
  retry send_email
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
