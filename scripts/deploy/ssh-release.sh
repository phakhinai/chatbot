#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
: "${VPS_HOST:?}" "${VPS_USER:?}" "${SSH_PRIVATE_KEY:?}" "${SSH_KNOWN_HOSTS:?}" "${GITHUB_SHA:?}" "${API_IMAGE:?}" "${WEB_IMAGE:?}" "${RUNNER_TEMP:?}"
[[ "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]] || exit 1
[[ "$VPS_HOST" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ && "$VPS_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || exit 1
[[ "${VPS_PORT:-22}" =~ ^[0-9]{1,5}$ ]] || exit 1
for image in "$API_IMAGE" "$WEB_IMAGE"; do
  [[ "$image" =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]] || { echo 'Expected immutable GHCR digest.' >&2; exit 1; }
done
key="$RUNNER_TEMP/rag-deploy-key"
known="$RUNNER_TEMP/rag-known-hosts"
printf '%s\n' "$SSH_PRIVATE_KEY" > "$key"
printf '%s\n' "$SSH_KNOWN_HOSTS" > "$known"
chmod 600 "$key" "$known"
ssh_args=(-i "$key" -p "${VPS_PORT:-22}" -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known")
target="$VPS_USER@$VPS_HOST"
release="/opt/rag-chatbot/releases/$GITHUB_SHA"
# Archive includes no .env, credentials, dependencies, or database data.
tar -czf - infra scripts/deploy .env.production.example | ssh "${ssh_args[@]}" "$target" "mkdir -p '$release' && tar -xzf - -C '$release'"
ssh "${ssh_args[@]}" "$target" "bash '$release/scripts/deploy/release.sh' /opt/rag-chatbot/.env.production deploy '$API_IMAGE' '$WEB_IMAGE'"
