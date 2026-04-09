# Misalignment registry (legacy fork narrative vs current behavior)

**Purpose:** Track docs and rules that still describe **fork project-bridge** as the only “new app” story. **Authoritative deploy path:** [MTX_DEPLOY_CONTRACT.md](MTX_DEPLOY_CONTRACT.md), [INFRA_AND_DEPLOY_REFERENCE.md](INFRA_AND_DEPLOY_REFERENCE.md). **Authoritative create path:** [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md) — **`mtx create`** = **payload template** (`template-basic` / `MTX_PAYLOAD_TEMPLATE_REPO`), **`payload-*`** repo, **`gh`**.

**Target architecture (customer `client-*`, master Railway project, etc.):** [project-bridge docs/finalize/06_TARGET_ARCHITECTURE_LOCKED.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/finalize/06_TARGET_ARCHITECTURE_LOCKED.md).

---

## Resolved or updated in this repo (MTX)

| Item | Status |
|------|--------|
| **INFRA_AND_DEPLOY_REFERENCE.md** — `mtx deploy` vs `./terraform/apply.sh` | **Updated:** `deploy.sh` always runs **`$MTX_ROOT/terraform/apply.sh`**; PROJECT_ROOT resolves to project-bridge for Terraform. |
| **MTX_CREATE_AND_DEPLOYMENT_FLOW.md** — §2.2 fork narrative | **Updated:** Describes actual **`create.sh`** (payload template, not project-bridge fork). |
| **create.sh** | **Implementation:** Clones **`template-basic`** (or `MTX_PAYLOAD_TEMPLATE_REPO`), **`payload-*`** naming — see script header in repo. |

---

## project-bridge — docs that may still emphasize fork-only flows

| File | Issue | Suggested action |
|------|--------|------------------|
| **MASTER_FLOW_AND_MTX_CREATE_PLAN.md** | Older fork-centric plan. | Add banner: superseded by **MTX_CREATE_AND_DEPLOYMENT_FLOW** + **finalize/06**; keep for history. |
| **PLATFORM_EXPLORATION_MASTER.md**, **PLATFORM_MASTER_DIAGRAM.md** | Fork-only diagrams. | Add short “payload = app” note at top or link to **MTX_CREATE_AND_DEPLOYMENT_FLOW**. |
| **OUTSTANDING_WORK.md** | Mixed create/deploy tasks. | Trim stale rows; point to **finalize/06** for target architecture (ongoing hygiene). |

---

## Cursor / agent rules (project-bridge)

Framework phase rules and **framework-doctrine.mdc** still reference **MASTER_FLOW_AND_MTX_CREATE_PLAN** and fork wording in places. **Align** required reading with **MTX_CREATE_AND_DEPLOYMENT_FLOW.md** and [project-bridge docs/finalize/06_TARGET_ARCHITECTURE_LOCKED.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/finalize/06_TARGET_ARCHITECTURE_LOCKED.md); keep **MASTER_FLOW** as historical context only.

---

## Code — MTX `create.sh`

| File | Current behavior |
|------|------------------|
| **MTX/create.sh** | **Payload template** flow (`desc` line): clone template, **`payload-*`** repo, **`gh repo create`**, snippet for `server.apps`. **Not** a project-bridge fork. |

---

## Quick reference

| Concept | Legacy (misaligned) | Current |
|--------|---------------------|---------|
| **`mtx create`** | Fork project-bridge only | **Payload** repo from **`template-basic`** (or override template). |
| **`mtx deploy`** | Project’s `./terraform/apply.sh` | **MTX** `$MTX_ROOT/terraform/apply.sh` only. |
| **New app on existing host** | N/A | Payload + **`server.apps`** entry. |
