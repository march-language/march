`[P2]` # The compiled backend still carries the unreachable `link`/`unlink` builtin

## Background

2026-08-16 removed the interpreter's `link` builtin, `link_actors`, and
`ai_links` crash-propagation machinery (see
`specs/progress/2026-08-16-links-removed-monitors-are-the-fault-model.md`)
because the typechecker never exposed `link` to typed March, so no program
could reach it. **That removal was interpreter-only.** The compiled/LLVM
backend still declares and implements the identical unreachable `link`/
`unlink` pair, and it needs the same treatment.

## What's still there

- `lib/tir/llvm_builtins.ml:865-868` — the `link` and `unlink` builtin-table
  entries (`march_name = "link"`, `c_name = Some "march_link"`, and the
  `unlink`/`march_unlink` sibling immediately below it).
- `lib/tir/llvm_builtins.ml:1551-1552` — the corresponding `PDeclare
  "march_link"` / `PDeclare "march_unlink"` forward declarations emitted into
  every compiled module's prelude.
- `runtime/march_runtime.c:6287` (`march_link`) and `:6296` (`march_unlink`).
- `runtime/march_runtime.h:409-419` — the doc comments on the two functions.
  These **overclaim the semantics** and are wrong today, independent of this
  todo: they say a link means "if either dies, the other receives a Down
  notification (and **may crash too**)" and that "children are registered
  separately via `march_link`" for supervisors. Neither is true of the actual
  implementation (see Finding, below), and supervisor children are registered
  via `march_register_supervisor` plus a separate child-registration call, not
  `march_link` at all. Pre-existing inaccuracy, but it belongs in the same
  cleanup rather than a separate pass.
- `test/test_eval.ml:3500` — `test_actor_compile_link_emitted`, which calls
  `emit_actor_ir` directly (bypassing the typechecker, the same way the
  now-deleted interpreter-side tests did) to build IR containing `link(a, b)`,
  then asserts `march_link` appears in the emitted IR.
- Seven golden `.ll` files under `test/native/` carry the `march_link`/
  `march_unlink` forward declarations by virtue of sharing the standard
  builtin prelude: `supervisor_one_for_all_restart.ll`,
  `supervisor_one_for_one_restart.ll`, `supervisor_rest_for_one_restart.ll`,
  `supervisor_spawn_children.ll`, `signal_watch.ll`,
  `actor_registry_restart.ll`, `actor_registry_restart_batch.ll`. None of
  these actually call `march_link`/`march_unlink`; the declarations are
  boilerplate that would disappear from the prelude (and need regenerating
  in these goldens) once the builtin-table entries are removed.

## Finding: the two backends never agreed even before this

While reviewing the interpreter-side removal, a closer read of
`runtime/march_runtime.c:6287-6292` turned up that the compiled backend's
`march_link` was **not** equivalent to the interpreter's `link_actors` even
while both existed:

- Interpreter (`ai_links`, now removed): a genuine bidirectional
  crash-propagation link — `crash_actor_with_reason` walked `inst.ai_links`
  and recursively called `crash_actor` on every linked peer, so one actor's
  death directly killed the other.
- Compiled (`march_link`, still present): implemented as **two one-way
  monitors** (`march_monitor(actor_a, actor_b); march_monitor(actor_b,
  actor_a);`). A monitor only delivers a `Down` message — it does **not**
  crash the watcher. So on the compiled backend, killing one linked actor
  never killed the other; it only queued a `Down` in its mailbox, which the
  actor would have to explicitly act on (and no built-in "trap and crash"
  handler existed to make it act on it the way the interpreter did
  automatically).

So `link` was not merely unreachable — had it somehow been reachable, calling
it would have observably behaved differently depending on which backend the
program ran on. That's a second, independent argument for finishing the
removal rather than exposing it: there is no single semantics to expose
without deciding one from scratch, and Option 1 in the prior decision record
(exposing `link` with real exit-signal propagation) would need to define that
semantics fresh rather than just "typecheck what's there."

## What finishing the removal requires

1. Delete the two `llvm_builtins.ml` table entries and their `PDeclare`s.
2. Delete `march_link`/`march_unlink` from `runtime/march_runtime.c` and their
   declarations from `runtime/march_runtime.h` (and fix or delete the
   `march_unlink`-referencing comment at `runtime/march_runtime.c:6485` about
   `monitor_head` discipline, which will need to describe monitor-only
   detachment once `march_unlink` is gone alongside it — check whether any
   other function's monitor-list handling still needs that discipline
   documented once the link-specific caller disappears).
3. **Delete `test_actor_compile_link_emitted` in the same change that removes
   the machinery it exercises, not before.** Deleting the test first (e.g. as
   a quick cleanup ahead of the real removal) would leave the compiled `link`
   builtin live with zero test coverage — worse than the current state, where
   at least a regression in codegen would be caught. The test and the
   machinery it covers must go together.
4. Regenerate the 7 affected `.ll` goldens (`UPDATE_SNAPSHOTS=1` if they're
   snapshot-managed, or by hand — check how each is produced) once the
   `PDeclare`s are gone, and review the diff.
5. Add the mirror of the 2026-08-16 doc section/CHANGELOG bullet if the docs
   need updating further — the actors chapter's "Why there are no links"
   section already states the *language-level* decision and doesn't
   distinguish backends, so it likely needs no further edit; confirm this
   when doing the work rather than assuming.

## Acceptance

`grep -rn "march_link\|march_unlink" lib/ runtime/ test/` returns nothing
(aside from historical mentions in comments/specs, which should also be swept
if found), the build is clean, and `run_eval`/`run_codegen`/`run_compiler`
all still pass with the `.ll` goldens regenerated and reviewed.
