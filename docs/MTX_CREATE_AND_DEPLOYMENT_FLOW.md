# MTX Create & Holistic Deployment Flow

This document describes the **desired end-to-end flow**: how a **new app** is created, how **project-bridge** runs as the central host, how **admin/backend** and **payloads** deploy, and how everything works together. It has been updated to reflect that **an app is fundamentally a payload** hosted by project-bridge, and that **creating a new app** is not necessarily forking project-bridge.

**Related references:**

- **MTX:** [INFRA_AND_DEPLOY_REFERENCE.md](INFRA_AND_DEPLOY_REFERENCE.md) — Tokens, config, Terraform, Railway, CI.
- **project-bridge:** [MASTER_FLOW_AND_MTX_CREATE_PLAN.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MASTER_FLOW_AND_MTX_CREATE_PLAN.md) — Earlier fork-based plan (see divergence below).
- **project-bridge:** [SERVER_CONFIG.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/SERVER_CONFIG.md), [PAYLOAD_CREATION_AND_SERVER_CONFIG.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/PAYLOAD_CREATION_AND_SERVER_CONFIG.md) — Payload = app, config-driven hosting.
- **project-bridge:** [logic/deployment-flow.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/logic/deployment-flow.md), [terraform/DEPLOY-MASTER-BACKEND.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/terraform/DEPLOY-MASTER-BACKEND.md) — Deploy flow, master vs Project Backend.
- **MTX:** [MISALIGNMENT.md](MISALIGNMENT.md) — Code and docs that still state the old (fork-based) flow or are misaligned with payload = app.

---

## Architecture shift: payload = app, project-bridge = central host

**What changed from the original (fork-based) documentation:**

| Old (fork-based) model | Current / desired model |
|------------------------|-------------------------|
| **New app** = fork of project-bridge (clone, rebrand, new repo). Every app is its own full project-bridge repo. | **New app** = **payload**. An app is fundamentally a **payload**: a bundle (path, package, or git) that the server **hosts** and serves. You do **not** need to fork project-bridge to create a new app. |
| project-bridge = “the framework” as in “the repo you fork to get an app.” | **project-bridge = central framework that runs and hosts** — one (or few) deployments of project-bridge **point to** many payloads (apps) via `config/server.json`. |
| **mtx create** = only path: clone project-bridge → rebrand → fork → push. | **`mtx create`** (see §2.2) creates a **payload** repo from **`template-basic`** (or `MTX_PAYLOAD_TEMPLATE_REPO`) — not a project-bridge fork. The **primary** way to add an app to an **existing** host is still **create/register a payload** in `server.apps` (path, package, or git). |

**Implications:**

- **One host, many apps:** A single project-bridge deployment can serve many apps by listing multiple payloads in `server.apps` (with optional `domains` / `pathPrefix` for routing).
- **Creating a new app** = (1) Create the payload (copy template or scaffold, implement views/routes), (2) Add an entry to **config/server.json** under `server.apps` with `id`, `name`, `slug`, `source` (path, package, or git), (3) Restart/redeploy the host so the new payload is loaded. No server code change; no fork of project-bridge required.
- **Full project-bridge clone** (optional): For a **standalone host** repo, clone/rebrand **project-bridge** manually or from your own template — **`mtx create`** does **not** do this today (see §2.2).

---

## 1. The Big Picture

| Layer | What it is | How it’s created / deployed |
|-------|------------|-----------------------------|
| **Central host** | **project-bridge** — runs the unified server, **hosts** payloads (apps) via `config/server.json` | Deploy **one** project-bridge instance (or one per tenant/org); it **points to** many payloads. |
| **App** | A **payload**: one entry in `server.apps` with `source` (path, package, or git). The server discovers and serves it; no server code change to add one. | **New app** = new payload: create payload code, add entry to `config/server.json`; optionally source from **git** (own repo). Redeploy host or restart. |
| **Infrastructure (Railway)** | One project per owner; staging + production; 4 services (backend-staging, backend-production, app-staging, app-production) | **mtx deploy** → **terraform/apply.sh** — discover or create project/services, then deploy the **host** (project-bridge) code. |
| **Admin/backend servers** | Same **unified server** with `config/server.json` listing the **admin** payload; serves admin UI + backend addons | **mtx deploy** / **mtx deploy asadmin** — backend services get server + backend build, `railway up`. |
| **App (payload) serving** | Same **unified server** with `config/server.json` listing **app payloads**; serves client UIs by domain/path | **mtx deploy** — app services get server build; at runtime the host serves all payloads listed in config. |

**One binary, two deploy shapes:** The same server is deployed twice per environment: (1) **backend service** = admin payload + backend addons; (2) **app service** = app payloads only. Mode is determined by **config** (`server.json`), not by a different binary. The **host** (project-bridge) is what you deploy; **apps** are payloads the host points to.

---

## 2. Creating a New App: Payload vs Fork

**In the current model, “new app” = new payload** (hosted by project-bridge). **`mtx create`** scaffolds a **payload** repo (§2.2). A **full standalone project-bridge** deployment is a separate, manual process.

