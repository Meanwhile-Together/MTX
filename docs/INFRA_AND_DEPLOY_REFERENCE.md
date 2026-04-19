# Infrastructure & Deploy — MTX + project-bridge (Holistic Reference)

Single reference for infra and deployment across **MTX** (wrapper/CLI), **org hosts** (`org-*` deploy roots), and **project-bridge** (framework monorepo: reference **`terraform/`**, packages, CI). Normative **deploy root** is an **org host**; running apply from a **project-bridge** checkout alone is **transitional**, not the documented end state ([rule-of-law.md](rule-of-law.md) §1, §6).

**Create / scaffolding narrative (payload vs **`template-*`** payload templates vs org):** [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md).

---

## 1. Where Things Live

| What | Repo / path | Notes |
|------|-------------|--------|
| **Deploy entry (CLI)** | MTX `deploy.sh` | Menu (staging/production), then always runs **`$MTX_ROOT/deploy/terraform/apply.sh`** (MTX’s copy — never the project tree’s `terraform/apply.sh`) |
| **Path payload vendoring** | MTX **`lib/vendor-payloads-from-config.sh`** (bash + **`jq`**) | Run from **`mtx build`** / **`mtx deploy`** (before org **`npm run prepare:railway`**) when the org uses **`scripts/prepare-railway-artifact.sh`**: builds local **`apps[].source.path`** trees, copies into **`./payloads/<slug>/`**, writes **`config/server.json.railway`**. Env: **`MTX_SKIP_PAYLOAD_VENDOR`**, **`MTX_VENDOR_FAIL_ON_ERROR`**. If **`payloads`** is pinned in **`.mtx-vendor.pinned`**, the script exits immediately (no path payload build/rsync). |
| **Apply + deploy logic** | MTX `deploy/terraform/apply.sh` + **`$PROJECT_ROOT/terraform/`** | **`deploy.sh`** invokes **only** MTX’s `deploy/terraform/apply.sh`. That script resolves **PROJECT_ROOT** to the directory containing **`config/app.json`** (normatively an **`org-*`** host; a **project-bridge** checkout may still satisfy that during migration) and runs Terraform from **`$PROJECT_ROOT/terraform/`**. Reference **`*.tf`** in **project-bridge** is the upstream template orgs vendor or mirror. A **copy** of `apply.sh` may exist under a project tree for direct runs; keep behavior aligned with MTX’s script. See [MTX_DEPLOY_CONTRACT.md](MTX_DEPLOY_CONTRACT.md). |
| **Terraform (IaC)** | **Org host** `terraform/` (often derived from **project-bridge**) | `main.tf`, `variables.tf`, `outputs.tf`, `backend.tf`, `modules/railway-owner`, `modules/railway` — **MTX has no main.tf**; **project-bridge** ships the canonical module tree for copying/vendoring |
| **Terraform auto re-vendor** | MTX **`lib/vendor-terraform-from-bridge.sh`** | **`mtx build`** uses **`--sync-mode=auto`**: on digest mismatch, **rsync** from **project-bridge/terraform** (same file set as before) and refresh **`terraform/.mtx-bridge-terraform.sha256`**. **`mtx deploy`** / **`mtx deploy terraform apply`** default to **`--sync-mode=prompt`** when stdin is a TTY: warn on drift and ask **upgrade** vs **skip** (default skip); non-TTY or **`MTX_DEPLOY_VENDOR_AUTO=1`** uses **auto**. **`--revendor`** (or **`MTX_VENDOR_REVENDOR=1`**) forces rsync unless **`terraform`** is listed in **`.mtx-vendor.pinned`** (see **`lib/mtx-vendor-pinned.sh`**). After successful **apply**, digest is written unless pinned. Skips when **PROJECT_ROOT/terraform** is the bridge tree itself. |
| **Config (app/deploy)** | **Deploy root** (`org-*` or transitional checkout) | `config/app.json`, `config/deploy.json` |
| **Secrets** | **Deploy root** `.env` | `RAILWAY_*` tokens; gitignored |
| **Railway build config** | **Deploy root** | Root `railway.json` (app), backend variant as per template |
| **Setup (first-time + deploy)** | Template / org scripts (e.g. **`scripts/setup.sh`** when present) | May call apply patterns; **MTX** remains the contract entry for **`mtx deploy`** |

