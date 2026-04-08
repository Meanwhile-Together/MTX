# ADR-001: Single-App Hardening First, Then Multi-App Host

**Status:** Accepted  
**Date:** 2026-03-27  
**Context:** Meanwhile-Together platform (MTX + project-bridge unified server).

## Context

The platform must support a **project-bridge central host** that serves **payloads** (apps) with strict **mutual agnosticism**, clear **deploy orchestration**, and a phased rollout: **solidify single-app operation before** enabling full multi-payload hosts.

## Decision

### Locked architecture

| Topic | Decision |
|-------|----------|
| Deploy SOT | **MTX** is the source of truth for human and CI deploy entry (`mtx deploy`). Terraform/apply are implementation details behind MTX, not the primary user contract. |
| Topology (now) | **Shared host (A)** — one app-host service per env carries bundled payloads; roadmap to **hybrid (C)** (promote dedicated hosts when policy requires). |
| Railway layout | **One project per owner**; **two service roles** per environment: **app-host** (unified server, app payloads) and **backend/admin** (unified server, admin payload + backend addons). |
| Payload identity | **`payloadEntry.id`** — canonical internal key (grants, audit, stable references). **`payloadEntry.slug`** — URL and routing segment (`/api/<slug>`). |
| Isolation | **A + B:** (A) **DB boundary** — default payload-scoped schema/DB; (B) **service boundary** — cross-payload access only via **admin-governed**, auditable paths. |
| App-host packaging | **Bundled (B)** — payload build outputs copied into the host artifact at build time; deterministic; supports offline-capable client releases. |
| Deploy target resolution | **Hybrid (C)** — bootstrap by **service name** discovery; **persist service IDs** in `.env`; steady-state deploys prefer **IDs**. |

### Phased delivery

1. **Stage 1 — Single-app hardening:** One payload on the app-host lane; harden deploy, identity, DB policy, manifest, CI parity, rollback; pass `npm run verify:platform` in project-bridge.
2. **Stage 2 — Multi-app host:** Multiple payloads in `server.apps`; preserve routing/context alignment; admin grants; ops controls.
3. **Roadmap — Hybrid:** Document promotion from shared to dedicated host; no mandatory implementation before multi-app host work is stable.

## Consequences

- New “apps” are **payloads + config**, not new Railway services per app (in shared-host mode).
- **Legacy “new app = new project-bridge-shaped repo”** documentation is superseded for product narrative; see [MISALIGNMENT.md](../MISALIGNMENT.md) if drift reappears.
- Apple / store programs (e.g. mini-app hosts) are **out of scope** for this ADR; legal eligibility is separate.

## Related documents

- [MTX_DEPLOY_CONTRACT.md](../MTX_DEPLOY_CONTRACT.md)
- [SERVICE_LANE_SEPARATION.md](../SERVICE_LANE_SEPARATION.md)
- project-bridge: [PAYLOAD_CREATION_AND_SERVER_CONFIG.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/PAYLOAD_CREATION_AND_SERVER_CONFIG.md) (payload `id` vs `slug`), `docs/PAYLOAD_DATABASE_POLICY.md`, `docs/BUNDLE_MANIFEST.md`, `docs/PLATFORM_VERIFY_CRITERIA.md`, `docs/ADMIN_GRANTS_AND_AUDIT.md`, `docs/MULTI_APP_OPS_AND_INCIDENTS.md`, [CURRENT_ARCHITECTURE.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/CURRENT_ARCHITECTURE.md) (hybrid host roadmap §10)
