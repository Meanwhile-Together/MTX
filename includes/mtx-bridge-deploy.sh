# shellcheck shell=bash
# Canonical master org host repo (normative basename). Override with MTX_BRIDGE_ORG_BASENAMES=comma,separated.
# Used by mtx deploy / apply / urls for master-lane secrets without MTX_ASADMIN or RUN_AS_MASTER.

mtx_deploy_resolve_project_root() {
  local root=""
  if [ -f "config/app.json" ] || [ -f "config/org.json" ]; then
    root="$(pwd)"
  fi
  if [ -z "$root" ] && { [ -f "../config/app.json" ] || [ -f "../config/org.json" ]; }; then
    root="$(cd .. && pwd)"
  fi
  if [ -z "$root" ]; then
    for d in . ..; do
      { [ -f "${d}/config/app.json" ] || [ -f "${d}/config/org.json" ]; } && root="$(cd "$d" && pwd)" && break
    done
  fi
  [ -z "$root" ] && root="$(pwd)"
  printf '%s' "$root"
}

# Returns 0 when this org tree is the canonical project-bridge host (master deploy lane).
mtx_deploy_is_org_project_bridge() {
  local root="${1:-}"
  [ -n "$root" ] || return 1
  local base slug
  base="$(basename "$root")"
  case ",${MTX_BRIDGE_ORG_BASENAMES:-org-project-bridge}," in
    *,"$base",*) return 0 ;;
  esac
  if [ -f "$root/config/org.json" ] && command -v jq >/dev/null 2>&1; then
    slug="$(jq -r '.org.slug // empty' "$root/config/org.json" 2>/dev/null || true)"
    slug="${slug//$'\r'/}"
    slug="${slug//$'\n'/}"
    [ -n "$slug" ] && [ "$slug" != "null" ] || slug=""
    case ",${MTX_BRIDGE_ORG_SLUGS:-project-bridge}," in
      *,"$slug",*) return 0 ;;
    esac
  fi
  return 1
}
