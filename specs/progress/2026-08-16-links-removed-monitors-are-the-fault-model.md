`[P2]` # Decision: remove the unreachable `link` builtin; monitors + supervisors are the fault model

## The gap (as filed 2026-08-12)

`lib/eval/eval.ml` defined a `link` builtin (backed by `link_actors` /
`ai_links` machinery), but there was no entry in the typechecker's builtin
table, so the function did not exist as far as typed March was concerned:

```
    link(a, b)
         ^^^^
    I cannot find `link`.
```

`unlink` was in the same position, and there was no `trap_exit` / exit-signal
propagation of any kind. The runtime carried half an implementation of a
fault-propagation model that no March program could reach.

## The fork

This was a genuine design fork, not an obvious omission:

1. **Expose it** — type `link`/`unlink`, define exit-signal propagation (a
   linked actor's death kills its peer unless the peer traps exits), add
   `trap_exit` so a trapping actor receives an Exit message instead of dying.
   BEAM treats links as foundational; this is the "finish what was started"
   option.
2. **Remove it** — delete the interpreter builtin and `ai_links`, and state in
   the actors chapter that March's fault model is monitors + supervisors,
   Akka-style, so the absence is documented rather than discovered.

## The decision (2026-08-16)

**Option 2.** Removed the `link` builtin, `link_actors`, the `ai_links` field
and its initializers, and the crash-propagation block in `crash_actor_with_reason`
that walked `inst.ai_links` — from `lib/eval/eval.ml`, plus the OCaml-level
tests that exercised that machinery directly (`test/test_supervision.ml`,
`test/test_stdlib_suite.ml`, `test/test_helpers.ml`). Documented the choice in
`docs/actors.md` and `specs/lang/actors.md` (identical "Why there are no
links" section in both, since they are drifted duplicates) and in
`CHANGELOG.md` under `[Unreleased] / Removed`.

**Why option 2 and why now:** PR #284 (`actor: deliver reasoned local monitor
Down messages`) gave monitors a reason-carrying `Down(ref, pid, reason)` with
`Normal`/`Killed`/`Crash(msg)` — closing the main capability gap that made
links attractive in the first place. A monitor's `Down` now tells a watcher
everything a link's exit signal would have, without the bidirectional
coupling a link implies or the `trap_exit` escape hatch that coupling would
need to be survivable. Failure in March propagates *downward* through
supervision trees (parent restarts child), never sideways between peers, and
that stayed true; this decision just stops the interpreter from carrying an
unreachable, half-built alternative to it. Nothing was lost: no March program
could reach `link`, so nothing regresses.

**Option 1 remains available** if peer-to-peer failure propagation between
actors with no supervisory relationship ever turns out to be a real,
demonstrated need — the todo this file replaces has the shape that
implementation would take (typed `link`/`unlink`, exit-signal propagation,
`trap_exit`).

## Verification

- `DUNE_CACHE=disabled dune build --root . --force` — exit 0.
- `run_eval` — 0 failures.
- `run_stdlib` — 0 failures.
- `scripts/check-docs.sh` — pass (source pointers, stdlib count, corpus
  counts all still consistent after the doc edit).
- `diff <(sed -n '/### Why there are no links/,/^## /p' docs/actors.md) <(sed -n '/### Why there are no links/,/^## /p' specs/lang/actors.md)` —
  empty (both copies identical).
