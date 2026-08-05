# `cap no_panic`: consult a call's actual contract instead of banning it by name

**Date:** 2026-08-05
**Files:** `lib/refinecheck/panic_surface_by_proof.ml` (new), `lib/refinecheck/dune`,
`lib/typecheck/typecheck.ml`, `bin/main.ml`, `test/test_refinecheck.ml`,
`test/test_compiler.ml`, `test/dune`, `lsp/test/test_lsp.ml`,
`docs/capabilities.md`, `specs/lang/capabilities.md`, `CHANGELOG.md`

Task 3 of `docs/superpowers/plans/2026-08-05-no-panic-proof-based-and-group-b.md`.
Builds on Task 1 (ban-list audit, `specs/progress/2026-08-05-no-panic-ban-list-audit.md`)
and Task 2 (per-call-site verdict index in `lib/refinecheck/obligation.ml`).

## What changed

`cap no_panic` used to reject every name on the panic-surface ban list by a purely
syntactic match, plus a transitive fixpoint that blamed every caller up the chain.
For the names that carry a real refinement precondition, that ban is replaced by a
question about the call's own verdict.

### 1. New pass: `lib/refinecheck/panic_surface_by_proof.ml`

Walks the same scope `Typecheck.check_no_panic_module` scanned (top-level `DFn`s of a
`cap no_panic` module, recursing into nested `DMod`s, which re-derive their own `cap`).
For a call whose head name is in the covered set, it looks up the call's precondition
verdict and reports the SAME error message, at the same span, unless the verdict is
`Proved`.

It discharges nothing itself. Building a second VC generator here would be free to
drift from the real one; it only reads what `Refine_check` already recorded.

**Covered set** (20 qualified + 5 bare): `head`, `tail`, `last`, `unwrap`, `expect`;
`List.nth`, `List.head`, `List.last`, `List.tail`, `List.maximum_int`,
`List.minimum_int`, `Option.unwrap`, `Option.expect`, `Result.unwrap`,
`Result.expect`, `Result.unwrap_err`, `Random.normal`, `Random.exponential`,
`Random.bernoulli`, `Random.choice`, `DateTime.fixed_zone`, `DateTime.fixed_zone_hm`,
`Stats.mean`, `Stats.min_val`, `Stats.max_val`.

### 2. Two deliberate rules

**Only `Proved` is silent.** `Violated`, any `Skipped _`, `Trusted`, and "no obligation
recorded at this site" all produce the error. Fail-closed on the absent case is what
keeps the twelve coverage holes Task 1 closed from silently reopening. `Trusted` is on
the error side on purpose: it is an unchecked user assertion, and `cap verified`
accepting one is about disclosure, whereas `cap no_panic` is a guarantee.

