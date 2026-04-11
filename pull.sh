#!/usr/bin/env bash
# Fetch origin and hard-reset each workspace sibling repo to match the remote tip (discards local commits and dirty trees).
# Repo list: includes/workspace-repos.sh (same as mtx workspace). Override root: MTX_WORKSPACE_ROOT (default: parent of MTX).
desc="Fetch and hard-reset all workspace repos to origin (main/master); discards local changes"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=includes/workspace-repos.sh
source "$MTX_ROOT/includes/workspace-repos.sh"

WORKSPACE_ROOT="${MTX_WORKSPACE_ROOT:-$(cd "$MTX_ROOT/.." && pwd)}"
WORKSPACE_ROOT="$(cd "$WORKSPACE_ROOT" && pwd)"

case "${1:-}" in
  -h|--help|help)
    echo "Usage: mtx pull"
    echo "  For each repo in the workspace list (see MTX/includes/workspace-repos.sh):"
    echo "    git fetch origin --prune"
    echo "    git checkout -B <branch> origin/<branch>   (default branch: origin/HEAD, else main, else master)"
    echo ""
    echo "  Workspace root: $WORKSPACE_ROOT (set MTX_WORKSPACE_ROOT to override)"
    echo "  Destructive: uncommitted work and unpushed commits in those repos are discarded."
    exit 0
    ;;
esac

echo "Workspace root: $WORKSPACE_ROOT"
echo "⚠️  This will hard-reset each repo to match origin (local changes and unpushed commits are discarded)."
read -rp "Continue? (y/N): " answer
if [[ ! "${answer:-}" =~ ^[Yy]$ ]]; then
  echo "Cancelled." >&2
  exit 0
fi

mtx_pull_resolve_branch() {
  local dir="$1"
  local b
  b=$(git -C "$dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|ref: refs/remotes/origin/||')
  if [ -n "$b" ] && git -C "$dir" rev-parse -q --verify "origin/$b" >/dev/null 2>&1; then
    echo "$b"
    return 0
  fi
  for b in main master; do
    if git -C "$dir" rev-parse -q --verify "origin/$b" >/dev/null 2>&1; then
      echo "$b"
      return 0
    fi
  done
  return 1
}

failures=0
for repo in "${MTX_WORKSPACE_REPOS[@]}"; do
  path="$WORKSPACE_ROOT/$repo"
  if [ ! -d "$path" ]; then
    echo "⏭️  skip (missing): $repo"
    continue
  fi
  if [ ! -d "$path/.git" ]; then
    echo "⏭️  skip (not a git repo): $repo"
    continue
  fi
  echo ""
  echo "━━ $repo ━━"
  if ! git -C "$path" fetch origin --prune; then
    echo "❌ fetch failed: $path" >&2
    failures=$((failures + 1))
    continue
  fi
  branch="$(mtx_pull_resolve_branch "$path")" || {
    echo "❌ could not resolve origin/main or origin/master: $path" >&2
    failures=$((failures + 1))
    continue
  }
  if ! git -C "$path" checkout -B "$branch" "origin/$branch"; then
    echo "❌ checkout/reset failed: $path" >&2
    failures=$((failures + 1))
    continue
  fi
  echo "✅ $repo @ $branch ($(git -C "$path" rev-parse --short HEAD))"
done

echo ""
if [ "$failures" -gt 0 ]; then
  echo "Done with $failures failure(s)." >&2
  exit 1
fi
echo "✅ All repos updated."
