# Misalignment: Legacy Fork-Based Flow vs New Payload-as-App Flow

This document lists **code and documentation** that do **not** follow or correctly state the **new flow** (project-bridge = central host, payload = app, new app = new payload). These are either part of the **old legacy system** or are **misaligned** with the current architecture.

**Authoritative current flow:** [MTX_CREATE_AND_DEPLOYMENT_FLOW.md](MTX_CREATE_AND_DEPLOYMENT_FLOW.md) — project-bridge runs and hosts; payloads are apps; creating a new app = create payload + register in `server.apps` (path/package/git); fork path (mtx create) is optional for standalone deployments.

---

## 1. Documentation — Legacy / Misaligned

### 1.1 project-bridge (fully fork-based, no payload-as-app)

| File | Issue | What it says (legacy) |
|------|--------|------------------------|
| **docs/MASTER_FLOW_AND_MTX_CREATE_PLAN.md** | Entire doc is the **old** authoritative plan. | Goal: MTX create = central entry; master flow = **forking project-bridge**; every new app is a **fork**; "Create is the single entry point for 'new app'"; "all 'new app' flows go through mtx create"; "Creating a new app = forking project-bridge and rebranding it." No mention of payload = app or central host. |
| **docs/OUTSTANDING_WORK.md** | Opening and Section 3 frame create as the only path. | "Master flow = fork: New app = **fork of project-bridge** … **MTX create** is the central entry point." Section 3 title: "MTX create (central entry: fork under logged-in user)"; tasks 3.1–3.4 and 8.4 assume "new app" = fork; 8.4: "run mtx create … then compile/deploy from the **created (forked) repo**." |
| **docs/PLATFORM_EXPLORATION_MASTER.md** | Describes platform as fork-only. | "MASTER_FLOW_AND_MTX_CREATE_PLAN.md — Authoritative plan: master flow = **fork** project-bridge; MTX create = central entry." Table: "MTX create is the **central entry point** … creates the new app as a **fork of project-bridge**"; "Every new app is a **fork** of project-bridge"; "create app | MTX create: clone project-bridge, rebrand, fork/create repo." |
| **docs/PLATFORM_MASTER_DIAGRAM.md** | Diagram and narrative are fork-only. | "Master flow: … New app = **fork** of project-bridge … **MTX create** is the central entry point." Section 4: "MTX create — central entry (fork under logged-in user)" with flowchart: clone → rebrand → fork → push. Diagram "Intended" shows "project-bridge **fork** terraform." Footer: "fork project-bridge, MTX create central." |
| **docs/MTX_AND_PROJECT_B.md** | No misstatement of create, but doesn’t mention payload-as-app. | Describes MTX vs project-bridge and script patterns; does not state that new app = payload or that project-bridge is the central host. Could add one paragraph aligning with MTX_CREATE_AND_DEPLOYMENT_FLOW. |

### 1.2 MTX

| File | Issue | What it says (legacy / missing) |
|------|--------|----------------------------------|
| **docs/INFRA_AND_DEPLOY_REFERENCE.md** | Doesn’t define "new app" or central host. | Describes deploy/infra and links to MTX_CREATE_AND_DEPLOYMENT_FLOW; does not explicitly state payload = app or that project-bridge is the central host. Optional: add one line in §1 or "Related" that the canonical create/new-app narrative is MTX_CREATE_AND_DEPLOYMENT_FLOW (payload = app, fork optional). |
| **docs/getting-started.md** | Not checked in this audit; may say "mtx create" as first step. | If it says "run mtx create" as the only way to get an app, align with "new app = payload (or optionally mtx create for standalone)." |

### 1.3 cicd

| File | Issue | What it says (legacy) |
|------|--------|------------------------|
| **DEPRECATED.md** | Points to old plan as "current architecture." | "See MTX docs (e.g. `docs/PLATFORM_EXPLORATION_MASTER.md`, `docs/MASTER_FLOW_AND_MTX_CREATE_PLAN.md`) for the **current** architecture." Those docs are fork-based; current flow is in MTX `docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md`. |

---

## 2. Cursor / Agent Rules — Misaligned

These rules tell agents to follow the **fork-based** narrative.

