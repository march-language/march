# Hot reload: undecided migrations are checked on the live data (M10)

Lemmas design `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` §3.3 item 3, phase
A2 (first half; M11, derived migrations, is the second).

## Before

A `migrate_state` the prover could neither prove nor refute was refused at deploy, or, with
`--accept-unproved`, activated with no check at all: the new handlers then assumed a state
contract nothing had established for the states the actors actually held. A `migrate_msg`
result that broke the new handler's refinements reached the handler.

## Fix

- **Generated check** (`lib/desugar/desugar_migrate_check.ml`, `--hot-reload` builds only, so
  `--check`, the editor and plain builds see nothing new). Beside `<actor>_migrate_state`,
  when the actor has field refinements or an `@invariant`:
  `<actor>_migrate_state__check(old) : String` runs the migration and evaluates each conjunct
  of the new contract on the result. Verdict: `""` holds, `"!<conjunct>"` fails,
  `"?<conjuncts>"` holds but those were not evaluable. A conjunct is evaluated only inside the
  deploy gate's grammar and when every function it calls is declared beside the actor, so a
  check can never break the build it checks. Exported as `@__migrate_check_<Actor>`
  (`llvm_toplevel.ml`), a migration entry point everywhere else (`Tir_names.is_migrate_fn_name`:
  DCE and mono root, default visibility, no owned clone), parameter pinned owned (`Borrow`).
  Its own calls are direct, not dispatched (`llvm_emit_call.ml`): before ACTIVATE a dispatched
  call would reach the running version's `migrate_state`.
- **Message guard.** The `<actor>_migrate_msg__hcr` wrapper returns its `none` sentinel (the
  runtime's "dropped", counted like a `None`) for a converted message that fails the new
  handler's evaluable parameter conjuncts, through a generated `<actor>_migrate_msg__guard`.
  A separate function because a match on a qualified `<Actor>.<Msg>` pattern nested in a
  `Some` arm miscompiles (todo `2026-11-05-nested-match-qualified-actor-msg-pattern-miscompile`).
- **Runtime** (`march_hcr_migrate_check`, `march_runtime.c`). An inspect request whose field 2
  holds the check runs it on the actor's own thread between handlers, on an incrc'd copy of
  the state (`a[4]`), under a crash trap (a panic is a failed check). `busy` (asked inside a
  `receive`) and `behind` (the actor has not reached the current epoch, so its state is not the
  deployed shape) are asked again until the deadline; a dead actor is skipped; a timeout fails.
- **Reload server** (`activate_items`). Before `march_hcr_activate`, for each item whose state
  changed and whose image exports the check: any failure is `ERR migration_check <Actor>
  pid:<n> <conjunct>`, audit result `err_migration_check`, nothing activated. `COMMIT_BATCH`
  passes that line through instead of `commit_partial_failure`. Success logs
  `[hcr] migrate check: <Actor>: checked on live data (N actors)` and any unevaluated
  conjuncts. Deadline `MARCH_HCR_MIGRATE_CHECK_MS` (default 5000). Not at replay.
- **forge** prints the refusal (`refused: <Actor>'s new migrate_state fails on its live
  state (...)`). `test/hcr_deploy.ml` takes `ENTRY=<file>` for the migration check.

## Result

`test/two_node/hcr_migration_check`: v2's migration keeps `count = 137`, which its invariant
`not_137(count)` rejects (undecided at compile time, accepted with `--accept-unproved`). The
deploy is refused naming `Counter`, the pid and the conjunct, and the schemas are unchanged;
v3's migration (`count + 1`) passes and the actor reports `v3 count: 138`. RED with the check
disabled in the server ("v2's migration was activated over a state its invariant rejects").
`test/hcr_migration_check/check_fns.march` pins the generated functions' verdicts (holds,
field refinement fails, `@invariant` conjunct fails, unevaluable conjunct) and the message
guard (passed, dropped, unrefined).

## Residuals

- A function the migration or a predicate calls, which this deploy also changes, runs its
  running version during the check (only the check's own calls are direct).
- A state can change between the check and the actor's switch at its epoch marker.
- An unchanged-layout deploy that only tightens the contract (no `migrate_state`, so
  `MIGRATE_STATE` is not set) is not checked on the live data; the deploy gate's proof
  still covers it.
- Messages are checked as they are converted, not ahead of time (the design's intent). An
  unevaluable handler conjunct is not tested, and the drop is counted with the `None` drops,
  not reported apart.
- Phase B's guarantee report should show `checked on live data (N actors)`, never `proved`.
