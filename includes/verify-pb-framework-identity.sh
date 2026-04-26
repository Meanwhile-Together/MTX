#!/usr/bin/env bash
# Require project-bridge (framework) config/org.json to be the template-org placeholder
# (org.slug=org-host). Sourced from MTX build.sh, deploy/terraform/apply.sh, etc.
# Canonical checker: $PB/scripts/verify-framework-org-identity.sh in a project-bridge checkout.
# See project-bridge/docs/rule-of-law.md §1 2026-04-27.
#
# Usage: source this file, then:
#   mtx_verify_project_bridge_identity_for_build_context "$PROJECT_ROOT" "$MTX_ROOT"
# Exits the shell with 1 on failure (caller should use: ... || exit 1).

mtx_verify_project_bridge_identity_for_build_context() {
  local project_root="${1:-}"
  local mtx_root="${2:-}"
  if [ -z "$project_root" ] || [ -z "$mtx_root" ]; then
    return 0
  fi

  local vscript pb

  # Building inside project-bridge itself (package name projectb)
  if [ -f "$project_root/package.json" ] && grep -qE '"name"[[:space:]]*:[[:space:]]*"projectb"' "$project_root/package.json" 2>/dev/null; then
    vscript="$project_root/scripts/verify-framework-org-identity.sh"
    if [ ! -f "$vscript" ]; then
      echo "❌ project-bridge missing scripts/verify-framework-org-identity.sh at $vscript" >&2
      return 1
    fi
    echo "ℹ️  Verifying project-bridge framework org identity (placeholder org.json)…" >&2
    ( PROJECT_BRIDGE_ROOT="$project_root" bash "$vscript" ) || return 1
    return 0
  fi

  # Org host: config/app.json + resolvable project-bridge (same contract as mtx build server)
  if [ ! -f "$project_root/config/app.json" ]; then
    return 0
  fi

  pb=""
  if [ -n "${PROJECT_BRIDGE_ROOT:-}" ] && [ -f "${PROJECT_BRIDGE_ROOT}/package.json" ]; then
    pb="$(cd "${PROJECT_BRIDGE_ROOT}" && pwd)"
  else
    for vscript in "$project_root/vendor/project-bridge" "$project_root/../project-bridge"; do
      if [ -f "$vscript/package.json" ]; then
        pb="$(cd "$vscript" && pwd)"
        break
      fi
    done
  fi
  if [ -z "$pb" ]; then
    echo "❌ org repo has config/app.json but project-bridge not found (../project-bridge, vendor/project-bridge, or PROJECT_BRIDGE_ROOT)." >&2
    return 1
  fi
  vscript="$pb/scripts/verify-framework-org-identity.sh"
  if [ ! -f "$vscript" ]; then
    echo "❌ Missing $vscript" >&2
    return 1
  fi
  echo "ℹ️  Verifying project-bridge framework org identity at $pb (placeholder org.json)…" >&2
  ( PROJECT_BRIDGE_ROOT="$pb" bash "$vscript" ) || {
    echo "❌ Sibling project-bridge config/org.json is not the framework placeholder. Fix the project-bridge repo (see rule-of-law §1) — snapshot/restore in org-build-server re-applies the last committed state." >&2
    return 1
  }
  return 0
}
