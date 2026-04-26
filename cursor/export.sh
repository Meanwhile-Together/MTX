#!/usr/bin/env bash
# mtx cursor export — export Cursor agent chat transcripts as JSON.
#
# Interactive by default: pick a project (or ALL projects), then "all" or
# one specific conversation. Fully non-interactive flags are supported too.
#
# Cursor's JSONL transcript format (empirically deduced):
#   Each non-empty line:
#     { "role":"user"|"assistant", "message":{"content":[<block>,...]} }
#   Block types observed: "text" { text }, "tool_use" { name, id?, input }.
#   Per-message timestamps are NOT persisted; thread timestamps come from
#   file ctime/mtime. Subagents live at
#     <project>/agent-transcripts/<uuid>/subagents/<sub-uuid>.jsonl
#
# Usage (interactive):
#   mtx cursor export
#     → choose project (or ALL) → choose "all" or a single thread.
#
# Usage (non-interactive):
#   mtx cursor export --all-projects                       -o out.json
#   mtx cursor export --project-slug <slug> --all          -o out.json
#   mtx cursor export --project-slug <slug> --thread <uid> -o out.json
#   mtx cursor export --project-dir  <path> --all          -o out.json
#
# Flags:
#   -o, --output PATH       Output file (default ./chat-export.json).
#                           With --split, PATH is treated as a directory.
#   -p, --project-dir DIR   Explicit Cursor project dir.
#   -P, --project-slug SLUG Cursor project slug under ~/.cursor/projects/.
#       --all-projects      Export every project found under ~/.cursor/projects.
#       --all               Export every thread in the chosen project(s).
#       --thread UUID       Export a single thread (plus its subagents).
#       --pretty            Pretty-print JSON (2-space indent).
#       --split             Emit one file per thread + index.json.
#                           With --all-projects, each project gets a subdir.
#       --no-attachments    Skip canvases/assets/uploads/terminals listings.
#   -y, --yes               Accept defaults; no prompts (non-interactive).
#   -h, --help              Show this help.
desc="Export Cursor agent chat transcripts to JSON (interactive picker)"
nobanner=1
set -e

# --- fallbacks in case bolors isn't loaded ----------------------------------
declare -F color   >/dev/null || color()   { shift 2>/dev/null; echo -n "$*"; }
declare -F echoc   >/dev/null || echoc()   { shift 2>/dev/null; echo "$*"; }
declare -F info    >/dev/null || info()    { echo "[INFO] $*"; }
declare -F success >/dev/null || success() { echo "[OK]   $*"; }
declare -F warn    >/dev/null || warn()    { echo "[WARN] $*" >&2; }
declare -F error   >/dev/null || error()   { echo "[ERR]  $*" >&2; }

command -v python3 >/dev/null 2>&1 || {
  error "python3 is required for mtx cursor export"
  return 2 2>/dev/null || exit 2
}

# --- arg parsing -------------------------------------------------------------
OUT=""
PROJECT_DIR=""
PROJECT_SLUG=""
ALL_PROJECTS=0
PRETTY=0
SPLIT=0
ATTACH=1
MODE=""          # "all" | "thread"
THREAD_UUID=""
NONINTERACTIVE=0

show_help() {
  sed -n '/^# mtx cursor export/,/^desc=/p' "${BASH_SOURCE[0]}" \
    | sed -e 's/^# \{0,1\}//' -e '/^desc=/d'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)        OUT="$2"; shift 2;;
    -p|--project-dir)   PROJECT_DIR="$2"; shift 2;;
    -P|--project-slug)  PROJECT_SLUG="$2"; shift 2;;
    --all-projects)     ALL_PROJECTS=1; shift;;
    --all)              MODE="all"; shift;;
    --thread)           MODE="thread"; THREAD_UUID="$2"; shift 2;;
    --pretty)           PRETTY=1; shift;;
    --split)            SPLIT=1; shift;;
    --no-attachments)   ATTACH=0; shift;;
    -y|--yes)           NONINTERACTIVE=1; shift;;
    -h|--help)          show_help; return 0 2>/dev/null || exit 0;;
    *) error "unknown option: $1"; show_help; return 1 2>/dev/null || exit 1;;
  esac
