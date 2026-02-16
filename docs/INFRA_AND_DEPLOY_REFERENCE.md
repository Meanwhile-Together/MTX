# Infrastructure & Deploy — MTX + project-bridge (Holistic Reference)

Single reference for infra and deployment across **MTX** (wrapper/CLI) and **project-bridge** (app + Terraform). Use this to understand the full flow, where each piece lives, and how to run or debug deploys.

---

## 1. Where Things Live

| What | Repo / path | Notes |
|------|-------------|--------|
| **Deploy entry (CLI)** | MTX `deploy.sh` | Menu (staging/production), then calls project’s `./terraform/apply.sh` |
| **Apply + deploy logic** | project-bridge `terraform/apply.sh` | Same script is in MTX `terraform/apply.sh`; both resolve PROJECT_ROOT and run Terraform from **project’s** `terraform/` |
| **Terraform (IaC)** | project-bridge only | `terraform/main.tf`, `variables.tf`, `outputs.tf`, `backend.tf`, `modules/railway-owner`, `modules/railway` — **MTX has no main.tf** |
| **Config (app/deploy)** | project-bridge | `config/app.json`, `config/deploy.json` |
| **Secrets** | project-bridge `.env` | `RAILWAY_*` tokens; gitignored |
| **Railway build config** | project-bridge | Root `railway.json` (app), `targets/backend-server/railway.json` (backend) |
| **Setup (first-time + deploy)** | project-bridge `scripts/setup.sh` | Source of truth for deployment setup; can call apply.sh |

**Contract:** Deploy is always run from the **project root** (the repo that has `config/app.json`). That is project-bridge when using the Meanwhile-Together workspace. MTX’s `deploy.sh` runs `./terraform/apply.sh`; apply.sh resolves PROJECT_ROOT (current dir, parent, or `../project-bridge`) so that the same script works whether you run `mtx deploy` from project-bridge or from a parent dir.

---

## 2. End-to-End Deploy Flow

1. **Entry**
   - **Local:** From project root: `mtx deploy` or `mtx deploy staging` (or `./terraform/apply.sh staging` / `./scripts/setup.sh --setup-deployment`).
   - **CI:** project-bridge `.github/workflows/03-deploy-staging.yml` and `04-deploy-production.yml` (see §7; **outdated** vs setup.sh/apply.sh).

2. **Config**
   - apply.sh requires `config/deploy.json` with `platform: ["railway"]` and `config/app.json` with `app.name`, `app.slug`, `app.owner`.

3. **Tokens**
   - **Account token** (`RAILWAY_ACCOUNT_TOKEN` or `RAILWAY_TOKEN`): Terraform + Railway GraphQL (discovery, create project/services). From https://railway.app/account/tokens.
   - **Project tokens (per env):** `RAILWAY_PROJECT_TOKEN_STAGING`, `RAILWAY_PROJECT_TOKEN_PRODUCTION`: used only for `railway up` (deploy code). From Project → Settings → Tokens, scoped to staging or production.
   - Never use project token for Terraform (→ “serviceCreate Not Authorized”). Never use account token for `railway up` (→ Unauthorized).

4. **Resolve workspace & project**
   - Workspace: from `config/app.json` `app.owner` via Railway GraphQL, or `RAILWAY_WORKSPACE_ID` in `.env`.
   - Project: `RAILWAY_PROJECT_ID` in `.env`, or discover by owner name in workspace. Optional: `RAILWAY_PROJECT_ID_STAGING` / `RAILWAY_PROJECT_ID_PRODUCTION` for two-project setup.

5. **Service discovery**
   - GraphQL: list services in project. Names: `backend-staging`, `backend-production`, `{slug}-staging`, `{slug}-production` (slug from app.json).
   - If services exist, their IDs are passed as Terraform vars so Terraform does not recreate (state rm + pass IDs). File `.railway-backend-invalidated` forces backend IDs to be cleared so backends are re-created.

