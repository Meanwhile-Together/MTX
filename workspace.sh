#!/usr/bin/env bash
# MTX workspace: create a fresh Meanwhile-Together multi-repo workspace (empty folder only).
# Prompts, then creates a VS Code workspace file and clones the full current repo set (see REPOS).
desc="Create fresh Meanwhile-Together workspace (empty folder); clones full MT repo list (REPOS in script)"
set -e

# Require empty folder (only ., .., and optionally .git)
if [ -n "$(find . -maxdepth 1 ! -name . ! -name .git -print -quit 2>/dev/null)" ]; then
  echo "❌ This folder is not empty. Run mtx workspace from an empty directory." >&2
  exit 1
fi

echo ""
echo ""
echo ""
read -rp "Create a fresh Meanwhile-Together workspace here? (y/N): " answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
  echo "Cancelled." >&2
  exit 0
fi

GITHUB_ORG="Meanwhile-Together"
MTX_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=includes/workspace-repos.sh
source "$MTX_SCRIPT_DIR/includes/workspace-repos.sh"
REPOS=("${MTX_WORKSPACE_REPOS[@]}")
WORKSPACE_FILE="Meanwhile-Together.code-workspace"

echo "📦 Creating $WORKSPACE_FILE and cloning ${#REPOS[@]} repos..." >&2

# Build workspace JSON (folders array)
folders_json=""
for repo in "${REPOS[@]}"; do
  [ -n "$folders_json" ] && folders_json="$folders_json,"
  folders_json="$folders_json{\"name\":\"$repo\",\"path\":\"$repo\"}"
done
echo "{\"folders\":[$folders_json]}" > "$WORKSPACE_FILE"

clone_failures=0
for repo in "${REPOS[@]}"; do
  echo "🔨 clone $repo..." >&2
  if ! git clone "https://github.com/${GITHUB_ORG}/${repo}.git" "$repo"; then
    echo "⚠️  clone failed (private, renamed, or not on GitHub yet): $repo — add manually if needed." >&2
    clone_failures=$((clone_failures + 1))
  fi
done

if [ "$clone_failures" -gt 0 ]; then
  echo "✅ Workspace file written; $clone_failures repo(s) failed to clone. Open $WORKSPACE_FILE in VS Code." >&2
else
  echo "✅ Done. Open $WORKSPACE_FILE in VS Code." >&2
fi
