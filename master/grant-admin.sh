#!/bin/bash
#
# mtx master grant-admin
#
# Promote an existing master backend_user to a host/scope/role UserRole grant
# on the master's app database. Used when the primordial auto-grant didn't
# fire (pre-2026-04-24 deployment) or when a second platform-admin is needed.
#
# Usage:
#   mtx master grant-admin <email> [scope] [role]
#     <email>   — the backend_users.email of the target account on master
#     scope     — default `host` (platform-wide). Also accepts `org:<slug>`
#                 or `payload:<slug>` if an operator wants a narrower grant.
#     role      — default `admin`. Also accepts `investor`.
#
# Database URLs: platform singleton — read from $MTX_WORKSPACE_ROOT/.mtx.prepare.env
# (MASTER_DATABASE_URL, optional MASTER_BACKEND_DATABASE_URL) via mtx prepare; or from
# exported env; or --env-file; legacy: first of ./.env in cwd.
#
# Exit codes:
#   0 — grant succeeded (or already existed)
#   1 — bad usage / missing email
#   2 — could not locate/read master env
#   3 — target email not found in backend_users (register on master first)
#   4 — psql command failed
#
desc="Grant an existing master admin a UserRole (host/org/payload scope)."

set -euo pipefail

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# shellcheck source=../includes/prepare-env.sh
source "$MTX_ROOT/includes/prepare-env.sh"

env_file=""
remaining=()
while [ $# -gt 0 ]; do
  if [ "$1" = "--env-file" ] && [ -n "${2:-}" ]; then
    env_file="$2"
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

email="${1:-}"
scope="${2:-host}"
role="${3:-admin}"

if [ -z "$email" ]; then
  echo "Usage: mtx master grant-admin [--env-file <path>] <email> [scope] [role]" >&2
  echo "  scope defaults to 'host'; role defaults to 'admin'." >&2
  echo "  DB URLs: workspace .mtx.prepare.env (MASTER_*), export, or --env-file; legacy: cwd .env" >&2
  exit 1
fi

pluck() {
  local key="$1" file="$2"
  [ -f "$file" ] || return 0
  grep -E "^${key}=" "$file" | head -n1 | sed -E "s/^${key}=//; s/^\"(.*)\"\$/\\1/; s/^'(.*)'\$/\\1/"
}

APP_DB=""
BACKEND_DB=""

if [ -n "$env_file" ]; then
  if [ ! -f "$env_file" ]; then
    echo "[grant-admin] --env-file not found: $env_file" >&2
    exit 2
  fi
  APP_DB=$(pluck MASTER_DATABASE_URL "$env_file")
  [ -z "$APP_DB" ] && APP_DB=$(pluck DATABASE_URL "$env_file")
  BACKEND_DB=$(pluck MASTER_BACKEND_DATABASE_URL "$env_file")
  [ -z "$BACKEND_DB" ] && BACKEND_DB=$(pluck BACKEND_DATABASE_URL "$env_file")
  BACKEND_DB="${BACKEND_DB:-$APP_DB}"
else
  # Exported (CI) or already in shell
  if [ -n "${MASTER_DATABASE_URL:-}" ]; then
    APP_DB="${MASTER_DATABASE_URL}"
  elif [ -n "${DATABASE_URL:-}" ]; then
    APP_DB="${DATABASE_URL}"
  fi
  if [ -n "${MASTER_BACKEND_DATABASE_URL:-}" ]; then
    BACKEND_DB="${MASTER_BACKEND_DATABASE_URL}"
  elif [ -n "${BACKEND_DATABASE_URL:-}" ]; then
    BACKEND_DB="${BACKEND_DATABASE_URL}"
  fi
  if [ -z "$APP_DB" ] && mtx_source_prepare_file_from_cwd "$(pwd)"; then
    if [ -n "${MASTER_DATABASE_URL:-}" ]; then
      APP_DB="${MASTER_DATABASE_URL}"
    elif [ -n "${DATABASE_URL:-}" ]; then
      APP_DB="${DATABASE_URL}"
    fi
    if [ -n "${MASTER_BACKEND_DATABASE_URL:-}" ]; then
      BACKEND_DB="${MASTER_BACKEND_DATABASE_URL}"
    elif [ -n "${BACKEND_DATABASE_URL:-}" ]; then
      BACKEND_DB="${BACKEND_DATABASE_URL}"
    fi
  fi
  BACKEND_DB="${BACKEND_DB:-$APP_DB}"
  if [ -z "$APP_DB" ]; then
    for candidate in "./.env" "./master/.env" "../.env"; do
      if [ -f "$candidate" ]; then
        env_file="$candidate"
        break
      fi
    done
  fi
  if [ -z "$APP_DB" ] && [ -n "$env_file" ]; then
    APP_DB=$(pluck MASTER_DATABASE_URL "$env_file")
    [ -z "$APP_DB" ] && APP_DB=$(pluck DATABASE_URL "$env_file")
    BACKEND_DB=$(pluck MASTER_BACKEND_DATABASE_URL "$env_file")
    [ -z "$BACKEND_DB" ] && BACKEND_DB=$(pluck BACKEND_DATABASE_URL "$env_file")
    BACKEND_DB="${BACKEND_DB:-$APP_DB}"
  fi
fi

if [ -z "$APP_DB" ] || [ -z "$BACKEND_DB" ]; then
  echo "[grant-admin] Set MASTER_DATABASE_URL in workspace .mtx.prepare.env (mtx prepare), or export DATABASE_URL, or use --env-file, or a legacy .env in cwd." >&2
  exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "[grant-admin] psql is required but not installed." >&2
  exit 4
fi

# Look up the target's backend_users.id so we can build the compound primitive id.
user_id=$(psql "$BACKEND_DB" -t -A -c "SELECT id FROM backend_users WHERE email = '$email' LIMIT 1;" 2>/dev/null || true)
user_id=$(echo "$user_id" | tr -d '[:space:]')

if [ -z "$user_id" ]; then
  echo "[grant-admin] No backend_users row for '$email'. Register on master first." >&2
  exit 3
fi

primitive_id="master:$user_id"

# Idempotent upsert — relies on the UserRole composite primary key
# (primitiveId, scope, role). ON CONFLICT DO NOTHING keeps re-runs safe.
psql "$APP_DB" -v ON_ERROR_STOP=1 <<SQL
INSERT INTO "user_roles" ("primitiveId", "scope", "role", "grantedBy", "grantedAt")
VALUES ('$primitive_id', '$scope', '$role', NULL, NOW())
ON CONFLICT ("primitiveId", "scope", "role") DO NOTHING;
SQL

echo "[grant-admin] granted $role on $scope to $email ($primitive_id)"
