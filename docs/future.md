# Future / notes

- **Don’t use cross-env in scripts.** Prefer inline env vars (e.g. `NODE_ENV=development electron "$@"`) on Unix. That avoids a dependency and “command not found” when the project doesn’t have cross-env installed. If Windows support is needed later, handle it explicitly (e.g. a Windows-specific script or a different mechanism).
