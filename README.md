# MTX

A single-command wrapper that uses a git repository as a package source: install once, then run any script in the repo by name from anywhere. No copying files or hunting for that script you left on a VPS—everything stays in the repo and stays up to date. This is the evolved version of the idea behind Nice Network Wrapper; you get one binary, one repo, and a straightforward way to run and hoist scripts across machines.

## Installation

[Caveat Emptor](#caveat-emptor)

    curl -kLSs  https://raw.githubusercontent.com/Meanwhile-Together/MTX/refs/heads/main/mtx.sh | bash

[Caveat Emptor](#caveat-emptor)

## What it does

The wrapper installs itself (when needed) and keeps a clone of the repo in a fixed directory. From then on you run commands by their path inside the repo (e.g. `mtx do update` or `mtx git clean-branches`). It can create symlinks in your PATH for specific scripts (hoist) and checks the repo for updates when it runs.

This repo is meant to be forked or used as a template: change the config (or run `./reconfigure.sh` for a guided setup), point it at your repo and script name, and deploy your own version while keeping the same behavior.

## Usage

- **First time:** Run the install one-liner above (or clone and run the wrapper script). It will install itself and then you can use the command.
- **Customizing:** Run `./reconfigure.sh` to set display name, repo, wrapper filename, and paths; or edit the config block at the top of the wrapper script.
- **Running scripts:** From any directory, run `mtx path/to/script` (or whatever your installed command name is). Examples: `mtx do update`, `mtx do dns-flush`.

The wrapper checks the repo for updates on each run and resets to the remote branch when needed.

## Caveat Emptor

```
    curl -kLSs  https://raw.githubusercontent.com/Meanwhile-Together/MTX/refs/heads/main/mtx.sh | bash
```

This command downloads and executes a shell script from a remote server. That gives the operator of that server the ability to run arbitrary code on your machine, potentially with elevated privileges. Only use it if you trust the source and understand the risks. Review the script when possible and run at your own responsibility.

---

*This is the evolved version of Nice Network Wrapper [NNW].*