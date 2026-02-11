# Getting started: writing and adding scripts

This guide is for adding new scripts to MTX so they appear in `mtx help` and run in the project directory. For patterns and anti-patterns, see **script-patterns.md**. For how the wrapper works (help, includes), see **mtx-patterns.md**. For change history derived from git, see **history.md**.

---

## Where scripts live

- **Top-level command:** A single script `mtx.sh` in the repo root is the wrapper. Your scripts go in **directories** next to it.
- **Command category:** Each directory is a category. Examples: `dev/`, `setup/`, `deploy/`, `sys/`, `terraform/`. The user runs `mtx <category> <script>` (e.g. `mtx dev run-electron`).
- **Script file:** Put your script in that category as `<name>.sh`. So `dev/run-electron.sh` is run with `mtx dev run-electron`.
- **Subcommands only:** If a category has no `category.sh` and only `category/*.sh`, those appear as subcommands (e.g. `mtx compile android-debug`). If there is both `deploy.sh` and `deploy/*.sh`, the wrapper merges them so the directory’s scripts show as subcommands of `deploy`.

- **Top-level with paired subfolder:** If you have both `compile.sh` and `compile/`, the **top-level script must not take arguments**. When the user runs `mtx compile` (no subcommand), only `compile.sh` runs—it may show usage or perform the default action (e.g. build all). Other targets live in `compile/*.sh` (e.g. `mtx compile vite`, `mtx compile android`). Do not dispatch on `$1` in the top-level script.

So: pick or create a category dir (e.g. `dev/`), add `<something>.sh`, and the command is `mtx dev something`.

---

## Minimal script structure

1. **Shebang** (optional but good): `#!/usr/bin/env bash`
2. **`desc`** in the first 30 lines so `mtx help` shows a one-line description.
3. **`set -e`** so the script exits on first failing command (recommended).

Example:

```bash
#!/usr/bin/env bash
# Optional comment (e.g. what this does or when to use it)
desc="One-line description for mtx help"
set -e

# Your script runs with current directory = project root (where the user ran mtx).
npm run build
```

Save as e.g. `dev/build-thing.sh`. After MTX is installed or updated, `mtx help` will list it and `mtx dev build-thing` will run it.

---

## You're already in the project root

When your script runs, the current directory is the **project** (where the user ran `mtx`), not the script’s directory. So:

- Run project commands: `npm run build`, `npm install`, `./gradlew assembleDebug`.
- Go into a subdir: `cd targets/desktop`, `cd terraform`.
- Read config: `config/deploy.json`, `.env` (relative to project root).
- **Don’t** use a “root” variable: no `ROOT_`, no `ROOT`. Use relative paths and `cd` as needed.

If you `cd` into a subdir and need to get back to the project root later, use `cd ..` (if you’re one level down) or a small helper that walks up until it finds `package.json`. See **script-patterns.md** for the pattern.

---

## Adding a new script (checklist)

1. **Choose a category** (e.g. `dev/`, `setup/`, `deploy/`). Use an existing dir or create one.
2. **Create the file** `category/name.sh` (e.g. `dev/my-task.sh`).
3. **Add shebang, `desc`, and `set -e`** in the first 30 lines. Example:
   - `desc="Short user-facing description"`
   - If the script is **interactive** (menu, `read` prompts), add **`nocapture=1`** so its output is shown at default verbosity (see **mtx-patterns.md** § nocapture).
4. **Write the body** using relative paths from the project root (e.g. `targets/desktop`, `config/app.json`). Don’t rely on any variable set by the wrapper except that you’re in the project directory.
5. **Make it executable** (optional; mtx sources it): `chmod +x dev/my-task.sh`
6. **Run it:** From the project directory, run `mtx dev my-task` (after install/update). Run `mtx help` to confirm it appears.

---

## Examples

**Delegate to an npm script (no `cd`):**

```bash
#!/usr/bin/env bash
desc="Build Android debug APK (optional: ADB install)"
set -e
npm run build:android:debug
```

(Don't use `exec`: it replaces the shell so the script never returns to the caller and traps/cleanup never run.)

**Run a command in a project subdir:**

```bash
#!/usr/bin/env bash
desc="Run Electron; kill nodemon on clean exit"
set -e

cd targets/desktop
cross-env NODE_ENV=development electron "$@"
# ... rest of script
```

**Read project config:**

```bash
#!/usr/bin/env bash
desc="Do something with deploy config"
set -e

if [ ! -f "config/deploy.json" ]; then
  echo "Missing config/deploy.json" >&2
  exit 1
fi
# use config/deploy.json, .env, etc.
```

---

## Help and docs

- **`mtx help`** — Lists all commands and their `desc`. Built from the **installed** copy of MTX (`$scriptDir`), not the repo you’re editing. After you install or update, help will show your new script.
- **script-patterns.md** — What scripts should and shouldn’t do (no ROOT, relative paths, getting back to root).
- **mtx-patterns.md** — How the wrapper works (includes, help, `desc` extraction, known issues).
- **history.md** — Change history derived from git (chronological summary and themes).
