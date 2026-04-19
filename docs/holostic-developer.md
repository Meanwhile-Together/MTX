# Holistic view — developer drill-down

**Audience:** people who **build or change** Meanwhile-Together platform pieces: **project-bridge**, **MTX**, **templates** (`template-org`, `template-payload`), and **org-host** wiring—not only app feature work inside a single payload.

**Read first:** [holostic.md](holostic.md) (full stack mental model). **Executive story:** [holostic-executive-brief.md](holostic-executive-brief.md). **Org owners / AI collaborators:** [holostic-client.md](holostic-client.md).

---

## How this doc relates to `holostic.md`

`holostic.md` explains **what connects to what**. This page adds **where work lives**, **which contracts must not break**, and **what to verify** when you touch the framework or operator layer.

---

## Repo map (where your change probably belongs)

| You are changing… | Primary home | Often also touch… |
|-------------------|--------------|-------------------|
| Unified server behavior, routing, addons, listen/bind | **project-bridge** `targets/server/` | `shared/`, Bridge `docs/`, MTX deploy/build if contracts shift |
| Shared types, config loading, server helpers, master/GitHub integration | **project-bridge** `shared/` | `engine/`, `ui/`, server imports |
| Bridge “app shell” / engine factory / web-facing bridge APIs | **project-bridge** `engine/`, `ui/` | Client bundles vs Node-only imports (avoid pulling Node loaders into web bundles—see rule-of-law cross-links) |
| `mtx create`, org/payload scaffold, metadata, GitHub publish | **MTX** `lib/create-from-template.sh`, `create/` | Template repos, `rule-of-law.md` defaults (`MTX_*_TEMPLATE_REPO`) |
| Deploy, Terraform apply path, `railway up`, build server orchestration | **MTX** `deploy.sh`, `deploy/terraform/`, `build.sh` | Org host `terraform/`, `prepare:railway`, Bridge `scripts/run-mtx-deploy.sh` (delegates to MTX) |
| Default config files vendored into new orgs | **project-bridge** `config/` | **MTX** `lib/create-from-template.sh` (copy/merge rules) |
| Reference infra modules | **project-bridge** `terraform/` | **MTX** apply uses **`$PROJECT_ROOT/terraform`** on the **org host** after vendoring |
| New-starter shape for payloads or orgs | **template-payload** / **template-org** (repos) | **MTX** env defaults, docs in MTX + Bridge |

**Normative product class:** the **deployable host** is an **`org-*`** host repo (config + payloads + `mtx deploy`), not “fork project-bridge and call that your customer host.” Bridge stays the **framework monorepo**. Details: [rule-of-law.md](rule-of-law.md), [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md).

---

## Hard contracts (do not “improve” these casually)

1. **Deploy contract** lives in **MTX** (`deploy.sh` → `deploy/terraform/apply.sh`). Org hosts run Terraform from **`$PROJECT_ROOT/terraform`**. Bridge’s `npm run deploy:*` is a **thin wrapper** to MTX (`project-bridge/scripts/run-mtx-deploy.sh`).
2. **`mtx create`** scaffolds **payload-** / **org-** / **template-*** repos from **template git repos**; it does **not** clone project-bridge as a customer host. Saying otherwise in docs or scripts creates operator confusion.
3. **Sibling resolution:** MTX primes Bridge from **`../project-bridge`**, **`vendor/project-bridge`**, or **`PROJECT_BRIDGE_ROOT`**. Build scripts assume a sane workspace layout; changing resolution rules requires updating **all** call sites (see `MTX/build.sh`, `create-from-template`, clean helpers).
4. **Payload vs org shape:** **`mtx create payload`** must default to a **single-app** template (`template-payload`). Pointing payload create at an **org-shaped** tree causes deploy/static/MIME failure classes documented in [rule-of-law.md](rule-of-law.md).
5. **Service lanes:** master/admin env (`RUN_AS_MASTER`, `MASTER_JWT_SECRET`) belongs on the **backend** service story, not mixed into the public app lane—[SERVICE_LANE_SEPARATION.md](SERVICE_LANE_SEPARATION.md), [MTX_DEPLOY_CONTRACT.md](MTX_DEPLOY_CONTRACT.md).

---

## Extension points (safe places to add product surface)

- **New hosted app:** new **payload** repo or path + registration on the org host’s **`server.json`** `apps` (slug, `source.path` / `package` / `git`, static `dist` where applicable). Follow Bridge server config docs (`project-bridge/docs/SERVER_CONFIG.md`).
- **Framework behavior:** Bridge **addons** and server middleware—keep framework routes namespaced (internal vs payload APIs per existing patterns).
- **Operator automation:** new **`mtx <domain> <action>`** verbs under MTX’s nested layout—[MTX_COMMAND_SURFACE.md](MTX_COMMAND_SURFACE.md).

---

## Verification checklist (after non-trivial changes)

- **Bridge:** `npm` scripts you touched still run (root `package.json`); server starts in dev; payload resolution still matches `SERVER_CONFIG` expectations if you changed config or routing.
- **MTX:** `mtx help` / affected commands; **`mtx deploy`** dry path or staging if you changed deploy/build; wrapper install note in [rule-of-law.md](rule-of-law.md) if you changed **published** behavior on `main`.
- **Templates:** fresh **`mtx create payload|org`** from local siblings produces a tree that **builds** and matches docs.
- **Cross-repo:** update **both** MTX and Bridge docs when the **contract** moves (not every typo—contract).

---

## Diagram (same as holistic technical doc)

The technical relationship diagram lives in [holostic.md](holostic.md#mental-model-diagram) so it stays in one place.

---

## Bookmarked implementation entry points

- **MTX:** [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md), [INFRA_AND_DEPLOY_REFERENCE.md](INFRA_AND_DEPLOY_REFERENCE.md), `lib/create-from-template.sh`, `build.sh`, `deploy.sh`, [MTX_DEPLOY_CONTRACT.md](MTX_DEPLOY_CONTRACT.md)
- **Bridge:** `project-bridge/docs/CURRENT_ARCHITECTURE.md`, `project-bridge/docs/MTX_AND_PROJECT_B.md`, `project-bridge/docs/PAYLOAD_CREATION_AND_SERVER_CONFIG.md`, `targets/server/src/index.ts`, `shared/src/addons/`
- **Law / sharp edges:** [rule-of-law.md](rule-of-law.md)

---

## Bottom line for contributors

Treat **MTX** as the **operator contract** and **project-bridge** as the **runtime + shared packages + reference infra**. **Org hosts** carry customer-specific config and payload assembly; **payload repos** stay product-shaped. When in doubt, align docs and code with **[rule-of-law.md](rule-of-law.md)** before adding a second “truth.”
