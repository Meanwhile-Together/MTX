# First Day Quickstart

This doc covers what to expect on your first day with MTX and Project Bridge. It stays at the conceptual level — command-level detail will be added as we validate each step together.

## Prerequisites

- Node.js 18+ (20+ recommended for mobile builds).
- npm 8+.
- Git.
- GitHub CLI (`gh`) for payload creation workflows.

## What you need cloned

Both repos, side by side in the same parent directory:

```
workspace/
  MTX/
  project-bridge/
```

This sibling layout matters — MTX scripts expect to find project-bridge as a neighbor.

## First orientation

1. **MTX:** Run `mtx help` to see available commands and their descriptions.
2. **Project Bridge:** Run `npm install` then `npm run dev` from the project-bridge root to start the unified development server.

## What to expect

- MTX is the developer operating surface. You use it to create payloads, deploy, and manage lifecycle workflows.
- Project Bridge is the runtime host. It serves your payload apps from a unified server.
- On first use, `mtx help` is your command map. The README in each repo is your entry point for that repo's purpose.

## What is not obvious yet

- The relationship between the two repos is not stated in either README (tracked as a pain point — see `product/Notes.md`).
- Deploy workflows assume both repos are present and cloned as siblings.
- Some MTX help text still references legacy naming ("NNW").

## Future expansion

Step-by-step command sequences will be added here as each flow is explicitly reviewed and validated.

---

See also: [Mental Model](./00-mental-model.md) | [Common Flows](./02-common-flows.md)
