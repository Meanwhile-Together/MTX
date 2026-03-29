# MTX deploy contract (source of truth)

This document defines the **canonical deploy interface** for Meanwhile-Together: **`mtx deploy`** (and `mtx deploy asadmin` where applicable). Low-level Terraform and `apply.sh` behavior are **implementation details** invoked by MTX; operators and CI should not fork alternate deploy paths without updating this contract.

## Entry points

| Command | Purpose |
|---------|---------|
| `mtx deploy` [staging\|production] | Interactive menu if env omitted; runs MTX `terraform/apply.sh` for the chosen env; provisions/adopts infra; deploys app-host and backend artifacts. |
| `mtx deploy asadmin` [staging\|production] | Same flow with `RUN_AS_MASTER=true` and `MASTER_JWT_SECRET` handling for master backend. |

Implementation references: [deploy.sh](../deploy.sh), [deploy/asadmin.sh](../deploy/asadmin.sh), [terraform/apply.sh](../terraform/apply.sh).

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
- Current GitHub Actions in project-bridge may predate this contract; see [project-bridge docs/CI_MTX_DEPLOY.md](../../project-bridge/docs/CI_MTX_DEPLOY.md) for alignment notes.

## Non-goals

- Defining Terraform variable names here (see project-bridge `terraform/` and [INFRA_AND_DEPLOY_REFERENCE.md](INFRA_AND_DEPLOY_REFERENCE.md)).
