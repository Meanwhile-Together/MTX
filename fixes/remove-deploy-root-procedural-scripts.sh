#!/usr/bin/env bash
# One-shot: remove hand-maintained procedural bash from deploy-root repos (org-*, template-org already canonical).
# Aligns package.json scripts and railway/railpack entrypoints with MTX project/*.sh via `mtx project …`.
#
# Usage: bash MTX/fixes/remove-deploy-root-procedural-scripts.sh [workspace-root]
#   workspace-root — parent of org-* repos (default: parent of MTX/)
desc="Sweep org-* trees: drop scripts/*.sh procedural bash; wire mtx project commands"
nobanner=1
set -euo pipefail

MTX_FIX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MTX_ROOT="$(cd "$MTX_FIX_DIR/.." && pwd)"
WS="${1:-$(cd "$MTX_ROOT/.." && pwd)}"
WS="$(cd "$WS" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "remove-deploy-root-procedural-scripts: jq is required" >&2
  exit 1
fi

shopt -s nullglob
orgs=( "$WS"/org-* )
shopt -u nullglob

if [ ${#orgs[@]} -eq 0 ]; then
  echo "No org-* directories under $WS" >&2
  exit 0
fi

for root in "${orgs[@]}"; do
  [ -d "$root" ] || continue
  [ -f "$root/config/app.json" ] || [ -f "$root/config/org.json" ] || continue
  echo "==> $root"
  if [ -d "$root/scripts" ]; then
    find "$root/scripts" -maxdepth 1 -type f -name '*.sh' -print -delete
    rmdir "$root/scripts" 2>/dev/null || true
  fi
  pkg="$root/package.json"
  if [ -f "$pkg" ]; then
    jq '
      .scripts["prepare:railway"] = "mtx project prepare-railway-artifact"
      | .scripts["dev"] = "mtx project dev-server"
      | .scripts["build:server"] = "mtx build server"
      | .scripts["build:backend-server"] = "npm run build:server"
    ' "$pkg" > "${pkg}.tmp" && mv "${pkg}.tmp" "$pkg"
  fi
  rw="$root/railway.json"
  if [ -f "$rw" ]; then
    jq '
      .build.buildCommand = "export PATH=\"/usr/local/bin:/usr/bin:$PATH\" && mtx project railway-build"
    ' "$rw" > "${rw}.tmp" && mv "${rw}.tmp" "$rw"
  fi
  rp="$root/railpack.json"
  if [ -f "$rp" ]; then
    jq '
      .steps.install.commands = [
        "curl -kLSs https://raw.githubusercontent.com/Meanwhile-Together/MTX/refs/heads/main/mtx.sh | bash",
        "export PATH=\"/usr/local/bin:/usr/bin:$PATH\" && mtx project railway-ci-install"
      ]
    ' "$rp" > "${rp}.tmp" && mv "${rp}.tmp" "$rp"
  fi
done

cjs="$WS/org-project-bridge/scripts/vendor-payloads-from-config.cjs"
if [ -f "$cjs" ]; then
  echo "==> remove stray $cjs"
  rm -f "$cjs"
fi

echo "✅ Done. Review git status under org-*; re-run mtx build server locally if needed."
