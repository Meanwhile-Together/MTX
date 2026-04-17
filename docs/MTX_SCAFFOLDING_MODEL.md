# MTX scaffolding model (payloads, templates, org, admin)

This document is the **single narrative** for how **MTX `create`** relates to **project-bridge** hosting. Read this before [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md) for deploy mechanics.

---

## Core idea

| Concept | What it is |
|--------|------------|
| **Payload** | Anything the unified server loads from `server.apps`: client apps, org surface, admin UI, etc. **Same mechanism** (path, package, or git). |
| **Payload templates** | **`template-*`** repos are **for payloads only**. **`mtx create payload`** clones from **`MTX_PAYLOAD_TEMPLATE_REPO`** (default **`template-basic`**). To publish a **new** template from an existing payload, run **`mtx create template [name]`** from **that payload’s repo root**; it snapshots the tree into **`template-<name>`** (excludes `.git`, `node_modules`, `dist`, …). |
| **Org surface** | Usually **one shared** org payload (one git repo or path), **reused** across tenants; **routing and config** differ per deployment (`domains`, `pathPrefix`, env). **`mtx create org`** exists for the **exceptional** case where you need a **separate org product line** as its own `org-*` repo. |
| **Admin** | **A payload**, not a separate platform. Typically **`payload-admin`** (or another app entry) with **`slug`/name** expressing “admin”; add another payload template later only if you need a **second admin product line**. |

**Templates in MTX mean “templates for building payloads.”** We do **not** maintain parallel template families for org or admin as first-class `mtx create` types—those surfaces are still **payloads**, distinguished in **`config/server.json`** (`id`, `name`, `slug`, optional fields you add later).

---

## Commands (what to use when)

| Goal | Command | Repo / result |
|------|---------|-----------------|
| New **customer / app** repo | `mtx create payload [name]` or `mtx create [name]` | **`payload-*`** from `MTX_PAYLOAD_TEMPLATE_REPO` (default **`template-basic`**) |
| New **payload template** from an existing payload | `cd` into payload root, then `mtx create template [name]` or `mtx template create [name]` | Snapshots cwd → **`template-*`** beside MTX; then point **`MTX_PAYLOAD_TEMPLATE_REPO`** / **`MTX_TEMPLATE_SOURCE_REPO`** at it for **`mtx create payload`** |
| New **org product repo** (rare) | `mtx create org [name]` | **`org-*`** from `MTX_ORG_TEMPLATE_REPO` (default **`template-basic`**). Template **`config/`** matches project-bridge ( **`app.json`** full shape, **`deploy*.json`**, **`server*.example`**, **`backend*.json`**, examples). **Interactive prompts** (with defaults): repo name, slug, owner, version, dev/staging/prod URLs, optional Railway **`projectId`**, **`server.json`** port / `projectRoot` / `stateDir`. Non-interactive: set **`MTX_ORG_*`** env vars (see `lib/create-from-template.sh` header). Vendors **`terraform/`** from sibling **`project-bridge`** when present. **`npm run dev`** / **`build:server`** / **`prepare:railway`**: project-bridge comes **only** from your workspace (`../project-bridge`, **`PROJECT_BRIDGE_ROOT`**, or **`vendor/`** after **`prepare:railway`**); hosts do not fetch it remotely. Railway: **`npm run prepare:railway`** then **`railway up`**; build mirrors **`targets/server/dist`**. |
| **Register** any payload | Edit **project-bridge** `config/server.json` **`apps[]`** | No MTX create required if code already exists |

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

**`template-<name>`** always means a **payload** template (scaffold for **`mtx create payload`**). There is no separate `template-org-*` / `template-admin-*` MTX command—org and admin are **payloads** in **`server.apps`**, not different template taxonomies.

---

## Env vars (quick reference)

| Variable | Role |
|----------|------|
| **`MTX_PAYLOAD_TEMPLATE_REPO`** | Source repo for **`mtx create payload`** (default **`template-basic`**) |
| **`MTX_ORG_TEMPLATE_REPO`** | Source repo for **`mtx create org`** (default **`template-basic`**) |
| **`MTX_TEMPLATE_SOURCE_REPO`** | When **`mtx create template`**, which repo to clone **from** (defaults chain to **`template-basic`**) |

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
- [project-bridge: Payload creation and server config](../../project-bridge/docs/PAYLOAD_CREATION_AND_SERVER_CONFIG.md) — `server.apps` registration (GitHub: [link](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/PAYLOAD_CREATION_AND_SERVER_CONFIG.md))  
