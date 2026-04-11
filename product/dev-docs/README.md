# MTX Developer Docs

Developer-user documentation for MTX, the developer operating surface for Project Bridge.

These docs are written from a beginner-first, plain-language perspective. They cover only material explicitly reviewed and validated. Each doc is marked with "future expansion" sections for content not yet reviewed.

## Documents

| Doc | Purpose |
|-----|---------|
| [00-mental-model.md](./00-mental-model.md) | What MTX is, what Project Bridge is, how they interact |
| [01-first-day-quickstart.md](./01-first-day-quickstart.md) | Clone, setup, and run sequence for both repos |
| [02-common-flows.md](./02-common-flows.md) | Developer story arc: client brief to production (health vertical example) |
| [03-command-map.md](./03-command-map.md) | Plain-language task to command lookup |
| [04-confusions-and-fixes.md](./04-confusions-and-fixes.md) | Known friction points and clear guidance |
| [05-glossary.md](./05-glossary.md) | Key terms and what they mean |

## Mirrored docs in project-bridge

The same doc structure exists in `project-bridge/product/dev-docs/`. Content is tailored to each repo's perspective but follows the same narrative arc.

## Authoritative technical docs (deep detail)

These live in the main `docs/` folders and go deeper than the developer-user docs above:

- `MTX/docs/MTX_SCAFFOLDING_MODEL.md` — **`template-*`** payload templates (`template-basic` + forkable starters), universal org, admin as payload.
- `MTX/docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md` — Canonical architecture: payload = app, Project Bridge = central host, fork path optional.
- `MTX/docs/MTX_DEPLOY_CONTRACT.md` — Deploy entry point contract.
- `MTX/docs/INFRA_AND_DEPLOY_REFERENCE.md` — Tokens, config, Terraform, Railway, CI.
- `MTX/docs/MISALIGNMENT.md` — Tracks legacy fork-first wording that needs updating.
- `project-bridge/docs/MTX_AND_PROJECT_B.md` — Relationship between MTX and project-bridge.
- `project-bridge/docs/SERVER_CONFIG.md` — Server config and payload hosting detail.
- `project-bridge/docs/PAYLOAD_CREATION_AND_SERVER_CONFIG.md` — Payload creation and registration detail.

## Wording convention

These docs use **payload-first** language consistently:
- "New app" = new payload registered in server config (primary path).
- "Fork" = optional standalone host deployment (not the default "new app" path).
- Project Bridge = central host/runtime, not "the repo you fork."
- MTX = developer operating surface, not a GUI dashboard.

This aligns with `MTX/docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md` as the authoritative architecture narrative.
