# Repository guide for AI agents

## Purpose and layout

This repository is a small, flake-less collection of reusable
[devenv](https://devenv.sh/) modules. Consumers import the repository from
`devenv.yaml`; `devenv.nix` is the public module entrypoint.

- `devenv.nix` imports every public module. Add a new public module here.
- `shared-proxy/default.nix` defines `services.sharedProxy`, which manages one
  user-level Caddy instance shared by active devenv projects.
- `shared-proxy/shared-proxy.sh` is the runtime manager packaged by that Nix
  module. It registers project Caddyfiles, serializes changes with a lock, and
  starts, reloads, or stops Caddy.
- `laravel/default.nix` defines `services.laravel`, a convenience layer that
  expands Laravel site definitions into `services.sharedProxy.virtualHosts`.
- `README.md` is the user-facing API reference and examples. Keep it in sync
  with any public option, behavior, or operational change.

There is no application build artifact, lockfile, or test harness in this
repository. Do not introduce one incidentally.

## Working conventions

- Read the relevant module and README section before changing behavior. Keep
  public option names, defaults, and documented examples compatible unless a
  breaking change is explicitly requested.
- Nix modules use two-space indentation, `lib.mkOption` for options,
  `lib.mkIf` for conditional configuration, and Nix assertions for invalid
  declarative inputs. Follow the surrounding style rather than reformatting
  unrelated code.
- Keep `shared-proxy/shared-proxy.sh` Bash-compatible with `set -euo pipefail`.
  Quote expansions, validate externally supplied values, retain the existing
  lock/rollback behavior, and preserve restrictive permissions on state and
  runtime files.
- The proxy owns ports 80 and 443 and persistent user-level Caddy state. Avoid
  commands that start, stop, or delete that state during routine validation.
- Treat the module boundary as intentional: Laravel generates virtual hosts;
  generic Caddy configuration belongs in `sharedProxy`.

## Validation

Run the narrowest relevant checks before handing work over:

```sh
nixfmt devenv.nix shared-proxy/default.nix laravel/default.nix
shellcheck shared-proxy/shared-proxy.sh
devenv eval
```

Only run commands relevant to files you changed. `nixfmt` rewrites files, so
review its diff afterward. If `devenv eval` needs project-specific inputs that
are unavailable, report that limitation and still run the static checks that
apply. When changing public behavior, also verify the README examples and
option descriptions match the implementation.

## Version control: Jujutsu required

Use Jujutsu (`jj`) exclusively in this repository; do not use `git` commands
for status, history, staging, commits, branches, or restoration. Suppress
pagers and colors in scripted inspection:

```sh
jj --no-pager --color=never st
jj --no-pager --color=never diff
jj --no-pager --color=never log
```

- Check status first. If the working-copy change is non-empty, create a fresh
  change with `jj new` before starting unrelated work.
- Each logical change must be atomic and described before starting another.
  Use `jj describe -m "📝 Add repository agent guidance"` (with the appropriate
  allowed gitmoji) when it is complete.
- Commit subjects use an allowed gitmoji, imperative mood, no trailing period,
  and at most 50 characters. Add a body only to record non-obvious rationale.
- Never discard work with `jj abandon` or casually rewrite a failed approach.
  Describe a failed attempt with `⚗️`, then branch from the prior change. Use
  `jj edit` only for user-requested revisions or trivial corrections.
- Finish by checking `jj st` and `jj diff`. Do not leave a non-empty,
  undescribed working-copy change.

## Scope and handoff

Keep diffs focused. Do not modify `.agents/` unless the request is specifically
about agent configuration or skills. In the handoff, state the files changed,
checks run and their outcomes, and any validation that could not be performed.