| File | Issue | What it says (legacy) |
|------|--------|------------------------|
| **project-bridge/.cursor/rules/README.md** | Lists old plan as "Master flow." | "Master flow: project-bridge `docs/MASTER_FLOW_AND_MTX_CREATE_PLAN.md`, `docs/OUTSTANDING_WORK.md`, `docs/PLATFORM_MASTER_DIAGRAM.md`." No mention of MTX_CREATE_AND_DEPLOYMENT_FLOW or payload = app. |
| **project-bridge/.cursor/rules/framework-phase-polishing.mdc** | Requires alignment with fork narrative. | "MASTER_FLOW_AND_MTX_CREATE_PLAN.md — Platform narrative (fork, MTX create, cicd deprecated)." "Align with platform narrative: **Master flow = fork project-bridge**; MTX create = central entry; fork under logged-in user; cicd deprecated." Checklist: "Wording aligns with MASTER_FLOW_AND_MTX_CREATE_PLAN." |
| **project-bridge/.cursor/rules/framework-phase-bug-fixing.mdc** | References old plan as "intended create flow." | "MASTER_FLOW_AND_MTX_CREATE_PLAN.md — Intended create flow." "Use platform docs: … MASTER_FLOW_AND_MTX_CREATE_PLAN.md (intended create flow)." |
| **project-bridge/.cursor/rules/framework-phase-development.mdc** | References old docs as primary. | "Reference docs: **MASTER_FLOW_AND_MTX_CREATE_PLAN.md**, OUTSTANDING_WORK.md, PLATFORM_MASTER_DIAGRAM.md, MTX docs." No reference to payload = app or MTX_CREATE_AND_DEPLOYMENT_FLOW. |
| **project-bridge/.cursor/rules/framework-doctrine.mdc** | Doesn’t list create/new-app flow. | Required reading: FRAMEWORK_DOCTRINE, DEPLOYMENT, MTX_AND_PROJECT_B, INFRA_AND_DEPLOY_REFERENCE. Does not list MTX_CREATE_AND_DEPLOYMENT_FLOW or payload-as-app; adding it would align agents with the new flow. |

---

## 3. Code — Comments / UX Only (Behavior Is Optional Path)

These describe the **fork** path only in comments or user-facing strings. The **behavior** of create.sh is still valid as the **optional** standalone (fork) path; the misalignment is that nothing in code states that "new app" is primarily a payload.

| File | Issue | What it says |
|------|--------|--------------|
| **MTX/create.sh** | Comments describe fork as the only model. | Line 2: "Create new app: clone project-bridge from GitHub, rebrand, create repo …" Comments: "Keep .git so the new repo can be a **real fork** (same history as project-bridge)"; "Create the GitHub repo as a **fork of project-bridge** if it doesn't exist"; "Creating fork …"; "Ensure remote origin points to the **fork**"; "Push (fork already exists at this point)." No comment that this is the **optional** (standalone) path and that the primary "new app" is a payload. |
| **MTX/reconfigure.sh** | Uses "fork" in a different sense (user’s fork of MTX). | "For your own fork only"; "YOUR OWN version (fork) of …" — refers to MTX wrapper fork, not project-bridge fork. **No change needed** for payload-as-app; leave as-is. |

**Recommendation:** Add a short comment at the top of **create.sh** (after the desc line): e.g. "Optional path for a full standalone host. Primary 'new app' flow is create a payload and add to config/server.json (see docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md)."

---

## 4. Summary: What to Update

| Category | Action |
|----------|--------|
| **project-bridge docs** | Add a deprecation/context note to **MASTER_FLOW_AND_MTX_CREATE_PLAN.md** (e.g. "Legacy plan; see MTX docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md for current flow: payload = app, fork optional."). Update **OUTSTANDING_WORK.md** §1 and §3 to allow "new app = payload" and treat mtx create as optional path; adjust 8.4. Update **PLATFORM_EXPLORATION_MASTER.md** and **PLATFORM_MASTER_DIAGRAM.md** to state payload = app, central host, and mtx create as optional for standalone. |
| **Cursor rules** | Point framework-phase-* and README to **MTX_CREATE_AND_DEPLOYMENT_FLOW.md** as the create/new-app narrative; add payload = app and "fork optional" to polishing/bug-fixing/development rules. Add **MTX_CREATE_AND_DEPLOYMENT_FLOW.md** to framework-doctrine required/related reading. |
| **cicd DEPRECATED.md** | Change "current architecture" link to MTX `docs/MTX_CREATE_AND_DEPLOYMENT_FLOW.md` (and optionally keep MASTER_FLOW as legacy reference). |
| **MTX create.sh** | Add one-line comment that this is the optional (standalone) path; primary new app = payload (see MTX_CREATE_AND_DEPLOYMENT_FLOW.md). |
| **MTX INFRA_AND_DEPLOY / getting-started** | Optionally add one sentence that canonical create/new-app flow is in MTX_CREATE_AND_DEPLOYMENT_FLOW (payload = app, fork optional). |

---

## 5. Quick Reference: New vs Legacy

| Concept | Legacy (misaligned docs/code) | New (MTX_CREATE_AND_DEPLOYMENT_FLOW.md) |
|--------|--------------------------------|----------------------------------------|
| New app | Fork of project-bridge (clone, rebrand, new repo). | **Primary:** New payload + entry in `server.apps` (path/package/git). **Optional:** Fork via mtx create for standalone host. |
| project-bridge | "The framework" = repo you fork to get an app. | **Central host** = runs and hosts; points to many payloads via `config/server.json`. |
| mtx create | Central entry for "new app"; produces fork. | **Optional** path for full standalone deployment; "new app" is mainly new payload + config. |
| Single entry for "new app" | All flows through mtx create. | New app = create payload + register on host; mtx create only for standalone. |

This file is the single place to track misalignments until the listed docs and rules are updated to match the new flow.
