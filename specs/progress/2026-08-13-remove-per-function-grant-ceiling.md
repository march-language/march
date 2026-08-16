# Remove the per-function grant ceiling (R1 stage C, `check_fn_grants`)

**Status:** Landed (2026-08-13). Task 3 of the capability-UX plan
(`specs/2026-08-13-capability-ux-plan.md`).

## The problem

R1 stage C made any function with a concrete `Cap(X)` parameter a
per-function grant discharge point: its own transitive capability closure
had to sit under the union of the capabilities its parameters named. That
sounds like a stricter, more composable guarantee than the whole-program
grant, but it made explicit capability *passing* strictly more painful than
not passing anything at all — and the pain grew with the size of the call
graph reachable from that one function.

```march
fn handle(c : Cap(IO.FileWrite), name : String) : () do
  println("handling")   -- ERROR under stage C: granted Cap(IO.FileWrite),
                         -- but reaches IO.Console via println
end
```

The only fix was to widen `handle`'s signature with a second `Cap(IO.Console)`
parameter, and then propagate that widening to every caller, transitively,
for the whole call graph above `handle`. A function that took **no**
capability parameter carried no such obligation — its module's `needs`
covered it. So the one place a March author reached for the more explicit,
more auditable form (a capability parameter instead of ambient module
`needs`) was punished with exactly the parameter-threading the module-scoped
design exists to avoid ("we don't want to thread caps, that's the whole
point of making them module scoped" — design intent for this task).

## The fix

Deleted `check_fn_grants` (`lib/typecheck/typecheck.ml`) and its call site in
`check_module_core`. A `Cap(X)` parameter is now purely an authority marker
at a module boundary — it no longer creates a discharge point of its own.
What remains, unchanged:

- **`check_main_grant`** — `main`'s parameter(s) are still the ceiling on the
  whole program's reachable capability closure. This is the guarantee that
  actually matters (the "program cannot silently do X" claim) and it is
  untouched by this change.
- **The per-module `needs` ceiling.**
- **Check 1** — a `Cap(X)` appearing anywhere in a signature still requires
  the enclosing module to declare `needs X`.
- **Check 4** — demand-driven import propagation.

`env.fn_grant_points` (which functions carry a concrete `Cap(P)` parameter,
and where) is still populated by `check_module_needs` — a later task (Task 8)
reads it to attribute a whole-program grant violation to the user's call
chain — but nothing currently checks it. `cap_reach_chain`, the BFS helper
`check_fn_grants` used to build its "via a -> b -> c" diagnostic hint, is
kept for the same reason (`let _ = cap_reach_chain` silences the now-unused
warning; do not delete it).

**Row-solve simplification.** `~with_rows` on `fn_capability_rows_tbl` only
mattered because `check_fn_grants` read the `deps`/`unknown` fields of the
solved row; `check_main_grant` deliberately never consults them (documented
in its own source comment — a function value's untraceable origin only
matters when *that function* is the discharge point, and at `main` the
program is closed). The row-solve call in `check_module_core` now passes
`~with_rows:false` explicitly, so `--check` keeps paying only the caps-only
fixpoint cost `check_main_grant` actually needs — not the previous
conditional-on-`fn_grant_points` cost, which would otherwise regress to
"always pay the row-seed walk" now that the flag it read
(`Hashtbl.length final_env.fn_grant_points > 0`) no longer gates anything
meaningful. `dump_cap_rows` (the `MARCH_DUMP_CAP_ROWS=1` debug dump) is
unaffected — it always solves its own copy of the table with `~with_rows`
at its default (`true`), gated behind the env var, independent of this call.

## What was deliberately given up

A narrow `Cap` parameter on a library function is no longer, by itself, a
per-function bound. A library that is never linked into a `main` is now
governed only by its module `needs` ceiling — there is no discharge point
inside the library itself that a standalone `--check` of that library can
fail against. That is the module-scoped guarantee this design intends (the
ceiling that matters is the module's and the program's, not an ad hoc
per-function one), but it is a real reduction in what could previously be
certified about an individual function in isolation, so it's called out
explicitly rather than left implicit.

## Tests

`test/test_compiler.ml`, `cap_fn_grant` suite:

- **Deleted** (each asserted a per-function grant *violation* — the removed
  behavior itself): `test_fn_grant_narrow_rejects_filewrite`,
  `test_fn_grant_violation_through_helper`,
  `test_fn_grant_supplier_is_charged_for_the_callback`,
  `test_fn_grant_refuses_untraceable_invocation`,
  `test_fn_grant_narrow_refuses_foreign`.
- **Kept unchanged** (each asserts *no* error — still true with no
  per-function check at all, so these remain valid no-regression pins even
  though several no longer exercise anything specific to a removed check):
  `test_fn_grant_narrow_covers_console`,
  `test_fn_grant_multi_cap_params_union`,
  `test_fn_grant_polymorphic_cap_param_is_no_gate`,
  `test_fn_grant_invoking_a_parameter_still_certifies`,
  `test_fn_grant_full_io_accepts_untraceable_invocation`,
  `test_fn_grant_dead_code_is_not_charged`,
  `test_fn_grant_main_is_not_double_reported`.
  (`test_fn_grant_multi_cap_params_union` was miscategorized as a "delete" in
  an earlier draft of the task-3 brief — its body asserts `false
  (has_errors ctx)`, not a per-function violation, so it survives the
  removal unchanged and was moved to "keep" instead.)
- **Rewritten and renamed** (see below):
  `test_fn_grant_with_stdlib_prepended` ->
  `test_module_scoped_caps_with_stdlib_prepended`,
  `test_fn_grant_with_prelude_flattened` ->
  `test_module_scoped_caps_with_prelude_flattened`.
- **Added**, verbatim from the plan: `test_cap_param_does_not_force_threading`
  (red before this change: `handle`'s `Cap(IO.FileWrite)` parameter used to
  be flagged for reaching `println`'s `IO.Console`; green after) and
  `test_main_grant_still_bounds_the_program` (pins that `main`'s grant is
  unweakened by this removal — already green before the change, stays green
  after).

### Why the two rewrites, not deletes

An earlier draft of the task-3 brief listed `test_fn_grant_with_stdlib_prepended`
and `test_fn_grant_with_prelude_flattened` as tests to "keep unchanged." That
was wrong: both assert `has_error_with ... "granted \`Cap(...)\`"` (or a
capability name) against a *non-`main`* function under a per-function
grant — exactly the diagnostic `check_fn_grants` produced and this task
deletes. Neither could pass unchanged.

They were not simply deleted, either. Both exist specifically to guard
against the regression documented in
`specs/progress/2026-08-09-cap-shadowing-false-positive.md`: nine green unit
tests once shipped a capability-check regression because every one of them
built its module from a bare `parse_and_desugar` helper, never exercising
the real stdlib-prepended or prelude-flattened shape `bin/main.ml` actually
produces. Deleting these two would reopen that exact hole.

Each was rewritten with its setup (the stdlib-prepending / prelude-flattening
construction, same module source shape) kept verbatim, and only the
assertions changed:

1. A negative assertion that the non-`main` function's `Cap(X)` parameter no
   longer produces a per-function violation (`false (has_error_with ...)`
   against the specific `` `stamped` is granted `` / `` `talk`/`scribble`
   is granted `` diagnostic text) — this actively pins the removed behavior
   as removed, not just "no errors anywhere."
2. In the same test, `main` was given a narrow grant that the program's
   closure exceeds (`main` now calls the helper that reaches the
   uncovered capability), and a positive assertion that `main`'s grant still
   fires (`true (has_error_with ... "granted \`Cap(...)\`")`). This keeps the
   test non-vacuous: a test whose only assertion is "nothing errors" would
   pass even if the whole capability pipeline silently stopped running under
   these real pipeline shapes, which is precisely the failure mode the 2026-08-09
   incident was about.

## Verification

Machine note: this task ran on a box with 5 other worktrees running their own
test suites concurrently (load average up to ~180). `dune runtest` and the
full `scripts/run-tests.sh` were unusably starved, so verification here is
scoped to the `test/run_compiler.exe` binary run directly with a name-regex
filter over the capability suites, not the whole-repo suite. The full
`scripts/run-tests.sh` is deferred to the final whole-branch review.

Build (both exit 0):
```
dune build --root . bin/main.exe
dune build --root . test/run_compiler.exe
```

**Genuine red/green cycle**, done by temporarily reverting only
`lib/typecheck/typecheck.ml` to its committed (pre-task) content via
`git checkout -- lib/typecheck/typecheck.ml` (safe: the change was still
uncommitted, so this restores from `HEAD`, not a stash — no stash was used),
rebuilding, and running the narrow suite, then restoring the edited file from
a backup copy and rebuilding again:

- **Red** (`check_fn_grants` still present, new/rewritten tests already in
  place): `./_build/default/test/run_compiler.exe test cap_fn_grant -e`
  exited 1 — `3 failures! in 0.029s. 11 tests run.` The three failures were
  exactly the ones expected to be sensitive to the removal:
  `test_module_scoped_caps_with_stdlib_prepended` (`` `stamped` is granted ``
  still present), `test_module_scoped_caps_with_prelude_flattened`
  (`` `scribble` is granted `` still present), and
  `test_cap_param_does_not_force_threading` (`handle` still flagged for
  reaching `IO.Console`).
- **Green** (edited `typecheck.ml` restored): same command exited 0 —
  `Test Successful in 0.051s. 11 tests run.`

Broader capability regression check, same binary, name-regex over the
adjacent suites (`cap_grant`, `cap_grant_required`, `cap-closure`,
`cap_shadow`, `cap_propagation`, `cap_infer`, `cap_body_enforce`):
`113 tests run`, all green, `0` failures.

`scripts/check-docs.sh` — exit 0 (checked directly, no pipe):
```
== Check A: source pointers in current docs ==
  ok — all cited source paths exist
== Check B: stdlib module count (actual: 115) ==
  ok — no stale stdlib counts
== Check C: conformance-corpus INDEX counts ... ==
  ok — corpus INDEX counts match on-disk file counts
doc-lint passed
```

**One bug found and fixed in the plan's own verbatim test source** (Step 1
gave `test_cap_param_does_not_force_threading`'s body to add "verbatim"):
`fn main(cap : Cap(IO)) : () do ... end` needs `needs IO` declared — Check 1
requires a `needs` entry that *subsumes* every `Cap(X)` in a signature, and
`needs IO.Console` / `needs IO.FileWrite` do not subsume the broader `IO`.
Without it the test failed with an unrelated, pre-existing Check 1 diagnostic
(`` `Cap(IO)` used in module `NoThread` but `IO` is not declared in `needs` ``),
masking the intended per-function-ceiling assertion entirely. Added
`needs IO` to the module; confirmed via `bin/main.exe --check` on the
extracted source before and after (exit 1 -> exit 0, only a pre-existing
unused-variable warning and a narrowing hint remain). This is unrelated to
Check 1's own correctness — Check 1 itself was not touched by this task and
behaved exactly as documented.

Doc updates applied identically to `specs/lang/capabilities.md` and its
drifted `docs/` copy at `docs/capabilities.md` (both the intro note and the
"stage C and not built" sentence near "The grant").
