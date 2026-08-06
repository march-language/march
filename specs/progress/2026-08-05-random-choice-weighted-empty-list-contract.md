# `Random.choice_weighted` — empty-list panic refined; zero/negative-weight panics deliberately left unrefined

Task 5 of the 2026-08-05 no-panic-proof-based-and-group-b plan.

## The function, and which of its panics are in scope

`stdlib/random.march`'s `Random.choice_weighted(rng : Rng, items : List((a,
Float))) : (a, Rng)` panics on three distinct conditions:

1. `items` is empty (`Nil -> panic("Random.choice_weighted: empty item
   list")`) — **structural**, a property of the list's length. In scope.
2. Every weight in `items` is zero, i.e. the weights sum to zero
   (`panic("Random.choice_weighted: weights sum to zero")`) — **data-dependent**,
   a property of the `Float` *values* inside the tuples.
3. Any single weight is negative (`panic("Random.choice_weighted: negative
   weight")`) — also data-dependent, same reason.

Per the plan's Global Constraints, a data-dependent panic is out of scope for
this plan: "these stay banned-and-unrefined; do not attempt to force a
refinement onto them." Conditions 2 and 3 were investigated (both panic sites
read directly, `stdlib/random.march:286` and `:289`, plus the internal
`pick_by_cumulative` helper's own `Nil -> panic("...empty or degenerate
weights")` fallback at line 259, which is unreachable from a public caller once
condition 1 is refined and total > 0) and deliberately left unrefined: no
measure over a `List((a, Float))` can express "the sum of the second tuple
component across all elements is positive" or "every second tuple component is
non-negative" — those are arithmetic facts about the payload, not a structural
shape fact like length, and this plan's refinement machinery (Tier 1/Tier 2
induction over `len`/user `@[measure]`s driven by ADT structure) has no way to
state or discharge them. This is the same reasoning already applied in this
plan to `Stats.linear_regression`'s zero-variance panic and
`Stats.correlation`'s zero-stddev panic — recorded here again so a future
reader does not reopen the question for `choice_weighted` specifically.

Only condition 1 is addressed by this task.

## The contract

Same shape as `Random.choice`'s existing `{List(a) | len(_) > 0}`, applied to
the tuple-element list:

```march
fn choice_weighted(rng : Rng, items : {List((a, Float)) | len(_) > 0}) : (a, Rng) do
```

(`stdlib/random.march:281`, formerly `items : List((a, Float))`.) The
docstring above the function was also updated to state the empty-list
precondition explicitly and to note that the weight conditions remain
runtime-only checks.

## `len` over a tuple-element list — empirically confirmed, not assumed

This is the first task in this plan to put a refined list parameter's element
type at a tuple rather than a bare type variable or ADT. `len` is generic over
any `List(_)` value (it pattern-matches `Nil`/`Cons`, indifferent to what the
`Cons` head actually contains), so it was expected to resolve the same way —
but the brief required confirming a **positive discharge**, not just a clean
compile, since a prior task in this plan (`Array.length`) showed a contract can
compile clean while silently proving nothing.

Fixture (`/tmp/t5-nopanic/fixture_guarded.march`, outside `stdlib/` per the
sweep-control requirement below):

```march
mod FixtureG do
  cap no_panic
  fn pick(rng : Random.Rng, items : List((Int, Float))) : (Int, Random.Rng) do
    if List.length(items) > 0 do
      Random.choice_weighted(rng, items)
    else
      (0, rng)
    end
  end
end
```

`./_build/default/bin/main.exe --refine-report --compile -o /tmp/... fixture_guarded.march`:

```
refinement obligations (user code): 1 proved, 0 violated, 0 trusted, 0 skipped
  by kind: 1 precondition, 0 postcondition, 0 division
```

**1 proved, 0 violated** — a real discharge of `len(_) > 0` over
`List((Int, Float))`, not merely "no error reported." Confirmed.

## TDD cycle

