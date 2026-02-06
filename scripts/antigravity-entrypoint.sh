#!/bin/sh
# ==============================================================================
# ANTIGRAVITY ENTRYPOINT WRAPPER (OPTIONAL)
# ==============================================================================
# Script này là optional - chỉ cần nếu muốn thêm logic trước khi start antigravity
# Ví dụ: check READY flag, chờ database, validate config, etc.
# ==============================================================================

set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    printf '%b[INFO]%b %s - %s\n' "${BLUE}" "${NC}" "$(timestamp)" "$*"
}

log_success() {
    printf '%b[SUCCESS]%b %s - %s\n' "${GREEN}" "${NC}" "$(timestamp)" "$*"
}

log_warn() {
    printf '%b[WARN]%b %s - %s\n' "${YELLOW}" "${NC}" "$(timestamp)" "$*"
}

# ==============================================================================
# WAIT FOR READY FLAG
# ==============================================================================
log_info "Waiting for rclone-sync to complete initial sync..."

MAX_WAIT=300
elapsed=0

while [ ! -f /shared/READY ]; do
    if [ "${elapsed}" -ge "${MAX_WAIT}" ]; then
        log_warn "Timeout waiting for READY flag, starting anyway..."
        break
    fi

    sleep 2
    elapsed=$((elapsed + 2))

    if [ $((elapsed % 10)) -eq 0 ]; then
        log_info "Still waiting... (${elapsed}s elapsed)"
    fi
done

if [ -f /shared/READY ]; then
    ready_time="$(cat /shared/READY 2>/dev/null || echo unknown)"
    log_success "READY flag detected (created at: ${ready_time})"
else
    log_warn "Starting without READY flag confirmation"
fi

# ==============================================================================
# VALIDATE DATA DIRECTORY
# ==============================================================================
DATA_DIR="/root/.antigravity_tools"

if [ ! -d "${DATA_DIR}" ]; then
    log_warn "Data directory does not exist, creating: ${DATA_DIR}"
    mkdir -p "${DATA_DIR}"
fi

file_count="$(find "${DATA_DIR}" -type f 2>/dev/null | wc -l | tr -d ' ')"
log_info "Files in data directory: ${file_count}"

# ==============================================================================
# START ANTIGRAVITY
# ==============================================================================
log_success "Starting Antigravity Manager..."
exec "$@"
