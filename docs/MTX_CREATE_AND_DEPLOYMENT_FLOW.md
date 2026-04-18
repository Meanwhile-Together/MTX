# MTX Create & Holistic Deployment Flow

This document describes the **desired end-to-end flow**: how a **new app** is created, how an **org host** (`org-*`) is the **deploy root** that runs the unified server and **hosts payloads**, how **admin/backend** and **payloads** deploy, and how **project-bridge** fits in as the **framework monorepo** (not “the repo you fork to go live”). **Creating a new app** is **payload + `server.apps`**; **creating a new host** is **`mtx create org`** / **`template-org`** — not cloning project-bridge as a standalone product host.

**Related references:**

- **MTX:** [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md) — **Authoritative story:** payload vs **`template-*`** payload templates, org defaults, admin as payload.
- **MTX:** [INFRA_AND_DEPLOY_REFERENCE.md](INFRA_AND_DEPLOY_REFERENCE.md) — Tokens, config, Terraform, Railway, CI.
- **project-bridge:** [MASTER_FLOW_AND_MTX_CREATE_PLAN.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MASTER_FLOW_AND_MTX_CREATE_PLAN.md) — Earlier fork-based plan (see divergence below).
- **project-bridge:** [SERVER_CONFIG.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/SERVER_CONFIG.md), [PAYLOAD_CREATION_AND_SERVER_CONFIG.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/PAYLOAD_CREATION_AND_SERVER_CONFIG.md) — Payload = app, config-driven hosting.
- **project-bridge:** [logic/deployment-flow.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/logic/deployment-flow.md), [terraform/DEPLOY-MASTER-BACKEND.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/terraform/DEPLOY-MASTER-BACKEND.md) — Deploy flow, master vs Project Backend.
- **MTX:** [MISALIGNMENT.md](MISALIGNMENT.md) — Code and docs that still state the old (fork-based) flow or are misaligned with payload = app.

---

## Architecture shift: payload = app, org host = deploy root, project-bridge = framework

**What changed from the original (fork-based) documentation:**

| Old (fork-based) model | Current / desired model |
|------------------------|-------------------------|
| **New app** = fork of project-bridge (clone, rebrand, new repo). Every app is its own full project-bridge repo. | **New app** = **payload**. An app is a **payload** (path, package, or git) registered in **`server.apps`**. You do **not** fork project-bridge to add an app. |
| project-bridge = “the repo you fork to get a host.” | **Org host (`org-*`)** = deploy root: **`mtx create org`**, `config/`, `payloads/`, **`mtx deploy`**. **project-bridge** = **framework** (packages, reference Terraform, templates) consumed **into** org hosts — **not** the long-term “standalone deploy target” for operators. |
| **mtx create** = only path: clone project-bridge → rebrand → fork → push. | **`mtx create payload`** / plain **`mtx create`** → **`payload-*`** from **`template-payload`**. **`mtx create org`** → **`org-*`** host. **`mtx create template`** → **`template-*`**. None of these clone project-bridge as a host. |

**Implications:**

- **One org host, many apps:** An **`org-*`** deployment lists multiple payloads in `server.apps` (with optional `domains` / `pathPrefix` for routing).
- **Creating a new app** = (1) Create the payload (copy template or scaffold), (2) Add **`server.apps`** entry, (3) Redeploy or restart the **org host**. No project-bridge fork.
- **No canonical “standalone project-bridge fork” path** in documentation: **horizon** — deploy-from-bridge-root-only shrinks; **org host** is the only first-class story ([rule-of-law.md](rule-of-law.md) §1, §5–§6).

---

## 1. The Big Picture

| Layer | What it is | How it’s created / deployed |
|-------|------------|-----------------------------|
| **Org host (deploy root)** | **`org-*`** repo — unified server + **`config/server.json`** + **`payloads/`** (see **`template-org`**) | **`mtx create org`** then **`mtx deploy`** from that root; **points to** many payloads via `server.apps`. **During migration**, some teams still use a **project-bridge** checkout as the directory with `config/app.json` — that is **transitional**, not the documented end state ([rule-of-law.md](rule-of-law.md) §6). |
| **App** | A **payload**: one entry in `server.apps` with `source` (path, package, or git). The server discovers and serves it; no server code change to add one. | **New app** = new payload: create payload code, add entry to `config/server.json`; optionally source from **git** (own repo). Redeploy org host or restart. |
| **Infrastructure (Railway)** | One Railway project per **deploy root** (`.env` `RAILWAY_PROJECT_ID`); staging + production; unified app services `{slug}-staging` / `{slug}-production` | **mtx deploy** → **deploy/terraform/apply.sh** — discover or create project/services, then deploy **host** artifacts from the org root. |
| **Admin/backend servers** | Same **unified server** with `config/server.json` listing the **admin** payload; serves admin UI + backend addons | **mtx deploy** / **mtx deploy asadmin** — backend services get server + backend build, `railway up`. |
| **App (payload) serving** | Same **unified server** with `config/server.json` listing **app payloads**; serves client UIs by domain/path | **mtx deploy** — app services get server build; at runtime the host serves all payloads listed in config. |