6. **Terraform**
   - Run in **project-bridge/terraform/** (`SCRIPT_DIR = PROJECT_ROOT/terraform`).
   - `terraform init -reconfigure`, optional import of existing project, state rm for legacy or “use existing” resources, then `terraform apply -auto-approve` with TF_VARS.
   - Modules: **railway-owner** (one project, backend-staging, backend-production, optional db), **railway** (app-staging, app-production).

7. **Deploy code (after successful apply)**
   - Read outputs: `railway_app_service_id_staging`/`_production`, `railway_backend_staging_service_id`/`railway_backend_production_service_id`, `railway_project_id`.
   - Ensure env exists (staging/production); prompt for project tokens if missing.
   - **App:** Link `.railway` to app service, `npm run build:server`, `railway up` with **project token** for chosen env.
   - **Backend:** Swap root `railway.json` to `targets/backend-server/railway.json`, `npm run build:backend-server`, `railway link` to backend service, `railway up` with same project token; then restore root `railway.json` and `.railway` link.
   - On backend 404/upload failure: optional self-heal (state rm backend_${env}, touch `.railway-backend-invalidated`, re-run apply).

---

## 3. Railway Model (One Project, Two Environments)

- **One Railway project** per owner (name from `app.owner`).
- **Environments:** `staging`, `production` (Railway environments inside that project).
- **Services (all in same project):**
  - `backend-staging` → backend for staging env.
  - `backend-production` → backend for production env.
  - `{slug}-staging` → app for staging (e.g. `project-bridge-staging`).
  - `{slug}-production` → app for production.

Terraform creates or adopts these; apply.sh discovers existing IDs and passes them in so nothing is destroyed.

---

## 4. Terraform Modules (project-bridge)

- **terraform/main.tf**
  - Reads `config/app.json` and `config/deploy.json`.
  - If `platform` contains `railway`: calls `module.railway_owner` and `module.railway_app`.

- **modules/railway-owner**
  - One `railway_project` (imported in apply.sh when using existing project).
  - `railway_service.backend_staging` / `backend_production` (count 0 if existing ID passed).
  - Optional `railway_service.db` (create_db_service).
  - Outputs: project id, backend_staging_service_id, backend_production_service_id, db_service_id.

- **modules/railway**
  - `railway_service.app_staging` / `app_production` (count 0 if existing ID passed).
  - service_name_base from app slug (e.g. `project-bridge`).
  - Outputs: service_id_staging, service_id_production, etc.

- **State:** `backend "local" { path = "terraform.tfstate" }` in project-bridge/terraform/backend.tf. Terraform Cloud block is commented out.

---

## 5. Config Files

- **config/app.json:** `app.name`, `app.owner`, `app.slug` (and version, etc.). Owner used for workspace/project naming and discovery.
- **config/deploy.json:** `platform: ["railway"]`, optional `projectId`, `staging.healthEndpoints`, `production.healthEndpoints`.
- **.env (project-bridge):** `RAILWAY_WORKSPACE_ID`, `RAILWAY_PROJECT_ID`, `RAILWAY_ACCOUNT_TOKEN`, `RAILWAY_PROJECT_TOKEN_STAGING`, `RAILWAY_PROJECT_TOKEN_PRODUCTION`. Optional: `RAILWAY_PROJECT_ID_STAGING`, `RAILWAY_PROJECT_ID_PRODUCTION`.
- **railway.json (root):** App build/start (RAILPACK; build:server; start `node targets/server/dist/index.js`).
- **targets/backend-server/railway.json:** Backend build/start (build:backend-server + build:backend; start `node targets/backend-server/dist/index.js`). apply.sh temporarily copies this to root for backend `railway up`.

---

## 6. MTX Script Behaviour

- **mtx deploy** [staging|production]: runs `./terraform/apply.sh [env]` from **current directory** (project root). If you run from project-bridge, that’s project-bridge/terraform/apply.sh.
- **mtx terraform apply** (if exposed): would run the same apply.sh (from MTX’s copy); PROJECT_ROOT resolution can point to `../project-bridge`, so Terraform still runs in project-bridge/terraform (because SCRIPT_DIR = PROJECT_ROOT/terraform and PROJECT_ROOT is set to the dir that has config/app.json).
- Preconditions (e.g. `precond/01-is-projectb.sh`) run before commands; they don’t change deploy behaviour.

---

## 7. CI (GitHub Actions) — Outdated vs Local

- **Source of truth for deploy:** project-bridge **scripts/setup.sh** and **terraform/apply.sh** (and thus `mtx deploy` when run from project-bridge). DEPLOYMENT.md states that **GitHub Actions workflows are outdated**.
- **03-deploy-staging.yml / 04-deploy-production.yml:**
  - Use Terraform Cloud backend and TF_VAR_* that don’t match current variables.tf (e.g. `railway_create_backend_service`, `railway_backend_service_id`, single `railway_service_id`).
  - Use `deployment-project-id` from **deploy.json** `projectId` (often empty); current apply.sh uses **Terraform outputs** and discovery, not projectId for deploy.
  - Railway deploy step uses `railway-app/railway-deploy@v1` with `service: deployment-project-id` — that’s a service ID, but CI doesn’t get env-specific app/backend service IDs from Terraform outputs.
- To align CI with current behaviour you’d: use same Terraform vars as apply.sh, run apply (or plan/apply) in project-bridge/terraform, read `railway_app_service_id_staging`/`railway_app_service_id_production` and optionally backend IDs from outputs, then run deploy (e.g. Railway CLI or action) per service with the correct project token per environment.

---

## 8. Knowledge Gaps Filled

- **Where is Terraform defined?** Only in **project-bridge** (terraform/*.tf and modules). MTX only has a copy of apply.sh and FLOW.md.
- **Who runs Terraform?** apply.sh, which runs in **project-bridge/terraform** whenever PROJECT_ROOT is project-bridge (normal case when you run from project-bridge or apply.sh finds it).
- **Two apply.sh copies?** MTX and project-bridge have the same apply.sh; PROJECT_ROOT resolution ensures the **project’s** terraform dir and .env are used.
- **Token roles:** Account = Terraform + API. Project token staging/production = `railway up` only, per environment.
- **Backend vs app deploy:** App uses root railway.json and build:server; backend deploy swaps in backend-server/railway.json and uses build:backend-server, then restores.
- **Self-heal:** Backend 404/upload failure can trigger state rm of backend_${env} and `.railway-backend-invalidated` so next apply recreates backend.
- **DATABASE_URL:** In Railway, app/backend use private URL (e.g. from Postgres plugin or Backend service); per-app DB name `{slug}_{env}` via shared helpers; no URL mutation for in-project services.

---

## 9. Quick Commands (from project-bridge root)

```bash
# Full setup + first-time deploy (prompts for tokens, creates envs, runs Terraform + deploy)
./scripts/setup.sh --setup-deployment

# Non-interactive (use existing .env)
./scripts/setup.sh --setup-deployment -y

# Redeploy only (infra already exists)
./terraform/apply.sh staging
./terraform/apply.sh production

# Or via MTX (from project-bridge)
mtx deploy staging
mtx deploy production
```

---

## 10. Related Docs

- **MTX:** `terraform/FLOW.md` (state and logic flows), `docs/getting-started.md`, `docs/script-patterns.md`, `docs/mtx-patterns.md`.
- **project-bridge:** `docs/rulebooks/DEPLOYMENT.md` (token table, build order, troubleshooting), `docs/rulebooks/DEPLOYMENT2.md` (minimal shell + Terraform), `docs/MTX_AND_PROJECT_B.md` (MTX ↔ project-bridge relationship).

This document is the single place to see how MTX and project-bridge together implement infra and deploy; use the related docs above for deeper detail on tokens, builds, or script patterns.
