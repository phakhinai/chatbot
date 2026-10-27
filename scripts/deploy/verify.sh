#!/usr/bin/env bash
source "$(dirname -- "$0")/common.sh"
compose ps
compose exec -T api node < "$ROOT/scripts/deploy/probe.cjs"
verify_public
echo 'PASS reverse proxy /api/health and frontend connected to backend.'
