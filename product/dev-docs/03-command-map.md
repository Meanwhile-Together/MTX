# Command Map

Plain-language task to command lookup. Only includes commands explicitly reviewed in chat. Detailed usage and flags will be added as each flow is validated.

## MTX commands (developer operating surface)

| I want to... | Command | Notes |
|--------------|---------|-------|
| See all available commands | `mtx help` | Lists commands with descriptions from installed copy |
| Create a new payload app repo | `mtx create` / `mtx create payload [name]` | Clones from `MTX_PAYLOAD_TEMPLATE_REPO` (default `template-basic`); creates `payload-*` on GitHub; prints `server.apps` snippet |
| Publish a payload tree as a new `template-*` repo | `cd` payload root, then `mtx create template [name]` | Snapshots cwd into `template-*` beside MTX; point `MTX_TEMPLATE_SOURCE_REPO` at it for future `mtx create payload` |
| Scaffold a separate org product repo (unusual) | `mtx create org [name]` | Creates `org-*`; default ops model is **one shared org payload** + tenant config—see [MTX_SCAFFOLDING_MODEL.md](../../docs/MTX_SCAFFOLDING_MODEL.md) |
| Deploy to staging | `mtx deploy staging` | Runs terraform/apply.sh, provisions infra if needed, deploys app + backend |
| Deploy to production | `mtx deploy production` | Same flow as staging, targeting production environment |
| Deploy as master admin | `mtx deploy asadmin` | Same deploy flow with RUN_AS_MASTER=true and MASTER_JWT_SECRET handling |
| Bootstrap a workspace | `mtx workspace` | Creates workspace file, clones MTX + project-bridge + client-a as siblings |

## Project Bridge commands (runtime host)

| I want to... | Command | Notes |
|--------------|---------|-------|
| Start development server | `npm run dev` | Unified server: API + frontend on same port (3001) |
| Install dependencies | `npm install` | Run from project-bridge root |
| Build everything | `npm run build` | Builds all packages and targets |
| Build server only | `npm run build:server` | Server target only |

## Future expansion

Additional commands (compile targets, run targets, setup flows, project menu) will be documented here as each is explicitly reviewed.

---

See also: [Common Flows](./02-common-flows.md) | [First Day Quickstart](./01-first-day-quickstart.md)
