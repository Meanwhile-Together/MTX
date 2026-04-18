# Rule of law (MTX)

Single curated ledger for **facts**, **constraints**, **failure modes**, **intentional deprecations**, **horizon**, and **debt**. It complements normative specs (for example [MTX_COMMAND_SURFACE.md](MTX_COMMAND_SURFACE.md)); it does **not** replace git history.

**How to add:** use the Cursor skill **`rol`** (slash **`/rol`**) or ask the agent to append here and re-sort. The skill lives in **`~/.cursor/skills/rol/`** (personal) so it works in **multi-root workspaces** where **`MTX/.cursor/skills/`** is not on Cursor’s skill path. One idea per bullet unless a tight table is clearer.

---

## 1. Facts (what is true today)

| Topic | Law |
|--------|-----|
| CLI contract | **`mtx create <payload \| org \| template>`** scaffolds repos; **non-create** host actions live under **`mtx <domain> <action>`** (e.g. **`mtx payload install`**). Spec: [MTX_COMMAND_SURFACE.md](MTX_COMMAND_SURFACE.md). |
| Create templates (distinct defaults) | **`mtx create payload`** clones **`MTX_PAYLOAD_TEMPLATE_REPO`** (default **`template-payload`**) — **single-app** SPA at repo root (`npm run build` → **`dist/`**), not an org host tree. **`mtx create org`** clones **`MTX_ORG_TEMPLATE_REPO`** (default **`template-org`**) — **org host** layout (`payloads/`, **`prepare:railway`**, org scripts, project-bridge-shaped **`config/`**). Full narrative: [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md). |
| **`template-basic`** | **Legacy** name for the **old unified** starter (org-shaped). It must **not** remain the mental model for “the one template”; **remove** it from the product once **`template-org`** is published and callers migrate (repo rename or new repo, docs, workspace lists). Until removal, **`MTX_ORG_TEMPLATE_REPO=template-basic`** or a local sibling symlink **`template-org` → `template-basic`** is an acceptable bridge — **not** a reason to point **`mtx create payload`** at **`template-basic`**. |
| Payload install code | Implementation lives in **`lib/install-payload.sh`** (`mtx_install_payload_main`). **`payload/install.sh`** is the only supported `mtx` entry for host wiring. |
| Legacy create | **`mtx create`** with **no** kind still runs the **payload** scaffold; prefer **`mtx create payload`** in scripts and docs. |
| Help source | **`mtx help`** reflects the **installed** clone (`$scriptDir`), not necessarily the working copy you are editing. |
| **`mtx` git-synced wrapper** | The **distributed** `mtx` install is a **self-updating** checkout from **git**; **canonical** behavior is whatever **`origin/main`** contains **after** it is **committed and pushed**. Operators should **push MTX `main`**, let the wrapper **pull/sync**, then run **`mtx`** — not treat an **unpushed** editor-only tree as “what `mtx` is” unless the install explicitly tracks that path. |
| **`mtx` change velocity** | **Routine** work (**moving** command files, **`desc=`** / help text, nested layout under **`$MTX_ROOT`**) is **normal repo commits**; it does **not** require a separate “bump the wrapper artifact” step beyond what the **git-linked** install already pulls. |
| **`MTX_ROOT` (env / variable)** | **Fundamentally not desired** as durable architecture: it **exports “where is the repo?”** into child shells instead of **one** wrapper that resolves its **own install path** and re-invokes with **`$0`**. **Today** many scripts **`source "$MTX_ROOT/…"`** — **accidental**, **tech debt**, to **eliminate eventually** (**§6–§7**); do **not** treat it as something new features should entrench. |
| Nested CLI shape | **`mtx <domain> <segment> …`** maps to scripts under **`$MTX_ROOT/<domain>/`** today (see “Nested segments under a domain” in [MTX_COMMAND_SURFACE.md](MTX_COMMAND_SURFACE.md)). **Purpose:** bound top-level verbs, group related operator steps, avoid name collisions (e.g. “terraform” as MTX vs HashiCorp). **Horizon:** same **nesting contract**, but paths resolved from the **wrapper install dir** without an operator-visible **`MTX_ROOT`** — **§6**. |
| Pre-deploy hook point | For org repos that use **`npm run prepare:railway`** (detection: **`scripts/prepare-railway-artifact.sh`** + **`scripts/generate-railway-deploy-manifest.sh`** exist), **`MTX/build.sh`** runs **`mtx_predeploy_after_payload_assembly`** immediately **after** `prepare:railway` and **before** the unified server build. Source: [`includes/mtx-predeploy.sh`](../includes/mtx-predeploy.sh). |
| Org stub | Optional **`scripts/org-pre-deploy.sh`** at the **org project root**; invoked first when present; **non-zero exit fails the build**. The **`template-org`** scaffold ships a **silent no-op** stub at the same path (`exit 0`) for clones to replace (legacy trees copied from **`template-basic`** kept the same path). |
| Payload normalization (automatic) | **Bash + sed + mktemp** (portable: Linux / macOS / WSL): under each **`payloads/*/`**, rewrite root-absolute **`src`/`href`** in **`index.html`**, **`dist/index.html`**, **`targets/client/dist/index.html`** where present; coerce **`base: '/'` → `base: './'`** in common **`vite.config.*`** names. Also touches org **`targets/client/dist/index.html`** if it exists. **Not** a substitute for correct **`base`** at author time; catches common path-prefix / MIME failure class after assembly. |