**RED** (before any change, `.march/cas/artifacts-v2` and `.march/cas/vc`
cleared once beforehand): an unguarded call inside `cap no_panic` compiled
clean under both `--check` and `--compile`:

```march
mod Fixture do
  cap no_panic
  fn pick(rng : Random.Rng, items : List((Int, Float))) : (Int, Random.Rng) do
    Random.choice_weighted(rng, items)
  end
end
```

`--check`: exit 0, no diagnostics. `--compile`: exit 0, binary produced. This
is exactly the "call that can genuinely panic compiling clean" failure mode
the plan's Global Constraints call out as serious.

**Implementation:**
- `stdlib/random.march:281` — contract added (see above).
- `lib/typecheck/typecheck.ml`'s `panic_surface_contracted` — added
  `"Random.choice_weighted"` alongside the existing `"Random.choice"` entry.
  This is the ONLY list edited: `Panic_surface_by_proof.covered`
  (`lib/refinecheck/panic_surface_by_proof.ml`) is a structural alias of
  `panic_surface_contracted` (`SS.of_list ... |> StringSet.fold ... `), not a
  second hand-maintained list, so disjointness between the syntactic ban lists
  (`panic_surface_all_direct`, `panic_surface_stdlib`) and the proof-based
  covered set holds automatically — verified `Random.choice_weighted` does not
  appear in either ban list before or after this change.

**GREEN** (same fixtures, after rebuild — note: rebuilding `bin/main.exe`
alone via a targeted `dune build --root . bin/main.exe` does NOT restage
`stdlib/*.march` into `_build/default/stdlib/`; a full `dune build --root .`
was required, confirmed by `grep`-diffing `_build/default/stdlib/random.march`
against the source before trusting any of these results — see
`project_build_stdlib_missing_copies.md` in the operator's memory, this is a
recurring trap):

- Unguarded fixture: `--check` and `--compile` both now exit 1 with
  `` `pick` in `mod Fixture` (declared `cap no_panic`) calls
  `Random.choice_weighted`, which can panic. `` plus the
  `precondition len(_) > 0 ... was NOT verified here` hint.
- Guarded fixture (`fixture_guarded.march` above): `--check` exits 0 (proved,
  silent) — the positive discharge.
- `march check` (the typecheck-only subcommand, distinct from the `--check`
  flag) on the SAME guarded fixture: exit 1, still reporting the call — this
  is the documented, intentional divergence (that pipeline never builds a
  verdict index, so it stays conservative). Confirms the two-pipeline design
  is intact for this new name, not just for `List.tail`.

## Load-bearing mutation

Reverted only the contract (`{List((a, Float)) | len(_) > 0}` back to plain
`List((a, Float))`) via a file-copy swap (not `git stash`, per repo
convention), rebuilt (full `dune build --root .`, for the restaging reason
above), and re-ran the guarded fixture: it now errors (exit 1, same message as
the unguarded case) — the contract, not some other artifact of the change, is
what was making the guarded call provable. Restored the contract and rebuilt
again; re-confirmed both fixtures back to their GREEN states before proceeding.

## OCaml unit tests (`test/test_refinecheck.ml`)

Added a `stdlib_random_mod` loader (mirrors the existing `stdlib_list_mod`)
and `no_panic_errors_with_random`/`has_no_panic_error_random` (mirrors
`no_panic_errors`/`has_no_panic_error`, extended to prepend the REAL
`stdlib/random.march` as a sibling `DMod` alongside `list.march` and prelude —
the real file, not an inline stand-in, so the claim under test is the shipped
contract). Three new cases appended to the `no-panic-by-proof` group:

- "a PROVABLY safe Random.choice_weighted (guarded) compiles clean" — ACCEPT.
- "an unguarded Random.choice_weighted still errors" — REJECT control.
- "an UNDECIDABLE Random.choice_weighted call still errors (fail-closed)" — a
  `Bool` flag guard (not a length check), matching the `List.tail`
  undecidable case's shape.

