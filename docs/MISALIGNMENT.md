# Misalignment registry (legacy fork narrative vs current behavior)

**Purpose:** Track docs and rules that still describe **fork project-bridge** as the “new app” or **standalone deploy-from-bridge** story. **Normative host** = **`org-*`** ([rule-of-law.md](rule-of-law.md) §1, §5–§6). **Authoritative deploy path:** [MTX_DEPLOY_CONTRACT.md](MTX_DEPLOY_CONTRACT.md), [INFRA_AND_DEPLOY_REFERENCE.md](INFRA_AND_DEPLOY_REFERENCE.md). **Authoritative create path:** [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md) (narrative) · [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md) (steps) — **`mtx create payload`** = **payload** repo from **`template-payload`** / `MTX_PAYLOAD_TEMPLATE_REPO`, **`payload-*`**, **`gh`**; **`mtx create org`** = **`org-*`** from **`template-org`** / `MTX_ORG_TEMPLATE_REPO`; **`mtx create template`** = snapshot payload cwd → **`template-*`** (run from payload root).

**Target architecture (customer `client-*`, master Railway project, etc.):** [project-bridge docs/finalize/06_TARGET_ARCHITECTURE_LOCKED.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/finalize/06_TARGET_ARCHITECTURE_LOCKED.md).

---

## Resolved or updated in this repo (MTX)

| Item | Status |
|------|--------|
| **INFRA_AND_DEPLOY_REFERENCE.md** — `mtx deploy` vs `./terraform/apply.sh` | **Updated:** `deploy.sh` always runs **`$MTX_ROOT/deploy/terraform/apply.sh`**; **PROJECT_ROOT** = tree with **`config/app.json`** (normatively **`org-*`**; legacy **project-bridge** checkout during migration). |
| **MTX_CREATE_AND_DEPLOYMENT_FLOW.md** — §2.2 fork narrative | **Updated:** Describes actual **`create.sh`** (payload template, not project-bridge fork). |
| **create.sh** | **Implementation:** Clones **`template-payload`** (or `MTX_PAYLOAD_TEMPLATE_REPO`), **`payload-*`** naming — see script header in repo. |

---

## project-bridge — docs that may still emphasize fork-only or bridge-as-host flows

| File | Issue | Suggested action |
|------|--------|------------------|
| **MASTER_FLOW_AND_MTX_CREATE_PLAN.md** | Older fork-centric plan. | Add banner: superseded by **MTX_CREATE_AND_DEPLOYMENT_FLOW** + **finalize/06** + **MTX rule-of-law** (org host = deploy root); keep for history. |
| **PLATFORM_EXPLORATION_MASTER.md**, **PLATFORM_MASTER_DIAGRAM.md** | Fork-only / bridge-as-product-host diagrams. | Add “**org host** + payload = app” note at top; link **MTX_CREATE_AND_DEPLOYMENT_FLOW** / **rule-of-law**. |
| **OUTSTANDING_WORK.md** | Mixed create/deploy tasks. | Trim stale rows; point to **finalize/06** for target architecture (ongoing hygiene). |
| **CURRENT_ARCHITECTURE.md** | Previously: “standalone project-bridge deployment” language. | **Aligned:** org host = deploy root; bridge = framework; horizon = no standalone bridge deploy ([MTX rule-of-law](https://github.com/Meanwhile-Together/MTX/blob/main/docs/rule-of-law.md) §6). |

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
| **`mtx create payload`** (plain **`mtx create`**) | “Fork project-bridge for an app” | **`payload-*`** from **`template-payload`** (or override). |
| **`mtx create org`** | N/A in old story | **`org-*`** host = **deploy root**; vendors framework from **project-bridge**. |
| **`mtx deploy`** | Project’s `./terraform/apply.sh` | **MTX** `$MTX_ROOT/deploy/terraform/apply.sh` only. |
| **New app on existing host** | N/A | Payload + **`server.apps`** entry on the **org host**. |
| **Deploy root** | “project-bridge checkout is the product host” | **`org-*`** first-class; **project-bridge** = framework ([rule-of-law.md](rule-of-law.md) §1, §6). |

---

## Org-shaped payloads: aigotchi and org-nack-ai batch

**Incident (named):** **`payload-aigotchi`** and **~24** sibling **`payload-*`** repos were **org-host trees** (`payloads/`, **`prepare:railway`**, unified-server wiring) while keeping **`payload-*`** names — including **nested** **`payloads/aigotchi/payloads/mt-platform/`** (a **second host-like tree inside a payload path**) under **`org-nack-ai`**. Same root cause class as **`mtx create payload`** + **org-shaped** template (**`template-basic`** / wrong **`MTX_PAYLOAD_TEMPLATE_REPO`**).

| What to read | Where |
|--------------|--------|
| Law + failure class + remediation order | [rule-of-law.md](rule-of-law.md) §1 (cross-repo **org-shaped `payload-*`** bullet), §2 last implication, §4 **Org-shaped `payload-*`**, §7 todos (**pilot `payload-aigotchi`**, batch the rest) |
| Step-by-step migration (hoist / reclassify) | [PAYLOAD_ORG_SHAPE_MIGRATION.md](PAYLOAD_ORG_SHAPE_MIGRATION.md) |
| Workspace inventory | [`scripts/inventory-org-shaped-payloads.sh`](../scripts/inventory-org-shaped-payloads.sh) |
| Hoist helper | [`scripts/hoist-payload-subdir-to-root.sh`](../scripts/hoist-payload-subdir-to-root.sh) |
