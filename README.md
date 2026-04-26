# MTX

A single-command wrapper that uses a git repository as a package source: install once, then run any script in the repo by name from anywhere. No copying files or hunting for that script you left on a VPS—everything stays in the repo and stays up to date. This is the evolved version of the idea behind Nice Network Wrapper; you get one binary, one repo, and a straightforward way to run and hoist scripts across machines.

## Installation

[Caveat Emptor](#caveat-emptor)

    curl -kLSs  https://raw.githubusercontent.com/Meanwhile-Together/MTX/refs/heads/main/mtx.sh | bash

[Caveat Emptor](#caveat-emptor)

## What it does

The wrapper installs itself (when needed) and keeps a clone of the repo in a fixed directory. From then on you run commands by category and script name (e.g. `mtx deploy staging`, `mtx build`, `mtx create org`). It can create symlinks in your PATH for specific scripts (hoist) and checks the repo for updates when it runs.

Clone this repo (or your organization’s mirror), then change the config or run `./reconfigure.sh` for a guided setup: point the wrapper at your git repo and command layout so operators run **your** scripts from anywhere while keeping the same update model.

## Usage

- **First time:** Run the install one-liner above (or clone and run the wrapper script). It will install itself and then you can use the command.
- **Customizing:** Run `./reconfigure.sh` to set display name, repo, wrapper filename, and paths; or edit the config block at the top of the wrapper script.
- **Running scripts:** From any directory, run `mtx <category> <script>` or a top-level command (or whatever your installed command name is). Examples: `mtx deploy staging`, `mtx create org`, `mtx run dev`, `mtx clean` — see `mtx help` for this repo’s categories.

The wrapper checks the repo for updates on each run and resets to the remote branch when needed.

## Architecture (Meanwhile-Together)

- **Deploy root (normative):** **`org-*`** org hosts (**`mtx create org`** / **`template-org`**) — `config/`, `payloads/`, **`mtx deploy`**. **project-bridge** is the **framework** monorepo (packages, reference Terraform); see [CURRENT_ARCHITECTURE.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/CURRENT_ARCHITECTURE.md) and [rule-of-law.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/rule-of-law.md) §1 / §6 (hosts are org-shaped; bridge-only deploy is not the eventual operator story).
- **Command surface:** [MTX_COMMAND_SURFACE.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_COMMAND_SURFACE.md) — **`mtx create <payload|org|template>`** for new repos; **`mtx payload install`** to register an existing payload on a host. **Scaffolding:** **`mtx create payload`** → **`payload-*`** (clone from **`MTX_PAYLOAD_TEMPLATE_REPO`**, default **`template-payload`** — single-app SPA shape). **`mtx create org`** → **`org-*`** from **`MTX_ORG_TEMPLATE_REPO`** (default **`template-org`** — org host / `payloads/` layout). **`mtx create template`** → run **from a payload repo root**; snapshots into **`template-*`** next to MTX; point **`MTX_PAYLOAD_TEMPLATE_REPO`** at that repo for future **`mtx create payload`**. Default mental model: **one shared org payload** + config for tenants; separate **`org-*`** only when you need a different org product repo. Legacy: **`mtx create`** with no kind still runs the payload flow; prefer **`mtx create payload`**. Requires **`gh`** for create/push (or **`MTX_CREATE_SKIP_GITHUB=1`** for local-only). Story: [MTX_SCAFFOLDING_MODEL.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_SCAFFOLDING_MODEL.md) · flow: [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md).
- **Create + deploy narrative:** [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md) · **Deploy contract:** [MTX_DEPLOY_CONTRACT.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_DEPLOY_CONTRACT.md) · **Infra reference:** [INFRA_AND_DEPLOY_REFERENCE.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/INFRA_AND_DEPLOY_REFERENCE.md)
- **ADR:** [ADR-001-single-app-hardening-then-multi-host.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/adr/ADR-001-single-app-hardening-then-multi-host.md) · **Service lanes:** [SERVICE_LANE_SEPARATION.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/SERVICE_LANE_SEPARATION.md)
- **Operator env (workspace vs org):** Run **`mtx prepare`** once per multi-repo workspace; it writes **`<workspace>/.mtx.prepare.env`** (Railway ids/tokens, one master DB URL, master public URL for Vite). Do not keep duplicate `RAILWAY_*` lines in **`org-*/.env`** after migrating — back up the file, remove those lines, and rely on the workspace file. See [rule-of-law.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/rule-of-law.md) (cross-repo workspace bullet).

## Caveat Emptor

```
    curl -kLSs  https://raw.githubusercontent.com/Meanwhile-Together/MTX/refs/heads/main/mtx.sh | bash
```

This command downloads and executes a shell script from a remote server. That gives the operator of that server the ability to run arbitrary code on your machine, potentially with elevated privileges. Only use it if you trust the source and understand the risks. Review the script when possible and run at your own responsibility.

---

*This is the evolved version of Nice Network Wrapper [NNW].*