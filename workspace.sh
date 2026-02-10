#!/usr/bin/env bash
# MTX workspace: create a fresh Meanwhile-Together multi-repo workspace (empty folder only).
# Prompts, then creates a VS Code workspace file and clones 6 repos.
desc="Create fresh Meanwhile-Together workspace (empty folder); clones MTX, project-bridge, archive-dogfood, test, client-a, cicd"
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
REPOS=(MTX project-bridge test client-a cicd)
WORKSPACE_FILE="Meanwhile-Together.code-workspace"

echo "📦 Creating $WORKSPACE_FILE and cloning ${#REPOS[@]} repos..." >&2

# Build workspace JSON (folders array)
folders_json=""
for repo in "${REPOS[@]}"; do
  [ -n "$folders_json" ] && folders_json="$folders_json,"
  folders_json="$folders_json{\"name\":\"$repo\",\"path\":\"$repo\"}"
done
echo "{\"folders\":[$folders_json]}" > "$WORKSPACE_FILE"

for repo in "${REPOS[@]}"; do
  echo "🔨 clone $repo..." >&2
  git clone "https://github.com/${GITHUB_ORG}/${repo}.git" "$repo"
done

echo "✅ Done. Open $WORKSPACE_FILE in VS Code." >&2
