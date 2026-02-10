#!/usr/bin/env bash
# MTX setup setup: full project setup — rebrand, build, optional deployment (from shell-scripts.md §2, cohesion)
set -e

cd "$ROOT_"

# 1. Identity + apply-names (project name, scope, package.json/app.json)
"$0" dev rebrand "$@"

# 2. Build
echo ""
echo "Building..."
"$0" dev build all

# 3. Optional deployment
echo ""
read -rp "Run deployment setup (tokens, Terraform, Railway)? (y/N): " do_deploy
if [[ "$do_deploy" =~ ^[Yy]$ ]]; then
  "$0" setup deploy-menu
fi

echo ""
echo "✅ Setup complete. Next: mtx dev menu, mtx setup deploy-menu"