**Not `Obligation.verdict_at`.** That helper folds EVERY obligation kind at a span down
to the weakest verdict, which is right for a report and wrong for this consumer: a call
site with a `Proved` precondition sharing a span with an unrelated `Division` (or another
callee's) obligation would fold to the weaker verdict and a provably-safe call would be
REJECTED — a false positive, this subsystem's cardinal sin. `verdict_for` filters
`Obligation.obligations_at` to `Precondition` obligations whose `callee` is the name being
checked, then folds weakest-wins over only those. Weakest-wins still matters inside the
filtered set: one call raises one obligation per refined parameter, and "first proved,
second skipped" is not a proof.

The lookup key is the `EApp` call-expression span (what `Obligation.record` files a
precondition under), not the callee name's span — keying on the latter would silently
never match. The diagnostic is still reported at the NAME span, so the caret is
unchanged.

### 3. Ban lists narrowed, and un-seeded from the fixpoint

`lib/typecheck/typecheck.ml`:

- `panic_surface_prelude` → **empty** (all five names are contracted).
- `panic_surface_stdlib` → **`Array.get`, `Array.set` only** (they panic out of bounds
  and carry no contract yet; Group B).
- `panic_surface_direct` — `panic`, `panic_`, `todo_`, `unreachable_` — **unchanged**.

`is_direct_panic_site` reads exactly these sets, so removing the covered names from them
also removes them from what SEEDS the fixpoint. That is the whole of the transitivity
change: leaving them as seeds would have reproduced chain-blaming even with the direct
site proof-checked.

**Disjointness:** covered set ∩ (`panic_surface_prelude` ∪ `panic_surface_stdlib` ∪
`panic_surface_direct`) = ∅. `panic_surface_prelude` is empty; `panic_surface_stdlib` is
`{Array.get, Array.set}`; `panic_surface_direct` is `{panic, panic_, todo_,
unreachable_}`; none of those six appear in the covered set.

### 4. Behavior change: no transitive blame for covered names

A helper making an unprovable covered call now gets ONE error, at the real call site,
matching how `Division_safety` has always reported — not one per caller. Documented
explicitly in both capability docs, since a reader debugging "why did my error move"
needs it stated rather than discovered.

### 5. Pipeline placement — TWO call sites

The pass needs Task 2's verdict index, which only exists after
`Refine_check.check_module`, so it cannot live inside the typechecker. It is called from
`bin/main.ml` immediately after `Division_safety.check_module` (which only ADDS to the
index).

`bin/main.ml` has **two** copies of that pipeline: the main compile/check path
(~line 2031) and `run_test_cmd`'s (~line 1385). Wiring only the second one made the pass
a silent no-op for `--check` — caught by the corpus sweep, not by the unit tests, since
neither test suite drives the CLI. Both are now wired, and the comment at each site says
so.

## Testing

New `no-panic-by-proof` group in `test/test_refinecheck.ml`, running the production
pipeline (typecheck → `Refine_check` → `Division_safety` → `Panic_surface_by_proof`)
over the REAL `stdlib/list.march` loaded as a sibling `DMod`, exactly as `bin/main.ml`
prepends the stdlib — an inline stand-in contract would keep passing after the shipped
one changed:

- guarded `List.tail` compiles clean (the point of the task);
- unguarded `List.tail` still errors (REJECT control);
- undecidable `if flag do List.tail(xs)` still errors (fail-closed control);
- a helper + two callers produce exactly ONE error (dropped transitivity);
- `panic` + two callers still produce THREE (regression guard: the syntactic ban and its
  fixpoint are untouched).

New `no-panic-verdict-filter` group unit-tests `verdict_for` directly, by recording
obligations at a shared span by hand. A same-span cross-kind collision is not currently
constructible from March source (a postcondition keys on a clause span, a division on the
`/` node's own span), so a test that could only observe the filter through source would
silently stop testing it. Covers: a `Proved` precondition survives an unrelated
`Division` skip at the same span; a different callee's skip does not veto; weakest-wins
still applies within the filtered set; a missing obligation reads as absent, never
proved; `Trusted` is not admitted.

`test/test_compiler.ml`: Task 1's `test_cap_no_panic_list_tail_guarded_still_error` had
its assertion INVERTED in place (rather than replaced) so the two revisions of that one
case document the before/after. Thirteen Task-1 cases that assert an unguarded contracted
call errors were moved from the `typecheck`-only harness to a new
`typecheck_with_no_panic_passes` harness running the full pipeline — with no stdlib
loaded, those calls resolve to nothing, raise no obligation, and are rejected fail-closed,
which is exactly the property they assert.

### RED (Step 2)

With the pass stubbed to a no-op: the positive case FAILED (`Expected false, Received
true` — the syntactic ban still fired) and the dropped-transitivity case FAILED
(`Expected 1, Received 3`). Both controls and the `panic` regression case were already
GREEN and stayed GREEN.

### Load-bearing (Step 5)

- `is_proved` → always `true`: reject control, fail-closed control, and transitivity
  count (0, not 1) all FAIL; positive passes trivially.
- `is_proved` → always `false`: positive case FAILS.
- `"List.tail"` restored to `panic_surface_stdlib` (re-seeding the fixpoint): positive
  case FAILS and transitivity returns to 3.
- `verdict_for`'s kind/callee filter removed (fold everything at the span): three of the
  five filter cases FAIL, including the Proved-vs-Division false positive.
- `is_proved` widened to accept `Trusted`: the `Trusted` case FAILS.

All restored and re-verified green.

## Stdlib + corpus sweep

A/B against a binary built from the parent commit's `typecheck.ml`/`bin/main.ml` (no
`panic_surface_by_proof.ml`), both exes run from the same path with sibling
`stdlib`/`runtime` symlinks so path text is comparable, CAS caches
(`.march/cas/artifacts-v2`, `.march/cas/vc`) cleared once before each sweep.

Corpus: every `stdlib/*.march` and `test/native/*.march`, plus three scratch control
fixtures outside `stdlib/`.

Result: **no diff on any stdlib or native file** other than worktree-path text inside a
pre-existing "Overlapping implementation" diagnostic on `prelude.march` (an artifact of
passing a stdlib file as the entry file, so it is loaded twice; same noise Task 1
reported). `json_stream.march` is the only stdlib module declaring `cap no_panic` and it
calls nothing in the covered set.

**Positive control — and it can fail.** The plan's prescribed control (edit
`json_stream.march`) is invalid: `bin/main.ml` filters every stdlib-span diagnostic before
printing, so an injected error there is invisible regardless. The control was a scratch
fixture outside `stdlib/`:

| fixture | before | after |
|---|---|---|
| `cap no_panic` + guarded `List.tail` | ERROR, exit 1 | clean, exit 0 |
| `cap no_panic` + unguarded `List.tail` | ERROR, exit 1 | ERROR, exit 1 |
| `cap no_panic` + helper/2 callers, unprovable | 3 ERRORs, exit 1 | 1 ERROR, exit 1 |

The pre-change binary rejecting the guarded fixture is what proves the control could
fail; the sweep is not a byte-identical no-op.

Types corpus (`specs/lang/types/check_types.sh`): 244 passed, 0 failed.


---

## Review round 2 (2026-08-05): three pipelines, not two

Review found the pass was wired into only two of March's **three** check
pipelines. `bin/main.ml`'s `run_check_cmd` (`march check`, `march caps`) is a
third, package-level, typecheck-only path that deliberately skips refinecheck;
the LSP is a fourth consumer of the typechecker that never links
march_refinecheck at all. With the contracted names removed from the syntactic
ban unconditionally, `march check` exited **0** on provably panicky code.

