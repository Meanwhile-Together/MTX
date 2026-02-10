# MTX patterns (wrapper)

This doc covers **mtx.sh** (the wrapper): how it runs, loads includes, builds help, and what it guarantees to child scripts. For how child scripts should behave, see **script-patterns.md**.

---

## Caller contract (what mtx guarantees to child scripts)

- Before sourcing a child script, mtx.sh does **`cd "$execDir"`** where `execDir` is the directory the user ran `mtx` from (the project root). Child scripts must not assume anything else.
- mtx.sh does **not** set or export a "root" or "project root" variable. Child scripts rely on current working directory only.

---

## Includes (bolors)

- **Load order:** (1) `$scriptDir/includes/*.sh` if present (installed copy), (2) else `$dir/includes/*.sh` if present (running from repo before install), (3) else stub functions so `info`, `success`, `error`, `warn`, `debug`, `color`, `c`, `echoc` exist (no-op or plain echo).
- **Why:** When the user runs `./mtx.sh` from the repo before any install, `$scriptDir` may not exist or be empty; loading from `$dir/includes` gives bolors so logging works during install and clone. If neither path has includes, stubs avoid "command not found."
- **Package list file:** Created only when `$scriptDir` exists; otherwise `touch "$packageListFile"` would fail before install.

---

## `desc` and the help menu

### `desc` (script description)

- The wrapper expects every runnable script (top-level `*.sh` or `*/subcommand.sh`) to define **`desc`** in the first **30 lines** so the help menu can show a one-line description.
- **Format:** `desc="Short description here"` or `desc='Short description here'`. Single or double quotes; they are stripped when displayed.
- **Extraction:** `get_desc "$file"` reads the first 30 lines of the script, takes the first line that matches `^desc=`, strips the `desc=` and the quotes, and echoes the value. If there is no `desc=` line or the script isn't readable, nothing is echoed and the help entry shows the label only (no description).

### Help menu (`mtx help`)

- **Trigger:** First argument is the literal string `help` (e.g. `mtx help`). mtx.sh then prints a command list and does not run any child script.
- **Source of commands:** The menu is built from **`$scriptDir`** only (the installed copy, e.g. `/etc/mtx`). It does **not** scan the repo you're running from. If `$scriptDir` doesn't exist (e.g. before first install), the help shows "No scripts directory at: $scriptDir" and only the options section.
- **Layout:**
  - **Top-level commands:** Every `*.sh` in `$scriptDir` except `mtx.sh` and files under `includes/` or dot-prefixed. Each becomes a line like `  cmd` with its `desc` (from `get_desc`) aligned to the right.
  - **Subcommands:** For every directory `$scriptDir/<name>`, if there is also `$scriptDir/<name>.sh`, only the directory is used (merged). Otherwise the directory is listed and each `*.sh` inside is a subcommand: `    subcmd` with its `desc`. A blank line is printed after the last subcommand of each group.
  - **Options:** At the end, help always prints the same options block (e.g. `--help`, `--version`, `--verbose`, `--update`, `--uninstall`, `--reinstall`, `--hoist=`, `--submerge`).
- **Paired top-level + subfolder:** When both `<name>.sh` and `<name>/` exist and the user passes another word (e.g. `mtx compile vite`), the wrapper checks for `<name>/<next>.sh`. If it exists, that subcommand script is run instead of the top-level script with the word as an argument. So `mtx compile vite` runs `compile/vite.sh`, not `compile.sh` with `vite` as `$1`.

- **Anti-pattern:** Don't assume help is built from the current repo. After install, help reflects `$scriptDir` (the cloned copy). Scripts without `desc` in the first 30 lines still appear in the menu but with no description next to them.

---

## Known issues and fixes (wrapper)

### 1. Race: using bolors before repo is cloned

- **Issue:** On first run from the repo, mtx.sh used to load includes only from `$scriptDir/includes`. But `scriptDir` is the install target (e.g. `/etc/mtx`); before install it doesn't exist or is empty, so bolors was never loaded. Then `installWrapper` → `updateCheck` called `info("Checking for updates...")` and similar, leading to "command not found" or similar.
- **Fix:** Load includes from `$dir/includes` when `$scriptDir/includes` is not available. `$dir` is the directory containing mtx.sh (the repo when run as `./mtx.sh`). Also add a stub block when neither path has includes, so all logging/color functions exist (no-op or plain echo).

### 2. ROOT_ / project root variable

- **Issue:** Child scripts used `ROOT_` or `ROOT` and assumed the caller set it. mtx.sh never set or exported it, so e.g. `cd "$ROOT_/targets/desktop"` became `cd "/targets/desktop"` and failed.
- **Fix:** The wrapper does not set a root variable. Child scripts use relative paths and current directory; if they `cd` away, they use `..` or a "walk up to package.json" helper (see script-patterns.md).

### 3. Redundant or wrong `cd` in child scripts

- **Issue:** Scripts did `cd "$ROOT_"` or `cd .` to "ensure we're in root." No-op or wrong when `ROOT_` is empty.
- **Fix:** Addressed in child scripts: omit no-op `cd`; for "return to project root after being in a subdir," use `cd ..` or a small helper that walks up until `package.json` exists.

### 4. `c` vs `color` in bolors

- **Issue:** mtx.sh calls `c yellow "..."` in a few places; bolors.sh only defined `color`, not `c`.
- **Fix:** Add `c() { color "$@"; }` in bolors.sh and in the stub block in mtx.sh so `c` is always available.

---

## Summary table (wrapper)

| Anti-pattern | Pattern |
|-------------|--------|
| Loading includes only from `$scriptDir` | Also load from `$dir` when running from repo; stub when neither exists |
| Calling `info`/`success`/`error` before clone | Stub definitions when no includes dir is available |
| Creating package list when `$scriptDir` missing | Create `$packageListFile` only when `$scriptDir` exists |
| Assuming help lists scripts from current repo | Help is built from `$scriptDir` (installed copy) only |
