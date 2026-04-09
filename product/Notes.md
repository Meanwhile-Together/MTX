# Product Notes

Feedback, questions, and observations for the team. Add new entries at the top.

## Entry Template

Use this structure for new entries (copy/paste, fill in, delete unused fields):

```
## YYYY-MM-DD — Short title (Name / role)

### Context
What you were trying to do; repo(s) involved.

### Audience
First-time / returning / CI / external contributor.

### What went well
- Specific surfaces: file, command, doc path.

### Friction
- Symptom + where you looked (README, which doc, CLI output).

### Expected vs actual
One or two lines if helpful.

### Docs already checked
List paths you opened (avoids duplicate requests for docs that exist but are hard to find).

### Severity
Blocks onboarding / slows repeat task / polish.

### Suggestions
Numbered, each tied to a concrete artifact (README section, doc, script, error message).

### Acceptance (optional)
"I'd consider this fixed when ..."

Tags: #onboarding #deploy #mtx #project-bridge #docs #npm-scripts
```

---

## 2026-04-05 — Infinite loop when running mtx from MTX directory (Ash developer)

### Context
After entering the sudo password, `mtx deploy staging` completed the update but then entered an infinite loop. Every iteration prints `HEAD is now at 80f9319 fix: improve MTX_ROOT resolution and update update-check logic` followed by `workspace not found, workspace features disabled`, repeating endlessly until Ctrl+C.

### Cause
Observed in two scenarios:
1. Running `mtx deploy staging` **from inside the MTX repo directory** instead of from the project-bridge root.
2. Running from the **correct directory (project-bridge)** but when the auto-update pulls new changes to the MTX wrapper. After `git reset --hard` applies the update, the wrapper re-sources itself and enters an infinite loop of reset + precondition + re-dispatch.

**Root cause:** `mtx.sh` modifies itself while bash is executing it. When `updateCheck` runs `git reset --hard origin/main` and the remote has new commits, the file at `/etc/mtx/mtx.sh` gets rewritten on disk. But bash is still reading from that same file — its internal file-position pointer becomes invalid because the bytes have shifted. Bash continues reading from the wrong offset in the new file, lands at an earlier section of the script, and re-executes the reset, creating an infinite loop.

This only triggers when the update actually changes `mtx.sh` (or nearby files that shift byte offsets). When there are no new commits, `git reset --hard` is a no-op and the file doesn't change, so bash's pointer stays valid.

**Fix options for Nick:**
- Read the entire wrapper into memory before running the update (e.g. wrap the body in a function and call it at the end so bash parses the whole file before executing).
- After updating, `exec` into the new version of the script cleanly instead of continuing execution from the modified file.
- Move the update logic into a separate script that the wrapper calls, so the currently-executing file is never the one being rewritten.

### Friction
- **No guard against running from the wrong directory.** MTX should detect this and print a clear error instead of looping.
- **The "workspace not found" message repeats on every loop iteration** but gives no actionable guidance.
- **Requires Ctrl+C to escape.** No timeout, no max-retry, no self-detection of the loop.

### Correct usage
Run MTX commands from the project-bridge directory: `cd project-bridge && mtx deploy staging`

### Severity
Blocks the command entirely. Looks like the tool is broken. Requires knowledge that wasn't communicated anywhere.

### Suggestions for Nick
1. Detect when `cwd` is the MTX repo itself (e.g. check for `mtx.sh` in current dir) and print: "You're inside the MTX repo. Run this command from your project root (e.g. project-bridge/)."
2. Add loop detection (e.g. counter or PID file) to prevent infinite re-execution.
3. Document the "run from project root" requirement prominently in `mtx help` output and README.

Tags: #onboarding #mtx #blocker #first-run #infinite-loop

---

## 2026-04-05 — Sudo password loop during auto-update (Ash developer)

### Context
Ran `mtx deploy staging` from the MTX directory. Before the deploy even starts, MTX's auto-update pulled new changes and then prompted for a sudo password three times in a row.

### Friction
- **Unexpected sudo prompt with no explanation.** The terminal shows "Password:" with no context about what it's for or why elevated permissions are needed. A developer who doesn't know the system might not feel safe entering their password.
- **Password loop on failure.** When the password isn't entered (or is wrong), it retries with "Sorry, try again" — up to three times before failing. No guidance on what to do.
- **Why it needs sudo:** MTX stores its installed clone at `/etc/mtx` and symlinks at `/usr/local/bin/mtx`. Both are system directories that require `sudo` for writes. The update runs `sudo chmod +x` and `sudo ln -sf` after pulling changes.
- **No opt-out in the moment.** The only escape is `Ctrl+C`. There's no message saying "press Ctrl+C to skip" or "run with MTX_SKIP_UPDATE=1 to bypass."
- **Workaround:** `MTX_SKIP_UPDATE=1 mtx deploy staging` skips the auto-update entirely.

