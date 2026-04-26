#!/bin/bash
#
# mtx master provision-tenant
#
# Provision a new tenant in the App Bridge Federation registry on the master
# host (rule-of-law §1 2026-04-25 per-tenant tenantSecret). Generates a fresh
# 32-byte hex `tenantSecret`, inserts (or upserts) the `tenant_registry` row,
# and prints the secret to stdout exactly once. The operator is expected to
# paste the secret into the tenant's `TENANT_SECRET` env var (Railway dash,
# .env file, etc.) — it is NEVER stored on disk.
#
# Used by:
#   - Operator first-time onboarding of a tenant (no heartbeat yet).
#   - Re-provisioning after secret rotation (re-run, paste new secret into
#     tenant env, redeploy tenant).
#
# Usage:
#   mtx master provision-tenant <orgSlug> <baseUrl> [railwayServiceId]
#     <orgSlug>          — canonical tenant id (matches `config/org.json#org.slug`)
#     <baseUrl>          — public https URL of the tenant (no trailing slash)
#     [railwayServiceId] — optional Railway service UUID for fleet audit join
#
# Exit codes:
#   0 — row provisioned (insert or update); secret printed to stdout
#   1 — bad usage
#   2 — no DB URL (workspace prepare / env / --env-file / legacy .env)
#   3 — psql or openssl missing
#   4 — psql command failed
#
desc="Provision a tenant: generate tenantSecret, upsert tenant_registry row, print secret."

set -euo pipefail

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# shellcheck source=../includes/prepare-env.sh
source "$MTX_ROOT/includes/prepare-env.sh"

env_file_arg=""
remaining=()
while [ $# -gt 0 ]; do
  if [ "$1" = "--env-file" ] && [ -n "${2:-}" ]; then
    env_file_arg="$2"
    shift 2
  else
    remaining+=("$1")
    shift
  fi
done
if [ ${#remaining[@]} -gt 0 ]; then
  set -- "${remaining[@]}"
else
  set --
fi

org_slug="${1:-}"
base_url="${2:-}"
railway_service_id="${3:-}"

if [ -z "$org_slug" ] || [ -z "$base_url" ]; then
  echo "Usage: mtx master provision-tenant [--env-file <path>] <orgSlug> <baseUrl> [railwayServiceId]" >&2
  echo "  orgSlug must match the tenant's config/org.json#org.slug" >&2
  echo "  baseUrl must be the tenant's public https URL (no trailing slash)" >&2
  echo "  DB: workspace .mtx.prepare.env (MASTER_DATABASE_URL) or --env-file or export or legacy .env" >&2
  exit 1
fi

# Sanity check the baseUrl up-front so the operator gets a clear error rather
# than a heartbeat reject later. Master enforces the same rule on heartbeat.
case "$base_url" in
  https://*) ;;
  *)
    echo "[provision-tenant] baseUrl must be https://. Got: $base_url" >&2
    exit 1
    ;;
esac

# Reject credentials in URL — federation traffic must use Authorization headers.
case "$base_url" in
  *"@"*)
    echo "[provision-tenant] baseUrl must not contain credentials (no '@'). Got: $base_url" >&2
    exit 1
    ;;
esac

pluck() {
  local key="$1" file="$2"
  [ -f "$file" ] || return 0
  grep -E "^${key}=" "$file" | head -n1 | sed -E "s/^${key}=//; s/^\"(.*)\"\$/\\1/; s/^'(.*)'\$/\\1/"
}

APP_DB=""
if [ -n "$env_file_arg" ]; then
  if [ ! -f "$env_file_arg" ]; then
    echo "[provision-tenant] --env-file not found: $env_file_arg" >&2
    exit 2
  fi
  APP_DB=$(pluck MASTER_DATABASE_URL "$env_file_arg")
  [ -z "$APP_DB" ] && APP_DB=$(pluck DATABASE_URL "$env_file_arg")
else
  if [ -n "${MASTER_DATABASE_URL:-}" ]; then
    APP_DB="${MASTER_DATABASE_URL}"
  elif [ -n "${DATABASE_URL:-}" ]; then
    APP_DB="${DATABASE_URL}"
  fi
  if [ -z "$APP_DB" ]; then
    mtx_source_prepare_file_from_cwd "$(pwd)" || true
    if [ -n "${MASTER_DATABASE_URL:-}" ]; then
      APP_DB="${MASTER_DATABASE_URL}"
    elif [ -n "${DATABASE_URL:-}" ]; then
      APP_DB="${DATABASE_URL}"
    fi
  fi
  if [ -z "$APP_DB" ]; then
    for candidate in "./.env" "./master/.env" "../.env"; do
      if [ -f "$candidate" ]; then
        env_file_arg="$candidate"
        break
      fi
    done
  fi
  if [ -z "$APP_DB" ] && [ -n "$env_file_arg" ]; then
    APP_DB=$(pluck MASTER_DATABASE_URL "$env_file_arg")
    [ -z "$APP_DB" ] && APP_DB=$(pluck DATABASE_URL "$env_file_arg")
  fi
fi

if [ -z "$APP_DB" ]; then
  echo "[provision-tenant] Set MASTER_DATABASE_URL in .mtx.prepare.env (mtx prepare), or export DATABASE_URL, or use --env-file, or a legacy .env in cwd." >&2
  exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "[provision-tenant] psql is required but not installed." >&2
  exit 3
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "[provision-tenant] openssl is required but not installed." >&2
  exit 3
fi

# 32 bytes = 64 hex chars. HS256 takes any byte length but 32 bytes matches
# the algorithm's recommended key size.
tenant_secret=$(openssl rand -hex 32)

# Upsert: idempotent re-run on the same slug rotates the secret. The unique
# constraint on `orgSlug` (the @id) makes this safe; we deliberately do NOT
# overwrite `firstSeenAt` so the registry preserves provenance.
psql "$APP_DB" -v ON_ERROR_STOP=1 <<SQL
INSERT INTO "tenant_registry" (
  "orgSlug", "baseUrl", "railwayServiceId", "tenantSecret",
  "lastHeartbeatAt", "firstSeenAt"
)
VALUES (
  '$org_slug',
  '$base_url',
  $( [ -n "$railway_service_id" ] && echo "'$railway_service_id'" || echo "NULL" ),
  '$tenant_secret',
  '1970-01-01T00:00:00Z',
  NOW()
)
ON CONFLICT ("orgSlug") DO UPDATE SET
  "baseUrl" = EXCLUDED."baseUrl",
  "railwayServiceId" = EXCLUDED."railwayServiceId",
  "tenantSecret" = EXCLUDED."tenantSecret";
SQL

echo
echo "[provision-tenant] OK — tenant '$org_slug' provisioned at $base_url"
echo
echo "Paste this secret into the tenant's environment (NEVER commit, NEVER print again):"
echo
echo "  TENANT_SECRET=$tenant_secret"
echo
echo "Also ensure the tenant has:"
echo "  MASTER_BASE_URL=<this master's public url>"
echo
