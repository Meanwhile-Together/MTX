#!/usr/bin/env bash
# mtx tools fixes org-terraform-config-triad — rewrite an org-*'s vendored terraform/apply.sh and
# terraform/destroy.sh to read identity from config/org.json (canonical) with a legacy fallback to
# config/app.json. Idempotent: files that already define ORG_IDENTITY_FILE are left untouched.
#
# Why this fix exists (rule-of-law §1 2026-04-20 Config triad, org terraform identity):
#   Older org terraform scaffolds used `config/app.json.app.{name,slug,owner}` as the
#   deploy-time identity. When orgs migrated to `config/org.json.org.*` (Config triad), the
#   vendored terraform scripts kept reading the now-missing `config/app.json`, which would
#   break `mtx deploy` on next run. This fix backports the org.json-first resolver.
#
# Usage:
#   mtx tools fixes org-terraform-config-triad                 # patch cwd if it's an org-*; else all workspace siblings
#   mtx tools fixes org-terraform-config-triad org-foo org-bar # patch explicit paths
#   mtx tools fixes org-terraform-config-triad --dry-run ...   # show what would change, no writes
desc="Patch org-*/terraform/{apply,destroy}.sh to read config/org.json (canonical) with config/app.json fallback"
nobanner=1
set -e

# Resolve MTX root + load bolors if available.
_fix_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MTX_ROOT="${MTX_ROOT:-$(cd "$_fix_dir/../.." && pwd)}"
if [ -d "$MTX_ROOT/includes" ]; then
  # shellcheck disable=SC1091
  for f in "$MTX_ROOT"/includes/*.sh; do source "$f"; done
fi
declare -F echoc   >/dev/null || echoc()   { local _c="$1"; shift || true; echo "$*"; }
declare -F info    >/dev/null || info()    { echo "[INFO] $*"; }
declare -F warn    >/dev/null || warn()    { echo "[WARN] $*" >&2; }
declare -F error   >/dev/null || error()   { echo "[ERROR] $*" >&2; }
declare -F success >/dev/null || success() { echo "[SUCCESS] $*"; }

DRY_RUN=0
TARGETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do TARGETS+=("$1"); shift; done; break ;;
    -*) error "Unknown flag: $1"; exit 2 ;;
    *)  TARGETS+=("$1"); shift ;;
  esac
done

# --- target discovery ---
if [ "${#TARGETS[@]}" -eq 0 ]; then
  cwd="$(pwd)"
  base="$(basename "$cwd")"
  if [[ "$base" == org-* ]]; then
    TARGETS=("$cwd")
  else
    ws="${MTX_WORKSPACE_ROOT:-$(cd "$MTX_ROOT/.." && pwd)}"
    for d in "$ws"/org-*; do
      [ -d "$d" ] || continue
      [ -f "$d/terraform/apply.sh" ] || [ -f "$d/terraform/destroy.sh" ] || continue
      TARGETS+=("$d")
    done
    [ "${#TARGETS[@]}" -eq 0 ] && { error "No org-* targets found (cwd not org-*, no siblings under $ws)."; exit 1; }
    echoc dim "Auto-detected ${#TARGETS[@]} org-* target(s) under $ws"
  fi
fi

# --- Python-powered structural patcher (multi-line block replace + single-line substitutions) ---
_patch_one() {
  local path="$1" kind="$2" dry="$3"
  [ -f "$path" ] || { echoc dim "  skip (missing): $path"; return 0; }
  python3 - "$path" "$kind" "$dry" <<'PYEOF'
import sys, re, pathlib
path, kind, dry = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
text = pathlib.Path(path).read_text()
original = text

# Idempotency is per-pattern: each edit fires only when its exact old shape is present.
# (Earlier top-level "if ORG_IDENTITY_FILE in text: skip" was wrong — APP_OWNER sub introduces
# the variable before the destroy.sh APP_NAME insert runs, which would silently strand
# destroy.sh referencing undefined ORG_IDENTITY_FILE on line 45.)
changes = []

# --- apply.sh project-root block -> org.json-first resolver ---
if kind == "apply":
    # Old comment line just before the project-root if-chain.
    old_comment = "# Resolve project root (directory containing config/app.json) so .env is always loaded from the right place"
    new_comment = (
        "# Resolve project root (directory containing config/org.json or legacy config/app.json) so .env\n"
        "# is always loaded from the right place. Per rule-of-law \u00a71 2026-04-20 Config triad, an org's\n"
        "# identity lives in config/org.json; config/app.json is retired on orgs but tolerated as a fallback."
    )
    if old_comment in text:
        text = text.replace(old_comment, new_comment, 1)
        changes.append("project-root comment")

    # The exact project-root if-chain from legacy org terraform scaffolds.
    old_block = (
        'if [ -f "config/app.json" ]; then\n'
        '  PROJECT_ROOT="$(pwd)"\n'
        'fi\n'
        'if [ -z "$PROJECT_ROOT" ] && [ -f "../config/app.json" ]; then\n'
        '  PROJECT_ROOT="$(cd .. && pwd)"\n'
        'fi\n'
        'if [ -z "$PROJECT_ROOT" ]; then\n'
        '  for d in . .. ../project-bridge; do\n'
        '    [ -f "${d}/config/app.json" ] && PROJECT_ROOT="$(cd "$d" && pwd)" && break\n'
        '  done\n'
        'fi'
    )
    new_block = (
        'PROJECT_ROOT=""\n'
        'for root_candidate in . .. ../project-bridge; do\n'
        '  if [ -f "${root_candidate}/config/org.json" ] || [ -f "${root_candidate}/config/app.json" ]; then\n'
        '    PROJECT_ROOT="$(cd "$root_candidate" && pwd)"\n'
        '    break\n'
        '  fi\n'
        'done\n'
        '[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(pwd)"\n'
        '\n'
        '# Identity source: prefer config/org.json (.org.*), fall back to config/app.json (.app.*).\n'
        '# Exposes ORG_IDENTITY_FILE + ORG_IDENTITY_KEY for jq paths below.\n'
        'if [ -f "$PROJECT_ROOT/config/org.json" ]; then\n'
        '  ORG_IDENTITY_FILE="$PROJECT_ROOT/config/org.json"\n'
        '  ORG_IDENTITY_KEY="org"\n'
        'elif [ -f "$PROJECT_ROOT/config/app.json" ]; then\n'
        '  ORG_IDENTITY_FILE="$PROJECT_ROOT/config/app.json"\n'
        '  ORG_IDENTITY_KEY="app"\n'
        'else\n'
        '  ORG_IDENTITY_FILE=""\n'
        '  ORG_IDENTITY_KEY=""\n'
        'fi'
    )
    if old_block in text:
        text = text.replace(old_block, new_block, 1)
        changes.append("project-root + identity-source")
    elif "ORG_IDENTITY_FILE" in text:
        # Already migrated in a prior run (normal idempotent re-run path).
        pass
    else:
        print(f"  [!] project-root block not in expected shape: {path}", file=sys.stderr)
        sys.exit(2)

    # APP_NAME / APP_SLUG two-liner.
    old_ns = (
        'APP_NAME=$(jq -r \'.app.name\' "$PROJECT_ROOT/config/app.json" 2>/dev/null || echo "")\n'
        'APP_SLUG=$(jq -r \'.app.slug // .app.name // "app"\' "$PROJECT_ROOT/config/app.json" 2>/dev/null | tr \'[:upper:]\' \'[:lower:]\' | sed \'s/[^a-z0-9]/-/g\' | sed \'s/^-*//;s/-*$//\')'
    )
    new_ns = (
        'if [ -n "$ORG_IDENTITY_FILE" ]; then\n'
        '    APP_NAME=$(jq -r ".${ORG_IDENTITY_KEY}.name // empty" "$ORG_IDENTITY_FILE" 2>/dev/null || echo "")\n'
        '    APP_SLUG=$(jq -r ".${ORG_IDENTITY_KEY}.slug // .${ORG_IDENTITY_KEY}.name // \\"app\\"" "$ORG_IDENTITY_FILE" 2>/dev/null | tr \'[:upper:]\' \'[:lower:]\' | sed \'s/[^a-z0-9]/-/g\' | sed \'s/^-*//;s/-*$//\')\n'
        'else\n'
        '    APP_NAME=""\n'
        '    APP_SLUG=""\n'
        'fi'
    )
    if old_ns in text:
        text = text.replace(old_ns, new_ns, 1)
        changes.append("APP_NAME+APP_SLUG")

