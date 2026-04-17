# Infrastructure & Deploy — MTX + project-bridge (Holistic Reference)

Single reference for infra and deployment across **MTX** (wrapper/CLI) and **project-bridge** (app + Terraform). Use this to understand the full flow, where each piece lives, and how to run or debug deploys.

**Create / scaffolding narrative (payload vs **`template-*`** payload templates vs org):** [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md).

---

## 1. Where Things Live

| What | Repo / path | Notes |
|------|-------------|--------|
| **Deploy entry (CLI)** | MTX `deploy.sh` | Menu (staging/production), then always runs **`$MTX_ROOT/terraform/apply.sh`** (MTX’s copy — never the project tree’s `terraform/apply.sh`) |
| **Apply + deploy logic** | MTX `terraform/apply.sh` + project-bridge `terraform/` | **`deploy.sh`** invokes **only** MTX’s `terraform/apply.sh`. That script resolves **PROJECT_ROOT** to the directory containing `config/app.json` (usually **project-bridge**) and runs Terraform from **`$PROJECT_ROOT/terraform/`**. A **copy** of `apply.sh` also exists under project-bridge for direct runs (e.g. `./terraform/apply.sh` from project root); keep copies in sync. See [MTX_DEPLOY_CONTRACT.md](MTX_DEPLOY_CONTRACT.md). |
| **Terraform (IaC)** | project-bridge only | `terraform/main.tf`, `variables.tf`, `outputs.tf`, `backend.tf`, `modules/railway-owner`, `modules/railway` — **MTX has no main.tf** |
| **Config (app/deploy)** | project-bridge | `config/app.json`, `config/deploy.json` |
| **Secrets** | project-bridge `.env` | `RAILWAY_*` tokens; gitignored |
| **Railway build config** | project-bridge | Root `railway.json` (app), `targets/backend-server/railway.json` (backend) |
| **Setup (first-time + deploy)** | project-bridge `scripts/setup.sh` | Source of truth for deployment setup; can call apply.sh |

**Contract:** **`mtx deploy`** runs **MTX’s** `terraform/apply.sh` only. That script finds **PROJECT_ROOT** (the tree with `config/app.json` — typically **project-bridge**) and executes Terraform in **`$PROJECT_ROOT/terraform/`**. You may also run **`./terraform/apply.sh`** directly from project-bridge root (project’s copy); behavior should match when PROJECT_ROOT is the same.

---

## 2. End-to-End Deploy Flow

1. **Entry**
   - **Local:** From project root: `mtx deploy` or `mtx deploy staging` (or `./terraform/apply.sh staging` / `./scripts/setup.sh --setup-deployment`).
   - **CI:** project-bridge `.github/workflows/03-deploy-staging.yml` and `04-deploy-production.yml` — provision/deploy entry aligned with **`bash MTX/deploy.sh`** (see [project-bridge docs/CI_MTX_DEPLOY.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/CI_MTX_DEPLOY.md)); details in §7.

2. **Config**
   - apply.sh requires `config/deploy.json` with `platform: ["railway"]` and `config/app.json` with `app.name`, `app.slug`, `app.owner`.

3. **Tokens**
   - **Account token** (`RAILWAY_ACCOUNT_TOKEN` or `RAILWAY_TOKEN`): Terraform + Railway GraphQL (discovery, create project/services). From https://railway.app/account/tokens.
   - **Project tokens (per env):** `RAILWAY_PROJECT_TOKEN_STAGING`, `RAILWAY_PROJECT_TOKEN_PRODUCTION`: used only for `railway up` (deploy code). From Project → Settings → Tokens, scoped to staging or production.
   - Never use project token for Terraform (→ “serviceCreate Not Authorized”). Never use account token for `railway up` (→ Unauthorized).

4. **Resolve workspace & project**
   - Workspace: from `config/app.json` `app.owner` via Railway GraphQL, or `RAILWAY_WORKSPACE_ID` in `.env`.
   - Project: `RAILWAY_PROJECT_ID` in `.env`, or discover by project name in workspace. Optional: `RAILWAY_PROJECT_ID_STAGING` / `RAILWAY_PROJECT_ID_PRODUCTION` for two-project setup.

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

### 2.1 GitHub and CI

GitHub Actions (and any other CI) should use the **same flow** as local `mtx deploy`: Terraform outputs (e.g. `railway_app_service_id_staging` / `railway_app_service_id_production`) drive the deploy step, not a single `deployment-project-id` from config. For the full task list (aligning workflows, secrets, and optional MTX invocation), see **project-bridge** [docs/OUTSTANDING_WORK.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/OUTSTANDING_WORK.md) (sections 1 and 4).

---

## 3. Railway Model (One Project per Deploy Root, Two Environments)

- **One Railway project** per **deploy root** (the repo where you run `mtx deploy`): selected by `RAILWAY_PROJECT_ID` in that repo’s `.env`, or created when missing. `app.owner` helps **workspace** discovery and supplies the **default name** when Terraform creates a project; it is not a platform rule that each “owner” globally gets exactly one Railway project. Multiple org repos can share a workspace and either **different** projects or the **same** project with **different** `{slug}-*` services, depending on how you set `.env`.
- **Environments:** `staging`, `production` (Railway environments inside that project).
- **Services (in that project):** unified server deploys to **`{slug}-staging`** / **`{slug}-production`**. Legacy `backend-*` names may still appear in older state; new layouts use the app services only.

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

