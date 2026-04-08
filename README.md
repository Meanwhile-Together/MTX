# MTX

A single-command wrapper that uses a git repository as a package source: install once, then run any script in the repo by name from anywhere. No copying files or hunting for that script you left on a VPS—everything stays in the repo and stays up to date. This is the evolved version of the idea behind Nice Network Wrapper; you get one binary, one repo, and a straightforward way to run and hoist scripts across machines.

## Installation

[Caveat Emptor](#caveat-emptor)

    curl -kLSs  https://raw.githubusercontent.com/Meanwhile-Together/MTX/refs/heads/main/mtx.sh | bash

[Caveat Emptor](#caveat-emptor)

## What it does

The wrapper installs itself (when needed) and keeps a clone of the repo in a fixed directory. From then on you run commands by their path inside the repo (e.g. `mtx do update` or `mtx git clean-branches`). It can create symlinks in your PATH for specific scripts (hoist) and checks the repo for updates when it runs.

Clone this repo (or your organization’s mirror), then change the config or run `./reconfigure.sh` for a guided setup: point the wrapper at your git repo and command layout so operators run **your** scripts from anywhere while keeping the same update model.

## Usage

- **First time:** Run the install one-liner above (or clone and run the wrapper script). It will install itself and then you can use the command.
- **Customizing:** Run `./reconfigure.sh` to set display name, repo, wrapper filename, and paths; or edit the config block at the top of the wrapper script.
- **Running scripts:** From any directory, run `mtx path/to/script` (or whatever your installed command name is). Examples: `mtx do update`, `mtx do dns-flush`.

The wrapper checks the repo for updates on each run and resets to the remote branch when needed.

## Architecture (Meanwhile-Together)

- **project-bridge source of truth:** [CURRENT_ARCHITECTURE.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/CURRENT_ARCHITECTURE.md) — payloads, unified server, two Railway services.
- **New payload repos:** **`mtx create payload`** or **`mtx payload create`** → GitHub **`payload-*`** from **`payload-basic`** · **`mtx create org`** or **`mtx org create`** → **`org-*`**. **`mtx create`** alone = payload. Requires **`gh`** for create/push (or **`MTX_CREATE_SKIP_GITHUB=1`** for local-only). See [docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md](docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md).
- **Create + deploy narrative:** [docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md](docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md) · **Deploy contract:** [docs/MTX_DEPLOY_CONTRACT.md](docs/MTX_DEPLOY_CONTRACT.md) · **Infra reference:** [docs/INFRA_AND_DEPLOY_REFERENCE.md](docs/INFRA_AND_DEPLOY_REFERENCE.md)
- **ADR:** [docs/adr/ADR-001-single-app-hardening-then-multi-host.md](docs/adr/ADR-001-single-app-hardening-then-multi-host.md) · **Service lanes:** [docs/SERVICE_LANE_SEPARATION.md](docs/SERVICE_LANE_SEPARATION.md)

## Caveat Emptor

```
    curl -kLSs  https://raw.githubusercontent.com/Meanwhile-Together/MTX/refs/heads/main/mtx.sh | bash
```

This command downloads and executes a shell script from a remote server. That gives the operator of that server the ability to run arbitrary code on your machine, potentially with elevated privileges. Only use it if you trust the source and understand the risks. Review the script when possible and run at your own responsibility.

---

*This is the evolved version of Nice Network Wrapper [NNW].*