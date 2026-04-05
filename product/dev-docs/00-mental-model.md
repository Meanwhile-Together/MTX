# Mental Model: MTX + Project Bridge

You are not choosing between MTX and Project Bridge.
You use them together, but for different jobs.

**Project Bridge** is the platform runtime. It is the technology host that serves and coordinates your app experiences.

**MTX** is the developer operating surface. It is how you run the workflows that shape and ship those experiences.

**Payloads** are the actual user-facing app experiences inside that system.

## How they connect

- Project Bridge is where the product lives at runtime.
- MTX is how the developer drives creation, setup, and release behavior.
- Payloads are the distinct apps that end users interact with.

## Example: Health vertical

A client wants a health platform with three experiences:
- **Diet** — nutrition tracking and diet-specific UX.
- **Workout** — training plans and workout tracking UX.
- **Chat** — conversational interface that references data from Diet and Workout.

In this model:
- Project Bridge is the shared host serving all three.
- MTX is how the developer creates, registers, and deploys those payloads.
- Each payload has its own domain responsibility and data ownership.
- Chat reads approved aggregate context from Diet and Workout with explicit permission-based rules.

## Developer workflow progression

1. Translate client intent into payload boundaries.
2. Shape those payloads into one platform model.
3. Validate that model in staging as a cohesive experience.
4. Promote to production when both product behavior and developer operations are reliable.

## Why documentation should be developer-user focused first

The priority order for docs:
1. What decision you are making.
2. Why it matters.
3. What outcome you should expect.

And only after that:
4. Exact command details.
5. Low-level implementation specifics.

This keeps MTX understandable as a practical control surface and Project Bridge understandable as the runtime foundation of the product you are building.

---

See also: [Developer Story Arc](./02-common-flows.md) for the full journey from client brief to production.