**One binary, two deploy shapes:** The same server is deployed twice per environment: (1) **backend service** = admin payload + backend addons; (2) **app service** = app payloads only. Mode is determined by **config** (`server.json`), not by a different binary. The **org host** is what you deploy; **apps** are payloads the host registers; **project-bridge** supplies framework pieces, not a “fork me to deploy” product story.

---

## 2. Creating a New App (payload) vs Creating a Host (org)

**“New app” = new payload** registered on an **org host**. **`mtx create payload`** scaffolds a **`payload-*`** repo (§2.2). **“New host”** = **`mtx create org`** → **`org-*`**; that repo is where **`mtx deploy`** runs. There is **no** documented path to “stand up production by forking project-bridge alone.”

### 2.1 Primary path: new app = new payload (no fork)

1. **Create the payload** — Copy a payload template (e.g. **`template-payload`**, client-portal), or scaffold a minimal payload (views, routes, schema as needed). The payload can live in the **same repo** as project-bridge (e.g. under **`demo/`** or a path pointed to by config) or in its **own repo**.
2. **Register on the host** — Add an entry to **config/server.json** under `server.apps` (or `payloads`) with `id`, `name`, `slug`, and **source**:
   - **path** — e.g. `"./payloads/my-app"` (relative to project root).
   - **package** — e.g. `"@org/my-payload"` (resolved from `node_modules`).
   - **git** — e.g. `{ "url": "https://github.com/org/my-app.git", "ref": "main" }`; server clones into `stateDir/payloads/<slug>` at startup. So the **app can be a separate repo**; project-bridge just points to it.
3. **Redeploy or restart** — So the host picks up the new payload. No server code change; config-only.

**Optional future:** `npm run create-payload` or **`mtx create payload`** could scaffold a payload folder and optionally add the `server.apps` entry (see project-bridge PAYLOAD_CREATION_AND_SERVER_CONFIG.md). **`mtx payload install`** registers an existing package on a host ([MTX_COMMAND_SURFACE.md](MTX_COMMAND_SURFACE.md)).

### 2.2 `mtx create` today: new **payload** repo from a template (not a project-bridge fork)

