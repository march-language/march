# Dependency grants and `restrict`: roadmap

**Spec:** `specs/2026-11-09-dependency-grants-and-restrict-design.md` (approved 2026-11-09).

The spec's eight phases are separate subsystems (stdlib guard, every runtime, the type of
every capability builtin, forge), so each gets its own plan, written when the phase
starts, against the code as it is then. Each phase merges on its own.

| # | Phase | Plan | Depends on | Ships alone? |
|---|---|---|---|---|
| 1 | Path scopes on `IO.NetConnect` | `2026-11-09-path-scopes-plan.md` | host scopes (#1213) | yes: a module may scope to a path today |
| 2 | Every capability operation returns `Result` (+ `forge fix` migration) | to write | — | yes (breaking, pre-1.0) |
| 3 | Opaque file and socket handles | to write | — | yes |
| 4 | Run-time authority context in every runtime (C, interpreter, JS) + cross-backend conformance suite; module-level scoped `needs` become frames | to write | 2, 3 | yes: module scopes become run-time enforced everywhere |
| 5 | Compile-time checks (ceiling, host scopes) under `--check`, the interpreter and the REPL | to write | — | yes |
| 6 | `restrict ... do ... end` | to write | 4, 5 | yes |
| 7 | Dependency grants in `forge.toml` | to write | 4, 5 | yes |
| 8 | Capability values (`cap_narrow` to a scope, library parameters) | to write | 4 | yes |

Phases 2, 3 and 5 are independent of each other and of 1, and can run in parallel
sessions. 4 is the keystone.
