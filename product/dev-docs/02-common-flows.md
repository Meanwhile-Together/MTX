# Common Flows: Developer Story Arc

This document captures the full developer journey from client brief to production-ready multi-app platform. It uses a health vertical example (Diet, Workout, Chat) to ground each stage.

---

## Journey 01 — Brief to Platform Shape

1. **Start with the client outcome.** Three experiences in the health vertical: Diet app, Workout app, and Chat companion.
2. **Translate to architecture.** Project Bridge as host platform. MTX as developer operating surface. Product scope is three payload apps: Diet, Workout, Chat.
3. **Define boundaries first.** Diet payload owns nutrition tracking and diet-specific UX. Workout payload owns training plans and workout tracking UX. Chat payload owns conversational interface and cross-app guidance.
4. **Define shared platform responsibilities.** One host runtime serves multiple payloads. Shared auth/session model across payloads. Shared deployment path for staging/production.
5. **Plan data relationship at concept level.** Each payload keeps domain-specific data ownership. Chat reads approved aggregate context from Diet and Workout. Cross-app data access rules are explicit and permission-based.
6. **Developer execution framing.** Use MTX to create/operate payload workflows. Register all payloads in Project Bridge host configuration. Deploy and validate the full multi-app experience as one platform.
7. **Validation outcome expected.** Three distinct app experiences. Cohesive shared identity and navigation feel. Chat can reason across the two domain apps.
8. **DX feedback loop.** Capture confusion, ambiguity, and onboarding pain points at each stage. Feed improvements into product notes and future docs.

---

## Journey 02 — Platform Shape to First Staging Release

1. **Define staging-ready as cohesive and testable, not fully complete.** All three payloads are reachable and usable in one environment.
2. **Set minimum viable cross-app behavior.** Diet and Workout each have clear core flows. Chat can reference both domains at a basic but trustworthy level. Shared identity/session behavior feels consistent.
3. **Lock release boundaries.** Separate "must-have for first staging" from "post-staging enhancements." Keep scope tight to validate architecture and developer workflow first.
4. **Confirm host integration expectations.** Project Bridge presents all three payloads as one coherent product surface. Routing and app boundaries are understandable to both developers and testers. Cross-app data access is intentionally constrained.
5. **Prepare operational readiness.** Team knows what gets validated in staging. Ownership is clear: payload-level issues vs host/platform-level issues. Roll-forward strategy is preferred for early iterations.
6. **Execute first staging release.** Deploy the host + payload set into staging as a single platform release moment. Treat this as a workflow rehearsal as much as a product test.
7. **Validate with two lenses.** Client lens: "Does this feel like one health product with three experiences?" Developer lens: "Is operating this multi-payload system understandable and repeatable?"
8. **Record learnings.** Capture confusion points in onboarding, naming, boundaries, and release flow. Convert recurring friction into explicit documentation improvements.

---

## Journey 03 — Staging Feedback to Production Readiness

1. **Turn staging into a decision point.** Confirm the three-payload model works as one product experience. Decide if the platform is ready to scale confidence, not just ship code.
2. **Classify feedback by layer.** Payload-level feedback (Diet, Workout, Chat UX/content). Platform-level feedback (shared identity, routing, cohesion). Developer-experience feedback (clarity of setup, operations, release workflow).
3. **Prioritize production blockers.** Fix issues that break trust, continuity, or data interpretation first. Defer non-critical polish until after production baseline is stable.
4. **Stabilize cross-app intelligence.** Ensure Chat responses are consistent with Diet and Workout data boundaries. Make cross-app context rules explicit and predictable for users.
5. **Confirm operational confidence.** Team can repeat release flow without ambiguity. Ownership and escalation paths are clear when issues appear. Monitoring/verification expectations are understood before launch.
6. **Define production readiness criteria.** Cohesive user journey across all three payloads. Acceptable reliability and supportability for first real users. Documentation sufficient for the developer team to operate confidently.
7. **Execute production as a controlled transition.** Treat production as a managed expansion of proven staging behavior. Preserve a short feedback loop immediately after launch.
8. **Close the loop into docs and notes.** Promote validated staging lessons into core developer docs. Keep unresolved confusion in product notes until converted into clear guidance.

---

## Core model to keep consistent

- **Project Bridge**: host/runtime technology.
- **MTX**: developer orchestration surface.
- **Payloads**: product experiences (Diet, Workout, Chat) delivered as one cohesive platform.

---

See also: [Mental Model](./00-mental-model.md) | [First Day Quickstart](./01-first-day-quickstart.md) | [Command Map](./03-command-map.md)