done

CURSOR_ROOT="${CURSOR_PROJECTS_DIR:-$HOME/.cursor/projects}"
if [[ ! -d "$CURSOR_ROOT" ]]; then
  error "Cursor projects root not found: $CURSOR_ROOT"
  return 3 2>/dev/null || exit 3
fi

# --- helper: list projects as "slug<TAB>threads<TAB>last_iso" ---------------
list_projects_tsv() {
  CURSOR_ROOT="$CURSOR_ROOT" python3 - <<'PY'
import os, sys
from pathlib import Path
from datetime import datetime, timezone
root = Path(os.environ["CURSOR_ROOT"])
rows = []
for d in sorted(root.iterdir()):
    if not d.is_dir(): continue
    tr = d / "agent-transcripts"
    if not tr.is_dir(): continue
    threads = []
    for child in tr.iterdir():
        if not child.is_dir(): continue
        cand = child / f"{child.name}.jsonl"
        if not cand.exists():
            alts = list(child.glob("*.jsonl"))
            if not alts: continue
            cand = alts[0]
        threads.append(cand)
    if not threads: continue
    last = max(t.stat().st_mtime for t in threads)
    iso = datetime.fromtimestamp(last, tz=timezone.utc).strftime("%Y-%m-%d %H:%M")
    rows.append((last, d.name, len(threads), iso))
rows.sort(key=lambda r: -r[0])
for _, slug, n, iso in rows:
    print(f"{slug}\t{n}\t{iso}")
PY
}

# --- helper: list threads in one project ------------------------------------
list_threads_tsv() {
  PROJECT_DIR_ARG="$1" python3 - <<'PY'
import os, re, json
from pathlib import Path
from datetime import datetime, timezone
proj = Path(os.environ["PROJECT_DIR_ARG"])
tr = proj / "agent-transcripts"
USER_Q = re.compile(r"<user_query>\s*(.*?)\s*</user_query>", re.DOTALL)
rows = []
for child in sorted(tr.iterdir()):
    if not child.is_dir(): continue
    p = child / f"{child.name}.jsonl"
    if not p.exists():
        alts = list(child.glob("*.jsonl"))
        if not alts: continue
        p = alts[0]
    title = ""
    try:
        with p.open("r", encoding="utf-8", errors="replace") as fp:
            for line in fp:
                line = line.strip()
                if not line: continue
                obj = json.loads(line)
                if obj.get("role") != "user": break
                for b in (obj.get("message") or {}).get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "text":
                        txt = b.get("text","") or ""
                        m = USER_Q.search(txt)
                        cand = (m.group(1) if m else txt).strip()
                        if cand:
                            title = cand.splitlines()[0].strip()
                            break
                break
    except Exception:
        title = ""
    if len(title) > 90:
        title = title[:87] + "..."
    title = title.replace("\t", " ").replace("\r", " ")
    subdir = p.parent / "subagents"
    subs = len(list(subdir.glob("*.jsonl"))) if subdir.is_dir() else 0
    st = p.stat()
    iso = datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).strftime("%Y-%m-%d %H:%M")
    msgs = sum(1 for l in p.open("r", encoding="utf-8", errors="replace") if l.strip())
    rows.append((st.st_mtime, p.stem, iso, msgs, subs, title))
rows.sort(key=lambda r: -r[0])
for _, uid, iso, msgs, subs, title in rows:
    print(f"{uid}\t{iso}\t{msgs}\t{subs}\t{title}")
PY
}

# --- pick project(s) ---------------------------------------------------------
PROJECT_DIRS=()   # list of absolute project dirs to export