- **config/app.json:** `app.name`, `app.owner`, `app.slug` (and version, etc.). `owner` helps workspace discovery and the default name when Terraform **creates** a Railway project; the live project is always whatever `RAILWAY_PROJECT_ID` points to.
- **config/deploy.json:** `platform: ["railway"]`, optional `projectId`, `staging.healthEndpoints`, `production.healthEndpoints`.
- **.env (project-bridge):** `RAILWAY_WORKSPACE_ID`, `RAILWAY_PROJECT_ID`, `RAILWAY_ACCOUNT_TOKEN`, `RAILWAY_PROJECT_TOKEN_STAGING`, `RAILWAY_PROJECT_TOKEN_PRODUCTION`. Optional: `RAILWAY_PROJECT_ID_STAGING`, `RAILWAY_PROJECT_ID_PRODUCTION`.
- **railway.json (root):** App build/start (RAILPACK; build:server; start `node targets/server/dist/index.js`).
- **targets/backend-server/railway.json:** Backend build/start (build:backend-server + build:backend; start `node targets/backend-server/dist/index.js`). apply.sh temporarily copies this to root for backend `railway up`.

### 5.1 PostgreSQL and `DATABASE_URL` (each org app service)

The **unified server** deploys to **`{slug}-staging`** / **`{slug}-production`** only. A separate backend service no longer auto-provides the database. **Each** of those app services needs **`DATABASE_URL`** (and **`JWT_SECRET`**) in Railway, usually by adding **PostgreSQL** in the same project and **referencing** its `DATABASE_URL` on the app service variables. See project-bridge **[RAILWAY_DATABASE.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/RAILWAY_DATABASE.md)** (Railway database templates, variable references, optional Terraform `railway_create_db_service` caveat).

---

## 6. MTX Script Behaviour

- **mtx deploy** [staging|production]: always runs **`"$MTX_ROOT/terraform/apply.sh"`** (see `MTX/deploy.sh` — **never** `./terraform/apply.sh` from the project). Preconditions (e.g. `precond/01-is-projectb.sh`) run before most commands; they don’t change this contract.

### 6.1 apply.sh: two copies on disk

- **MTX `terraform/apply.sh`:** This is what **`mtx deploy`** executes. It resolves **PROJECT_ROOT** to the directory containing `config/app.json` and runs Terraform in **`$PROJECT_ROOT/terraform/`** (e.g. project-bridge/terraform).
- **project-bridge `terraform/apply.sh`:** Used when you invoke **`./terraform/apply.sh`** directly from the project root (without going through `mtx deploy`). Should stay **in sync** with MTX’s copy (same logic, different entry path).
- **Authoritative Terraform files:** `*.tf` and modules live only under **project-bridge/terraform/**. MTX does not duplicate `main.tf`.

---

## 7. CI (GitHub Actions)

- **Source of truth for deploy:** Same as local: **MTX `deploy.sh` → MTX `terraform/apply.sh`** (or manual `./terraform/apply.sh` from project-bridge). See [project-bridge docs/CI_MTX_DEPLOY.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/CI_MTX_DEPLOY.md).
- **03-deploy-staging.yml / 04-deploy-production.yml** checkout **MTX** and use **`bash MTX/deploy.sh`** for the provision/deploy contract step; build steps use project-bridge `package.json` scripts. If a workflow drifts (e.g. wrong `npm run` name), fix **workflows** and **project-bridge** `verify:airlock` — do not document CI as “outdated” without checking the current YAML.

---

## 8. Knowledge Gaps Filled

- **Where is Terraform defined?** Only in **project-bridge** (terraform/*.tf and modules). MTX only has a copy of apply.sh and FLOW.md.
- **Who runs Terraform?** apply.sh, which runs in **project-bridge/terraform** whenever PROJECT_ROOT is project-bridge (normal case when you run from project-bridge or apply.sh finds it).
- **Two apply.sh copies?** Yes — **MTX** `terraform/apply.sh` (used by **`mtx deploy`**) and **project-bridge** `terraform/apply.sh` (for direct `./terraform/apply.sh`). Both resolve **PROJECT_ROOT** so Terraform runs in the **project’s** `terraform/` with that repo’s `.env`.
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

- **MTX:** [adr/ADR-001-airlock-single-app-then-multi-host.md](adr/ADR-001-airlock-single-app-then-multi-host.md) (locked architecture: airlock single-app, then multi-app host), [MTX_DEPLOY_CONTRACT.md](MTX_DEPLOY_CONTRACT.md), [SERVICE_LANE_SEPARATION.md](SERVICE_LANE_SEPARATION.md), `docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md` (holistic flow: mtx create, admin vs payload deploy, instant provisioning), `terraform/FLOW.md` (state and logic flows), `docs/getting-started.md`, `docs/script-patterns.md`, `docs/mtx-patterns.md`.
- **project-bridge:** `docs/logic/deployment-flow.md` (deploy flow summary), `docs/MTX_AND_PROJECT_B.md` (MTX ↔ project-bridge relationship, script patterns), `docs/OUTSTANDING_WORK.md` (task list: GitHub/CI alignment, apply.sh source, docs, packages).

This document is the single place to see how MTX and project-bridge together implement infra and deploy; use the related docs above for deeper detail on tokens, builds, or script patterns.