### Severity
Blocks the command entirely until password is entered or user knows to Ctrl+C. Alarming for first-time users who don't expect a developer tool to ask for system credentials without explanation.

### Suggestions for Nick
1. Print a one-line explanation before the sudo prompt: "Updating MTX at /usr/local/bin — sudo required for system directory."
2. If sudo fails, catch the error and print: "Update skipped (sudo required). Run with MTX_SKIP_UPDATE=1 to bypass, or re-run with sudo."
3. Consider installing to a user-writable directory (e.g. `~/.local/bin`) instead of `/usr/local/bin` so sudo is never needed.
4. At minimum, suppress the retry loop — fail once and move on with a clear message.

Tags: #onboarding #mtx #sudo #blocker #first-run

---

## 2026-04-05 — Deploy step: `mtx deploy staging` (Ash developer)

### Context
Continued the Ashe Austaire new-client flow. After creating and building the payload, attempted `mtx deploy staging` from the project-bridge root.

### Audience
First-time developer deploying for the first time.

### What happened
- Deploy script ran, detected Railway platform from `config/deploy.json`, checked for API keys.
- **Correctly blocked:** No `.env` file exists, no `RAILWAY_ACCOUNT_TOKEN` set. Script exited with a clear error.
- Error message is one of the better DX moments: tells you what's needed (Railway account token), where to set it (`.env`), and where to get it (https://railway.app/account/tokens).
- In interactive mode (TTY), it would prompt for the token with hidden input and save it to `.env` automatically. In piped/non-interactive mode, it prints the instruction and exits.

### What went well
- The deploy script's token detection and prompting flow is clear and actionable.
- It reads app name/slug from `config/app.json` automatically.
- Tokens are persisted to `.env` so subsequent deploys don't re-prompt.

### Friction
- **"workspace not found" message** appears again (same as during `mtx create`). Still no explanation.
- **No `.env` file exists by default.** The deploy script creates/updates it, but a new developer doesn't know `.env` is expected until they hit this error.
- **No pre-deploy checklist.** A developer might not know they need: (1) a Railway account, (2) an account token, (3) later a project token per environment. The deploy script handles discovery but the overall prerequisites aren't documented in a quickstart.

### What the deploy flow does (if tokens were present)
Based on reading `MTX/terraform/apply.sh` (1228 lines):
1. Load `.env` for tokens.
2. Parse `config/deploy.json` (platform) and `config/app.json` (name, slug, owner).
3. Check/prompt for Railway account token. Save to `.env`.
4. Discover Railway workspace from `app.owner` via GraphQL.
5. Discover or create Railway project.
6. Discover existing services (backend-staging, backend-production, slug-staging, slug-production).
7. Terraform apply: create or adopt Railway services (two modules: railway-owner for backend, railway for app).
8. Deploy code: build server + `railway up` for app service; swap railway.json + build backend + `railway up` for backend service.
9. Print deploy URLs.

### Suggestions for Nick
1. Document Railway prerequisites in a deploy quickstart (account needed, where to get tokens, what `.env` should contain).
2. Suppress or explain the "workspace not found" message.
3. Consider a `mtx deploy preflight` or `mtx deploy check` command that validates prerequisites without running Terraform.

Tags: #deploy #mtx #onboarding #railway

---

## 2026-04-05 — Full new-client flow: Ashe Austaire end-to-end (Ash developer)

### Context
Attempted the complete flow a developer would follow to onboard a new client ("Ashe Austaire") using MTX and Project Bridge. No framework code was changed. Goal: see what works, what breaks, and what's missing.

### Audience
First-time developer onboarding a real client.

### Steps attempted and results

**Step 1: `mtx create` (create payload)**
- Ran `echo "Ashe Austaire" | mtx create` from project-bridge root.
- MTX auto-updated first (pulled 4 new commits). During update, `sudo chmod` and `sudo ln` failed with "a terminal is required to read the password" — noisy errors, but update continued.
- Output said "workspace not found, workspace features disabled" — no explanation of what this means.
- Template `template-basic` was cloned from GitHub into `../payload-ashe-austaire`.
- GitHub repo `Meanwhile-Together/payload-ashe-austaire` was created via `gh`.
- **BLOCKER:** `git push` failed because `create.sh` hardcodes SSH remote (`git@github.com:...`) but `gh auth` is configured for HTTPS. Had to manually switch remote to HTTPS and push.
- Output ended with a JSON snippet to add to `config/server.json` — but no guidance on how to create that file since it doesn't exist.

