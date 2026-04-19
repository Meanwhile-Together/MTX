#!/usr/bin/env bash
# Compare project-bridge/terraform to a cached digest on the org host; re-vendor when the
# canonical tree changed since the last mtx deploy (digest written after successful terraform apply)
# or when the operator opts in. See MTX build.sh and deploy/terraform/apply.sh.
#
# Usage:
#   bash .../vendor-terraform-from-bridge.sh [--sync-mode=auto|prompt] [--revendor] <project_root>
#   bash .../vendor-terraform-from-bridge.sh --write-digest <project_root>
#
# --sync-mode=prompt (deploy default when stdin is a TTY): on drift, ask upgrade vs skip (default skip).
# --sync-mode=auto: on drift, rsync immediately (mtx build / non-interactive deploy).
# --revendor: force rsync from bridge when not pinned (no prompt). Ignored when terraform is pinned.
# Env: MTX_VENDOR_TERRAFORM_MODE=auto|prompt — default before argv; explicit --sync-mode= wins.
#
# Pin: .mtx-vendor.pinned at project root — see lib/mtx-vendor-pinned.sh
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=mtx-vendor-pinned.sh
[ -f "$LIB_DIR/mtx-vendor-pinned.sh" ] && source "$LIB_DIR/mtx-vendor-pinned.sh"

MTX_VENDOR_TF_WRITE_DIGEST=0
MTX_VENDOR_TF_REVENDOR=0
SYNC_MODE="${MTX_VENDOR_TERRAFORM_MODE:-auto}"
PROJECT_ROOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --write-digest)
      MTX_VENDOR_TF_WRITE_DIGEST=1
      shift
      ;;
    --revendor)
      MTX_VENDOR_TF_REVENDOR=1
      shift
      ;;
    --sync-mode=auto|--sync-mode=prompt)
      SYNC_MODE="${1#--sync-mode=}"
      shift
      ;;
    --sync-mode=*)
      echo "vendor-terraform-from-bridge: unknown --sync-mode (use auto or prompt): $1" >&2
      exit 1
      ;;
    -*)
      echo "vendor-terraform-from-bridge: unknown option: $1" >&2
      exit 1
      ;;
    *)
      PROJECT_ROOT="$1"
      shift
      ;;
  esac
done

case "$SYNC_MODE" in auto|prompt) ;; *)
  echo "vendor-terraform-from-bridge: MTX_VENDOR_TERRAFORM_MODE / --sync-mode must be auto or prompt (got: $SYNC_MODE)" >&2
  exit 1
  ;;
esac

PROJECT_ROOT="${PROJECT_ROOT:?project root (directory with config/app.json)}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

mtx_resolve_bridge_terraform_src() {
  local root="$1"
  if [ -n "${PROJECT_BRIDGE_ROOT:-}" ] && [ -f "${PROJECT_BRIDGE_ROOT}/terraform/main.tf" ]; then
    echo "$(cd "${PROJECT_BRIDGE_ROOT}/terraform" && pwd)"
    return 0
  fi
  local cand
  for cand in "$root/vendor/project-bridge/terraform" "$root/../project-bridge/terraform"; do
    if [ -f "$cand/main.tf" ]; then
      echo "$(cd "$cand" && pwd)"
      return 0
    fi
  done
  return 1
}

mtx_hash_bridge_terraform() {
  local src="${1:?}"
  [ -d "$src" ] || return 1
  (cd "$src" && find . -type f \
    ! -path './.terraform/*' \
    ! -name '.terraform.lock.hcl' \
    ! -name 'terraform.tfstate' \
    ! -name '*.backup' \
    \( -name '*.tf' -o -name 'apply.sh' -o -name '*.tfvars.example' -o -name 'terraform.tfvars.example' \) \
    -print \
    | LC_ALL=C sort \
    | xargs -r sha256sum 2>/dev/null \
    | sha256sum \
    | awk '{print $1}')
}

mtx_rsync_bridge_terraform() {
  local src="$1"
  local dest="$2"
  mkdir -p "$dest"
  if command -v rsync &>/dev/null; then
    rsync -a \
      --exclude='.terraform' \
      --exclude='.terraform.lock.hcl' \
      --exclude='terraform.tfstate' \
      --exclude='terraform.tfstate.*' \
      --exclude='*.backup' \
      "$src/" "$dest/"
  else
    cp -a "$src/." "$dest/"
    rm -rf "$dest/.terraform" 2>/dev/null || true
    rm -f "$dest/terraform.tfstate" "$dest"/terraform.tfstate.* 2>/dev/null || true
  fi
  rm -f "$dest/.terraform.lock.hcl" 2>/dev/null || true
}

DIGEST_REL=".mtx-bridge-terraform.sha256"

mtx_vendor_terraform_dest_is_bridge() {
  local root="$1"
  local src dest
  if ! src="$(mtx_resolve_bridge_terraform_src "$root")"; then
    return 1
  fi
  [ -d "$root/terraform" ] || return 1
  dest="$(cd "$root/terraform" && pwd)"
  [ "$src" = "$dest" ]
}

