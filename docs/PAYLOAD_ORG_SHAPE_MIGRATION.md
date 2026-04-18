# Org-shaped `payload-*` migration (legacy `template-basic` era)

Many **`payload-*`** repos were scaffolded when **`mtx create payload`** defaulted to **`template-basic`**, which is an **org-host** layout: a **full monorepo mirror** under **`payloads/`** (dozens of sibling apps) plus **`prepare:railway`**, **`scripts/org-*.sh`**, **`config/server.json`** pointing at other repos, etc. That is **not** a **payload-shaped** repo.

**Canonical product shape** for a **`payload-*`** app is the same as **`payload-admin`** and **`template-payload`**: **one SPA at the repo root** — `package.json`, Vite (or equivalent), `src/`, **`npm run build` → `dist/`**, **`staticDir: "dist"`** from the host. There is **no** top-level **`payloads/`** in a correct single-app payload.

**Law + context:** [rule-of-law.md](rule-of-law.md) §1 cross-repo bullet **“Org-shaped `payload-*`”**, [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md), [`includes/mtx-predeploy.sh`](../includes/mtx-predeploy.sh) (heuristic only).

---

## 1. Canonical fix (what “right” means)

**Delete everything at the repo root except `.git`, then make the tree equal to the one true app that lived under `payloads/<slug>/`**, where:

- **`payload-<slug>`** is the repo folder name (`payload-breakwatch-ai` → **`slug = breakwatch-ai`**).
- **`payloads/<slug>/`** is the only subdirectory that belongs to **this** product (the Vite/React app for that slug).

After migration, the repo matches **`template-payload`** / **`payload-admin`**: **no** org scripts, **no** bundled copies of other products, **no** `payloads/` directory.

**Mechanical tool in this repo:** [`scripts/hoist-payload-subdir-to-root.sh`](../scripts/hoist-payload-subdir-to-root.sh)

```bash
# Dry-run one repo
./MTX/scripts/hoist-payload-subdir-to-root.sh /path/to/payload-foo

# Apply to one repo (destructive; commit or branch first)
./MTX/scripts/hoist-payload-subdir-to-root.sh /path/to/payload-foo --apply

# Apply to every payload-* under a workspace parent (e.g. …/MT)
./MTX/scripts/hoist-payload-subdir-to-root.sh --all-workspace /path/to/MT --apply
```

Then in **each** repo: **`npm install`** and **`npm run build`** so **`dist/`** exists at the **new** root.

**Inventory (detect only):** [`scripts/inventory-org-shaped-payloads.sh`](../scripts/inventory-org-shaped-payloads.sh)

```bash
./MTX/scripts/inventory-org-shaped-payloads.sh /path/to/MT
```

---

## 2. When this is *not* the right move

| Situation | Prefer |
|-----------|--------|
| You truly want **one Railway deploy** that bundles **many** apps under **`payloads/`** with org **`config/`** | **Reclassify** as **`org-*`** (rename / new repo). Do **not** keep calling it **`payload-*`**. |
| Only one app matters but you **cannot** delete the monorepo yet | Temporary: point **`server.apps`** at **`payloads/<slug>/dist`** with **`base: './'`** — still plan **hoist**; do not treat CDN + root **`index.tsx`** as acceptable long-term. |

---

## 3. Post-hoist checklist (per repo)

1. **`npm install` && `npm run build`** at repo root → **`dist/`**.
2. **Host `server.apps`:** `source.path` to repo (or git), **`staticDir`: `"dist"`** (or equivalent), **`slug`/`id`** match the product.
3. **Remove** any **Tailwind CDN** “not for production” usage if you are shipping production (replace with built CSS like admin).
4. **Railway / CI:** build command is root **`npm run build`** (no org **`prepare:railway`** unless this repo is an org host — after hoist it should not be).

---

## 4. Reclassify as org host (alternative)

If the **intention** is a **multi-app host**, use **`mtx create org`** / **`template-org`** naming and docs — not **`payload-*`**. Checklist: [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md).

---

## See also

- [rule-of-law.md](rule-of-law.md) — facts, failure modes, todos.  
- [MTX_SCAFFOLDING_MODEL.md](MTX_SCAFFOLDING_MODEL.md) — **`template-payload`** vs **`template-org`**.  
- [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md) — deploy roots.
