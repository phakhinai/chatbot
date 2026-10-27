#!/usr/bin/env bash
source "$(dirname -- "$0")/common.sh"
ACTION=${2:?Use deploy or rollback}
lock_operation
load_state() {
  local state=$1 key value
  while IFS='=' read -r key value; do
    case "$key" in API_IMAGE|WEB_IMAGE|COMPOSE_FILE) export "$key=$value" ;; *) return 1 ;; esac
  done < "$state"
  [[ -f "$COMPOSE_FILE" ]] || { echo 'Saved release files are missing.' >&2; return 1; }
}
if [[ "$ACTION" == rollback ]]; then
  [[ -f "$STATE_DIR/previous.env" ]] || { echo 'No previous successful release.' >&2; exit 1; }
  cp "$STATE_DIR/current.env" "$STATE_DIR/rollback-from.env"
  load_state "$STATE_DIR/previous.env"
elif [[ "$ACTION" == deploy ]]; then
  export API_IMAGE=${3:?Provide API image digest/tag} WEB_IMAGE=${4:?Provide web image digest/tag}
else
  echo 'Use deploy or rollback' >&2; exit 1
fi
# Pull before touching running applications; a missing image leaves the current release intact.
compose config --quiet
compose pull --policy missing api web proxy postgres redis
if compose ps --status running --services | grep -qx postgres; then
  backup_data
fi
candidate=$(mktemp "$STATE_DIR/candidate.XXXXXX")
printf 'API_IMAGE=%s\nWEB_IMAGE=%s\nCOMPOSE_FILE=%s\n' "$API_IMAGE" "$WEB_IMAGE" "$COMPOSE_FILE" > "$candidate"
if compose up -d --wait --wait-timeout "${DEPLOY_WAIT_TIMEOUT:-180}" && verify_public; then
  if [[ "$ACTION" == rollback ]]; then
    cp "$STATE_DIR/rollback-from.env" "$STATE_DIR/previous.env"
  elif [[ -f "$STATE_DIR/current.env" ]]; then
    cp "$STATE_DIR/current.env" "$STATE_DIR/previous.env"
  fi
  mv "$candidate" "$STATE_DIR/current.env"
  echo 'Release healthy; deployment state saved.'
else
  echo 'Release failed; attempting previous successful configuration.' >&2
  if [[ -f "$STATE_DIR/current.env" ]]; then
    load_state "$STATE_DIR/current.env"
    compose up -d --wait --wait-timeout "${DEPLOY_WAIT_TIMEOUT:-180}" && verify_public || { echo 'Recovery failed; inspect Docker logs immediately.' >&2; exit 2; }
    echo 'Previous successful release restored.' >&2
  else
    echo 'First release failed; no previous release exists. Volumes preserved.' >&2
  fi
  exit 1
fi
