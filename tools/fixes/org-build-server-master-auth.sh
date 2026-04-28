#!/usr/bin/env bash
# mtx fixes org-build-server-master-auth — bring MTX project/org-build-server.sh to
# master-auth parity: source .env so build-time VITE_MASTER_AUTH_URL is baked into payload-
# admin, derive VITE_MASTER_AUTH_URL from MASTER_AUTH_PUBLIC_URL when only the latter is
# set, and always run npm run build:backend (payload-admin) after build:client. Idempotent:
# already-patched files are recognised by sentinel comments and upgraded in place.
#
# Version history:
#   v1 — add .env source + VITE_MASTER_AUTH_URL derive + unconditional build:backend.
#   v2 — (RETIRED) also fanned out the admin API (VITE_MASTER_ADMIN_URL) to master.
#   v3 — strips the v2 VITE_MASTER_ADMIN_URL block. Admin API is same-origin on every host
#        (each org has its own config/server.json apps[], its own Railway project, its own
#        cross-app DB); only /auth fans out to master.
#
# Why this fix exists (rule-of-law §1 2026-04-21 Asmaster architecture):
#   payload-admin's SPA reads VITE_MASTER_AUTH_URL at BUILD TIME and defaults to same-origin
#   `/auth`. When an org's org-build-server.sh predates the master-auth fan-out contract,
#   older copies never sourced .env and gated the admin rebuild on a "slug" : "admin" grep that does
#   not match payload-admin entries (id: "payload-admin", no slug). Result: the tenant
#   admin bundle ships with authBasePath=/auth and admin login hits the tenant's local
#   auth instead of asmaster `/auth`, surfacing as "invalid username or password" even
#   with valid master credentials.
#
# Usage:
#   mtx fixes org-build-server-master-auth                 # patch cwd if it's an org-*; else all workspace siblings
#   mtx fixes org-build-server-master-auth org-foo org-bar # patch explicit paths
#   mtx fixes org-build-server-master-auth --dry-run ...   # show what would change, no writes
desc="Patch MTX project/org-build-server.sh to source .env and always rebuild payload-admin with VITE_MASTER_AUTH_URL"
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

# --- target discovery (canonical script is MTX/project/org-build-server.sh) ---
if [ "${#TARGETS[@]}" -eq 0 ]; then
  TARGETS=("$MTX_ROOT/project/org-build-server.sh")
  echoc dim "Default target: ${TARGETS[0]}"
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
SENTINEL_V2 = "# MTX-FIX: org-build-server-master-auth v2 (admin-api fan-out)"
SENTINEL_V3 = "# MTX-FIX: org-build-server-master-auth v3 (strip admin-api fan-out; auth-only)"

# v3 is the canonical shape. If v3 is stamped, nothing to do.
# If v2 is stamped but v3 is not, we must STRIP the VITE_MASTER_ADMIN_URL block
# (admin API is same-origin on every host — only /auth fans out to master).
if SENTINEL_V3 in text:
    print(f"  [=] already patched (v3 sentinel present): {path}")
    sys.exit(0)

changes = []

