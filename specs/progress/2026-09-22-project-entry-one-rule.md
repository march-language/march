# `Project.entry`: one entry-file rule for every forge command

**DONE 2026-09-22.** G5 of
[specs/plans/2026-09-21-distributed-deploys-groundwork-plan.md](../plans/2026-09-21-distributed-deploys-groundwork-plan.md).

## The bug

The default entry file was computed at ten sites, not the four the plan
counted, and they disagreed:

| Site | Default |
|---|---|
| `cmd_build`, `cmd_check`, `cmd_run`, `cmd_fix`, `cmd_refine` | `lib/<name>.march` |
| `cmd_install`, `cmd_interactive` | `lib/<name>.march`, ignoring `[package] entrypoint` |
| `cmd_deploy_hot`: `build_so` and both deploy paths | `src/<name>.march` |

So a project that `forge build` accepted failed `forge deploy hot` with a
build error on a file that did not exist, and the reverse. forgepm, the one
project under `~/code` with a `[hot-reload]` section, has
`lib/forgepm.march` and no `src/`, so its hot deploy could not build without
an explicit `entrypoint`.

## The rule

`Project.entry : project -> (string, string) result`:

1. `[package] entrypoint`, relative to the project root, if set. A missing
   file is an error naming the setting.
2. Else the first of `lib/<name>.march`, `src/<name>.march` that exists.
3. Else an error naming both paths.

All ten sites call it. Behaviour changes:

- `forge deploy hot` (and `--env`, `--canary`) now builds `lib/<name>.march`
  projects.
- `forge build`/`check`/`run`/`fix`/`refine` now accept a `src/<name>.march`
  entry. `build` and `check` used to stop at "no .march files found in lib"
  before looking at the entry; an app or tool with an entry now proceeds.
  Other modules are still found through `lib/` only (`MARCH_LIB_PATH`), so a
  multi-module project under `src/` is not supported by this change.
- `forge install` and `forge interactive` honour `[package] entrypoint`.
- A missing entry reports one message everywhere.

## Tests

`forge/test/test_entry_rule.ml` (new hermetic executable, same stanza shape
as `test_cap_sandbox`: the just-built `march` plus the staged runtime and
stdlib). For each layout it runs `Project.entry`, `Cmd_run.resolve_entry`,
`Cmd_check.check`, `Cmd_build.build` (and runs the binary, which prints which
file it was built from) and `Cmd_deploy_hot.build_so`, and asserts they agree:

| Layout | Expected entry |
|---|---|
| `lib/entryapp.march` | lib |
| `src/entryapp.march` | src |
| both, `src/` one broken | lib (picking src would fail to typecheck) |
| `entrypoint = "app/main.march"`, `src/` one broken | app/main.march |
| neither | every consumer's error names both paths |

5 of 5 pass (55 s). Perturbation: `build_so` reverted to the old `src/` rule
fails the lib layout ("deploy build step: build failed").