**Step 2: Install and build payload**
- `npm install` in `payload-ashe-austaire` — worked (12 packages, 0 vulnerabilities).
- `npm run build` (TypeScript compile) — worked.
- Result: `dist/` folder with compiled `index.js` exporting `getAppViews`, `getViewComponent`, `getAppRoutes`.

**Step 3: Register payload in Project Bridge**
- `config/server.json` does not exist in project-bridge. Only `config/server-multi-app.example.json` and `config/server-backend.example.json` exist.
- No doc or command tells you how to create `config/server.json` from the examples.
- Manually created `config/server.json` based on the example format with the payload entry.

**Step 4: Run Project Bridge dev server**
- `npm run dev` from project-bridge root — server starts on port 3001.
- Server output shows NO indication that `config/server.json` was found or that any payload was loaded. Silent.
- Health endpoint responds OK. Default client app loads at root.
- **The payload's API prefix (`/api/ashe-austaire`) returns 404.**
- The payload resolver middleware runs but resolves payloads for client-side view routing, not as standalone server routes.

**Step 5: See the payload in a browser**
- **NOT POSSIBLE with current flow.** The payload template provides TypeScript view components (`PayloadView[]`). These are meant to be rendered by the framework's client-side app. But there is no guidance, command, or automation that connects a newly created payload's views to the browser-visible UI.
- The client app (`targets/client`) renders the default project-bridge UI regardless of what payloads are registered.

### Friction (summary)

1. **`create.sh` SSH/HTTPS mismatch** blocks the push step entirely when `gh` uses HTTPS protocol.
2. **`sudo` errors during auto-update** are noisy and confusing in non-interactive or piped contexts.
3. **"workspace not found"** message has no explanation or guidance.
4. **No `config/server.json` by default** — only example files exist. No command or doc creates it for you.
5. **No server-side confirmation of payload loading** — the server silently reads (or ignores) config. No log says "Loaded 1 payload: ashe-austaire."
6. **Payload template is code-only, not runnable** — it gives you TypeScript exports, not a visible page. After following every documented step, you cannot see anything new in a browser.
7. **Missing end-to-end path** — the README says "register in server.json" as the last step, but there's no working connection from payload registration to a visible browser experience. The payload's views are React components but the client app doesn't render them.

### Severity
Steps 1-3 have fixable friction. Steps 4-5 are **architectural gaps** — the new-client onboarding flow does not produce a visible, working result. This blocks any new developer from validating that their setup works.

### Suggestions for Nick
1. Fix `create.sh` to detect `gh` git protocol and use HTTPS when configured.
2. Handle `sudo` failures gracefully in `mtx.sh` updateCheck (warn instead of printing raw errors).
3. Add `mtx create` step that also creates or updates `config/server.json` in project-bridge (or prints explicit instructions for creating it from the example).
4. Add server startup log when `config/server.json` is loaded: "Loaded N payloads: [slugs]."
5. Make the payload template produce a visible "hello world" page — not just TypeScript stubs — so a developer can immediately see their payload in the browser after registration.
6. Document or automate the connection between payload views and the client-side app rendering.

Tags: #onboarding #mtx #project-bridge #create #deploy #first-run #blocker

---

## 2026-04-05 — First `mtx create` run for client Ashe Austaire (Ash developer)

### Context
Ran `mtx create` from project-bridge root to create the first payload for client "Ashe Austaire." Testing the real first-run experience.

### Audience
First-time developer user creating their first payload.

### What went well
- Template cloned correctly from `Meanwhile-Together/template-basic`.
- GitHub repo `Meanwhile-Together/payload-ashe-austaire` was created automatically via `gh`.
- Payload metadata (package.json name, description, README) was rewritten correctly.
- Starter `src/index.ts` exports the interface Project Bridge expects (`getAppViews`, `getViewComponent`, `getAppRoutes`).

