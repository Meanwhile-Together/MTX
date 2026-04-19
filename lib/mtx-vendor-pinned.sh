# MTX: parse .mtx-vendor.pinned at deploy root — which vendored subtrees skip drift checks / re-vendor.
# Sourced by vendor-terraform-from-bridge.sh and vendor-payloads-from-config.sh (do not execute standalone).
#
# File: $PROJECT_ROOT/.mtx-vendor.pinned
#   - Lines starting with # are ignored.
#   - Comma-separated keys:  terraform,payloads
#   - Optional provenance (still pins the key; warns if bridge no longer matches):
#       [PINNED](terraform):<git-rev>@<folder-content-sha256>
#
# Keys: terraform, payloads (extend as new vendored roots get checks).

mtx_vendor_pin_file() {
  printf '%s' "${1:?}/.mtx-vendor.pinned"
}

# Parse [PINNED](key):git@hash → key|git|hash or empty.
mtx_vendor_pin_line_parse() {
  local line="${1:?}"
  printf '%s' "$line" | sed -E -n 's/^[[:space:]]*\[PINNED\]\(([^)]+)\):([^@]+)@([^[:space:]]+).*$/\1|\2|\3/p'
}

# mtx_vendor_is_pinned <project_root> <key>  → exit 0 if key is pinned
mtx_vendor_is_pinned() {
  local root="${1:?}"
  local want="${2:?}"
  local f line parsed key
  f="$(mtx_vendor_pin_file "$root")"
  [ -f "$f" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line//$'\r'/}"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    parsed="$(mtx_vendor_pin_line_parse "$line")"
    if [ -n "$parsed" ]; then
      key="${parsed%%|*}"
      [ "$key" = "$want" ] && return 0
      continue
    fi
    line="${line%%#*}"
    IFS=',' read -r -a parts <<< "$line"
    for tok in "${parts[@]}"; do
      tok="${tok#"${tok%%[![:space:]]*}"}"
      tok="${tok%"${tok##*[![:space:]]}"}"
      [ -z "$tok" ] && continue
      [ "$tok" = "$want" ] && return 0
    done
  done < "$f"
  return 1
}

# Prints "expect_git|expect_content" for [PINNED](key):...@... or empty if no such line.
mtx_vendor_pin_metadata_for_key() {
  local root="${1:?}"
  local want="${2:?}"
  local f line parsed key g c
  f="$(mtx_vendor_pin_file "$root")"
  [ -f "$f" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line//$'\r'/}"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    parsed="$(mtx_vendor_pin_line_parse "$line")"
    if [ -n "$parsed" ]; then
      key="${parsed%%|*}"
      rest="${parsed#*|}"
      g="${rest%%|*}"
      c="${rest#*|}"
      if [ "$key" = "$want" ]; then
        printf '%s|%s' "$g" "$c"
        return 0
      fi
    fi
  done < "$f"
  return 1
}
