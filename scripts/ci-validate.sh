#!/bin/sh

set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${ROOT_DIR}"

log() {
    printf '[CI] %s\n' "$*"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf '[CI][ERROR] Required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

require_command docker
require_command sh

ENV_FILE=".env"
if [ ! -f "${ENV_FILE}" ]; then
    ENV_FILE=".env.example"
fi

log "Checking shell syntax..."
sh -n scripts/sync-entrypoint.sh
sh -n scripts/antigravity-entrypoint.sh

log "Validating required variables in .env.example..."
for var in \
    ANTIGRAVITY_MANAGER_HOST_PORT \
    ANTIGRAVITY_MANAGER_WEB_PASSWORD \
    ANTIGRAVITY_MANAGER_REMOTE \
    ANTIGRAVITY_MANAGER_REMOTE_PATH \
    ANTIGRAVITY_MANAGER_SYNC_INTERVAL_SECONDS \
    ANTIGRAVITY_MANAGER_S3_ENDPOINT \
    ANTIGRAVITY_MANAGER_S3_REGION \
    ANTIGRAVITY_MANAGER_S3_ACCESS_KEY_ID \
    ANTIGRAVITY_MANAGER_S3_SECRET_ACCESS_KEY
do
    if ! grep -q "^${var}=" .env.example; then
        printf '[CI][ERROR] Missing variable in .env.example: %s\n' "${var}" >&2
        exit 1
    fi
done

log "Validating docker compose config using ${ENV_FILE}..."
docker compose --env-file "${ENV_FILE}" config >/dev/null

log "All validations passed."