### 2.1 Primary path: new app = new payload (no fork)

1. **Create the payload** — Copy a payload template (e.g. **`template-basic`**, client-portal), or scaffold a minimal payload (views, routes, schema as needed). The payload can live in the **same repo** as project-bridge (e.g. under **`demo/`** or a path pointed to by config) or in its **own repo**.
2. **Register on the host** — Add an entry to **config/server.json** under `server.apps` (or `payloads`) with `id`, `name`, `slug`, and **source**:
   - **path** — e.g. `"./payloads/my-app"` (relative to project root).
   - **package** — e.g. `"@org/my-payload"` (resolved from `node_modules`).
   - **git** — e.g. `{ "url": "https://github.com/org/my-app.git", "ref": "main" }`; server clones into `stateDir/payloads/<slug>` at startup. So the **app can be a separate repo**; project-bridge just points to it.
3. **Redeploy or restart** — So the host picks up the new payload. No server code change; config-only.

**Optional future:** `npm run create-payload` or `mtx payload create` could scaffold a payload folder and optionally add the `server.apps` entry (see project-bridge PAYLOAD_CREATION_AND_SERVER_CONFIG.md).

### 2.2 `mtx create` today: new **payload** repo from a template (not a project-bridge fork)

**Implemented behavior** ([`MTX/create.sh`](https://github.com/Meanwhile-Together/MTX/blob/main/create.sh)):

1. **Template** — Clones **`template-basic`** by default (`MTX_PAYLOAD_TEMPLATE_REPO` overrides; `MTX_GITHUB_ORG` defaults to `Meanwhile-Together`), or uses a local clone at `$WORKSPACE_ROOT/$TEMPLATE_REPO`.
2. **Naming** — Repo name is forced to **`payload-*`** via `ensure_payload_prefix`.
3. **Metadata** — Rewrites `package.json` / `README` for the new slug; **`gh repo create`** + push when `gh` is available.
4. **Registration** — Script prints a **`server.apps`** snippet for **project-bridge** `config/server.json` so the host can load the new payload (path/package/git as you choose).

**Subcommands:** **`mtx create payload`** (same as plain **`mtx create`**), **`mtx create org`** → **`org-*`**, **`mtx create template`** → **`template-*`**. The template subcommand uses the same machinery; the GitHub repo name prefix is **`template-`**, and the clone source defaults to **`template-basic`** unless **`MTX_TEMPLATE_SOURCE_REPO`** or **`MTX_PAYLOAD_TEMPLATE_REPO`** is set.

A **standalone full project-bridge fork** is **not** what `create.sh` does today; that remains a **manual** or separate flow if you need an entire host repo. Target **customer `client-*` repos** from [docs/finalize/06_TARGET_ARCHITECTURE_LOCKED.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/finalize/06_TARGET_ARCHITECTURE_LOCKED.md) are **future MTX/template work**, not `create.sh` yet.

### 2.3 Principles (updated)

- **project-bridge = central host** — It **runs and hosts**; it points to payloads (apps) via `config/server.json`. You do not need to fork it to create a new app.
- **Payload = app** — Creating a new app is creating a payload and registering it (path, package, or git); the host serves it.
- **Standalone host** — Forking **project-bridge** for a whole new deployment is **not** what **`mtx create`** automates; use **payload** registration + **`mtx deploy`** on a host repo, or maintain a full clone manually.
- **CICD repo** — Deprecated; deploy is via MTX and/or project-bridge’s own workflows.

---

## 3. How Deploy Provisions Infrastructure (Terraform + Railway)

Deploy is the **single path** that both provisions infrastructure and deploys code. It is invoked as **mtx deploy** or **mtx deploy asadmin** (from project root or workspace); both invoke **MTX’s** **`terraform/apply.sh`**, which resolves **PROJECT_ROOT** to the repo that has `config/app.json` so Terraform and `.env` live in the **project’s** directory.

### 3.1 Entry points

| Command | Effect |
|---------|--------|
| **mtx deploy** [staging\|production] | Menu if no env → runs **MTX** `terraform/apply.sh` for that env. Provisions infra (if needed), then deploys **app** and **backend** code. |
| **mtx deploy asadmin** [staging\|production] | Same as above, but sets **RUN_AS_MASTER=true** and ensures **MASTER_JWT_SECRET** (prompt if missing); apply.sh persists these to .env and sets them on the **backend** Railway service. So the backend for that run is the **master** (auth at `/auth`). |

### 3.2 Config and tokens (required for apply.sh)

- **config/app.json** — `app.name`, `app.slug`, `app.owner` (owner used for Railway workspace/project naming and discovery).
- **config/deploy.json** — `platform: ["railway"]`, optional `projectId`, health endpoints per env.
- **.env** (project root):  
  - **Account:** `RAILWAY_ACCOUNT_TOKEN` (or `RAILWAY_TOKEN`) — Terraform + Railway GraphQL (discovery, create project/services).  
  - **Project (per env):** `RAILWAY_PROJECT_TOKEN_STAGING`, `RAILWAY_PROJECT_TOKEN_PRODUCTION` — used only for `railway up` (deploy code).  
  - Optional: `RAILWAY_WORKSPACE_ID`, `RAILWAY_PROJECT_ID` (or `RAILWAY_PROJECT_ID_STAGING` / `_PRODUCTION` for two-project setup).  
  - For **asadmin:** `MASTER_JWT_SECRET` (and optionally `MASTER_AUTH_ISSUER`, `MASTER_CORS_ORIGINS`).

### 3.3 apply.sh flow (high level)

1. **Resolve PROJECT_ROOT** — Directory containing `config/app.json` (current, parent, or `../project-bridge`). Load `.env` from there.
2. **Parse config** — `config/deploy.json` (platform array), `config/app.json` (name, slug, owner).
3. **Railway tokens** — Ensure account token (prompt if missing, persist to .env). Project token for chosen env (staging/production) required for deploy step.
4. **Resolve workspace** — From `app.owner` via GraphQL or `RAILWAY_WORKSPACE_ID`.
5. **Resolve project** — From `.env` or discover by owner name in workspace. If existing project ID is used, Terraform will **import** it so it doesn’t create a duplicate.
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

1. **Central host** — One (or few) project-bridge deployment(s). Deploy the **host** via **mtx deploy** from the project-bridge repo: apply.sh provisions Railway project + four services, deploys app and backend code. The **app service** runs the unified server with `config/server.json` listing the payloads (apps) it hosts.
2. **New app** — Create a payload (code + optional own repo); add an entry to **config/server.json** under `server.apps` with `source` (path, package, or **git**). Redeploy the host (or restart). The new app is now served by the same host; no fork of project-bridge.
3. **Instant “new app”** — No new infra per app. Add config + payload; the host already running serves it (by domain/path). Git source means the app can live in a separate repo and the host just points to it.

**Fork path (optional, standalone):**

1. **mtx create** — Clone/fork project-bridge, rebrand, push to `owner/slug`. You now have a **full** project-bridge repo (your own host).
2. **mtx deploy** — From that repo: same apply.sh, same infra + app + backend deploy. That deployment is a **standalone** instance; you can add payloads to *its* `server.apps` the same way.

**Unified:** Admin/backend and app (payload) serving are still the same apply.sh and same binary; they differ only by config. The shift is that **the thing you deploy is the host** (project-bridge), and **apps are payloads the host points to** — so creating a new app is creating a payload and registering it, not necessarily forking the repo.

---

## 7. Summary Table

| Concern | Where it lives | How it’s done |
|--------|----------------|----------------|
| **Central host** | **project-bridge** | One deployment runs the server and **hosts** payloads (apps) via `config/server.json`. |
| **New app (primary)** | Payload + **config/server.json** | Create payload; add entry to `server.apps` with `id`, `name`, `slug`, `source` (path, package, or **git**). No fork. |
| **New app (optional)** | MTX **create.sh** | Fork path: clone project-bridge → rebrand → fork/create repo → push (full standalone host). |
| App identity (host) | **config/app.json** (project) | name, owner, slug for the **host** (Railway project naming, etc.). |
| Payload (app) identity | **config/server.json** `server.apps` | Each entry: id, name, slug, source; optional domains, pathPrefix. |
| Deploy config | **config/deploy.json** (project) | platform: ["railway"], health endpoints. |
| Infra (Railway) | **project-bridge/terraform/** | main.tf, modules/railway-owner, modules/railway. |
| Apply + deploy | **terraform/apply.sh** | Resolve PROJECT_ROOT, tokens, discovery, Terraform apply, then app + backend `railway up` (deploys the **host**). |
| Admin/backend deploy | Same apply.sh | Backend services; server + admin payload; optional RUN_AS_MASTER + MASTER_JWT_SECRET (asadmin). |
| Payload registration | **config/server.json** | server.apps entries; no server code change; source can be path, package, or git. |
| Master auth | **mtx deploy asadmin** + backend env | RUN_AS_MASTER, MASTER_JWT_SECRET on backend; master mounts /auth; Project Backends verify tokens. |

**Takeaway:** project-bridge is the **central framework that runs and hosts**; **payloads are apps**. Creating a new app is fundamentally **creating a payload and pointing the host at it** (config + optional git repo). The fork path (mtx create) remains for full standalone deployments but is not the primary definition of "new app."

---

## What’s different from the original (fork-based) doc

| Topic | Original doc | This revision |
|-------|--------------|----------------|
| **New app** | Always a fork of project-bridge (clone, rebrand, new repo). | **Primary:** New app = new **payload** (add to `server.apps`; source path/package/git). **Optional:** Fork via mtx create for standalone host. |
| **project-bridge** | “The framework” = the repo you fork to get an app. | **Central host** = runs once, **points to** many payloads (apps) via `config/server.json`. |
| **mtx create** | The single entry for “new app”; produces a fork. | One option for a **full standalone** host; “new app” is mainly “new payload + config.” |
| **Instant provisioning** | mtx create → repo; mtx deploy → infra + that repo’s app/backend. | Deploy the **host** once; new apps = add payloads to config (and optionally git repos); no new infra per app. |
