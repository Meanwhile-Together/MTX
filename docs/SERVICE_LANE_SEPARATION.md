# Service lane separation: app-host vs backend/admin

The unified server is **one binary** with two **deploy lanes** on Railway. Mixing lanes breaks security and operational clarity.

## Lanes

| Lane | Railway role (typical names) | Mode | Serves |
|------|------------------------------|------|--------|
| **App-host** | `{slug}-staging` / `{slug}-production` | Front-end / app mode (`backendMode` false) | App payloads from `config/server.json`, static assets, `/api/<slug>` routes. |
| **Backend/admin** | `backend-staging` / `backend-production` | Backend mode (`backendMode` true) | Admin static, backend addons, internal APIs; **optional** master auth when `RUN_AS_MASTER` + `MASTER_JWT_SECRET`. |

## Environment boundaries

**Backend-only variables** must not be set on the **app-host** service:

- `RUN_AS_MASTER`
- `MASTER_JWT_SECRET`
- `MASTER_AUTH_ISSUER`, `MASTER_CORS_ORIGINS` (when used for master)

**Rationale:** master JWT and `/auth` surface belong on the backend lane; leaking them to app-host widens attack surface.

## Build artifacts

- **App-host deploy:** root `railway.json`, `npm run build:server`, start unified server in app configuration.
- **Backend deploy:** swap to backend `railway.json` (see [INFRA_AND_DEPLOY_REFERENCE.md](INFRA_AND_DEPLOY_REFERENCE.md)), build backend + server as documented, deploy to backend service ID, restore app `railway.json`.

## Validation

- Post-deploy smoke: health on both public URLs; app-host must not expose master-only routes unless intentionally shared (should be false).

## Related

- [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md)
- [INFRA_AND_DEPLOY_REFERENCE.md](INFRA_AND_DEPLOY_REFERENCE.md)
