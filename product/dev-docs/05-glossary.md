# Glossary

Key terms and what they mean in this system. Only includes terms explicitly reviewed in chat.

---

**Project Bridge** — The platform runtime and host technology. A unified server that serves and coordinates payload apps. It is not one app; it is the system that hosts many apps.

**MTX** — The developer operating surface. A command wrapper that uses a git repo as a package source. You run MTX commands to create, configure, deploy, and manage payloads on a Project Bridge host.

**Payload** — A user-facing app experience served by a Project Bridge host. Each payload has its own domain responsibility (e.g., Diet, Workout, Chat). Payloads are registered in the host's server config and can be sourced from a local path, an npm package, or a git repo.

**Host** — A running instance of Project Bridge that serves one or more payloads. One host can serve many payloads. The host reads `config/server.json` to know which payloads to serve.

**Backend mode** — A configuration of the Project Bridge host where it serves the admin payload and backend addons. Triggered by an app entry with `slug === "admin"` in server config.

**App mode** — A configuration of the Project Bridge host where it serves front-end payload apps (not admin). Same server binary as backend mode, different config.

**Workspace** — The parent directory containing MTX, project-bridge, and payload repos as siblings. MTX scripts assume this layout.

**Project root** — The directory containing `config/app.json`. This is where MTX runs child scripts from (via `cd "$execDir"`). Typically the project-bridge repo root.

**Master backend** — A backend deployment with `RUN_AS_MASTER=true` and `MASTER_JWT_SECRET` set. Mounts `/auth` (login, register, verify). Project backends without this flag only verify master-issued JWTs.

**server.apps** — The array in `config/server.json` that lists payload entries. Each entry has `id`, `name`, `slug`, `source`, and optional routing fields (`domains`, `pathPrefix`, `apiPrefix`).

---

## Future expansion

Additional terms will be added here as each concept is explicitly reviewed and validated.
