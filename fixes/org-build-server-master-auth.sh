#!/usr/bin/env bash
# mtx fixes org-build-server-master-auth — bring an org-*'s scripts/org-build-server.sh to
# master-auth parity with template-basic: source .env so build-time VITE_MASTER_AUTH_URL
# is baked into payload-admin, derive VITE_MASTER_AUTH_URL from MASTER_AUTH_PUBLIC_URL
# when only the latter is set, and always run npm run build:backend (payload-admin) after
# build:client. Idempotent: already-patched files are recognised by a sentinel comment
# and left untouched.
#
# Why this fix exists (rule-of-law §1 2026-04-21 org-build-server parity):
#   payload-admin's SPA reads VITE_MASTER_AUTH_URL (or MASTER_AUTH_URL) at BUILD TIME and
#   defaults to same-origin `/auth`. When an org's org-build-server.sh predates the master-
#   auth fan-out contract, it never sources .env and gates the admin rebuild on a "slug" :
#   "admin" grep that does not match payload-admin entries (id: "payload-admin", no slug).
#   Result: the tenant admin bundle ships with authBasePath=/auth and admin login hits the
#   tenant's local auth instead of the asmaster `/auth`, surfacing as "invalid username or
#   password" even with valid master credentials.
#
# Usage:
#   mtx fixes org-build-server-master-auth                 # patch cwd if it's an org-*; else all workspace siblings
#   mtx fixes org-build-server-master-auth org-foo org-bar # patch explicit paths
#   mtx fixes org-build-server-master-auth --dry-run ...   # show what would change, no writes
desc="Patch org-*/scripts/org-build-server.sh to source .env and always rebuild payload-admin with VITE_MASTER_AUTH_URL"
nobanner=1
set -e

_fix_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MTX_ROOT="${MTX_ROOT:-$(cd "$_fix_dir/.." && pwd)}"
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
      sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
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
      [ -f "$d/scripts/org-build-server.sh" ] || continue
      TARGETS+=("$d")
    done
    [ "${#TARGETS[@]}" -eq 0 ] && { error "No org-* targets found (cwd not org-*, no siblings under $ws)."; exit 1; }
    echoc dim "Auto-detected ${#TARGETS[@]} org-* target(s) under $ws"
  fi
fi

if ! command -v python3 >/dev/null 2>&1; then
  error "python3 is required for this fix (used for multi-line structural edits)."
  exit 1
fi

