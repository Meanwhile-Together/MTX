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
| New **org product repo** (rare) | `mtx create org [name]` | **`org-*`** from `MTX_ORG_TEMPLATE_REPO` (default **`template-basic`**). Template **`config/`** matches project-bridge ( **`app.json`** full shape, **`deploy*.json`**, **`server*.example`**, **`backend*.json`**, examples). **Interactive prompts** (with defaults): repo name, slug, owner, version, dev/staging/prod URLs, optional Railway **`projectId`**, **`server.json`** port / `projectRoot` / `stateDir`. Non-interactive: set **`MTX_ORG_*`** env vars (see `lib/create-from-template.sh` header). Vendors **`terraform/`** from sibling **`project-bridge`** when present. Adds **`projectb`: `file:../project-bridge`**, **`npm run dev`** (`org-dev-server.sh`), **`npm run build:server`**, **`railway.json`**: dev/build snapshot project-bridge **`config/`**, apply org **`config/`**, **restore** on exit; build mirrors **`targets/server/dist`** (**`PROJECT_BRIDGE_ROOT`** / **`vendor/project-bridge`** supported). |
| **Register** any payload | Edit **project-bridge** `config/server.json` **`apps[]`** | No MTX create required if code already exists |

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

## See also

- [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md) — create + deploy steps  
- [project-bridge: Payload creation and server config](../../project-bridge/docs/PAYLOAD_CREATION_AND_SERVER_CONFIG.md) — `server.apps` registration (GitHub: [link](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/PAYLOAD_CREATION_AND_SERVER_CONFIG.md))  
