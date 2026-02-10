#!/usr/bin/env bash
# MTX setup setup: full project setup — rebrand, build, optional deployment (from shell-scripts.md §2, cohesion)
desc="Full project setup: rebrand, build, optional deployment"
set -e

# 1. Identity + apply-names (project name, scope, package.json/app.json)
"$0" project rebrand "$@"

# 2. Build
echo ""
echo "Building..."
"$0" compile all

# 3. Optional deployment
echo ""
read -rp "Run deployment setup (tokens, Terraform, Railway)? (y/N): " do_deploy
if [[ "$do_deploy" =~ ^[Yy]$ ]]; then
  "$0" setup deploy-menu
fi

echo ""
echo "✅ Setup complete. Next: mtx project menu, mtx setup deploy-menu"