mtx_vendor_warn_terraform_pin_metadata() {
  local root="$1"
  local md br src cur_g cur_c eg ec resolved_full
  md=""
  if declare -F mtx_vendor_pin_metadata_for_key &>/dev/null; then
    md="$(mtx_vendor_pin_metadata_for_key "$root" terraform 2>/dev/null || true)"
  fi
  [ -n "$md" ] || return 0
  eg="${md%%|*}"
  ec="${md#*|}"
  if ! src="$(mtx_resolve_bridge_terraform_src "$root")"; then
    return 0
  fi
  br="$(dirname "$src")"
  cur_g="$(git -C "$br" rev-parse HEAD 2>/dev/null || true)"
  cur_c="$(mtx_hash_bridge_terraform "$src")" || return 0
  if [ -n "$ec" ] && [ "$ec" != "$cur_c" ]; then
    echo "⚠️  [PINNED](terraform): recorded folder hash no longer matches project-bridge/terraform (pin still active; skipping re-vendor)." >&2
  fi
  if [ -z "$cur_g" ] || [ -z "$eg" ]; then
    return 0
  fi
  resolved_full="$(git -C "$br" rev-parse --verify "${eg}^{commit}" 2>/dev/null || true)"
  if [ -z "$resolved_full" ]; then
    echo "⚠️  [PINNED](terraform): recorded git ref ${eg} is not a commit in this bridge checkout (pin still active)." >&2
    return 0
  fi
  if [ "$resolved_full" != "$cur_g" ]; then
    echo "⚠️  [PINNED](terraform): recorded commit ${eg:0:7}… differs from bridge HEAD ${cur_g:0:7}… (pin still active)." >&2
  fi
}

mtx_vendor_terraform_write_digest() {
  local root="$1"
  if declare -F mtx_vendor_is_pinned &>/dev/null && mtx_vendor_is_pinned "$root" terraform; then
    return 0
  fi
  local src dest cur
  if ! src="$(mtx_resolve_bridge_terraform_src "$root")"; then
    return 0
  fi
  if mtx_vendor_terraform_dest_is_bridge "$root"; then
    return 0
  fi
  dest="$root/terraform"
  [ -d "$dest" ] || mkdir -p "$dest"
  cur="$(mtx_hash_bridge_terraform "$src")" || return 1
  printf '%s\n' "$cur" > "$dest/$DIGEST_REL"
}

mtx_vendor_terraform_prompt_upgrade() {
  local dest="$1"
  local ans
  echo "project-bridge/terraform differs from vendored copy in $dest (digest mismatch or first run)." >&2
  read -rp "Re-vendor terraform from project-bridge? [u]pgrade / [s]kip (default: skip): " ans || true
  case "${ans:-s}" in
    u|U|upgrade|Upgrade|y|Y|yes|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

mtx_vendor_terraform_maybe_sync() {
  local root="$1"
  local src dest cur prev mode rev
  mode="$SYNC_MODE"
  rev="$MTX_VENDOR_TF_REVENDOR"

  if declare -F mtx_vendor_is_pinned &>/dev/null && mtx_vendor_is_pinned "$root" terraform; then
    mtx_vendor_warn_terraform_pin_metadata "$root"
    if [ "$rev" = 1 ]; then
      echo "ℹ️  terraform is listed in .mtx-vendor.pinned — skipping --revendor." >&2
    fi
    return 0
  fi

  if ! src="$(mtx_resolve_bridge_terraform_src "$root")"; then
    return 0
  fi
  dest="$root/terraform"
  if [ ! -f "$dest/main.tf" ]; then
    return 0
  fi
  if mtx_vendor_terraform_dest_is_bridge "$root"; then
    return 0
  fi
  cur="$(mtx_hash_bridge_terraform "$src")" || return 1
  prev=""
  [ -f "$dest/$DIGEST_REL" ] && prev="$(tr -d '\n\r' < "$dest/$DIGEST_REL" || true)"

  if [ "$rev" != 1 ] && [ -n "$prev" ] && [ "$prev" = "$cur" ]; then
    return 0
  fi

  if [ "$rev" = 1 ]; then
    echo "==> mtx: --revendor — syncing project-bridge/terraform → $dest" >&2
    mtx_rsync_bridge_terraform "$src" "$dest"
    printf '%s\n' "$cur" > "$dest/$DIGEST_REL"
    return 0
  fi

  if [ "$mode" = "prompt" ]; then
    if [ ! -t 0 ]; then
      echo "⚠️  project-bridge/terraform drifted vs $dest/$DIGEST_REL — no TTY; not re-vendoring. Use --revendor, MTX_VENDOR_TERRAFORM_MODE=auto, or an interactive terminal." >&2
      return 0
    fi
    if ! mtx_vendor_terraform_prompt_upgrade "$dest"; then
      echo "ℹ️  Skipping terraform re-vendor (per your choice)." >&2
      return 0
    fi
  else
    echo "==> mtx: project-bridge/terraform changed (or first digest) — re-vendoring → $dest" >&2
  fi
  mtx_rsync_bridge_terraform "$src" "$dest"
  printf '%s\n' "$cur" > "$dest/$DIGEST_REL"
}

if [ "$MTX_VENDOR_TF_WRITE_DIGEST" = 1 ]; then
  mtx_vendor_terraform_write_digest "$PROJECT_ROOT"
else
  mtx_vendor_terraform_maybe_sync "$PROJECT_ROOT"
fi