# --- shared single-line substitutions ---
subs = [
    # APP_OWNER jq read.
    (
        'APP_OWNER=$(jq -r \'.app.owner // ""\' "$PROJECT_ROOT/config/app.json" 2>/dev/null || echo "")',
        'if [ -n "$ORG_IDENTITY_FILE" ]; then\n'
        '            APP_OWNER=$(jq -r ".${ORG_IDENTITY_KEY}.owner // \\"\\"" "$ORG_IDENTITY_FILE" 2>/dev/null || echo "")\n'
        '        else\n'
        '            APP_OWNER=""\n'
        '        fi',
        "APP_OWNER",
    ),
    # Error messages + comments.
    (
        '"⚠️  app.name not found in config/app.json, using default"',
        '"⚠️  name not found in config/org.json or config/app.json, using default"',
        "name-not-found msg",
    ),
    (
        "# Resolve workspace ID from app owner name (config/app.json); no manual RAILWAY_WORKSPACE_ID needed",
        "# Resolve workspace ID from org.owner (config/org.json) / app.owner (legacy config/app.json); no manual RAILWAY_WORKSPACE_ID needed",
        "workspace-id comment",
    ),
    (
        "❌ Could not resolve Railway workspace. Set RAILWAY_WORKSPACE_ID in .env or ensure config/app.json app.owner matches a Railway workspace name.",
        "❌ Could not resolve Railway workspace. Set RAILWAY_WORKSPACE_ID in the workspace .mtx.prepare.env (run: mtx prepare) or ensure config/app.json app.owner matches a Railway workspace name.",
        "workspace-resolve error app",
    ),
    (
        "❌ Could not resolve Railway workspace. Set RAILWAY_WORKSPACE_ID in .env or ensure config/org.json org.owner (or legacy config/app.json app.owner) matches a Railway workspace name.",
        "❌ Could not resolve Railway workspace. Set RAILWAY_WORKSPACE_ID in the workspace .mtx.prepare.env (run: mtx prepare) or ensure config/org.json org.owner (or legacy config/app.json app.owner) matches a Railway workspace name.",
        "workspace-resolve error org",
    ),
    (
        "✅${NC} Using existing project (config/app.json owner):",
        "✅${NC} Using existing project (from org.owner):",
        "existing-project log",
    ),
    # Header-comment line mentioning just config/app.json.
    (
        "# Reads config/app.json and config/deploy.json; loads .env from project root.",
        "# Reads config/app.json and config/deploy.json; org .env for tenant-only; RAILWAY_* from workspace .mtx.prepare.env (mtx prepare / apply).",
        "header comment",
    ),
    (
        "# Reads config/org.json (canonical; legacy fallback: config/app.json) and config/deploy.json; loads .env from project root.",
        "# Reads config/org.json (canonical; legacy: config/app.json) and config/deploy.json; org .env for tenant-only; RAILWAY_* from workspace .mtx.prepare.env (mtx prepare / apply).",
        "header comment org",
    ),
]
for old, new, tag in subs:
    if old in text:
        text = text.replace(old, new)
        changes.append(tag)

