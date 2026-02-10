# Understanding `mtx.sh`

**NNW** (Nice Network Wrapper / NickNetworks) is a Bash **script wrapper** that uses a Git repo as a package source. It installs itself under `/etc/NNW`, symlinks a single entrypoint in `/usr/bin`, and runs scripts from the repo by path (e.g. `nnw do update`, `nnw git clean-branches`). It can self-update from the remote and optionally “hoist” individual scripts as standalone commands.

---

## 1. Config (top of script)

| Variable        | Purpose |
|----------------|---------|
| `gitUsername`  | (Unused in current script) |
| `gitToken`     | (Unused in current script) |
| `domain`       | Git host, e.g. `https://github.com` |
| `displayName`  | Brand name, e.g. `NNW` |
| `slugName`     | Lowercase of `displayName` → `nnw` |
| `repo`         | Git repo path, e.g. `Nackloose/nnw` |
| `installedName`| Name of the symlink in `$PATH` (default `nnw`) |
| `binDir`       | Where the symlink is created (`/usr/bin`) |
| `scriptDir`    | Where the repo lives (`/etc/$slugName` → `/etc/nnw`) |
| `packageListFile` | File listing hoisted command names: `$scriptDir/.installed_packages` |

Version is derived from Git when possible: `git describe --tags` or short `HEAD`, else `"unknown"`.

---

## 2. Exit codes

| Code | Meaning |
|------|--------|
| 0 | Success |
| 1 | Both `--uninstall` and `--reinstall` given |
| 2 | `scriptDir` does not exist when required |
| 3 | Update failed and clone fallback failed |
| 4 | Script not found when using `--hoist=...` |
| 5 | (Reserved) Script already hoisted (logic commented out) |
| 6 | (Reserved) Script not in package list for uninstall |

---

## 3. Startup and includes

- **Wrapper location**: `dir` = directory containing the running `mtx.sh` (e.g. `/etc/nnw` when installed).
- **Execution directory**: `execDir` = current working directory when `nnw` was invoked (restored before running a script).
- **Includes**: All `$scriptDir/includes/*.sh` are `source`d (e.g. `bolors.sh` for colors and `debug`/`info`/`success`/`error`).
- **Package list**: `$packageListFile` is created if missing (used for hoist tracking).

**Note:** The script calls `c yellow ...` in a few places; `bolors.sh` only defines `color()`. So either add a `c()` alias for `color` in includes or replace `c` with `color` in `mtx.sh`.

---

## 4. Commands and flow

### 4.1 `nnw help`

- Prints usage and “Scripts & Directories” by scanning `$scriptDir` for `*.sh` (excluding paths containing `.`) and for directories (excluding `.` and `includes`).
- Lists each script as `nnw <path/to/script>` and directories with their contents.
- Documents options: `--help`, `--version`, `--verbose`, `--update`, `--uninstall`, `--reinstall`, `--hoist=<name>`, `--submerge`.

### 4.2 Global flags (parsed before the script path)

- `--version` → print version and exit 0.
- `--verbose` → set `verbose=1` (enables `debug` output).
- `--uninstall` → remove `$binDir/$installedName` and exit 0.
- `--reinstall` → (flag only; reinstall is done by running from outside `$binDir`).
- `--hoist=<name>` → after resolving the script, install it as a symlink `$binDir/<name>` and append `<name>` to `$packageListFile`, then exit 0.
- `--submerge` → remove every symlink in `$binDir` that points to the same script as the one being run, and remove those names from `$packageListFile`, then exit 0.

Uninstall and reinstall cannot both be set (exit 1).

---

## 5. Install vs run

- **If the script is not run from `$binDir`** (e.g. run from a clone in `~/NNW/mtx.sh`):
  - It calls `installWrapper` and exits.
  - `installWrapper`: removes and recreates `$scriptDir`, calls `updateCheck` (which may clone if needed), then creates `$binDir/$installedName` → symlink to `$scriptDir/mtx.sh` and makes it executable.

- **If the script is run from `$binDir`** (normal `nnw` usage):
  - `cd` to `$scriptDir`, run `updateCheck`, then resolve and run the requested script (or handle hoist/submerge).

