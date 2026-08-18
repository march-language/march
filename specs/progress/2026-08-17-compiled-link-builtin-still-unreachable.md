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

## Resolution (2026-08-18)

Finished the removal exactly as scoped above:

- `lib/tir/llvm_builtins.ml` — deleted the `link`/`unlink` builtin-table
  entries and their `PDeclare "march_link"` / `PDeclare "march_unlink"`
  prelude lines.
- `runtime/march_runtime.c` — deleted `march_link`/`march_unlink`. Fixed the
  `march_register_resource` comment at the old `:6485` (now earlier, after
  the two functions above it were removed) that cited "march_unlink's
  discipline for monitor_head" — `march_monitor`/`march_demonitor` still
  document and enforce that same `g_tbl_mu` discipline for `monitor_head`,
  so the comment is still load-bearing; it now just drops the removed
  function's name.
- `runtime/march_runtime.h` — deleted the `march_link`/`march_unlink`
  declarations and the "Actor link builtins" comment block. Also corrected
  the `march_register_supervisor` doc comment, which claimed "children are
  registered separately via march_link" — never true; the real call is
  `march_actor_register_child`.
- `test/test_eval.ml` — deleted `test_actor_compile_link_emitted` (built
  `link(a, b)` IR directly via `emit_actor_ir`, bypassing the typechecker)
  and its suite registration, in the same commit as the machinery it
  exercised.
- `test/test_codegen.ml` — two more `march_link`/`march_unlink` mentions the
  todo didn't enumerate, both needed fixing for the acceptance grep to pass:
  - The `golden_preamble_native_actor` byte-identical-prelude blob (feeds
    `test_preamble_byte_identical_native{,_repl}`/`_wasm`) carried the two
    `declare void @march_link(...)`/`@march_unlink(...)` lines verbatim; they
    were deleted from the golden string.
  - `test_compile_local_shadows_builtin_still_gets_rc_ops` (regression B10)
    deliberately used a local variable named `link` *because* `link` was a
    builtin, to test that a local shadowing a builtin name still gets its RC
    ops emitted. With `link` no longer a builtin, that local would stop
    exercising a real name collision (the "skip RC emission because the name
    matches a builtin" code path would simply never trigger) while still
    reporting green — a silent loss of coverage disguised as a passing test.
    Renamed the shadowed local from `link` to `kill` (a real, still-existing
    single-word actor builtin) throughout the test, so it keeps testing an
    actual shadow-a-builtin scenario. Left a comment explaining the rename.
    Same rationale applied to the analogous example in the doc comment on
    the `AVar` builtin-shadowing arm in `lib/tir/llvm_emit.ml` (~line 517),
    which cited `link` as the example builtin.

**The "7 golden `.ll` files" turned out not to be an IR-snapshot mechanism at
all.** Investigated `test/native/dune` and `test/test_ir_verify.ml`/
`test_codegen.ml` before touching anything: every one of the 7 named fixtures
(`supervisor_one_for_all_restart`, `supervisor_one_for_one_restart`,
`supervisor_rest_for_one_restart`, `supervisor_spawn_children`,
`signal_watch`, `actor_registry_restart`, `actor_registry_restart_batch`) is
wired in `test/dune` as `(diff native/<name>.expected native_<name>.out)`,
where `<name>.out` is the captured **stdout** of compiling and running
`native/<name>.march` — there is no LLVM-IR content anywhere in an
`.expected` file (confirmed by reading them: each is a few lines of program
output, e.g. `signal_watch.expected` is `before raise` / `after raise` /
`caught usr2`). The `march_link`/`march_unlink` `PDeclare`s only ever existed
in the LLVM prelude text, which these tests never inspect. So "regenerating"
these goldens meant literally nothing changed: none of the 7 fixtures call
`link`/`unlink` (confirmed by grep), removing two dead prelude declarations
cannot change a compiled program's stdout, and empirically rebuilding and
diffing all 7 (`dune build --root . test/native_<name>.out` then `diff
test/native/<name>.expected _build/default/test/native_<name>.out`)
confirms exact, unchanged matches — no golden file needed touching.
`UPDATE_SNAPSHOTS=1` (the
TIR-pretty-printer mechanism in `test/run_snapshots.exe`) does not apply
here at all — different mechanism, different files, never touched.

`docs/actors.md` / `specs/lang/actors.md` "Why there are no links" — checked
by diffing both copies against each other: identical, and neither mentions
`march_link`/the compiled backend by name; the language-level decision
("monitors plus supervisors, not links") holds at both backends uniformly.
No edit needed there, confirming the todo author's guess.

Swept for stale mentions beyond the todo's explicit list and found two more,
both fixed:
- `.claude/skills/march-lang/SKILL.md` (linted by `scripts/check-docs.sh`)
  still listed `` `link(pid)` | Link actors `` in the actors/process builtin
  table — removed the row.
- `specs/2026-06-21-distributed-otp-design.md` (dated design spec, outside
  doc-lint's scope, but a live pointer to a since-removed symbol is still
  worth fixing) had a future L5 roadmap bullet "Extend `march_link`/monitor
  over the net-kernel" — reworded to "Extend local `monitor`/`Down`
  delivery over the net-kernel" with a pointer to this file and the
  2026-08-16 decision record, so a future implementer doesn't go looking for
  a primitive that no longer exists.

Left untouched, and flagged rather than fixed:
- `.claude/skills/spec-search/docs/features/runtime.md` still documents
  `march_link`/`march_unlink`. This is a bundled, manually-refreshed
  point-in-time snapshot for the `spec-search` skill (its own `SKILL.md`
  says so explicitly), not read from this repo at skill-invocation time and
  not covered by `scripts/check-docs.sh` (which only checks
  `.claude/skills/march-lang/SKILL.md`). Refreshing it is a separate,
  periodic snapshot-rebuild task, not part of this removal.
- `docs/assets/march.js` (a `js_of_ocaml`-generated browser bundle) still
  contains a compiled `link_actors` function — it was already stale before
  this change (that symbol was removed from `lib/eval/eval.ml` on
  2026-08-16) and regenerating it is a build step outside this todo's scope.

### Verification

- `dune build --root . test/run_compiler.exe test/run_eval.exe
  test/run_codegen.exe bin/main.exe` — exit 0.
- `./_build/default/test/run_eval.exe -e` — 262 tests, 0 failures
  (`actor_compile` suite now has 8 cases, was 9; the "link emitted" case is
  gone and the rest renumbered).
- `./_build/default/test/run_codegen.exe -e` — 583 tests, 0 failures
  (580s wall-clock; the `llvm_ir_validity_gate` sub-check emits
  `--emit-llvm` for every `test/native/*.march` fixture, including all 7
  named in this todo — verifier-clean for all of them). A targeted subset
  (`tasks`, `llvm_builtins_preamble_golden`) was also run in isolation
  early, confirming pass before the full run finished.
- `./_build/default/test/run_compiler.exe -e` — 924 tests, 0 failures
  (707s wall-clock under heavy shared-host contention; a targeted subset
  covering every suite this change could plausibly affect —
  `dynamic_supervisor`, `session_compile`, `entry_mod_qual_erasure` — was
  also run in isolation early, confirming pass before the full run finished).
- `grep -rn "march_link\|march_unlink" lib/ runtime/ test/` — empty.
