#!/bin/sh
# ==============================================================================
# RCLONE SYNC ENTRYPOINT SCRIPT
# ==============================================================================
# Nhiệm vụ:
# 1. Generate rclone config từ environment variables
# 2. Sync DOWN từ S3 về local (initial sync)
# 3. Tạo file cờ /shared/READY để báo antigravity container
# 4. Loop sync UP từ local lên S3 theo interval
#
# Exit codes:
#   0: thành công
#   1: lỗi generic
#   2: thiếu/invalid environment variables
#   3: rclone sync failed (sau khi retry)
# ==============================================================================

set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail

# ==============================================================================
# COLORS & LOGGING
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_error() {
    printf '%b[ERROR]%b %s - %s\n' "${RED}" "${NC}" "$(timestamp)" "$*"
}

# ==============================================================================
# VALIDATE ENVIRONMENT VARIABLES
# ==============================================================================
log_info "Validating environment variables..."

require_env() {
    var_name="$1"
    eval "var_value=\${$var_name:-}"
    if [ -z "${var_value}" ]; then
        log_error "Required environment variable '${var_name}' is not set"
        return 1
    fi
    return 0
}

missing_vars=0
for var in REMOTE REMOTE_PATH S3_ENDPOINT S3_REGION S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY; do
    if ! require_env "${var}"; then
        missing_vars=$((missing_vars + 1))
    fi
done

if [ "${missing_vars}" -gt 0 ]; then
    log_error "Missing ${missing_vars} required environment variable(s)"
    log_error "Please check your .env file"
    exit 2
fi

SYNC_INTERVAL_SECONDS="${SYNC_INTERVAL_SECONDS:-60}"
RCLONE_LOG_LEVEL="${RCLONE_LOG_LEVEL:-INFO}"
RCLONE_EXTRA_FLAGS="${RCLONE_EXTRA_FLAGS:-}"
MAX_RETRIES="${MAX_RETRIES:-5}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-5}"

case "${SYNC_INTERVAL_SECONDS}" in
    ''|*[!0-9]*)
        log_error "SYNC_INTERVAL_SECONDS must be a positive integer"
        exit 2
        ;;
esac

if [ "${SYNC_INTERVAL_SECONDS}" -le 0 ]; then
    log_error "SYNC_INTERVAL_SECONDS must be greater than 0"
    exit 2
fi

log_success "All required environment variables are set"
log_info "Remote: ${REMOTE}"
log_info "Remote path: ${REMOTE_PATH}"
log_info "Sync interval: ${SYNC_INTERVAL_SECONDS} seconds"
log_info "Log level: ${RCLONE_LOG_LEVEL}"

# ==============================================================================
# GENERATE RCLONE CONFIG
# ==============================================================================
log_info "Generating rclone configuration..."

mkdir -p /root/.config/rclone

cat > /root/.config/rclone/rclone.conf <<EOF
[${REMOTE}]
type = s3
provider = Other
endpoint = ${S3_ENDPOINT}
region = ${S3_REGION}
access_key_id = ${S3_ACCESS_KEY_ID}
secret_access_key = ${S3_SECRET_ACCESS_KEY}
acl = private
list_version = 2
disable_multipart_uploads = true
EOF

log_success "Rclone configuration generated"

if rclone config show "${REMOTE}" >/dev/null 2>&1; then
    log_success "Rclone config verified successfully"
else
    log_error "Rclone config verification failed"
    exit 1
fi

# ==============================================================================
# PREPARE LOCAL DATA DIRECTORY
# ==============================================================================
DATA_DIR="/data/.antigravity_tools"
mkdir -p "${DATA_DIR}"
log_success "Data directory ready: ${DATA_DIR}"

run_rclone_sync() {
    source_path="$1"
    destination_path="$2"

    if [ -n "${RCLONE_EXTRA_FLAGS}" ]; then
        # Intentionally allow splitting for extra CLI flags.
        # shellcheck disable=SC2086
        rclone sync \
            "${source_path}" \
            "${destination_path}" \
            --log-level="${RCLONE_LOG_LEVEL}" \
            --s3-list-version=2 \
            --verbose \
            --stats=10s \
            --stats-one-line \
            ${RCLONE_EXTRA_FLAGS}
    else
        rclone sync \
            "${source_path}" \
            "${destination_path}" \
            --log-level="${RCLONE_LOG_LEVEL}" \
            --s3-list-version=2 \
            --verbose \
            --stats=10s \
            --stats-one-line
    fi
}

retry_sync() {
    operation="$1"
    source_path="$2"
    destination_path="$3"
    attempt=1

    while [ "${attempt}" -le "${MAX_RETRIES}" ]; do
        if run_rclone_sync "${source_path}" "${destination_path}"; then
            log_success "${operation} completed (attempt ${attempt}/${MAX_RETRIES})"
            return 0
        fi

        if [ "${attempt}" -lt "${MAX_RETRIES}" ]; then
            log_warn "${operation} failed (attempt ${attempt}/${MAX_RETRIES}), retry in ${RETRY_DELAY_SECONDS}s..."
            sleep "${RETRY_DELAY_SECONDS}"
        fi

        attempt=$((attempt + 1))
    done

    log_error "${operation} failed after ${MAX_RETRIES} attempts"
    return 1
}

cleanup_ready_flag() {
    rm -f /shared/READY >/dev/null 2>&1 || true
}

trap cleanup_ready_flag INT TERM

# ==============================================================================
# INITIAL SYNC DOWN (S3 -> LOCAL)
# ==============================================================================
log_info "Starting initial sync DOWN from S3..."
if ! retry_sync "Initial sync DOWN" "${REMOTE}:${REMOTE_PATH}" "${DATA_DIR}"; then
    exit 3
fi

file_count="$(find "${DATA_DIR}" -type f 2>/dev/null | wc -l | tr -d ' ')"
log_info "Files in data directory: ${file_count}"

if [ "${file_count}" -eq 0 ]; then
    log_warn "No files found after sync DOWN - this may be first run or an empty bucket"
else
    log_success "Data synced successfully"
fi

# ==============================================================================
# CREATE READY FLAG
# ==============================================================================
mkdir -p /shared
printf '%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" > /shared/READY
log_success "READY flag created at /shared/READY"
log_success "Antigravity container can now start"

# ==============================================================================
# CONTINUOUS SYNC UP LOOP (LOCAL -> S3)
# ==============================================================================
log_info "Starting continuous sync UP loop..."
log_info "Sync interval: ${SYNC_INTERVAL_SECONDS} seconds"

sync_iteration=0
while :; do
    sync_iteration=$((sync_iteration + 1))
    log_info "===== Sync UP iteration #${sync_iteration} ====="

    if ! retry_sync "Sync UP iteration #${sync_iteration}" "${DATA_DIR}" "${REMOTE}:${REMOTE_PATH}"; then
        log_warn "Sync UP iteration #${sync_iteration} failed - retry in next interval"
    fi

    log_info "Waiting ${SYNC_INTERVAL_SECONDS} seconds until next sync..."
    sleep "${SYNC_INTERVAL_SECONDS}"
done