### Friction
- **SSH vs HTTPS mismatch:** `create.sh` hardcodes the remote to `git@github.com:...` (SSH) but `gh auth status` shows HTTPS protocol. Push failed with "Repository not found." Had to manually switch remote to HTTPS and push.
- **`sudo` prompts during auto-update:** MTX's `updateCheck` tried to `sudo chmod` and `sudo ln` during the auto-update step, which fails in non-interactive/piped contexts. Output shows `sudo: a terminal is required to read the password`.
- **"workspace not found" message:** Output says "workspace not found, workspace features disabled" with no explanation of what this means or what to do about it.
- **Default payload is code-only, not runnable:** The template gives you TypeScript exports, not a visible app. No guidance on what "register in server.json" actually means in practice. A new developer sees a `NotConfigured` component and empty routes.

### Severity
SSH/HTTPS mismatch blocks the create flow entirely. Other items slow onboarding.

### Suggestions
1. Detect `gh` git protocol setting and use HTTPS when configured (`create.sh` line where `WANT_REMOTE` is set).
2. Handle `sudo` failures gracefully in `updateCheck` / `installWrapper` (skip or warn instead of printing raw sudo errors).
3. Explain or suppress the "workspace not found" message for users without a `.code-workspace` file.
4. Consider a richer default template that produces a visible page, not just TypeScript stubs.

Tags: #onboarding #mtx #create #first-run

---

## 2026-04-05 — Developer experience pain points (validated in chat review)

### Context
Full codebase review of MTX and project-bridge to validate developer mental model and identify friction. Both repos examined.

### Audience
First-time developer user trying to use MTX as the operating surface for Project Bridge.

### Friction

- **Cross-repo onboarding gap:** Neither README links to the other. A developer cloning both repos has no single path that says "you need both, here is what to do first." The relationship between MTX and project-bridge must be inferred from internal docs like `docs/MTX_AND_PROJECT_B.md` (project-bridge) and `docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md` (MTX).
- **Command ambiguity:** `mtx deploy` vs `npm run deploy:staging` vs direct `bash MTX/deploy.sh` vs `./terraform/apply.sh` are all valid entry points for deploy. No single doc says "use this one."
- **Legacy terminology drift:** Banner and help output still reference "NNW" (`mtx.sh` printVersion, help options). The product is MTX but code-level naming has not fully transitioned.
- **Hidden assumptions about repo layout:** `create.sh` defaults workspace root to parent directory (`cd ..`). `scripts/run-mtx-deploy.sh` in project-bridge expects MTX as a sibling at `../MTX`. These assumptions are not documented in primary surfaces.
- **Docs discoverability:** The authoritative "how to use both repos" narrative lives in `docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md` and `docs/INFRA_AND_DEPLOY_REFERENCE.md`, but neither is linked from the README. `docs/getting-started.md` is about writing scripts for MTX, not about using MTX as a product consumer.
- **README examples reference nonexistent paths:** README uses `mtx do update` and `mtx git clean-branches` as examples but no `do/` or `git/` directories exist in the repo.
- **`getting-started.md` references nonexistent paths:** Describes `dev/run-electron.sh` and `mtx dev run-electron` but no `dev/` directory exists.
- **Hard reset on every command run:** Before sourcing a script, `mtx.sh` runs `git reset --hard origin/main` on the installed clone. Local edits are silently wiped.

### Severity
Blocks onboarding for new developers. Slows repeat tasks for returning developers.

### Suggestions
1. Link MTX and project-bridge READMEs to each other.
2. Establish one canonical deploy entry point and document it clearly.
3. Replace NNW references with MTX in user-facing output.
4. Document the sibling-repo layout assumption in both READMEs.
5. Link `MTX_CREATE_AND_DEPLOYMENT_FLOW.md` from the MTX README.
6. Fix or remove README and getting-started examples that reference nonexistent command paths.

Tags: #onboarding #mtx #project-bridge #docs

---

## 2026-04-05 — First-time onboarding (Ash)

### Context
Trying to understand what MTX is and how to use it alongside project-bridge as a first-time user.

### What went well
- README explains the high-level purpose clearly (single-command wrapper, git repo as package source).
- `mtx help` lists available commands with descriptions — clean UX.

### What was confusing or hard
- **Relationship to project-bridge:** The README doesn't mention project-bridge at all. You have to read across multiple docs in both repos to understand they're companions.
- **No single getting-started path:** After cloning both repos, the question is "what do I do now?" There's no walkthrough that says: clone both, cd here, run this, expect that.
- **`docs/getting-started.md`** is useful for writing new MTX scripts but doesn't cover first-time setup as a user of the tool.

### Suggestions
1. Add a quick-start assuming the user has both MTX and project-bridge cloned side by side.
2. Mention project-bridge in the README so the relationship is clear from the start.

---

*Add new entries above this line.*