### The fix: a fail-closed opt-in flag

`Typecheck.proof_based_panic_surface : bool ref`, **default false**. When false
the contracted names are banned by name exactly as before 2026-08-05, transitive
fixpoint included; the two proof-capable pipelines set it to true before calling
`check_module`. A pipeline that forgets to opt in therefore gets the
conservative answer, which is the only sound default for a guarantee.

`march check` output on the control corpus is byte-identical to a binary built
from the parent commit — no regression, and no proof-based widening there. The
divergence (`march check` rejects a guarded `List.tail` that `march --check`
accepts) is stated in both capability docs and the changelog.

Route (b) of the two the reviewer offered. Route (a) — running `Refine_check`
inside `run_check_cmd` — was rejected: that path is package-level over every
file at once, is seeded from a cached stdlib typecheck env specifically to stay
fast, and pulling the solver in would change both its cost and its semantics for
a command whose job is a quick well-formedness answer.

### `panic_surface_contracted` moved into `typecheck.ml`

The typechecker now needs the set too, so it owns it and
`Panic_surface_by_proof.covered` aliases the binding. Two hand-maintained copies
could drift into a name banned in *neither* place.

### The five BARE prelude names were inert — now fixed

Measured, not assumed: bare `tail(xs)` **does** resolve for `Refine_check`
(`--refine-report` showed `1 proved` for a guarded call), yet the call was still
rejected with a *transitive* message. `bin/main.ml` unwraps prelude into the
entry module, so prelude's own `fn tail`/`head`/`last`/`unwrap`/`expect` are
`DFn`s of the `cap no_panic` module under check; their bodies call `panic`, so
the fixpoint seeded them and blamed every caller. A transitive verdict never
consults a proof, so the feature was inert for 5 of its 25 names, and the
unguarded form reported twice (direct + transitive).

Fix: `check_no_panic_module`'s `local_fns` excludes `panic_surface_contracted`.
Sound in both modes — with the flag false those names are direct-banned and the
transitive path is never needed; with it true, the proof pass owns the decision.

### The LSP: nested modules DID lose diagnostics, top-level ones never had any

`lsp/lib/analysis.ml` goes through `Typecheck.check_module_with_env`, which —
unlike `check_module_core` — never calls `check_no_panic_module` on the ENTRY
module. So a top-level `cap no_panic` module gets no editor squiggle for any
name, `panic_` included.

A NESTED `mod` is different: `check_decl`'s `DMod` branch does call
`check_no_panic_module` on the inner decls. Nested modules therefore genuinely
lost the contracted names' diagnostics when the syntactic ban was narrowed, and
genuinely regain them from `proof_based_panic_surface` defaulting to false. (A
first pass adjudicated this as "nothing was lost" on the strength of a top-level
probe; that conclusion was right only for top-level modules and is corrected
here and in `specs/lang/capabilities.md`.)

`lsp/test/test_lsp.ml`'s `cap no_panic diagnostics` group pins it with NESTED
fixtures — the only shape where the assertion can fail — and asserts first that
the reference case actually fires (`panic_` IS reported), then that a qualified
and a bare contracted name are reported exactly when it is.

### One error per call site (documented behavior change)

`check_no_panic_module`'s `site_map` held one site per function, so a function
with two unprovable `List.tail` calls reported one error; the proof-based pass
reports two. Verified against the pre-change binary (1 → 2 on a two-call
fixture). Documented in both capability docs and the changelog. Nothing new is
rejected.

`mod_name` provenance was checked for divergence and does **not** diverge: the
typechecker's `env.current_module` and this pass's AST `DMod` name are both the
bare module name, and a nested-module fixture prints `` `mod Inner` `` from
either path.


## Review round 3 (2026-08-05): three Minor closures

- **The LSP test group was vacuous.** Its fixtures were top-level modules, for
  which the LSP emits no panic-surface diagnostic at all, so the
  `reports panic_ = reports List.tail` equality held `false = false` regardless
  of the ban lists. Rewritten with NESTED fixtures (`mod Outer do mod Inner do
  cap no_panic … end end`), plus a leading assertion that the reference case
  fires. Load-bearing: dropping `panic_surface_contracted` from
  `is_direct_panic_site` while keeping `panic_` makes it fail
  (`Expected true, Received false`).
- **The doc sentence was false.** `specs/lang/capabilities.md` claimed the LSP
  reports no panic-surface diagnostics "for *any* name". True only for the entry
  module. Replaced with the nested-vs-top-level distinction; `docs/capabilities.md`
  gained the user-facing version ("trust `march --check`, not the squiggle").
- **Flag mutations are now `Fun.protect`ed** in `test/test_compiler.ml`
  (`typecheck_proof_mode`, `typecheck_with_no_panic_passes`) and
  `test/test_refinecheck.ml` (`no_panic_errors`). A bare reset would leak `true`
  past an exception into the `no-panic-syntactic-fallback` group, whose whole
  subject is the false default — weakening those assertions instead of failing
  them.