# --- destroy.sh needs the identity-source block inserted just before the APP_NAME read.
# Gate on the presence of the exact old APP_NAME pattern (not on ORG_IDENTITY_FILE — the APP_OWNER
# sub above introduces that variable name but does NOT define it at the top of destroy.sh).
if kind == "destroy":
    old_name = 'APP_NAME=$(jq -r \'.app.name\' "$PROJECT_ROOT/config/app.json" 2>/dev/null || echo "")'
    new_pre  = (
        '# Identity source: prefer config/org.json (.org.*), fall back to config/app.json (.app.*).\n'
        '# Per rule-of-law \u00a71 2026-04-20 Config triad, org identity lives in config/org.json.\n'
        'if [ -f "$PROJECT_ROOT/config/org.json" ]; then\n'
        '    ORG_IDENTITY_FILE="$PROJECT_ROOT/config/org.json"\n'
        '    ORG_IDENTITY_KEY="org"\n'
        'elif [ -f "$PROJECT_ROOT/config/app.json" ]; then\n'
        '    ORG_IDENTITY_FILE="$PROJECT_ROOT/config/app.json"\n'
        '    ORG_IDENTITY_KEY="app"\n'
        'else\n'
        '    ORG_IDENTITY_FILE=""\n'
        '    ORG_IDENTITY_KEY=""\n'
        'fi\n'
        '\n'
        '# Get org/app name\n'
        'if [ -n "$ORG_IDENTITY_FILE" ]; then\n'
        '    APP_NAME=$(jq -r ".${ORG_IDENTITY_KEY}.name // empty" "$ORG_IDENTITY_FILE" 2>/dev/null || echo "")\n'
        'else\n'
        '    APP_NAME=""\n'
        'fi'
    )
    if old_name in text:
        text = text.replace(old_name, new_pre, 1)
        changes.append("identity-source + APP_NAME (destroy)")

if text == original:
    print(f"  [=] no changes needed: {path}")
    sys.exit(0)

if dry:
    print(f"  [dry] would update {path}: {', '.join(changes)}")
    sys.exit(0)

pathlib.Path(path).write_text(text)
print(f"  [+] patched {path}: {', '.join(changes)}")
PYEOF
}

if ! command -v python3 >/dev/null 2>&1; then
  error "python3 is required for this fix (used for multi-line structural edits)."
  exit 1
fi

patched=0
skipped=0
failed=0
for org in "${TARGETS[@]}"; do
  if [ ! -d "$org" ]; then
    warn "skip: $org is not a directory"
    ((skipped++)) || true
    continue
  fi
  org_abs="$(cd "$org" && pwd -P)"
  base="$(basename "$org_abs")"
  case "$base" in
    org-*) ;;
    *) warn "skip: $org_abs (basename does not start with org-)"
       ((skipped++)) || true
       continue ;;
  esac
  echoc cyan "→ $base"

  for script in apply destroy; do
    file="$org_abs/terraform/${script}.sh"
    if [ ! -f "$file" ]; then
      echoc dim "  (no terraform/${script}.sh)"
      continue
    fi
    if _patch_one "$file" "$script" "$DRY_RUN"; then
      if [ "$DRY_RUN" -eq 0 ]; then
        if ! bash -n "$file"; then
          error "  bash -n failed on $file after patch — please inspect (backup not written)."
          ((failed++)) || true
        fi
      fi
    else
      error "  patch failed on $file"
      ((failed++)) || true
    fi
  done
  ((patched++)) || true
done

echo ""
if [ "$DRY_RUN" -eq 1 ]; then
  success "dry-run done. orgs scanned: $patched, skipped: $skipped"
else
  success "patch done. orgs processed: $patched, skipped: $skipped, failures: $failed"
fi
[ "$failed" -eq 0 ]
