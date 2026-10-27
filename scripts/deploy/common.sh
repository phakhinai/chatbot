#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=$(realpath -- "${1:?Usage: script ENV_FILE ...}")
# Deliberately do not source dotenv as shell code. Use unquoted KEY=value entries.
while IFS= read -r line || [[ -n "$line" ]]; do
  line=${line%$'\r'}
  [[ -z "$line" || "$line" == \#* ]] && continue
  [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || { echo 'Invalid env syntax; use unquoted KEY=value' >&2; exit 1; }
  key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}
  case "$key" in
    COMPOSE_PROJECT_NAME|POSTGRES_USER|POSTGRES_DB|POSTGRES_PASSWORD|REDIS_PASSWORD|SITE_ADDRESS|WEB_ORIGIN|ACME_EMAIL|HTTP_BIND|HTTP_PORT|HTTPS_PORT|API_IMAGE|WEB_IMAGE|BACKUP_DIR) export "$key=$value" ;;
    *) echo "Unsupported production env key: $key" >&2; exit 1 ;;
  esac
done < "$ENV_FILE"
: "${COMPOSE_PROJECT_NAME:?}" "${BACKUP_DIR:?}" "${API_IMAGE:?}" "${WEB_IMAGE:?}"
[[ "$COMPOSE_PROJECT_NAME" =~ ^[a-z0-9][a-z0-9_-]+$ ]] || exit 1
[[ "${POSTGRES_PASSWORD:-}" =~ ^[a-fA-F0-9]{32,}$ && "${REDIS_PASSWORD:-}" =~ ^[a-fA-F0-9]{32,}$ ]] || { echo 'Use >=32 random hex characters for each production password.' >&2; exit 1; }
[[ "${POSTGRES_USER:-}" =~ ^[a-z_][a-z0-9_]*$ && "${POSTGRES_DB:-}" =~ ^[a-z_][a-z0-9_]*$ ]] || exit 1
STATE_DIR="$(dirname -- "$ENV_FILE")/.deploy-state/$COMPOSE_PROJECT_NAME"
mkdir -p -- "$STATE_DIR" "$BACKUP_DIR"
chmod 700 "$STATE_DIR" "$BACKUP_DIR"
COMPOSE_FILE="$ROOT/infra/compose.prod.yml"
compose() { docker compose --project-name "$COMPOSE_PROJECT_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"; }
lock_operation() { exec 9>"$STATE_DIR/operation.lock"; flock -n 9 || { echo 'Another deployment/backup is running.' >&2; exit 1; }; }
backup_data() {
  local dest
  dest=$(mktemp -d "$BACKUP_DIR/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
  compose exec -T postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$dest/postgres.dump"
  compose exec -T postgres pg_restore --list < "$dest/postgres.dump" > /dev/null
  compose exec -T redis sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli --rdb /tmp/rag-backup.rdb >/dev/null 2>&1 && redis-check-rdb /tmp/rag-backup.rdb >/dev/null'
  compose cp redis:/tmp/rag-backup.rdb "$dest/redis.rdb" > /dev/null
  (cd "$dest" && sha256sum postgres.dump redis.rdb > SHA256SUMS)
  printf '%s\n' "$dest"
}
# For HTTPS sites, verify via public HTTPS instead of following redirects on Docker DNS.
verify_public() {
  curl --fail --silent --show-error --max-time 30 "${WEB_ORIGIN}/api/health" | python3 -c 'import json,sys; assert json.load(sys.stdin)["status"] == "ok"' || return 1
  curl --fail --silent --show-error --max-time 30 "$WEB_ORIGIN" | python3 -c 'import sys; assert "Connected" in sys.stdin.read()'
}
