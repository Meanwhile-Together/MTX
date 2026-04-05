# Known Confusions and Fixes

Documented friction points discovered during developer onboarding review. Each item includes what causes confusion and, where available, clear guidance. Items without a fix yet are marked as open.

---

## 1. Cross-repo relationship is invisible in READMEs

**Confusion:** Neither MTX nor project-bridge README mentions the other. A developer cloning both has no guidance that they are companion tools.

**Fix (open):** Add a cross-reference section in both READMEs. The authoritative relationship doc already exists at `project-bridge/docs/MTX_AND_PROJECT_B.md` — it needs to be linked from primary surfaces.

---

## 2. Multiple deploy entry points

**Confusion:** `mtx deploy`, `npm run deploy:staging`, direct `bash MTX/deploy.sh`, and `./terraform/apply.sh` are all valid ways to deploy. No single doc says "use this one."

**Fix (open):** Establish and document one canonical developer-facing deploy entry point. The deploy contract doc (`MTX/docs/MTX_DEPLOY_CONTRACT.md`) defines `mtx deploy` as canonical, but this is not stated in either README or quickstart.

---

## 3. Legacy naming ("NNW") in user-facing output

**Confusion:** `mtx help` and version output reference "NNW" (Nice Network Wrapper), the predecessor name. The product is MTX.

**Fix (open):** Replace NNW references with MTX in `mtx.sh` user-facing strings (printVersion, help options text).

---

## 4. Sibling repo layout assumed but not documented

**Confusion:** MTX scripts assume project-bridge is at `../project-bridge` relative to MTX. `create.sh` defaults workspace root to parent directory. Missing siblings cause hard errors with no guidance.

**Fix (open):** Document the expected workspace layout in both READMEs and in the quickstart doc.

---

## 5. README and getting-started examples reference nonexistent paths

**Confusion:** MTX README uses `mtx do update` and `mtx git clean-branches` as examples but no `do/` or `git/` directories exist. `docs/getting-started.md` references `dev/run-electron.sh` but no `dev/` directory exists.

**Fix (open):** Update examples to match actual command paths in the current repo, or remove/label them as illustrative-only.

---

## 6. Hard reset on every command run

**Confusion:** Before sourcing any script, `mtx.sh` runs `git reset --hard origin/main` on the installed clone at `scriptDir`. Any local edits to the installed copy are silently wiped.

**Fix (open):** Document this behavior clearly so developers expect it. Consider whether a warning is appropriate when local changes would be lost.

---

## 7. `mtx_run` hides subprocess output at default verbosity

**Confusion:** At default verbosity, `mtx_run` redirects stdout to `/dev/null`. Builds or tests wrapped in `mtx_run` appear silent while the script's own `echo` statements still print. This can make it look like commands are not running.

**Guidance:** Use `-vvv` for full output: `mtx -vvv <command>`.

---

## 8. No config/server.json by default in project-bridge

**Confusion:** Only `*.example.json` files exist under `config/` for server shapes. Multi-payload hosting requires creating `config/server.json`, but no onboarding doc explains this step.

**Fix (open):** Document how to create `config/server.json` from the example files, or provide a starter file.

---

## Future expansion

Additional confusions will be added here as each flow is explicitly reviewed and validated.

---

See also: [Mental Model](./00-mental-model.md) | [First Day Quickstart](./01-first-day-quickstart.md)
