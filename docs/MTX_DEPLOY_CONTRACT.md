# MTX deploy contract (source of truth)

This document defines the **canonical deploy interface** for Meanwhile-Together: **`mtx deploy`** (and `mtx deploy asadmin` where applicable). Low-level Terraform and `apply.sh` behavior are **implementation details** invoked by MTX; operators and CI should not introduce **parallel deploy entrypoints** (bypassing this contract) without updating this document.

## Entry points

| Command | Purpose |
|---------|---------|
| `mtx build` [server\|backend\|all] | Builds the same **npm** artifacts deploy uses (`build:server` / `build:backend-server`) from the resolved project root (`config/app.json`). **No** Terraform or `railway up`. Default target is **all**. Implementation: [build.sh](../build.sh). |
| `mtx deploy` [staging\|production] | Interactive menu if env omitted; runs MTX `terraform/apply.sh` for the chosen env; provisions/adopts infra; deploys app-host and backend artifacts. |
| `mtx deploy asadmin` [staging\|production] | Same flow with `RUN_AS_MASTER=true` and `MASTER_JWT_SECRET` handling for master backend. |

**Skip build during deploy:** set **`MTX_SKIP_BUILD=1`** so `apply.sh` does not run `mtx build` steps (use when artifacts were built already, e.g. `mtx build all && MTX_SKIP_BUILD=1 mtx deploy staging`).

## Import adapter (wave2)

`mtx import payload <standalone-app-dir> [output-dir]` provides the standalone->payload import path without changing deploy behavior. It scans a target app directory, calls project-bridge validators, and writes a non-destructive scaffold bundle:

- `payload-manifest.skeleton.json`
- `import-warnings.txt`
- `import-plan.json`

Default output is `<standalone-app-dir>/.mtx-import`. Existing files are preserved; import never overwrites generated files unless you remove them first.

Implementation references: [build.sh](../build.sh), [deploy.sh](../deploy.sh), [deploy/asadmin.sh](../deploy/asadmin.sh), [terraform/apply.sh](../terraform/apply.sh).

## Bootstrap vs steady state (target resolution: hybrid)

### First run (bootstrap)

- Resolve **project root** (directory containing `config/app.json`).
- Require `config/deploy.json` with `platform` including `railway`.
- Use **Railway account token** for Terraform / GraphQL (create or adopt project and services).
- **Discover services by name** in the project (e.g. `backend-staging`, `{slug}-staging`, per [INFRA_AND_DEPLOY_REFERENCE.md](INFRA_AND_DEPLOY_REFERENCE.md)).
- Pass discovered IDs into Terraform so existing services are **adopted**, not destroyed.

### Steady state

- Prefer **persisted service IDs** in project `.env` (e.g. `RAILWAY_PROJECT_ID`, env-specific app/backend service IDs as documented in infra reference).
- Reduces discovery drift and speeds deploys.

## CI alignment

- **Target state:** CI should invoke the **same** entry as humans: **`mtx deploy`** (or a documented wrapper that calls the same scripts), not a divergent Railway/Terraform-only path.
- project-bridge workflows should match this contract; see [CI_MTX_DEPLOY.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/CI_MTX_DEPLOY.md) (absolute link so MTX-only clones still resolve).

## Non-goals

- Defining Terraform variable names here (see project-bridge `terraform/` and [INFRA_AND_DEPLOY_REFERENCE.md](INFRA_AND_DEPLOY_REFERENCE.md)).
