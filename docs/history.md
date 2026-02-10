# MTX history (from git)

Summary of changes from the MTX repository git history. Use this for context when reading script-patterns, mtx-patterns, or when integrating with project-b.

---

## Chronological summary

**Initial commit** — Wrapper and payload layout.

**Deploy and Terraform**

- Scripts use relative calls for commands (staging.sh, menu.sh, setup.sh); deployment scripts call `terraform apply` via relative commands.
- Railway service discovery in apply.sh: dedicated function for GraphQL edges/node and direct array responses; re-discover existing services on Terraform conflict.
- apply.sh: treat "Deploy complete" as success; refactor backend build exit handling; do not let Terraform manage existing app services (avoid destroying live services).
- manual.sh: interactive menu for environment (replacing prompt); deploy.sh validates environment to staging or production with menu for invalid input.
- Removed deprecated new.sh and default.sh (old "nnw new" behavior).

**Help and desc**

- mtx.sh help: list top-level commands and subcommands; merge directories with same-name script so dir is not listed twice; clarify when no subcommands; use arrays for labels and descriptions.
- deploy scripts: add `desc` variable for each script (deploy.sh, manual.sh, production.sh, staging.sh).

**Includes and update behavior**

- mtx.sh: load includes from `$dir/includes` when `$scriptDir/includes` missing; stub undefined functions when no includes found; create package list file only when scriptDir exists; log commits during git update.
- MTX_SKIP_UPDATE: skip update check when set (e.g. when sourcing scripts to avoid update loops).

**run-electron and cross-env**

- run-electron.sh: remove cross-env; use inline NODE_ENV; simplify; use npx for Electron; conditional desktop build if main entry missing; later refactor to invoke desktop dev script directly.
- future.md: prefer inline env vars over cross-env on Unix.

**Compile and run scripts**

- Removed deprecated android-debug.sh, menu.sh, rebrand.sh.
- compile.sh: no argument handling; usage only; build all targets by default; remove all.sh, build.sh, and per-target client/desktop/mobile/server scripts; vite.sh builds all Vite targets (client, desktop, backend, mobile); ios.sh checks xcodebuild availability.
- Paired top-level + subfolder: mtx.sh runs `compile.sh` for `mtx compile`, and `compile/vite.sh` for `mtx compile vite`; top-level script must not take arguments when a same-name directory exists.
- mtx_run: scripts use mtx_run for subprocesses so output respects verbosity (-v / -vvv); mtx.sh self-heals if mtx_run is missing; android.sh handles Gradle/cache corruption.
- Build scripts: progress indicators and completion messages; compile and run scripts redirect output to stderr for logging consistency; setup.sh stderr for rebrand/build/deploy messages.

**Preconditions and system folders**

- precond: mtx.sh sources precond/*.sh in order before running the command; docs describe precond directory and error handling.
- System folders: mtx.sh excludes declared system folders (e.g. includes, precond) from command listing and execution; they do not appear in help.
- Precondition script output improved (messaging, no user prompts); mtx.sh skips precondition checks for workspace.sh so workspace can run from empty dir without project-b checks.

**Error handling and workspace**

- mtx.sh: checks for missing dependencies; improved logging for debugging; docs updated for error handling.
- workspace.sh: removed "dogfood" then "archive" from repo list; workspace clones MTX, project-bridge, test, client-a, cicd (five repos) and creates Meanwhile-Together.code-workspace.

---

## Themes

| Theme | What changed |
|-------|----------------|
| **Portability** | Relative calls; no cross-env; stderr for logging. |
| **Help and discoverability** | desc in scripts; merged help (top-level + subcommands); system folders hidden. |
| **Robustness** | Includes stubs; package list only when scriptDir exists; MTX_SKIP_UPDATE; mtx_run self-heal; precond; skip precond for workspace. |
| **Deploy** | Terraform relative; Railway discovery (GraphQL); don’t manage existing app services; staging/production menu. |
| **Structure** | Paired top-level + subfolder; deprecated scripts removed; compile builds all by default. |
