#!/usr/bin/env bash
# Deprecated: master lane is automatic when you `mtx deploy` from org-project-bridge.
desc="Deprecated — use mtx deploy from org-project-bridge (master lane is automatic)"
nobanner=1
set -e
echo "❌ mtx deploy asadmin is removed." >&2
echo "   Run: mtx deploy staging|production  from the org-project-bridge repo (canonical master host)." >&2
echo "   Master JWT rotation and Railway master secrets run automatically on that tree only." >&2
exit 2
