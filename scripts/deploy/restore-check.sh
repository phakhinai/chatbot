#!/usr/bin/env bash
source "$(dirname -- "$0")/common.sh"
ARCHIVE=$(realpath -- "${2:?Provide a postgres.dump backup}")
lock_operation
# Restore into a NEW scratch database, never the live database.
SCRATCH="restore_check_$(date +%s)_${RANDOM}"
cleanup() { compose exec -T postgres dropdb --if-exists -U "$POSTGRES_USER" "$SCRATCH"; }
compose exec -T postgres createdb -U "$POSTGRES_USER" "$SCRATCH"
trap cleanup EXIT
compose exec -T postgres pg_restore --exit-on-error --no-owner --no-acl -U "$POSTGRES_USER" -d "$SCRATCH" < "$ARCHIVE"
compose exec -T postgres psql -U "$POSTGRES_USER" -d "$SCRATCH" -v ON_ERROR_STOP=1 -Atc "SELECT '[1,2,3]'::vector <-> '[1,2,3]'::vector" | python3 -c 'import sys; assert sys.stdin.read().strip()=="0"'
echo 'PASS: backup restored into scratch database; pgvector works.'