if [[ $ALL_PROJECTS -eq 1 ]]; then
  MODE="${MODE:-all}"
elif [[ -n "$PROJECT_DIR" || -n "$PROJECT_SLUG" ]]; then
  :
else
  if [[ $NONINTERACTIVE -eq 1 || ! -t 0 ]]; then
    error "no project specified; pass --all-projects / --project-slug / --project-dir"
    return 1 2>/dev/null || exit 1
  fi

  mapfile -t PROJ_ROWS < <(list_projects_tsv)
  if [[ ${#PROJ_ROWS[@]} -eq 0 ]]; then
    error "no Cursor projects with agent-transcripts found under $CURSOR_ROOT"
    return 3 2>/dev/null || exit 3
  fi

  # Total thread count across all projects (for the "ALL" label).
  total_threads=0
  for row in "${PROJ_ROWS[@]}"; do
    rest="${row#*	}"
    n="${rest%%	*}"
    total_threads=$((total_threads + n))
  done

  echo
  echoc cyan "=== mtx cursor export ==="
  echo "Cursor projects under $CURSOR_ROOT:"
  echo
  printf "  %3d) %-60s  %4s threads  (every project)\n" 0 "ALL projects (${#PROJ_ROWS[@]})" "$total_threads"
  i=0
  for row in "${PROJ_ROWS[@]}"; do
    i=$((i+1))
    slug="${row%%	*}"
    rest="${row#*	}"
    threads="${rest%%	*}"
    iso="${rest#*	}"
    printf "  %3d) %-60s  %4s threads  last %s\n" "$i" "$slug" "$threads" "$iso"
  done
  echo
  while true; do
    read -rp "$(color yellow "Select project (0=ALL, 1-${#PROJ_ROWS[@]}, q=quit): ")" pick
    case "$pick" in
      q|Q|"") info "Aborted."; return 0 2>/dev/null || exit 0;;
      0)
        ALL_PROJECTS=1; MODE="all"; break;;
      *[!0-9]*) warn "Not a number.";;
      *)
        if [[ $pick -ge 1 && $pick -le ${#PROJ_ROWS[@]} ]]; then
          sel="${PROJ_ROWS[$((pick-1))]}"
          PROJECT_SLUG="${sel%%	*}"
          break
        fi
        warn "Out of range.";;
    esac
  done
fi

# Resolve single-project input → absolute dir.
if [[ $ALL_PROJECTS -eq 0 ]]; then
  if [[ -n "$PROJECT_SLUG" && -z "$PROJECT_DIR" ]]; then
    PROJECT_DIR="$CURSOR_ROOT/$PROJECT_SLUG"
  fi
  if [[ ! -d "$PROJECT_DIR/agent-transcripts" ]]; then
    error "no agent-transcripts at: $PROJECT_DIR"
    return 3 2>/dev/null || exit 3
  fi
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
  PROJECT_DIRS=("$PROJECT_DIR")
  PROJECT_SLUG="${PROJECT_SLUG:-$(basename "$PROJECT_DIR")}"
else
  # Collect every project dir that has transcripts.
  while IFS=$'\t' read -r slug _threads _iso; do
    PROJECT_DIRS+=("$CURSOR_ROOT/$slug")
  done < <(list_projects_tsv)
  if [[ ${#PROJECT_DIRS[@]} -eq 0 ]]; then
    error "no Cursor projects with agent-transcripts found under $CURSOR_ROOT"
    return 3 2>/dev/null || exit 3
  fi
fi

# --- pick mode/thread (only meaningful for single-project) ------------------
if [[ $ALL_PROJECTS -eq 1 ]]; then
  MODE="all"
  THREAD_UUID=""
elif [[ -z "$MODE" ]]; then
  if [[ $NONINTERACTIVE -eq 1 || ! -t 0 ]]; then
    MODE="all"
  else
    mapfile -t THREAD_ROWS < <(list_threads_tsv "$PROJECT_DIR")
    if [[ ${#THREAD_ROWS[@]} -eq 0 ]]; then
      error "no threads found in $PROJECT_DIR"
      return 3 2>/dev/null || exit 3
    fi
    echo
    echoc cyan "Project: $PROJECT_SLUG"
    echo "  0) Export ALL ${#THREAD_ROWS[@]} threads"
    i=0
    for row in "${THREAD_ROWS[@]}"; do
      i=$((i+1))
      IFS=$'\t' read -r uid iso msgs subs title <<<"$row"
      printf "  %3d) %s  %4s msgs  %2s subs  %s  %s\n" \
        "$i" "$iso" "$msgs" "$subs" "${uid:0:8}" "$title"
    done
    echo
    while true; do
      read -rp "$(color yellow "Select (0=all, 1-${#THREAD_ROWS[@]}, q=quit): ")" pick
      case "$pick" in
        q|Q) info "Aborted."; return 0 2>/dev/null || exit 0;;
        0)   MODE="all"; break;;
        *[!0-9]*|"") warn "Not a number.";;
        *)
          if [[ $pick -ge 1 && $pick -le ${#THREAD_ROWS[@]} ]]; then
            row="${THREAD_ROWS[$((pick-1))]}"
            THREAD_UUID="${row%%	*}"
            MODE="thread"
            break
          fi
          warn "Out of range.";;
      esac
    done
  fi
fi

# --- output path default -----------------------------------------------------
if [[ -z "$OUT" ]]; then
  if [[ $ALL_PROJECTS -eq 1 && $SPLIT -eq 1 ]]; then
    default_out="./chat-export-all-projects"
  elif [[ $ALL_PROJECTS -eq 1 ]]; then
    default_out="./chat-export-all-projects.json"
  elif [[ $SPLIT -eq 1 ]]; then
    default_out="./chat-export-$PROJECT_SLUG"
  elif [[ "$MODE" == "thread" ]]; then
    default_out="./chat-export-${THREAD_UUID}.json"
  else
    default_out="./chat-export-${PROJECT_SLUG}.json"
  fi
  if [[ $NONINTERACTIVE -eq 0 && -t 0 ]]; then
    read -rp "$(color yellow "Output path [$default_out]: ")" given
    OUT="${given:-$default_out}"
  else
    OUT="$default_out"
  fi
fi

# --- interactive toggles (only when defaults not set by flags + tty) --------
if [[ $NONINTERACTIVE -eq 0 && -t 0 && $PRETTY -eq 0 && $SPLIT -eq 0 ]]; then
  read -rp "$(color yellow "Pretty-print? (y/N): ")" ans
  [[ "$ans" =~ ^[Yy] ]] && PRETTY=1
  if [[ "$MODE" == "all" ]]; then
    read -rp "$(color yellow "Split into one file per thread? (y/N): ")" ans
    [[ "$ans" =~ ^[Yy] ]] && SPLIT=1
  fi
fi

info "scope   : $([[ $ALL_PROJECTS -eq 1 ]] && echo "ALL projects (${#PROJECT_DIRS[@]})" || echo "$PROJECT_SLUG")"
info "mode    : $MODE${THREAD_UUID:+ ($THREAD_UUID)}"
info "output  : $OUT"
info "pretty  : $PRETTY  split: $SPLIT  attachments: $ATTACH"

# --- run python worker -------------------------------------------------------
# Serialize the project dir list through an env var (newline-separated).
printf '%s\n' "${PROJECT_DIRS[@]}" > /tmp/.mtx-cursor-export-dirs.$$
export EXPORT_PROJECT_DIRS_FILE="/tmp/.mtx-cursor-export-dirs.$$"
export EXPORT_ALL_PROJECTS="$ALL_PROJECTS"
export EXPORT_OUT="$OUT"
export EXPORT_PRETTY="$PRETTY"
export EXPORT_SPLIT="$SPLIT"
export EXPORT_ATTACH="$ATTACH"
export EXPORT_MODE="$MODE"
export EXPORT_THREAD_UUID="$THREAD_UUID"
export EXPORT_CURSOR_ROOT="$CURSOR_ROOT"

python3 - <<'PY'
import json, os, sys, re
from datetime import datetime, timezone
from pathlib import Path

with open(os.environ["EXPORT_PROJECT_DIRS_FILE"]) as f:
    PROJECT_DIRS = [Path(l.strip()).resolve() for l in f if l.strip()]
ALL_PROJECTS = os.environ["EXPORT_ALL_PROJECTS"] == "1"
OUT_PATH     = Path(os.environ["EXPORT_OUT"])
PRETTY       = os.environ["EXPORT_PRETTY"] == "1"
SPLIT        = os.environ["EXPORT_SPLIT"] == "1"
ATTACH       = os.environ["EXPORT_ATTACH"] == "1"
MODE         = os.environ["EXPORT_MODE"]
THREAD_UUID  = os.environ.get("EXPORT_THREAD_UUID", "")
CURSOR_ROOT  = Path(os.environ["EXPORT_CURSOR_ROOT"]).resolve()

def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat().replace("+00:00", "Z")

USER_QUERY_RE = re.compile(r"<user_query>\s*(.*?)\s*</user_query>", re.DOTALL)

def extract_title(messages):
    for m in messages:
        if m["role"] != "user": continue
        for b in m["blocks"]:
            if b.get("type") == "text":
                txt = b.get("text", "") or ""
                match = USER_QUERY_RE.search(txt)
                candidate = (match.group(1) if match else txt).strip()
                if candidate:
                    first_line = candidate.splitlines()[0].strip()
                    if len(first_line) > 200:
                        first_line = first_line[:197] + "..."
                    return first_line
        break
    return None

def load_thread(jsonl_path: Path):
    messages, parse_errors = [], []
    tool_counter = {}
    block_counter = {"text": 0, "tool_use": 0, "other": 0}
    with jsonl_path.open("r", encoding="utf-8", errors="replace") as fp:
        for i, line in enumerate(fp):
            line = line.rstrip("\n")
            if not line.strip(): continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as e:
                parse_errors.append({"line": i, "error": str(e)})
                continue
            role = obj.get("role")
            raw_content = (obj.get("message") or {}).get("content")
            blocks = []
            if isinstance(raw_content, list):
                for b in raw_content:
                    if not isinstance(b, dict):
                        blocks.append({"type": "other", "raw": b})
                        block_counter["other"] += 1
                        continue
                    t = b.get("type")
                    if t == "text":
                        blocks.append({"type": "text", "text": b.get("text", "")})
                        block_counter["text"] += 1
                    elif t == "tool_use":
                        name = b.get("name")
                        blocks.append({
                            "type": "tool_use",
                            "name": name,
                            "id": b.get("id"),
                            "input": b.get("input"),
                        })
                        block_counter["tool_use"] += 1
                        if name:
                            tool_counter[name] = tool_counter.get(name, 0) + 1
                    else:
                        blocks.append({"type": t or "unknown", "raw": b})
                        block_counter["other"] += 1
            elif isinstance(raw_content, str):
                blocks.append({"type": "text", "text": raw_content})
                block_counter["text"] += 1
            messages.append({"index": len(messages), "role": role, "blocks": blocks})
    return messages, parse_errors, tool_counter, block_counter

def build_thread(jsonl_path: Path, project_dir: Path, parent_id=None, kind="root"):
    st = jsonl_path.stat()
    uid = jsonl_path.stem
    messages, parse_errors, tool_counter, block_counter = load_thread(jsonl_path)
    thread = {
        "id": uid,
        "kind": kind,
        "parent_id": parent_id,
        "path": str(jsonl_path),
        "relative_path": str(jsonl_path.relative_to(project_dir)),
        "bytes": st.st_size,
        "created_at": iso(st.st_ctime),
        "modified_at": iso(st.st_mtime),
        "message_count": len(messages),
        "block_counts": block_counter,
        "tool_use_counts": tool_counter,
        "title": extract_title(messages),
        "parse_errors": parse_errors,
        "messages": messages,
        "subagents": [],
    }
    if kind == "root":
        subdir = jsonl_path.parent / "subagents"
        if subdir.is_dir():
            for sp in sorted(subdir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime):
                thread["subagents"].append(
                    build_thread(sp, project_dir, parent_id=uid, kind="subagent")
                )
    return thread

def collect_attachments(project_dir: Path):
    data = {}
    for name in ("canvases", "assets", "uploads", "terminals", "agent-tools", "mcps"):
        d = project_dir / name
        if not d.is_dir(): continue
        entries = []
        for p in sorted(d.rglob("*")):
            if p.is_file():
                st = p.stat()
                entries.append({
                    "path": str(p.relative_to(project_dir)),
                    "bytes": st.st_size,
                    "modified_at": iso(st.st_mtime),
                })
        data[name] = entries
    return data

def walk(t):
    yield t
    for s in t["subagents"]:
        yield from walk(s)

def export_one_project(project_dir: Path):
    transcripts = project_dir / "agent-transcripts"
    if not transcripts.is_dir():
        return None
    root_paths = []
    for child in sorted(transcripts.iterdir()):
        if not child.is_dir(): continue
        p = child / f"{child.name}.jsonl"
        if not p.exists():
            alts = list(child.glob("*.jsonl"))
            if not alts: continue
            p = alts[0]
        root_paths.append(p)
    if MODE == "thread":
        root_paths = [p for p in root_paths if p.stem == THREAD_UUID]
    if not root_paths:
        return None
    root_paths.sort(key=lambda p: p.stat().st_mtime)
    threads = [build_thread(p, project_dir) for p in root_paths]

    total_threads = total_messages = 0
    total_blocks = {"text": 0, "tool_use": 0, "other": 0}
    total_tools = {}
    for t in threads:
        for node in walk(t):
            total_threads += 1
            total_messages += node["message_count"]
            for k, v in node["block_counts"].items():
                total_blocks[k] = total_blocks.get(k, 0) + v
            for k, v in node["tool_use_counts"].items():
                total_tools[k] = total_tools.get(k, 0) + v

    return {
        "project": {
            "slug": project_dir.name,
            "project_dir": str(project_dir),
            "transcripts_dir": str(transcripts),
        },
        "summary": {
            "root_thread_count": len(threads),
            "total_thread_count": total_threads,
            "total_message_count": total_messages,
            "total_block_counts": total_blocks,
            "total_tool_use_counts": total_tools,
        },
        "attachments": collect_attachments(project_dir) if ATTACH else None,
        "threads": threads,
    }

# --- run over every selected project ----------------------------------------
project_exports = []
for pd in PROJECT_DIRS:
    pe = export_one_project(pd)
    if pe is not None:
        project_exports.append(pe)

if not project_exports:
    print("no transcripts found in any selected project", file=sys.stderr)
    sys.exit(3)

# Aggregate summary across projects.
agg = {
    "project_count": len(project_exports),
    "root_thread_count": 0,
    "total_thread_count": 0,
    "total_message_count": 0,
    "total_block_counts": {"text": 0, "tool_use": 0, "other": 0},
    "total_tool_use_counts": {},
}
for pe in project_exports:
    s = pe["summary"]
    agg["root_thread_count"]  += s["root_thread_count"]
    agg["total_thread_count"] += s["total_thread_count"]
    agg["total_message_count"]+= s["total_message_count"]
    for k, v in s["total_block_counts"].items():
        agg["total_block_counts"][k] = agg["total_block_counts"].get(k, 0) + v
    for k, v in s["total_tool_use_counts"].items():
        agg["total_tool_use_counts"][k] = agg["total_tool_use_counts"].get(k, 0) + v

envelope = {
    "export_version": 1,
    "exported_at": iso(datetime.now(tz=timezone.utc).timestamp()),
    "export_mode": MODE,
    "export_thread_uuid": THREAD_UUID or None,
    "all_projects": ALL_PROJECTS,
    "cursor_root": str(CURSOR_ROOT),
    "summary": agg,
    "projects": project_exports,
}

indent = 2 if PRETTY else None
dumps_kwargs = dict(ensure_ascii=False, indent=indent)
if not PRETTY:
    dumps_kwargs["separators"] = (",", ":")

def strip_bodies(t):
    copy = {k: v for k, v in t.items() if k not in ("messages", "subagents")}
    copy["subagent_ids"] = [s["id"] for s in t["subagents"]]
    return copy

if SPLIT:
    OUT_PATH.mkdir(parents=True, exist_ok=True)
    if ALL_PROJECTS:
        # Top-level index lists projects; each project gets its own subdir.
        top_index = dict(envelope)
        top_index["projects"] = []
        for pe in project_exports:
            proj_dir = OUT_PATH / pe["project"]["slug"]
            proj_dir.mkdir(parents=True, exist_ok=True)
            # per-project index
            idx = {
                "project": pe["project"],
                "summary": pe["summary"],
                "attachments": pe["attachments"],
                "threads": [strip_bodies(t) for t in pe["threads"]],
            }
            (proj_dir / "index.json").write_text(
                json.dumps(idx, **dumps_kwargs), encoding="utf-8"
            )
            for t in pe["threads"]:
                (proj_dir / f"{t['id']}.json").write_text(
                    json.dumps(t, **dumps_kwargs), encoding="utf-8"
                )
                for s in t["subagents"]:
                    (proj_dir / f"{s['id']}.json").write_text(
                        json.dumps(s, **dumps_kwargs), encoding="utf-8"
                    )
            top_index["projects"].append({
                "project": pe["project"],
                "summary": pe["summary"],
                "dir": str(proj_dir.relative_to(OUT_PATH)),
            })
        (OUT_PATH / "index.json").write_text(
            json.dumps(top_index, **dumps_kwargs), encoding="utf-8"
        )
    else:
        pe = project_exports[0]
        idx = dict(envelope)
        idx["projects"] = [{
            "project": pe["project"],
            "summary": pe["summary"],
            "attachments": pe["attachments"],
            "threads": [strip_bodies(t) for t in pe["threads"]],
        }]
        (OUT_PATH / "index.json").write_text(
            json.dumps(idx, **dumps_kwargs), encoding="utf-8"
        )
        for t in pe["threads"]:
            (OUT_PATH / f"{t['id']}.json").write_text(
                json.dumps(t, **dumps_kwargs), encoding="utf-8"
            )
            for s in t["subagents"]:
                (OUT_PATH / f"{s['id']}.json").write_text(
                    json.dumps(s, **dumps_kwargs), encoding="utf-8"
                )
    written = str(OUT_PATH)
else:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(envelope, **dumps_kwargs), encoding="utf-8")
    written = str(OUT_PATH)

print(
    f"wrote {written} | "
    f"projects={agg['project_count']} "
    f"root_threads={agg['root_thread_count']} "
    f"threads={agg['total_thread_count']} "
    f"messages={agg['total_message_count']} "
    f"blocks={agg['total_block_counts']}",
    file=sys.stderr,
)
PY

rc=$?
rm -f "$EXPORT_PROJECT_DIRS_FILE"
[[ $rc -eq 0 ]] && success "Done." || error "Export failed (rc=$rc)"
return $rc 2>/dev/null || exit $rc
