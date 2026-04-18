# MTX scaffolding model (payloads, templates, org, admin)

This document is the **single narrative** for how **MTX `create`** relates to **project-bridge** hosting. Read this before [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md) for deploy mechanics.

---

## Core idea

| Concept | What it is |
|--------|------------|
| **Payload** | Anything the unified server loads from `server.apps`: client apps, org surface, admin UI, etc. **Same mechanism** (path, package, or git). |
| **Payload app template** | **`template-payload`** — default GitHub/local folder name for **`mtx create payload`**. **Single-app** shape at repo root (Vite SPA, `npm run build` → `dist/`), like **`payload-admin`**, **not** an org host tree with `payloads/*` + unified server scripts. Override with **`MTX_PAYLOAD_TEMPLATE_REPO`**. |
| **Org host template** | **`template-org`** — default for **`mtx create org`**: multi-app / host layout (`payloads/`, `prepare:railway`, org build scripts, `config/` aligned with project-bridge). Override with **`MTX_ORG_TEMPLATE_REPO`**. |
| **Forkable `template-*` snapshots** | **`mtx create template [name]`** (run from a **payload** repo root) copies the tree into **`template-<name>`** beside MTX (excludes `.git`, `node_modules`, `dist`, …). Point **`MTX_PAYLOAD_TEMPLATE_REPO`** at that folder/repo so **`mtx create payload`** clones your custom starter. |
| **Org surface** | Usually **one shared** org payload (one git repo or path), **reused** across tenants; **routing and config** differ per deployment (`domains`, `pathPrefix`, env). **`mtx create org`** is for the **exceptional** case where you need a **separate org product line** as its own `org-*` repo. |
| **Admin** | **A payload**, not a separate platform. Typically **`payload-admin`** with **`staticDir: "dist"`** in server config. |

**`template-basic`** (legacy name) is the **old unified default**; it matches the **org host** shape. Prefer **`template-org`** for org scaffolds and **`template-payload`** for new app repos. Until GitHub repos are renamed, keep a **local sibling** named **`template-org`** (for example `ln -sf template-basic template-org` next to MTX) or set **`MTX_ORG_TEMPLATE_REPO=template-basic`**.

**Mis-scaffolded `payload-*`:** repos that look like **org hosts** but use a **`payload-*`** name (top-level **`payloads/`**, **`prepare:railway`**, etc.) need a **deliberate migration** — flatten to single-app or reclassify as **`org-*`**. Playbook: [PAYLOAD_ORG_SHAPE_MIGRATION.md](PAYLOAD_ORG_SHAPE_MIGRATION.md).

---

## Commands (what to use when)

| Goal | Command | Repo / result |
|------|---------|-----------------|
| New **customer / app** repo | **`mtx create payload [name]`** (legacy: `mtx create [name]` without the `payload` keyword still works; prefer the explicit form — [MTX_COMMAND_SURFACE.md](MTX_COMMAND_SURFACE.md)) | **`payload-*`** from **`MTX_PAYLOAD_TEMPLATE_REPO`** (default **`template-payload`**) |
| New **payload template** from an existing payload | `cd` into payload root, then **`mtx create template [name]`** | Snapshots cwd → **`template-*`** beside MTX; then point **`MTX_PAYLOAD_TEMPLATE_REPO`** (or **`MTX_TEMPLATE_SOURCE_REPO`** in docs for the same idea) at it for **`mtx create payload`** |
| New **org product repo** (rare) | **`mtx create org [name]`** | **`org-*`** from **`MTX_ORG_TEMPLATE_REPO`** (default **`template-org`**). Template **`config/`** matches project-bridge ( **`app.json`** full shape, **`deploy*.json`**, **`server*.example`**, **`backend*.json`**, examples). **Interactive prompts** (with defaults): repo name, slug, owner, version, dev/staging/prod URLs, optional Railway **`projectId`**, **`server.json`** port / `projectRoot` / `stateDir`. Non-interactive: set **`MTX_ORG_*`** env vars (see `lib/create-from-template.sh` header). Vendors **`terraform/`** from sibling **`project-bridge`** when present. **`npm run dev`** / **`build:server`** / **`prepare:railway`**: project-bridge comes **only** from your workspace (`../project-bridge`, **`PROJECT_BRIDGE_ROOT`**, or **`vendor/`** after **`prepare:railway`**); hosts do not fetch it remotely. Railway: **`npm run prepare:railway`** then **`railway up`**; build mirrors **`targets/server/dist`**. |
| **Register** a payload on a host | **`mtx payload install <payload-id>`** from the host root (or edit **`config/server.json`** **`apps[]`** by hand) | No **`mtx create`** required if the repo already exists |

