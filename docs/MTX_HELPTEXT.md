# MTX `helptext` and wrapper-owned help

This document is normative for MTX command scripts and the `mtx` wrapper (`mtx.sh`).

## Rules

- **Data in the command file:** a command can define **`desc=`** (one line, used in `mtx help`) and optionally **`helptext=<<'MTXH' … MTXH`** (multiline usage: behavior, flags, environment, warnings for **that** command only).
- **Parsing in one place only:** the **`mtx`** wrapper prints help. **Sourced command scripts must not** implement `-h` / `--help` / `case` branches (or any other help parsing).
- **No catalog in `helptext`:** do not list subcommands, peer scripts, or “try these names” tables. **Discoverability** (global `mtx help`, command groups such as `fixes/*.sh`, nested paths) is **only** implemented in `mtx` — not duplicated inside `helptext`.
- **Command groups (directory, no `foo.sh`):** optional short prose may live in **`<group>/HELPTEXT`** using the same `helptext=<<'MTXH' … MTXH` form. The **enumerated** list of children is always printed by `mtx` from the directory; do not hand-maintain that list in `HELPTEXT`.

## `helptext=<<'MTXH' … MTXH`

- The opening line must be exactly: `helptext=<<'MTXH'` (fixed delimiter `MTXH` for v1).
- The closing line must be **exactly** `MTXH` (no leading/trailing spaces).
- `mtx` reads this block with **`get_helptext`** (e.g. `awk`) **without** `source`ing the file.
- Place the block after **`desc=`** and, when possible, before **`set -e`**, `source`, or I/O, so a future static layout check can validate ordering.
- If `helptext` is absent, `mtx <cmd> <help token>` falls back to **`get_desc`** (one line).

## Help tokens (first argument after the resolved command)

`mtx` treats the following as “print this command’s help and exit 0” when they are the **first** argument after the command path: `-h`, `--help`, `-help`, `--h`, `-?`, `--?`, `/?`, `?`, `help`, `usage`, `--usage`, `-usage`.

A bare `?` may be interpreted by the shell as a glob; use quoted `'?'` if needed (same as for any other CLI).

## Help-only runs and side effects

For help-only invocations, `mtx` does not **`source`** the command script, does not run **precond**, and does not run **`git reset --hard`** in the install tree (so a dirty checkout is not discarded just to print help).

## Command groups

- `mtx <group> --help` (or the same with another help token) prints a short **group** line, optional text from **`<group>/HELPTEXT`**, then the **generated** subcommand list.
- `mtx <group>` with no help token lists the group on **stderr** (warning style), same as before, then exits.

## See also

- **project-bridge** [`docs/rule-of-law.md`](../../project-bridge/docs/rule-of-law.md) — cross-repo ledger (MTX per-command help: §1 bullets dated 2026-04-28).
- Normative CLI surface (when checked in for your workspace): **MTX_COMMAND_SURFACE** in project-bridge or MTX docs.