So: **first run from a clone = install**; **subsequent runs via `nnw` = update check + script dispatch**.

---

## 6. Update logic (`updateCheck`)

- If `$scriptDir` does not exist → exit 2.
- Run `git -C "$scriptDir" remote update`.  
  - If that succeeds and local is not equal to `origin/main`: fetch, then `git reset --hard origin/main`, fix permissions and symlink in `$binDir`, print success and new SHA.
  - If local is up to date: print “up-to-date”.
- If `remote update` fails: try to clone into `$scriptDir` with `git clone ...` (note: variable used is `$scriptDir` for both clone target and “current” repo; the clone semantics here may overwrite or conflict depending on existing contents).

---

## 7. Script path resolution

- **`isolateScript`**: Given the remaining args (e.g. `do update`), walk a path step by step (e.g. `./do`, `./do/update`) and return the 1-based index of the first arg where `$pathSoFar.sh` exists as a file. If none, return 1.
- **`isolateDir`**: Same idea but for directories.

Flow:

1. Try `isolateScript "$@"`. If it returns a valid script index:
   - `script` = path built from args with spaces removed + `.sh` (e.g. `do/update.sh`).
2. If no script found, try `isolateDir`. If a directory is found:
   - Build the directory path from args (e.g. `new` → `new`, `a` `b` → `a/b`). If `$pathDir/default.sh` exists, set `script` to that and run it (so `nnw new` runs `new/default.sh`). Otherwise print that the path is a directory, list its contents, and exit.
3. If neither script nor directory:
   - Treated as “just run the wrapper” (e.g. update only); print “We’re done here.” and exit.

Script path is relative to `$scriptDir` (e.g. `do/update.sh` under `/etc/nnw`).

---

## 8. Running a script

- **Before running**: `git -C "$scriptDir" reset --hard origin/main` is run (again), then `chmod +x` on the script.
- **Arguments**: All args from the resolved script index to the end are passed to the script as a single string `$args` (e.g. `nnw do update --foo` → script gets `--foo`).
- **Execution**: `cd "$execDir"` (back to where the user ran `nnw`), then `source "$scriptDir/$script" $args` (script runs in current shell with those args).

---

## 9. Hoist and submerge

- **Hoist** (`--hoist=<name>`): When a script was resolved, create symlink `$binDir/<name>` → `$scriptDir/$script`, make it executable, append `<name>` to `$packageListFile`, then exit. (Multi-hoist is allowed; the “already hoisted” check is commented out.)
- **Submerge** (`--submerge`): For the resolved script, read `$packageListFile`; for each line `$alias`, if `$binDir/$alias` is a symlink to the same script, remove that symlink and remove the line from `$packageListFile`, then exit.

---

## 10. File layout (conceptual)

```
/etc/nnw/                    # scriptDir
  .git/
  .installed_packages        # one hoisted command name per line
  mtx.sh                     # this wrapper
  includes/
    bolors.sh                # colors, debug, info, success, error
  do/
    update.sh
    dns-flush.sh
    ...
  git/
  docker/
  tool/
  ...

/usr/bin/nnw                 # symlink → /etc/nnw/mtx.sh
/usr/bin/<hoisted-name>      # optional symlinks → /etc/nnw/<path>.sh
```

---

## 11. Summary

- **mtx.sh** is the single entrypoint: installer when run from outside `/usr/bin`, and dispatcher when run as `nnw`.
- It keeps the “package” in `/etc/nnw` (or configurable `scriptDir`), updates via `git fetch` + `reset --hard origin/main`, and runs scripts by path (e.g. `nnw do update`) by sourcing them from `scriptDir`.
- Optional **hoist** exposes a script as a global command; **submerge** removes those symlinks and cleans the package list.
- **default.sh in subfolders:** If the resolved path is a directory (e.g. `nnw new` with no subcommand), the wrapper looks for `default.sh` inside that directory. If it exists, it runs that script (e.g. `nnw new` → `new/default.sh`). If not, it lists the directory and exits.
- Dependencies: Bash, git, optional sudo; includes provide colors and logging (`bolors.sh`). Fixing the `c` vs `color` usage will avoid possible runtime errors on debug/success messages.