### Standalone React auto-migration (`mtx create payload`)

When you run `mtx create payload` **from inside a standalone React app root**, MTX now auto-detects that context and performs migration without a separate import step:

1. Scaffolds a new `payload-*` repo from the configured payload template.
2. Migrates the current app into `payload-<slug>/payloads/<slug>/`.
3. By default, **moves** source content out of the original app root after successful migration.

Default behavior is move-first for clean handoff. If you want copy-only behavior:

```bash
MTX_CREATE_MOVE_SOURCE=0 mtx create payload "My App"
```

Detection is intentionally strict to avoid false positives. It must look like a React app root (`package.json` with `react`) and not already be a standard host/payload root (`config/app.json`, `terraform/`, or `payloads/` present).

---

## Universal org (default mental model)

Most deployments should use **one org payload** (single `source.git` or `source.path`) and **separate tenants** via:

- **Domains / path prefixes** in config  
- **Environment** and **grants** (see project-bridge admin docs)

Use **`mtx create org`** when you truly need a **new repository** for a different org **product** (different codebase), not for each tenant.

---

## Admin as a payload

- **Admin UI** is loaded like any other app: an entry in **`server.apps`** (often built from **`payload-admin`** with **`staticDir`** / path).  
- **Subtype** “admin” is expressed by **convention** (`slug`, `name`, `id`) and routing—not by a separate MTX template category.  
- A **second client** or **second admin style** is either another **payload repo** or another **build** of the same repo—**business choice**, not a framework split.

---

## Naming rule

- **`template-payload`** — canonical default **source** for **`mtx create payload`** (single-app payload repo).  
- **`template-org`** — canonical default **source** for **`mtx create org`** (org host / multi-app bundle).  
- **`template-<name>`** (other names) — typically a **snapshot** produced by **`mtx create template`**; treat as a **custom** forkable starter and point **`MTX_PAYLOAD_TEMPLATE_REPO`** at it when you want **`mtx create payload`** to clone that tree instead.

---

## Env vars (quick reference)

| Variable | Role |
|----------|------|
| **`MTX_PAYLOAD_TEMPLATE_REPO`** | Source repo/folder name for **`mtx create payload`** (default **`template-payload`**) |
| **`MTX_ORG_TEMPLATE_REPO`** | Source repo/folder name for **`mtx create org`** (default **`template-org`**) |
| **`MTX_TEMPLATE_SOURCE_REPO`** | Documented alias for “which template-* should `mtx create payload` clone”; use **`MTX_PAYLOAD_TEMPLATE_REPO`** in scripts (same effect). |

---

## Compatibility baseline for new payloads

When scaffolding new `payload-*` repos, keep these compatibility conventions so hosts pass startup validation and routing checks:

- Include payload manifest export contract hints (`exports.views`, `exports.api`) when generating bundle manifests.
- Prefer static view routes; if dynamic patterns are needed (e.g. `/foo/:id`), keep them explicit and avoid catch-all patterns in manifest routing metadata.
- Keep client bundles free of secret-like keys (`*_SECRET`, private tokens, API keys) in exposed config manifests.
- For protected views, use shared auth/view gating helpers built around `AuthContext` instead of ad-hoc checks.

---

## See also

- [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md) — create + deploy steps  
- [PAYLOAD_ORG_SHAPE_MIGRATION.md](PAYLOAD_ORG_SHAPE_MIGRATION.md) — mis-scaffolded org-shaped **`payload-*`** (legacy **`template-basic`**) — flatten vs **`org-*`**  
- [project-bridge: Payload creation and server config](../../project-bridge/docs/PAYLOAD_CREATION_AND_SERVER_CONFIG.md) — `server.apps` registration (GitHub: [link](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/PAYLOAD_CREATION_AND_SERVER_CONFIG.md))  