**Cross-repo (org host + project-bridge framework)** — narrative law; applies to MTX docs and project-bridge contributor docs:

- **Deployable host is always an org host:** the **first-class deploy root** is an **`org-*`** repo (**`mtx create org`** / **`template-org`**: `config/`, `payloads/`, **`prepare:railway`**, **`mtx deploy`**). That repo **vendors or references** unified-server / Terraform patterns from **project-bridge**; it is **not** “fork project-bridge and treat that fork as your product host.”
- **`project-bridge`** is the **framework monorepo** (packages, reference **`terraform/`**, CI patterns, demo). **Horizon:** it **stops being a standalone operator deploy target** (“clone bridge → `mtx deploy` from bridge alone”); docs and comments must **not** idealize that path as normal or eventual — converge on **org host** only. [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md), [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md), project-bridge [CURRENT_ARCHITECTURE.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/CURRENT_ARCHITECTURE.md).
- **`mtx create`** scaffolds **payload-** / **org-** / **template-*** from template repos; it does **not** clone **project-bridge** as a host ([MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md)).
- **`deploy/asadmin.sh`** (`mtx deploy asadmin`): **`RUN_AS_MASTER`** / **`MASTER_JWT_SECRET`** belong on the **Railway backend** service (admin lane), not the unified **app** service — [SERVICE_LANE_SEPARATION.md](SERVICE_LANE_SEPARATION.md), [MTX_DEPLOY_CONTRACT.md](MTX_DEPLOY_CONTRACT.md).
- **2026-04-18 —** Server-only config in the monorepo: **`@meanwhile-together/shared/server`** is canonical (`getConfig` / `loadConfig`); **`@meanwhile-together/shared/server-config`** is a **deprecated** re-export. **Engine** code that must run in Node but sit in modules parsed for web bundles uses **dynamic `require` / `import()`** of that server entry so client bundles do not pull Node filesystem loaders — see **project-bridge** [`engine/src/bridge/factory.ts`](https://github.com/Meanwhile-Together/project-bridge/blob/main/engine/src/bridge/factory.ts) and [FRAMEWORK_DOCTRINE.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/rulebooks/FRAMEWORK_DOCTRINE.md).
- **2026-04-18 — Org-shaped `payload-*` (mis-scaffolded from `template-basic`):** many **`payload-*`** repos are **org-host trees** (`payloads/`, **`prepare:railway`**, unified-server wiring) but carry a **`payload-*`** name — **wrong product class** for “one customer app.” **Workspace scan (MT parent):** **25** such repos (e.g. **`payload-aigotchi`**, **`payload-breakwatch-ai`**, **`payload-gemini-pricing-master`**, … — all with top-level **`payloads/`**). **Failure class:** static root picks **`index.html`/`index.tsx`** without a root **`dist`**, **`text/html` vs `application/octet-stream`**, white screen on Railway. **Remediation is repo work, not MTX magic:** per repo choose **(A)** **flatten** to **single-app** (**`template-payload`** shape: Vite at root, **`staticDir: dist`**) by hoisting `payloads/<slug>/` → root, or **(B)** **reclassify** as an **`org-*`** host (rename / new repo, **`server.apps`** as org) if the tree truly is a **bundle host**. See [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md), **`includes/mtx-predeploy.sh`**, project-bridge static resolution.

---

## 2. Implications (if … then …)

- If **`mtx create payload`** clones an **org-shaped** tree (legacy **`template-basic`** / wrong **`MTX_PAYLOAD_TEMPLATE_REPO`**), new **`payload-*`** repos look like **hosts** (`payloads/*`, server prep) instead of **single-app** payloads → wrong deploy and static/MIME failure class → keep default **`template-payload`** and override **`MTX_PAYLOAD_TEMPLATE_REPO`** only deliberately ([MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md)).
- If docs or scripts still say **`mtx install`**, **`mtx payload create`**, or **`mtx template create`**, operators will hit **missing commands** or wrong mental models → **update the doc**, not the operator.
- If a new `mtx` verb is both **scaffolding** and **runtime**, split it: **create** stays under **`mtx create …`**; **mutations on a host** stay under a **domain** (`deploy`, `payload`, …).
- If a new operator concern is added as a **top-level** `mtx <word>` instead of **`mtx <domain> <sub>…`**, **`mtx help`** grows and users conflate **MTX domains** with **app/tool names** (Terraform, Railway, npm) → **nest under the right domain**; normative layout: [MTX_COMMAND_SURFACE.md](MTX_COMMAND_SURFACE.md).
- If the org **does not** use the **`prepare:railway`** pair of scripts, **`mtx build`** follows the plain **`build:server`** path — **no** automatic **`mtx_predeploy`** run (normalization is tied to that bundle contract, not every repo).
- If docs or README examples imply **`mtx create`** forks **project-bridge**, invent **`mtx do …`** categories, or describe a **“standalone project-bridge fork”** as the host, operators get the wrong repo shape or a deprecated deploy story → align with [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md), [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md), and [MTX_COMMAND_SURFACE.md](MTX_COMMAND_SURFACE.md).
- If **`MTX`** changes are **not** on **`origin/main`** (or the **installed** wrapper has **not** synced), **`PATH` `mtx`** can run **older defaults** (e.g. **`template-basic`**) while the **working tree** already shows **`template-payload`** — **commit, push, then run `mtx`** (or run **`bash MTX/create/…`** only as a **dev** escape hatch, knowing it is **not** the supported operator surface).
- If a **`payload-*`** repo is **org-shaped** (`payloads/` at root) but **`server.json`** treats it like a **single static SPA** at repo root, the host may serve **source** or wrong **`Content-Type`** → **white page / MIME errors** — fix **repo shape** or **config** (`staticDir`, nested **`path`**) per [§1 cross-repo](#1-facts-what-is-true-today) **org-shaped `payload-*`** bullet; **`mtx_predeploy`** is a **safety net**, not a substitute for correct layout.

---

## 3. Limitations and necessities

- **Node + npm** are required for **`mtx payload install`** (config merge uses Node).
- **Project root** for install is inferred from **`package.json`** plus **`config/`** / **`config/app.json`** / **`server.json`**, or **`org-*`** / scoped package name conventions — brittle layouts will fail detection by design.
- **`gh`** (or explicit skip flags) is a practical necessity for **`mtx create …`** flows that push to GitHub; document env overrides in scaffolding docs, not by duplicating them here unless they are invariant.
- **Pre-deploy normalization is heuristic** (regex on HTML / Vite config); odd templates or intentional absolute URLs may need **author-side** fixes — extend [`includes/mtx-predeploy.sh`](../includes/mtx-predeploy.sh) deliberately, not ad-hoc sed in org scripts.
- **Today’s implementation** still **`export`s / `source`s** paths via **`MTX_ROOT`** — **undesired** long-term (**§1** **`MTX_ROOT` row**, **§6–§7**). **Operators** should still use **`mtx …` only**; **contributors** should not add new **`MTX_ROOT`-shaped** “public” contracts (docs, CI, skills) beyond what exists until the **refactor** lands. Direct **`bash …/lib/…`** is **brittle** and **bypasses** wrapper **sync** and **cwd** semantics.

---

## 4. Failure modes (things that break)

- Running **`mtx`** flows **without** the wrapper’s includes can leave **`warn`/`echoc`** undefined in some scripts; entrypoints should define minimal fallbacks when intended for direct execution.
- **`mtx help`** and installed scripts can disagree with the repo on disk until **install/update** — confusion is a support cost, not “user error.”
- **`PATH` `mtx`** on a machine can track **`origin/main`** while your **local MTX clone** is **ahead** or on another branch → **symptoms** look like “wrong template / missing command” even though **your** tree is correct — resolve by **push + sync** or by aligning branch/remotes, not by blaming the framework first.
- **Org-shaped `payload-*`:** host points at repo root, **no** usable root **`dist/`**, nested client under **`payloads/<slug>/`** only — **symptoms** match **aigotchi**-class bugs (**`index.tsx`** as **`octet-stream`**, Tailwind CDN-only, blank UI). **Diagnosis:** compare repo to **`template-payload`** vs **`template-org`**; **fix** layout or **org** classification, not random one-off sed unless extending **`mtx_predeploy`** deliberately.
- **`scripts/org-pre-deploy.sh` exits non-zero** → **`mtx build`** fails after **`prepare:railway`** — treat the hook as **gated CI**, not a silent logger.

---

## 5. Intentional breakage (things that must not come back)

- **No** top-level **`mtx install`** for payload registration — removed in favor of **`mtx payload install`** only.
- **No** **`mtx payload create`** or **`mtx template create`** — removed; use **`mtx create payload`** / **`mtx create template`** only.
- **No** **`MTX/terraform/`** tree for **deploy orchestration** (`apply.sh` / `destroy.sh` / helpers) — those live under **`MTX/deploy/terraform/`**; do not reintroduce top-level **`mtx terraform …`** as a parallel product CLI to **`mtx deploy`**. (Project **`.tf`** trees under **`$PROJECT_ROOT/terraform/`** are unchanged.) Contract: [MTX_COMMAND_SURFACE.md](MTX_COMMAND_SURFACE.md).
- **No** reintroducing a **single** default template name for **both** **`mtx create org`** and **`mtx create payload`** — the split (**`template-org`** vs **`template-payload`**) is intentional; do not collapse back to one “basic” default for both flows.
- **No** resurrecting operator prose that says **“fork / clone project-bridge for a full host”** or **standalone project-bridge deploy** as the canonical or desirable model — **host = org host** (`org-*`); see §1 cross-repo bullets.

---

## 6. Forthcomings and future reference

- **2026-04-18 —** **`mtx` dispatch model (includes killing `MTX_ROOT`):** converge on a **single self-contained** wrapper entry that **re-invokes** the **install-directory** script via **`$0`** (or equivalent) with **`"$@"`**, preserving the **original working directory**. **Remove** the pattern where child scripts **require** an **`MTX_ROOT`** export to find **`lib/`**, **`create/`**, **`includes/`** — those paths should be derived **inside** the wrapper (or a single internal helper) from **the install path**, not from the operator’s environment. **No** operator-facing **`export MTX_ROOT`**, **`source lib/…`**, or **`bash …/create/…`** “because it’s faster.” Until then, **`MTX_ROOT`** is **tech debt**, not design intent.
- **2026-04-18 —** **Retire `template-basic`:** publish or rename the GitHub starter to **`template-org`**, migrate any remaining docs/CI/workspace assumptions, then **remove** **`template-basic`** from normative lists (for example **`includes/workspace-repos.sh`**) and from operator playbooks so only **`template-org`** / **`template-payload`** remain as named defaults.
- **Horizon — project-bridge deploy:** remove remaining **“deploy from project-bridge repo root as the product”** assumptions in docs and comments; **project-bridge** remains the **framework** source; **only org hosts** are first-class deploy roots (**soon**; track in project-bridge [CURRENT_ARCHITECTURE.md](https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/CURRENT_ARCHITECTURE.md)).

---

## 7. Todos and tech debt (actionable)

- **Org-shaped `payload-*` migration:** canonical fix is **payload-shaped root** (same as **`payload-admin`** / **`template-payload`**): hoist **`payloads/<slug>/`** to repo root and **delete** org bundle / other **`payloads/*`** — tool: [`scripts/hoist-payload-subdir-to-root.sh`](../scripts/hoist-payload-subdir-to-root.sh), doc: [PAYLOAD_ORG_SHAPE_MIGRATION.md](PAYLOAD_ORG_SHAPE_MIGRATION.md); inventory: [`scripts/inventory-org-shaped-payloads.sh`](../scripts/inventory-org-shaped-payloads.sh).
- **Inventory automation:** script or CI job that flags **`payload-*`** repos whose **root** has **`payloads/`** + org scripts (`prepare-railway-artifact.sh`, etc.) so new mis-scaffolds cannot silently accumulate (**GitHub** + local org mirrors).
- **Pilot then batch:** migrate **`payload-aigotchi`** first (document failure mode + fix); apply the same playbook to the **remaining ~24** org-shaped **`payload-*`** trees, **prioritizing** anything on **Railway** / in **`org-nack-ai`** / customer-visible.
- **`MTX_ROOT` elimination:** grep the **MTX** repo for **`MTX_ROOT`**, **`MTX_ROOT:`**, and **`source` … `MTX_ROOT`**; refactor toward **install-path-relative** dispatch (**`$0`**, `BASH_SOURCE`, one internal “repo root” resolver) so **operators never export** a root; update **docs/skills/CI** that teach **`MTX_ROOT=…`** as anything other than a **temporary** contributor workaround. **Goal:** **`MTX_ROOT`** disappears from the **public** contract entirely (**§1**, **§6**).
- Audit **external** repos and playbooks for removed commands (`mtx install`, `mtx payload create`, `MTX/install.sh`) and update pointers to **`mtx payload install`** / **`lib/install-payload.sh`**.
- **template-basic removal:** grep org-wide for **`template-basic`** / “default template” wording; switch to **`template-org`** (org) or **`template-payload`** (app); archive or delete the legacy repo when nothing depends on the old name.
- Promote **“commit + push MTX `main`, then run `mtx`”** (and how the **git-synced** install behaves) into [getting-started.md](getting-started.md) or install docs if not already explicit enough for new contributors.
- Consider documenting **`mtx.sh`** “always reset to `origin/main` before run” behavior in a normative doc if it remains true — it surprises contributors.

---

## 8. Things to remember (operator gotchas)

- **2026-04-18 —** **aigotchi / org-nack-ai batch (named):** **`payload-aigotchi`** showed **nested** **`payloads/.../payloads/mt-platform/`**; **org-nack-ai** and the workspace mirrored **~25** **`payload-*`** repos that are **org-shaped** at root — **white UI / MIME / wrong static root** until each tree is **flattened** to **`template-payload`** shape or **reclassified** as **`org-*`**. Registry: [MISALIGNMENT.md — Org-shaped payloads: aigotchi and org-nack-ai batch](MISALIGNMENT.md#org-shaped-payloads-aigotchi-and-org-nack-ai-batch); playbook: [PAYLOAD_ORG_SHAPE_MIGRATION.md](PAYLOAD_ORG_SHAPE_MIGRATION.md); scan: [`scripts/inventory-org-shaped-payloads.sh`](../scripts/inventory-org-shaped-payloads.sh).
- **2026-04-18 —** **Canonical `mtx` loop:** land changes on **Meanwhile-Together/MTX `main`** (**commit + push**), then run **`mtx`** so the **auto-updating** install matches; do not assume **`PATH` `mtx`** reads your **unpushed** working copy.
- Until **`template-org`** exists beside MTX (or on GitHub), **`ln -sf template-basic template-org`** next to MTX or **`MTX_ORG_TEMPLATE_REPO=template-basic`** — **`template-basic`** is **legacy**, not the long-term name ([MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md)).
- After changing MTX scripts locally, **`mtx help`** may still show the old menu until the **installed** MTX clone is updated.
- **`docs/rule-of-law.md`** is for **judgments and constraints**; procedural “how to add a script” stays in [getting-started.md](getting-started.md).
- **`mtx deploy terraform apply`** is the **same** apply engine as **`mtx deploy`** after environment selection — the nested form is for **discoverability and grouping**, not a second deploy pipeline ([MTX_DEPLOY_CONTRACT.md](MTX_DEPLOY_CONTRACT.md), [MTX_COMMAND_SURFACE.md](MTX_COMMAND_SURFACE.md)).
- **Pre-deploy** runs only on the **org Railway bundle** path (**`prepare:railway`**); it is **not** run by **`mtx deploy`** alone unless the deploy path invoked **`mtx build`** that hit **`prepare:railway`**. Ship org hooks in **`scripts/org-pre-deploy.sh`** when you need org-specific steps **after** payload assembly.
- **Deploy root:** run **`mtx deploy`** from an **`org-*`** host unless you are in an explicit **migration** window; do not document **“clone project-bridge alone as production”** as normal or eventual ([§1](#1-facts-what-is-true-today), [§6](#6-forthcomings-and-future-reference)).
- **2026-04-18 —** MTX Terraform **orchestration** docs and **`FLOW.md`** live under **`deploy/terraform/`** in this repo (not a resurrected top-level **`MTX/terraform/`** CLI tree — see §5). **`INFRA_AND_DEPLOY_REFERENCE.md`** §10 links **`deploy/terraform/FLOW.md`** and ADR **`ADR-001-single-app-hardening-then-multi-host.md`**.

---

## Curator notes (meta)

- **Prefer delete** over strikethrough when an item is obsolete; the file should stay scannable.
- **Promote** a bullet to [MTX_COMMAND_SURFACE.md](MTX_COMMAND_SURFACE.md) when it becomes a hard contract, not a team memory.
- Re-read **§5** before reintroducing a removed CLI path “for convenience.”