# --- 1) Insert master-auth env block right after the first `ROOT="$(cd ...)"` line. ---
env_block = (
    f'\n{SENTINEL} — source .env so build-time VITE_MASTER_AUTH_URL is baked into payload-admin.\n'
    '# payload-admin reads VITE_MASTER_AUTH_URL at BUILD TIME. If the org only has\n'
    '# MASTER_AUTH_PUBLIC_URL (the origin), derive VITE_MASTER_AUTH_URL from it by appending /auth.\n'
    '# Only /auth fans out to master — the admin API is same-origin on every host.\n'
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
    f'{SENTINEL_V3}\n'
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

# --- v2 strip: remove the VITE_MASTER_ADMIN_URL block if it's present from a prior v2 run.
#      Admin API is same-origin on every host; the admin SPA resolves its base from
#      window.location (rule-of-law §5 "No admin-API fan-out to master").
#      Three things to strip independently — they may or may not be contiguous in files
#      the v2 patcher produced:
#        (a) the v2 sentinel line                               (`# MTX-FIX: ... v2 ...`)
#        (b) the 1-3 comment lines immediately preceding the if (start with "# Admin API fan-out" etc.)
#        (c) the `if [ -z "${VITE_MASTER_ADMIN_URL:-}" ]; then … fi` block itself
stripped_any = False

# (c) strip the if-block first (anchors the other two).
admin_if_re = re.compile(
    r'^if \[ -z "\$\{VITE_MASTER_ADMIN_URL:-\}" \]; then\n'
    r'(?:^[ \t][^\n]*\n)+?'
    r'^fi\n',
    re.MULTILINE,
)
m_if = admin_if_re.search(text)
if m_if:
    start = m_if.start()
    # (b) walk backward and also eat any contiguous `# …` comment lines (and blank lines between them)
    # that look like the v2 explanation block, up to but not including the preceding VITE_MASTER_AUTH_URL
    # fi-line or the env-derive block.
    preceding = text[:start]
    lines = preceding.splitlines(keepends=True)
    eat_from = len(lines)
    for i in range(len(lines) - 1, -1, -1):
        line = lines[i]
        stripped_line = line.lstrip()
        if stripped_line.startswith('#') and 'MTX-FIX' not in stripped_line:
            eat_from = i
            continue
        if line.strip() == '':
            # only eat blank lines if they're sandwiched between comments we're already eating
            eat_from = i
            continue
        break
    if eat_from < len(lines):
        start = sum(len(l) for l in lines[:eat_from])
    text = text[:start] + text[m_if.end():]
    stripped_any = True

# (a) remove the v2 sentinel line(s), and any now-orphaned trailing blank line that
# follows the sentinel (so we don't leave double-blank gaps).
v2_sentinel_re = re.compile(
    r'^# MTX-FIX: org-build-server-master-auth v2[^\n]*\n(?:\n)?',
    re.MULTILINE,
)
if v2_sentinel_re.search(text):
    text = v2_sentinel_re.sub('', text)
    stripped_any = True

if stripped_any:
    changes.append("v3 strip: remove VITE_MASTER_ADMIN_URL block + v2 sentinel")

# If v1 was already stamped (with or without v2), promote to v3 by appending the v3 sentinel.
if SENTINEL in text and SENTINEL_V3 not in text:
    # Put v3 sentinel right after the v1 block's closing `fi` of the VITE_MASTER_AUTH_URL derivation.
    m_auth_fi = re.search(
        r'(if \[ -z "\$\{VITE_MASTER_AUTH_URL:-\}" \][\s\S]*?\nfi\n)',
        text,
    )
    if m_auth_fi:
        ins = m_auth_fi.end()
        text = text[:ins] + f'{SENTINEL_V3}\n' + text[ins:]
        changes.append("v3 stamp")
elif not (already_has_env_source and already_has_vite_derive):
    text = text[:insert_at] + env_block + text[insert_at:]
    changes.append("env + VITE_MASTER_AUTH_URL + DB_PROVIDER (v3)")
elif SENTINEL not in text:
    # Legacy script already has the pieces but no sentinel — stamp v1+v3 only.
    text = text[:insert_at] + f"\n{SENTINEL}\n{SENTINEL_V3}\n" + text[insert_at:]
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
_seen_files=""
for item in "${TARGETS[@]}"; do
  file=""
  if [ -f "$item" ]; then
    file="$(cd "$(dirname "$item")" && pwd -P)/$(basename "$item")"
  elif [ -d "$item" ] && [[ "$(basename "$item")" == org-* ]]; then
    file="$MTX_ROOT/project/org-build-server.sh"
    echoc dim "  (org dir $item → canonical $file)"
  else
    warn "skip: $item (pass a file path or org-* directory)"
    ((skipped++)) || true
    continue
  fi
  case " $_seen_files " in *" $file "*) continue ;; esac
  _seen_files="$_seen_files $file "
  if [ ! -f "$file" ]; then
    echoc dim "  (missing $file)"
    ((skipped++)) || true
    continue
  fi
  echoc cyan "→ $file"
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
  success "dry-run done. files scanned: $patched, skipped: $skipped"
else
  success "patch done. files processed: $patched, skipped: $skipped, failures: $failed"
fi
[ "$failed" -eq 0 ]