**Implemented behavior** ([`MTX/create.sh`](https://github.com/Meanwhile-Together/MTX/blob/main/create.sh)):

1. **Template** — Clones **`template-payload`** by default (`MTX_PAYLOAD_TEMPLATE_REPO` overrides; `MTX_GITHUB_ORG` defaults to `Meanwhile-Together`), or uses a local clone at `$WORKSPACE_ROOT/$TEMPLATE_REPO`.
2. **Naming** — Repo name is forced to **`payload-*`** via `ensure_payload_prefix`.
3. **Metadata** — Rewrites `package.json` / `README` for the new slug; **`gh repo create`** + push when `gh` is available.
4. **Registration** — Script prints a **`server.apps`** snippet for **project-bridge** `config/server.json` so the host can load the new payload (path/package/git as you choose).

**Subcommands:**

| Command | Repo prefix | Role |
|---------|-------------|------|
| **`mtx create payload`** (same as plain **`mtx create`**) | **`payload-*`** | New **app** repo; clone source **`MTX_PAYLOAD_TEMPLATE_REPO`** (default **`template-payload`**). |
| **`mtx create template`** | **`template-*`** | **From a payload root:** snapshots the current directory into a new **`template-*`** repo (rsync/copy; excludes `.git`, `node_modules`, `dist`, …). Must **`cd`** into the payload first. Others may set **`MTX_TEMPLATE_SOURCE_REPO`** / **`MTX_PAYLOAD_TEMPLATE_REPO`** to that repo so **`mtx create payload`** clones from it. |
| **`mtx create org`** | **`org-*`** | Use when you need a **separate org product repo**. The usual model is **one shared org payload** + tenant **routing/config**; see [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md). |

**Admin** is not a separate MTX template type: it is a **payload** (e.g. **`payload-admin`**) registered like any other app.

**`create.sh` never clones project-bridge as a host.** Customer **`client-*`** or legacy layouts are **out of band** unless captured in your own **org** template.

### 2.3 Principles (updated)

- **Org host = deploy root** — **`org-*`** holds `config/`, `payloads/`, and runs **`mtx deploy`**. It **hosts** payloads via `config/server.json`.
- **project-bridge = framework** — Source for packages, reference **`terraform/`**, and CI alignment; **not** the operator story “fork bridge → that fork is your host.”
- **Payload = app** — New app = payload + **`server.apps`** entry; the org host serves it.
- **CICD repo** — Deprecated; deploy is via MTX and org-host workflows.

---

## 3. How Deploy Provisions Infrastructure (Terraform + Railway)

Deploy is the **single path** that both provisions infrastructure and deploys code. It is invoked as **mtx deploy** or **mtx deploy asadmin** (from **org host** project root or workspace); both invoke **MTX’s** **`deploy/terraform/apply.sh`**, which resolves **PROJECT_ROOT** to the tree that contains **`config/app.json`** (normatively an **`org-*`** host; legacy **project-bridge** checkouts may still satisfy that until migration).

### 3.1 Entry points

| Command | Effect |
|---------|--------|
| **mtx deploy** [staging\|production] | Menu if no env → runs **MTX** `deploy/terraform/apply.sh` for that env. Provisions infra (if needed), then deploys **app** and **backend** code. |
| **mtx deploy asadmin** [staging\|production] | Same as above, but sets **RUN_AS_MASTER=true** and ensures **MASTER_JWT_SECRET** (prompt if missing); apply.sh persists these to .env and sets them on the **backend** Railway service. So the backend for that run is the **master** (auth at `/auth`). |

### 3.2 Config and tokens (required for apply.sh)

- **config/app.json** — `app.name`, `app.slug`, `app.owner` (`owner` helps Railway **workspace** discovery and the **default name** for a **new** Railway project when Terraform creates one).
- **config/deploy.json** — `platform: ["railway"]`, optional `projectId`, health endpoints per env.
- **.env** (project root):  
  - **Account:** `RAILWAY_ACCOUNT_TOKEN` (or `RAILWAY_TOKEN`) — Terraform + Railway GraphQL (discovery, create project/services).  
  - **Project (per env):** `RAILWAY_PROJECT_TOKEN_STAGING`, `RAILWAY_PROJECT_TOKEN_PRODUCTION` — used only for `railway up` (deploy code).  
  - Optional: `RAILWAY_WORKSPACE_ID`, `RAILWAY_PROJECT_ID` (or `RAILWAY_PROJECT_ID_STAGING` / `_PRODUCTION` for two-project setup).  
  - For **asadmin:** `MASTER_JWT_SECRET` (and optionally `MASTER_AUTH_ISSUER`, `MASTER_CORS_ORIGINS`).

### 3.3 apply.sh flow (high level)

1. **Resolve PROJECT_ROOT** — Directory containing `config/app.json` (current, parent, or discovery paths apply.sh implements). Load `.env` from there.
2. **Parse config** — `config/deploy.json` (platform array), `config/app.json` (name, slug, owner).
3. **Railway tokens** — Ensure account token (prompt if missing, persist to .env). Project token for chosen env (staging/production) required for deploy step.
4. **Resolve workspace** — From `app.owner` via GraphQL or `RAILWAY_WORKSPACE_ID`.
5. **Resolve project** — From `.env` (`RAILWAY_PROJECT_ID`) or discover by name in workspace. If an existing project ID is set, Terraform will **import** it so it doesn’t create a duplicate.
6. **Service discovery** — GraphQL list services in project; look for `backend-staging`, `backend-production`, `{slug}-staging`, `{slug}-production`. If found, pass IDs as Terraform vars so Terraform **adopts** them (state rm + pass IDs); no destroy/recreate.
7. **Terraform** — `terraform init -reconfigure`, optional import of existing project, state rm for legacy or “use existing” resources, then **terraform apply -auto-approve** with TF_VARS. Modules: **railway-owner** (one project, backend-staging, backend-production, optional db), **railway** (app-staging, app-production).
8. **Outputs** — After apply: `railway_app_service_id_staging` / `_production`, `railway_backend_staging_service_id` / `railway_backend_production_service_id`, `railway_project_id`.
9. **Deploy code (same run):**
   - **App service** — Link `.railway` to app service ID, `npm run build:server`, `railway up` with **project token** for chosen env. Root `railway.json` defines build/start for the **app** (server serving app payloads).
   - **Backend service** — Swap root `railway.json` to backend variant (`railway.backend.json` or `targets/backend-server/railway.json`), `npm run build:server` + `npm run build:backend`, `railway link` to backend service, `railway up` with same project token; optionally set `MASTER_JWT_SECRET` (and for asadmin, `RUN_AS_MASTER`) on the backend service via CLI; then restore root `railway.json` and `.railway` link.

So **one run** of **mtx deploy** (or **mtx deploy asadmin**) can: create or adopt Railway project and four services, then deploy both **app** and **backend** code. That is the “instant provisioning” of the full stack.

---

## 4. How Admin / Backend Servers Deploy

- **Backend** = one Railway **service** per environment (`backend-staging`, `backend-production`). It runs the **unified server** in **backend mode**: `config/server.json` lists a single payload with **slug: "admin"** and `source.path` pointing to the admin static (e.g. `./targets/backend/dist`). The server then serves admin UI + backend addons (`/api/internal/admin`, etc.).
- **Master vs Project Backend** — Same binary. If **RUN_AS_MASTER=1** (and **MASTER_JWT_SECRET**), that deployment is the **master**: it mounts `/auth` (login, /me, register, /verify) and issues JWTs. **Project Backends** do not mount `/auth`; they only **verify** master-issued JWTs. **mtx deploy asadmin** sets `RUN_AS_MASTER` and `MASTER_JWT_SECRET` on the backend service so that deploy is the master for that env.
- **Build** — Backend deploy uses a build that includes **server + admin static** (e.g. `npm run build:server` and `npm run build:backend`). Root `railway.json` is temporarily replaced by a backend-specific one so Railway runs the correct build/start for the backend service.
- **Where it lives** — Terraform creates or adopts the backend services; apply.sh deploys the backend artifact to those services and can set `MASTER_JWT_SECRET` (and for asadmin, `RUN_AS_MASTER`) via Railway CLI.

So: **admin servers** = backend Railway services; they deploy with the **same apply.sh** flow as the app; **mtx deploy asadmin** only changes env (RUN_AS_MASTER + MASTER_JWT_SECRET) so that backend is the master.

---

## 5. How Payloads Deploy (App Service)

- **Payloads** are **config-driven**. The server reads `config/server.json` (or `server.json` at project root); `server.apps` (or `payloads`) lists entries with `id`, `name`, `slug`, `source` (path, package, or git), and optional `domains`, `pathPrefix`, `staticDir`, `apiPrefix`. The server builds a payload registry at startup and resolves each `source`; **no server code change** is required to add a payload—only config and (if new) the payload folder/package.
- **App service** = Railway service that runs the **unified server** in **front-end mode**: `config/server.json` lists **app payloads** (e.g. client-portal, demo) and optionally domains; **no** payload with `slug: "admin"`. The same server binary is deployed with this config; it serves app UIs by domain/path.
- **Deploy** — For the **app** service, apply.sh runs `npm run build:server` (and any app payload builds that feed into the server’s static/assets), then `railway up` to the **app** service ID. The built artifact includes the server and the app payload static assets; at runtime the server uses `server.json` to know which payloads to serve and where.
- **Adding a new payload** — (1) Add payload code (e.g. copy client-portal, rename, implement views/routes). (2) Add an entry to `config/server.json` under `server.apps` with `source` pointing to that payload. (3) Build and deploy as usual; no change to Terraform or apply.sh—payloads are just part of the app build and config.

So: **payloads** don’t have separate “payload deploy” steps; they are part of the **app** service build and config. Backend (admin) is the other service, with its own config that lists only the admin payload.

---

## 6. How Everything Works Together

**Payload-as-app (primary):**

1. **Org host** — One (or few) **`org-*`** deployments. From the org repo root, **`mtx deploy`**: apply.sh provisions Railway project + four services, deploys app and backend. The **app service** runs the unified server with `config/server.json` listing the payloads (apps) it hosts. **project-bridge** remains the **framework** source vendored or linked per **`template-org`** — not a separate “fork bridge to get a host” step.
2. **New app** — Create a payload (code + optional own repo); add an entry to **config/server.json** under `server.apps` with `source` (path, package, or **git**). Redeploy the org host (or restart). No project-bridge fork.
3. **Instant “new app”** — No new infra per app. Add config + payload; the host already running serves it (by domain/path). Git source means the app can live in a separate repo and the host just points to it.

**New host (org):**

1. **`mtx create org`** — New **`org-*`** repo from **`template-org`** (or `MTX_ORG_TEMPLATE_REPO`): org layout, `config/`, **`prepare:railway`** as applicable. That repo **is** the deploy root — not a clone of project-bridge marketed as the product host.
2. **`mtx deploy`** — From that **org** root: same apply.sh contract, infra + app + backend. Add payloads to **`server.apps`** the same way as on any host.

**Unified:** Admin/backend and app (payload) serving use the same apply.sh and same binary; they differ only by config. **Deploy root = org host**; **apps = payloads**; **project-bridge = framework**, eventually **not** a standalone deploy-by-itself operator target ([rule-of-law.md](rule-of-law.md) §6).

---

## 7. Summary Table

| Concern | Where it lives | How it’s done |
|--------|----------------|----------------|
| **Org host (deploy root)** | **`org-*`** ( **`mtx create org`** / **`template-org`** ) | One deployment runs the server and **hosts** payloads via `config/server.json`. **project-bridge** = framework inputs, not “the host you fork.” |
| **New app (primary)** | Payload + **config/server.json** | Create payload; add entry to `server.apps` with `id`, `name`, `slug`, `source` (path, package, or **git**). No project-bridge fork. |
| **New host** | **`mtx create org`** | New **`org-*`** repo; **`mtx deploy`** from that root — not a standalone project-bridge-fork narrative. |
| App identity (host) | **config/app.json** (project) | name, owner, slug for the **host** (Railway project naming, etc.). |
| Payload (app) identity | **config/server.json** `server.apps` | Each entry: id, name, slug, source; optional domains, pathPrefix. |
| Deploy config | **config/deploy.json** (project) | platform: ["railway"], health endpoints. |
| Infra (Railway) | **`$PROJECT_ROOT/terraform/`** on the **org host** (often vendored from or aligned with **project-bridge** `terraform/`) | main.tf, modules/railway-owner, modules/railway. |
| Apply + deploy | **deploy/terraform/apply.sh** | Resolve PROJECT_ROOT, tokens, discovery, Terraform apply, then app + backend `railway up` (deploys the **org host**). |
| Admin/backend deploy | Same apply.sh | Backend services; server + admin payload; optional RUN_AS_MASTER + MASTER_JWT_SECRET (asadmin). |
| Payload registration | **config/server.json** | server.apps entries; no server code change; source can be path, package, or git. |
| Master auth | **mtx deploy asadmin** + backend env | RUN_AS_MASTER, MASTER_JWT_SECRET on backend; master mounts /auth; Project Backends verify tokens. |

**Takeaway:** **Org host** runs and hosts; **payloads are apps**. Creating a new app is **payload + `server.apps`**. Creating a new deployable host is **`mtx create org`**, not “fork project-bridge.” **project-bridge** is **framework** (packages, reference Terraform); operator docs must **not** treat **standalone deploy-from-bridge** as canonical or eventual ([rule-of-law.md](rule-of-law.md) §1, §6).

---

## What’s different from the original (fork-based) doc

| Topic | Original doc | This revision |
|-------|--------------|----------------|
| **New app** | Always a fork of project-bridge (clone, rebrand, new repo). | **Primary:** New app = new **payload** (`server.apps`). **Host:** **`org-*`** via **`mtx create org`** — not “fork project-bridge for a host.” |
| **project-bridge** | “The framework” = the repo you fork to get an app. | **Framework monorepo** — consumed into **org hosts**; **not** the long-term standalone deploy story. |
| **mtx create** | The single entry for “new app”; produces a fork. | **`payload-*` / `org-*` / `template-*`** scaffolds from templates — **never** “clone project-bridge as host.” |
| **Instant provisioning** | mtx create → repo; mtx deploy → infra + that repo’s app/backend. | Deploy the **org host** once; new apps = add payloads to config (and optionally git repos); no new infra per app. |