**Contract:** **`mtx deploy`** runs **MTX’s** `deploy/terraform/apply.sh` only (equivalently **`mtx deploy terraform apply`**). That script finds **PROJECT_ROOT** (the tree with `config/app.json` — **org host** first-class; **project-bridge** root only during migration) and executes Terraform in **`$PROJECT_ROOT/terraform/`**. Direct **`./terraform/apply.sh`** is implementation detail, not the primary operator story ([MTX_DEPLOY_CONTRACT.md](MTX_DEPLOY_CONTRACT.md), [rule-of-law.md](rule-of-law.md) §6).

---

## 2. End-to-End Deploy Flow

1. **Entry**
   - **Local:** From **org host** (or transitional) project root: `mtx deploy` or `mtx deploy staging` (or `./terraform/apply.sh staging` / `./scripts/setup.sh --setup-deployment` where your template provides them).
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
   - **App:** Link `.railway` to app service, **`mtx build server`** (org template: primes project-bridge, runs **`lib/vendor-payloads-from-config.cjs`**, then **`npm run prepare:railway`**), `railway up` with **project token** for chosen env.
   - **Backend:** Swap root `railway.json` to `targets/backend-server/railway.json`, `npm run build:backend-server`, `railway link` to backend service, `railway up` with same project token; then restore root `railway.json` and `.railway` link.
   - On backend 404/upload failure: optional self-heal (state rm backend_${env}, touch `.railway-backend-invalidated`, re-run apply).

### 2.1 GitHub and CI

GitHub Actions (and any other CI) should use the **same flow** as local `mtx deploy`: Terraform outputs (e.g. `railway_app_service_id_staging` / `railway_app_service_id_production`) drive the deploy step, not a single `deployment-project-id` from config. For workflows, secrets, and parity with **`MTX/deploy.sh`**, see **project-bridge** [docs/CI_MTX_DEPLOY.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/CI_MTX_DEPLOY.md).

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
  - One `railway_service.app` named from app slug (`service_name_base`); **staging vs production** = Railway **environments**, not separate service names.
  - Optional `railway_service_id` when adopting an existing service (count 0 if ID passed).
  - Outputs: `service_id`, `service_name` (root re-exports `railway_app_service_id` and legacy `railway_app_service_id_staging` / `_production` aliases pointing at the same id).

- **State:** `backend "local" { path = "terraform.tfstate" }` in project-bridge/terraform/backend.tf. Terraform Cloud block is commented out.

---

## 5. Config Files

- **config/app.json:** `app.name`, `app.owner`, `app.slug` (and version, etc.). `owner` helps workspace discovery and the default name when Terraform **creates** a Railway project; the live project is always whatever `RAILWAY_PROJECT_ID` points to.
- **config/deploy.json:** `platform: ["railway"]`, optional `projectId`, `staging.healthEndpoints`, `production.healthEndpoints`.
- **.env (deploy root):** `RAILWAY_WORKSPACE_ID`, `RAILWAY_PROJECT_ID`, `RAILWAY_ACCOUNT_TOKEN`, `RAILWAY_PROJECT_TOKEN_STAGING`, `RAILWAY_PROJECT_TOKEN_PRODUCTION`. Optional: `RAILWAY_PROJECT_ID_STAGING`, `RAILWAY_PROJECT_ID_PRODUCTION`.
- **railway.json (root):** App build/start (RAILPACK; build:server; start `node targets/server/dist/index.js`).
- **targets/backend-server/railway.json:** Backend build/start (build:backend-server + build:backend; start `node targets/backend-server/dist/index.js`). apply.sh temporarily copies this to root for backend `railway up`.

### 5.1 PostgreSQL and `DATABASE_URL` (each org app service)

The **unified server** deploys to **one** Railway app service (name = app **slug**). Use **`--environment staging`** or **`production`** (and matching project tokens) so each Railway environment has its own **`DATABASE_URL`** / **`JWT_SECRET`**. Add **PostgreSQL** in the project and reference it on that service per environment. See project-bridge **[RAILWAY_DATABASE.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/RAILWAY_DATABASE.md)** (Railway database templates, variable references, optional Terraform `railway_create_db_service` caveat).

---

## 6. MTX Script Behaviour

- **mtx deploy** [staging|production]: always runs **`"$MTX_ROOT/deploy/terraform/apply.sh"`** (see `MTX/deploy.sh` — **never** `./terraform/apply.sh` from the project). Preconditions (e.g. `precond/01-is-projectb.sh`) run before most commands; they don’t change this contract.

### 6.1 apply.sh: two copies on disk

