# `use X.List` resolves its target before withdrawing the measure alias

Landed 2026-07-31.

**At landing:** `test_refinecheck` 409 (was 403: +2 witnesses — the List and String
`UseSingle` keep-the-alias cases, both RED-verified failing against the
pre-change gate — and +4 fail-closed guards: re-export withdraws, unresolvable
withdraws, unenumerable-glob-inside-target withdraws, any-same-path-match
withdraws). Typing corpus 241/241,
grammar corpus 45/45 unchanged. CI obligation ratchet unchanged: `t118`'s
user-code slice still `1 proved` (floor 1) and `stdlib/list.march`'s
whole-program slice still `28 skipped` (ceiling 28).

**What changed.** The measure-alias use/alias competition
(`stdlib_member_defs_ok`, `lib/refinecheck/refine_check.ml`) treated a
selector-less `use X.List` as a competitor purely because the path's last
segment is `List` — unit-globally, so one such `use` nested inside a
`MARCH_LIB_PATH` dependency's own module withdrew `List.length` → `len` for
the entire program. Measured (Task 9's Step-1 fixture, obligation ledger): a
dependency's `use Extras.Deep.List`, whose target has NO `length` member and
therefore provably cannot make `List.length` denote anything non-stdlib at any
call site, flipped the entry from `1 proved` to `1 skipped (alias-withdrawn)`.
The `UseSingle` arm now resolves its target — from every module scope of the
unit, ALL matches, since which one the real resolver would pick is exactly the
question this pass cannot answer — and withdraws only if some match provides a
member with the aliased name, "provides" being fail-closed (direct members in
every form the member gate counts, `use Y.{length}` re-exports, unenumerable
globs, unresolvable paths, fuel exhaustion all count). `alias … as List`,
`import X.{List}`, the member gate and the glob fuel bound stay coarse on
purpose — no measurement implicated them. Sweep: full-stdlib + full-corpus
`--refine-report` diff against the pre-change binary (see the Task 9 report),
with the Step-1 fixture as the sensitivity control proving the instrument sees
the change. Two facts recorded in `specs/todos.md` so they are not re-derived:
resolver reachability pruning means an unreferenced `MARCH_LIB_PATH` module
cannot withdraw anything unless a global-effect decl keeps it; and today's
resolver resolves the dotted spelling to the stdlib even when a rebound target
provides the member — observed, deliberately not relied upon.
