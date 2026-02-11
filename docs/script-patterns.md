# Script patterns (child scripts)

Child scripts are **dev/*.sh**, **setup/*.sh**, **deploy/*.sh**, etc.—the scripts that mtx.sh **sources** after changing to the project directory. This doc is for authors of those scripts. For wrapper behavior (includes, help, install), see **mtx-patterns.md**.

---

## Contract from the wrapper

- mtx.sh runs **`cd "$execDir"`** before sourcing your script, where `execDir` is the directory the user ran `mtx` from (the project root).
- mtx.sh does **not** set or export a "root" or "project root" variable. You get only the current working directory.

---

## What scripts DON'T do (anti-patterns)

- **Don't use a "root" or "project root" variable.** No `ROOT_`, `ROOT`, or similar. The caller already put you in the project directory. If you need to reference "here" after changing directory, use relative paths (e.g. `../config`) or a small helper that finds the project (e.g. walk up until `package.json` exists).

- **Don't assume the script runs from the script's own directory.** You are run from the **project** directory (where the user invoked `mtx`). Paths are relative to the **current working directory** (the project), not the script file location.

- **Don't `cd` to an absolute "root" path.** Never `cd "$ROOT_/targets/desktop"` or `cd /targets/desktop`. If `ROOT_` is empty you get `cd "/targets/desktop"` and break. Use relative paths: `cd targets/desktop`.

- **Don't add no-op `cd`.** `cd "$ROOT_"` or `cd .` when you're already in the right place is pointless. Omit it.

- **Don't use `exec`.** `exec` replaces the shell process with the command, so control never returns to the caller, traps and cleanup never run, and the wrapper can't rely on the script process exiting normally. Run the command normally (e.g. `npm run build`) so the script exits after the command and the caller gets control back.

- **Don't give a top-level script arguments when it has a paired subfolder.** If you have both `compile.sh` and `compile/`, then `compile.sh` must not take arguments. Subcommands live in `compile/*.sh`; the top-level script runs when the user invokes `mtx compile` with no subcommand and may show usage or perform the default action (e.g. build all). Arguments belong to the subfolder scripts.

- **Don't require the caller to set or export variables for you.** Scripts should work with the environment mtx gives them (cwd = project root). If you need to "remember" where project root is after you `cd` away, derive it (e.g. walk up to find `package.json`) or use relative paths like `..` and `../config`.

---

## What scripts DO (patterns)

- **Rely on current working directory.** When the script runs, `pwd` is the project root. Use it: `cd targets/desktop`, `npm run build`, `config/deploy.json`, `.env`.

- **Use relative paths.** Paths are relative to the project: `targets/desktop`, `./config/deploy.json`, `terraform`, `.env`. After `cd terraform`, project root is `..` and config is `../config/deploy.json`.

- **If you leave the project dir, get back without a stored "root".** When you `cd terraform` (or similar), return by either:
  - `cd ..` when you know you're exactly one level down, or
  - A small helper, e.g. `while [ ! -f package.json ] && [ "$(pwd)" != "/" ]; do cd ..; done`, so you don't depend on any variable.

- **Keep scripts self-contained.** They should work given only: (1) mtx has done `cd "$execDir"`, and (2) the project has the expected layout (e.g. `package.json`, `targets/`, `config/`). No magic exports from the caller.

- **Set `desc` for the help menu.** In the first 30 lines of the script, define `desc="Short description"` or `desc='Short description'`. The wrapper uses it for `mtx help`. See **mtx-patterns.md** for how help is built.

- **Optional: `nobanner=1`** only to skip the 24h banner when this script runs. Script/precond output is never captured; only **mtx_run** subprocesses are quiet at default. See **mtx-patterns.md** § `nobanner`.

- **Use `mtx_run` for subprocesses so their output is quiet at default.** The wrapper sets `MTX_VERBOSE` (1=normal, 2=detail, 3=full, 4=trace). At default `-v`, your script’s echoes show but `mtx_run` subprocess output is quiet; at `-vvv` runs show full output; at `-vvvv` commands are traced. `echo`/`echoc` always print; only **`mtx_run`** is quiet at default. Use **`mtx_run`** for commands invoked by your script (e.g. `mtx_run npm run build`, `mtx_run "$0" compile vite`). Do **not** use `mtx_run` when you need to capture output (e.g. `APK_PATH=$(npm run -s find:apk ...)`).

---

## Summary table

| Anti-pattern | Pattern |
|-------------|--------|
| `ROOT_`, `ROOT`, or any "project root" variable | Use `pwd` and relative paths; you're already in the project |
| `cd "$ROOT_/targets/desktop"` | `cd targets/desktop` |
| `cd "$ROOT_"` / `cd .` to "ensure we're in root" | Omit, or use a helper that walks up to `package.json` |
| Requiring the caller to export where the project is | Script assumes cwd is project root when it starts |
| No `desc` in first 30 lines | Add `desc="One-line description"` near top for help menu |
| Skip 24h banner when this script runs (e.g. interactive menu) | Add `nobanner=1` in first 30 lines (optional) |
| `exec npm run ...` (or any `exec`) | Run the command normally so the script exits and caller gets control back |
| Top-level script with paired subfolder taking arguments (e.g. `compile.sh` with `$1`) | No arguments; subcommands live in the subfolder (e.g. `compile/client.sh`); top-level shows usage only |
| Noisy subprocess (npm, compile) | `mtx_run npm run build` / `mtx_run "$0" compile vite` so at `-v` runs stay quiet; at `-vvv` output shows |