One new case appended to `no-panic-syntactic-fallback`: "a GUARDED
Random.choice_weighted is also banned (no prover here)", confirming the
`march check`/LSP-mode divergence for this name specifically.

`./_build/default/test/test_refinecheck.exe`: exit 0, 505 tests run, `Test
Successful` (was 502 before this task's additions — the four new cases plus
one pre-existing failure-mode count did not change).

## Stdlib + ecosystem sweep

`grep -rn "choice_weighted" stdlib/ test/`: one production call site,
`stdlib/gen.march:390` (`Gen.frequency`). `mod Gen` does **not** declare `cap
no_panic`, so this call is unaffected — verified by reading the module header
(`stdlib/gen.march:20`, no `cap no_panic` line). The two stdlib modules that DO
declare `cap no_panic` (`stdlib/json_stream.march`, `stdlib/array.march`)
contain no `Random.` calls at all (`grep -n "Random\."` on both: empty).
Ecosystem checkouts (`conduit`, `test_conduit_app`) contain no
`Random.choice_weighted` call at all (only unrelated JSON index/phase files
matched the substring "choice_weighted" and were false-positive path noise,
not March source).

Positive control (per the plan's Global Constraint that a byte-identical diff
with no positive control proves nothing): the RED/GREEN fixtures above are
that control — the exact same source text (`fixture_unguarded.march`)
compiled clean before this change and errors after it, on the same binary
build process, which is what makes the "no stdlib module regressed" claim
above a measurement rather than a vacuous no-op.

**`Random.choice`'s behavior is unchanged** — confirmed with
`fixture_choice.march` (guarded `Random.choice` call, unrelated to this task's
edits) both before and after: exits 0 in both cases, `--refine-report` shows
the same 1-proved obligation shape it did before this task touched anything.
`panic_surface_contracted`'s only edit was an ADDITION of
`"Random.choice_weighted"`; `"Random.choice"`'s own entry, spelling, and
position were not touched.

## Full suite

`scripts/run-tests.sh` (foreground, redirected, judged by `$?`): full result
recorded in the commit's CI run / operator transcript. `run_compiler.exe -e`:
727 tests, `Test Successful`, exit 0. `run_stdlib.exe -e`: 830 tests, 1
failure — `adversarial-regressions #40 MARCH_SANITIZE`, the pre-existing
host-wide ASAN-hang flake this plan's operating notes call out by name as
unrelated to any task in this plan (mechanism check: the changed files here
are `stdlib/random.march` and `lib/typecheck/typecheck.ml`; that adversarial
regression exercises an unrelated sanitized binary and does not reach either
file). `test_stdlib_march.exe`: 56 tests, `Test Successful`, exit 0 (covers
`test/stdlib/test_random.march`'s existing `choice_weighted` behavioral tests
— unchanged, since the contract only adds a compile-time precondition and
neither test supplies an empty list). `test_refinecheck.exe`: 505 tests, `Test
Successful`, exit 0.

## Files changed

- `stdlib/random.march` — contract on `choice_weighted`'s `items` parameter;
  docstring updated to state the empty-list precondition and note the
  remaining runtime-only weight checks.
- `lib/typecheck/typecheck.ml` — `"Random.choice_weighted"` added to
  `panic_surface_contracted`.
- `test/test_refinecheck.ml` — `stdlib_random_mod`,
  `no_panic_errors_with_random`, `has_no_panic_error_random`, three cases in
  `no_panic_proof_suite`, one case in `syntactic_fallback_suite`.
- `docs/capabilities.md`, `specs/lang/capabilities.md` — `Random.choice_weighted`
  added to the contracted-names list; a new paragraph in each stating the
  zero-weight/negative-weight carve-out explicitly.
- `CHANGELOG.md` — `Random.choice_weighted` added to the existing `### Changed`
  bullet's list of newly-proof-checked partials.
- This file.