- **MTX `deploy/terraform/apply.sh`:** This is what **`mtx deploy`** (and **`mtx deploy terraform apply`**) executes. It resolves **PROJECT_ROOT** to the directory containing `config/app.json` and runs Terraform in **`$PROJECT_ROOT/terraform/`** (on an **org host**, that tree is often vendored from **project-bridge** `terraform/`).
- **In-tree `terraform/apply.sh`:** Some templates ship **`./terraform/apply.sh`** for direct runs without `mtx deploy`; behavior should stay **in sync** with MTX’s orchestrator where both exist.
- **Authoritative Terraform modules (upstream):** **`project-bridge/terraform/`** — canonical **`*.tf`** and modules for **copying into org hosts**; **MTX** does not ship `main.tf`.

---

## 7. CI (GitHub Actions)

- **Source of truth for deploy:** Same as local: **MTX `deploy.sh` → MTX `deploy/terraform/apply.sh`**. See [project-bridge docs/CI_MTX_DEPLOY.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/CI_MTX_DEPLOY.md) (workflows today often build from a **framework** checkout — migrating CI to **org-host** repos is separate hygiene).
- **03-deploy-staging.yml / 04-deploy-production.yml** checkout **MTX** and use **`bash MTX/deploy.sh`** for the provision/deploy contract step; build steps use the checked-out project’s `package.json` scripts. If a workflow drifts (e.g. wrong `npm run` name), fix **workflows** and **`verify:airlock`** — do not document CI as “outdated” without checking the current YAML.

---

## 8. Knowledge Gaps Filled

- **Where is Terraform defined?** **Upstream** **`project-bridge/terraform/`** (`*.tf`, modules). Each **org host** carries its own **`$PROJECT_ROOT/terraform/`** (often copied from that tree). **MTX** ships the **orchestrator** under **`deploy/terraform/`** (`apply.sh`, `destroy.sh`, `ensure-railway-domain.sh`, `FLOW.md`).
- **Who runs Terraform?** **MTX** `apply.sh`, **`cd`**’s to **PROJECT_ROOT** and runs **`terraform`** in **`$PROJECT_ROOT/terraform/`** — today that root may still be a **project-bridge** checkout during migration; **normative** root is an **`org-*`** host ([rule-of-law.md](rule-of-law.md) §6).
- **Two apply.sh entry styles?** **MTX** `deploy/terraform/apply.sh` is the **contract** entry for **`mtx deploy`**. Some repos also ship **`./terraform/apply.sh`**; both should resolve the same **PROJECT_ROOT** / `.env` semantics when present.
- **Token roles:** Account = Terraform + API. Project token staging/production = `railway up` only, per environment.
- **Backend vs app deploy:** App uses root railway.json and build:server; backend deploy swaps in backend-server/railway.json and uses build:backend-server, then restores.
- **Self-heal:** Backend 404/upload failure can trigger state rm of backend_${env} and `.railway-backend-invalidated` so next apply recreates backend.
- **DATABASE_URL:** In Railway, app/backend use private URL (e.g. from Postgres plugin or Backend service); per-app DB name `{slug}_{env}` via shared helpers; no URL mutation for in-project services.

---

## 9. Quick Commands (from deploy root)

```bash
# Full setup + first-time deploy (prompts for tokens, creates envs, runs Terraform + deploy)
./scripts/setup.sh --setup-deployment

# Non-interactive (use existing .env)
./scripts/setup.sh --setup-deployment -y

# Redeploy only (infra already exists)
./terraform/apply.sh staging
./terraform/apply.sh production

# Or via MTX (from the same deploy root)
mtx deploy staging
mtx deploy production
```

---

## 10. Related Docs

- **MTX:** [adr/ADR-001-single-app-hardening-then-multi-host.md](adr/ADR-001-single-app-hardening-then-multi-host.md) (single-app hardening first, then multi-app host), [MTX_DEPLOY_CONTRACT.md](MTX_DEPLOY_CONTRACT.md), [SERVICE_LANE_SEPARATION.md](SERVICE_LANE_SEPARATION.md), `docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md` (holistic flow: mtx create payload/org/template, admin vs payload deploy, instant provisioning), `deploy/terraform/FLOW.md` (state and logic flows), `docs/getting-started.md`, `docs/script-patterns.md`, `docs/mtx-patterns.md`.
- **project-bridge:** `docs/logic/deployment-flow.md` (deploy flow summary), `docs/MTX_AND_PROJECT_B.md` (MTX ↔ project-bridge relationship, script patterns), `docs/CI_MTX_DEPLOY.md` (GitHub Actions, secrets, MTX deploy parity), `docs/CURRENT_ARCHITECTURE.md` (source of truth for roles and deploy path).

This document is the single place to see how **MTX**, **org hosts**, and the **project-bridge** framework fit together for infra and deploy; use the related docs above for deeper detail on tokens, builds, or script patterns.