_patch_one() {
  local path="$1" dry="$2"
  [ -f "$path" ] || { echoc dim "  skip (missing): $path"; return 0; }
  python3 - "$path" "$dry" <<'PYEOF'
import sys, re, pathlib
path, dry = sys.argv[1], sys.argv[2] == "1"
text = pathlib.Path(path).read_text()
original = text

SENTINEL = "# MTX-FIX: org-build-server-master-auth v1"

# Self-skip if a prior run already stamped the sentinel.
if SENTINEL in text:
    print(f"  [=] already patched (sentinel present): {path}")
    sys.exit(0)

changes = []

# --- 1) Insert master-auth env block right after the first `ROOT="$(cd ...)"` line. ---
env_block = (
    f'\n{SENTINEL} — source .env so build-time VITE_MASTER_AUTH_URL is baked into payload-admin.\n'
    '# payload-admin reads VITE_MASTER_AUTH_URL at BUILD TIME. If the org only has\n'
    '# MASTER_AUTH_PUBLIC_URL (the origin), derive VITE_MASTER_AUTH_URL from it by appending /auth.\n'
    'ENV_FILE="$ROOT/.env"\n'
    'if [ -f "$ENV_FILE" ]; then\n'
    '  set -a\n'
    '  # shellcheck source=/dev/null\n'
    '  source "$ENV_FILE"\n'
    '  set +a\n'
    'fi\n'
    'if [ -z "${VITE_MASTER_AUTH_URL:-}" ] && [ -n "${MASTER_AUTH_PUBLIC_URL:-}" ]; then\n'
    '  base="${MASTER_AUTH_PUBLIC_URL%/}"\n'
    '  export VITE_MASTER_AUTH_URL="${base}/auth"\n'
    'fi\n'
    '\n'
    '# Prisma client must be generated for PostgreSQL on hosted builds: Railway often omits\n'
    '# DATABASE_URL during Docker build, which previously made db:generate default to sqlite\n'
    '# while runtime uses pg. Narrowed to hosted signals only so local `npm run dev` keeps\n'
    '# defaulting to SQLite unless the developer opts in explicitly.\n'
    'if [ -z "${DATABASE_PROVIDER:-}" ]; then\n'
    '  if [ -n "${RAILWAY_PROJECT_ID:-}${RAILWAY_SERVICE_ID:-}${RAILWAY_ENVIRONMENT:-}${CI:-}${GITHUB_ACTIONS:-}${VERCEL_ENV:-}" ]; then\n'
    '    export DATABASE_PROVIDER=postgresql\n'
    '  fi\n'
    'fi\n'
)

# Find the first `ROOT="$(cd ...)"` definition (template uses `(cd "$(dirname "$0")/.." && pwd)`).
m_root = re.search(r'^ROOT="\$\(cd "\$\(dirname "\$0"\)/\.\." && pwd\)"\s*$', text, re.MULTILINE)
if not m_root:
    print(f"  [!] could not locate ROOT= anchor line: {path}", file=sys.stderr)
    sys.exit(2)

insert_at = m_root.end()
# Don't duplicate if the raw strings are already present in some form.
already_has_env_source = bool(re.search(r'^\s*source "\$ENV_FILE"', text, re.MULTILINE))
already_has_vite_derive = "VITE_MASTER_AUTH_URL" in text
if not (already_has_env_source and already_has_vite_derive):
    text = text[:insert_at] + env_block + text[insert_at:]
    changes.append("env + VITE_MASTER_AUTH_URL + DB_PROVIDER")
else:
    # Legacy script already has the pieces but no sentinel — stamp sentinel only.
    text = text[:insert_at] + f"\n{SENTINEL}\n" + text[insert_at:]
    changes.append("sentinel-only (env + VITE already present)")

# --- 2) Replace stale `need_admin=false ... fi` grep-gated admin build block. ---
stale_admin_re = re.compile(
    r'[ \t]*need_admin=false\s*\n'
    r'[ \t]*for f in "\$ROOT/config/server\.json" "\$ROOT/config/server\.json\.railway"; do\s*\n'
    r'[ \t]*if \[ -f "\$f" \] && grep -q \'"slug"\[\[:space:\]\]\*:\[\[:space:\]\]\*"admin"\' "\$f"; then\s*\n'
    r'[ \t]*need_admin=true\s*\n'
    r'[ \t]*break\s*\n'
    r'[ \t]*fi\s*\n'
    r'[ \t]*done\s*\n'
    r'[ \t]*if \[ "\$need_admin" = true \]; then\s*\n'
    r'[ \t]*echo "==> org-build-server: server config lists admin → npm run build:backend \(payload-admin\)"\s*\n'
    r'[ \t]*npm run build:backend\s*\n'
    r'[ \t]*fi\s*\n'
)
replacement_admin = (
    '  # Admin SPA (payload-admin): picks up VITE_MASTER_AUTH_URL / MASTER_AUTH_PUBLIC_URL for master login fan-out.\n'
    '  npm run build:backend\n'
)
if stale_admin_re.search(text):
    text = stale_admin_re.sub(replacement_admin, text, count=1)
    changes.append("admin build (unconditional)")

# --- 3) Polly-style bare build: only `npm install` + `build:server`, no packages/client/backend.
#        Ensure packages + client + backend are built before server. ---
# Detect by: a (cd "$PB" ... ) subshell that has no `npm run build:packages` line.
subshell_re = re.compile(r'\(\s*\n([ \t]*cd "\$PB"[\s\S]*?)\n\)\s*\n', re.MULTILINE)
m_sub = subshell_re.search(text)
if m_sub and "npm run build:packages" not in m_sub.group(1):
    inner = m_sub.group(1)
    # Find the build:server line (with optional DATABASE_PROVIDER prefix) and insert chain before it.
    build_server_re = re.compile(r'^(?P<indent>[ \t]*)(?P<line>(?:DATABASE_PROVIDER=postgresql )?npm run build:server\s*)$', re.MULTILINE)
    m_bs = build_server_re.search(inner)
    if m_bs:
        indent = m_bs.group('indent')
        chain = (
            f"{indent}npm run build:packages\n"
            f"{indent}npm run build:client\n"
            f"{indent}# Admin SPA (payload-admin): picks up VITE_MASTER_AUTH_URL / MASTER_AUTH_PUBLIC_URL for master login fan-out.\n"
            f"{indent}npm run build:backend\n"
        )
        new_inner = inner[:m_bs.start()] + chain + inner[m_bs.start():]
        text = text[:m_sub.start()] + "(\n" + new_inner + "\n)\n" + text[m_sub.end():]
        changes.append("polly: inject packages+client+backend chain")

# --- 4) Media/retail/tools case: build:client present, build:backend absent. Insert build:backend
#        after build:client so payload-admin is rebuilt with VITE_MASTER_AUTH_URL baked in. ---
if "npm run build:client" in text and "npm run build:backend" not in text:
    insert_re = re.compile(r'^(?P<indent>[ \t]*)npm run build:client\s*$', re.MULTILINE)
    m_bc = insert_re.search(text)
    if m_bc:
        indent = m_bc.group('indent')
        admin_block = (
            f"\n{indent}# Admin SPA (payload-admin): picks up VITE_MASTER_AUTH_URL / MASTER_AUTH_PUBLIC_URL for master login fan-out.\n"
            f"{indent}npm run build:backend"
        )
        text = text[:m_bc.end()] + admin_block + text[m_bc.end():]
        changes.append("insert build:backend after build:client")

# --- 5) Safety: if the script builds admin but lacks `npm run build:client` before it,
#        client artifacts may be stale. Insert build:client immediately before build:backend.
if "npm run build:backend" in text and "npm run build:client" not in text:
    text = text.replace(
        "npm run build:backend",
        "npm run build:client\n  npm run build:backend",
        1,
    )
    changes.append("safety: build:client before build:backend")

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

  file="$org_abs/scripts/org-build-server.sh"
  if [ ! -f "$file" ]; then
    echoc dim "  (no scripts/org-build-server.sh)"
    ((skipped++)) || true
    continue
  fi
  if _patch_one "$file" "$DRY_RUN"; then
    if [ "$DRY_RUN" -eq 0 ]; then
      if ! bash -n "$file"; then
        error "  bash -n failed on $file after patch — please inspect."
        ((failed++)) || true
      fi
    fi
    ((patched++)) || true
  else
    error "  patch failed on $file"
    ((failed++)) || true
  fi
done

echo ""
if [ "$DRY_RUN" -eq 1 ]; then
  success "dry-run done. orgs scanned: $patched, skipped: $skipped"
else
  success "patch done. orgs processed: $patched, skipped: $skipped, failures: $failed"
fi
[ "$failed" -eq 0 ]
