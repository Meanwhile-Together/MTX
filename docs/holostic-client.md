# Holistic view — client drill-down (plain language)

**Audience:** **clients who own an org** (your company’s “home” on the platform): you may use **AI** (ChatGPT, Cursor, etc.) to help design or build **apps**, without being a full-time engineer. This page gives you **just enough vocabulary and boundaries** so you—and your AI—do not accidentally fight the system.

**Big picture (story, not specs):** [holostic-executive-brief.md](holostic-executive-brief.md). **Technical detail for your partners:** [holostic.md](holostic.md). **Platform builders:** [holostic-developer.md](holostic-developer.md).

---

## The three words that matter most

1. **Org (host)** — Think **building**. It is **your** main project that **owns the front door**: how things are listed, how they connect, and how updates go **live** on the internet. You usually have **one** org per company (or per serious brand).

2. **Payload (app)** — Think **apartment or shop inside the building**. Each one is a **product or experience** (a website, a tool, a customer portal). It can live in **its own folder or its own repository**, but the **org** decides **which** apartments exist and **how visitors reach them**.

3. **Deploy** — Think **“publish.”** It is the controlled path that takes what you built and puts it on **staging** (safe rehearsal) and **production** (real customers). It is supposed to work the **same way** each time, so “it worked on my laptop” is not the whole story.

If you tell an AI only one thing, say: **“We work inside an org host; individual apps are payloads; publishing goes through the org’s deploy path—not random uploads.”**

---

## What “Project Bridge” and “MTX” mean for you (without jargon)

- **Project Bridge** is the **shared engine under the hood**—the parts lots of products reuse so every team does not reinvent the same machinery.

- **MTX** is the **crew chief toolkit**—how technical people **create** new repos the right shape, **hook apps into the org**, and **run the publish pipeline** the same way in automation and by hand.

**You do not need to run MTX yourself** to be a good client—but you should know your technical people (or your AI, under their supervision) are expected to **respect that split**: creative work on the **apps**; org-wide wiring and **go-live** through the **host** and its standard scripts.

---

## How to work **with** an AI (so it helps instead of derailing)

### Give the AI a clear “jurisdiction”

- **“Build or change this one app”** → point it at the **payload** (that app’s repo or folder) and describe user-visible behavior.
- **“Add another app” or “change how apps are reached”** → that is **org** territory; someone with access to the host config needs to be in the loop.

When the AI tries to invent a **second custom server** or a totally different hosting layout “because it is simpler,” you are usually about to create **maintenance pain**. Politely steer it back: **one org playbook, many apps.**

### Words you can safely use with an AI

| Plain term | What it roughly means here |
|------------|----------------------------|
| Org / host | The main project that **runs and publishes** the bundle of apps |
| Payload / app | One **product** or surface users interact with |
| Config list | The **roster** of which apps exist and how traffic finds them (technical name: `server.json`—you do not need to edit raw JSON yourself if someone else owns that) |
| Staging vs production | **Rehearsal** environment vs **real customer** environment |
| Shared engine | Reusable under-the-hood code (**Project Bridge**) so apps stay smaller |

### Questions that are **good** to ask an AI

- “Summarize what this **app** should do for a non-technical stakeholder.”
- “Draft user-visible copy or flows for **this screen**.”
- “Given these requirements, what are **risks** or **edge cases** for users?”
- “Propose tests **in plain language** (what should always be true after a change?).”

### Things to **avoid** asking an AI to do without a technical owner

- “Redesign how our whole company hosts software” (that breaks the **shared playbook**).
- “Merge fifteen unrelated products into one giant file with no boundaries” (that recreates the **god-file** problem the platform avoids).
- “Deploy to production by hand-copying mystery folders” (bypasses the **repeatable publish** path).

---

## What you should expect from your team (or vendor)

- **Clear ownership:** who maintains the **org**, who owns each **payload**, who approves **production** publishes.
- **Same path to the cloud:** staging first when risk is non-trivial; production only after whoever is accountable says yes.
- **Honest role for AI:** great for **speed and drafts** inside known boundaries; not a replacement for **someone** checking that the publish path still passes and that customer data stays safe.

---

## If something goes wrong (intuition, not troubleshooting)

- **“White screen” or “works locally, blank online”** — often a **shape** mismatch (an app built one way but registered another). Your technical contact should compare **how the app is built** vs **how the org lists it**. (There is real law for this in [rule-of-law.md](rule-of-law.md); you can literally forward that link.)

- **“We have ten copies of the same glue code”** — usually a sign people bypassed the **shared engine** idea; fixing it is a **human process** decision, not an AI vibe session.

---

## One paragraph you can paste to a new AI chat

> We use Meanwhile-Together: one **org host** owns publishing and the roster of apps; each customer-facing product is a **payload**. Shared behavior lives in **Project Bridge**; operators use **MTX** for scaffolding and deploy. Please stay inside the **existing repo boundaries**—do not invent a parallel hosting architecture. Prefer small changes with clear scope; call out anything that would change **how apps are registered on the org** or **how deploy works** so a human can review.

---

## Where to send technical partners

- End-to-end system map: [holostic.md](holostic.md)  
- Operators and implementers extending the platform: [holostic-developer.md](holostic-developer.md)  
- Curated facts and sharp edges: [rule-of-law.md](rule-of-law.md)
