# MTX command surface (normative)

This document is the **single contract** for how CLI commands are named. If a script or doc contradicts it, treat this file as authoritative.

## Two shapes

### 1. Create something new → `mtx create <type> …`

Use **`mtx create`** with an explicit **kind** first:

| Kind | Command | Result |
|------|---------|--------|
| Payload app repo | `mtx create payload [display name…]` | New **`payload-*`** from the configured template (default **`template-payload`**). |
| Org product repo (rare) | `mtx create org [display name…]` | New **`org-*`** from the org template (default **`template-org`**). |
| Payload template repo | `mtx create template [name]` | Run **from a payload repo root**; snapshots into **`template-*`**. |

**Do not** rely on alternate spellings such as `mtx payload create` or `mtx template create`. Those entry points were removed so there is only one obvious path for scaffolding.

**Legacy (optional):** `mtx create` with **no** `payload|org|template` keyword still runs the **payload** scaffold for backward compatibility (same as `mtx create payload`), but you should pass **`payload`** explicitly in scripts and docs.

### 2. Act on a domain → `mtx <domain> <action> …`

Non-create operations live under a **domain** directory in the MTX repo (what `mtx help` shows as a group with subcommands).

| Domain | Example | Purpose |
|--------|---------|--------|
| **payload** | `mtx payload install <payload-id>` | Wire an **existing** payload (npm / path / git) into the **current host** and update **`config/server.json`** (or **`server.json`**) **`apps[]`**. |

Other domains (**`deploy`**, **`setup`**, **`project`**, …) follow the same pattern: **`mtx <domain> <script>`**.

### Top-level operator: `mtx clean`

**`mtx clean`** is a **top-level** script (**`clean.sh`** + **`clean/`**), not a domain folder. It removes build artifacts with **smart defaults** (org host vs single payload) and optional scopes **`payload`**, **`org`**, **`all`** (see **`mtx clean --help`**). Subcommands **`mtx clean payload`**, **`mtx clean org`**, **`mtx clean all`** map to **`clean/payload.sh`**, **`clean/org.sh`**, **`clean/all.sh`**.

**`mtx sys clean`** is **deprecated** (still runs the same engine and prints a warning); use **`mtx clean`** in scripts and docs.

### Nested segments under a domain (structural, not accidental)

The wrapper resolves **extra tokens** after a domain into **`domain/<segment>.sh`** when that file exists (and can chain again when both `domain/segment.sh` and `domain/segment/` exist). **Purpose:** keep the top-level **`mtx help`** list small and **group** related operator steps under one **domain** instead of minting new root verbs. Example: **`mtx deploy terraform apply`** uses **`deploy/terraform.sh`** to reach **`deploy/terraform/apply.sh`** — same deploy engine as **`mtx deploy`** after you pick an environment, without a misleading top-level **`mtx terraform`** that reads like a second product CLI. Mechanical detail: [getting-started.md](getting-started.md) §“Where scripts live”.

## What *not* to do

- **No** **`mtx sys clean`** in new scripts or docs — use **`mtx clean`** (**`mtx sys clean`** is deprecated).
- **No** top-level **`mtx install`** for payload registration — use **`mtx payload install`** only.
- **No** **`mtx payload create`** / **`mtx template create`** — use **`mtx create payload`** / **`mtx create template`**.
- **No** top-level **`mtx terraform …`** for MTX’s Railway/Terraform **orchestrator** — that logic lives under **`mtx deploy terraform …`** (see **Nested segments** above). HashiCorp **`terraform`** still runs **inside** the project’s **`$PROJECT_ROOT/terraform/`** when the orchestrator applies infra.

## Related docs

- Scaffolding narrative: [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md)
- Create + deploy flow: [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md)
- Adding new `mtx` scripts: [getting-started.md](getting-started.md)
