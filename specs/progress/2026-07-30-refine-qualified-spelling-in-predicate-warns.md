# A qualified spelling inside a predicate no longer enforces nothing silently

Landed 2026-07-30.

**At landing:** `test_refinecheck` 383 (was 379, +4 `qualified-predicate` tests).
Typing corpus 238/238 (was 237/237, +1 accept `t136`). `run_compiler` 619,
`run_codegen` 520, `run_eval` 256, `run_snapshots` 33, `run_stdlib` 826 with
only the pre-existing environmental `MARCH_SANITIZE` failure, grammar corpus
45/45 — all unchanged.

**What changed.** `{List(Int) | List.length(_) > 0}` parses, typechecks, and
enforces nothing. The `List.length`→`len` alias (2026-07-28) keys on a dotted
`EVar`, which is what the *desugarer* produces — but refinement predicates are
never run through the expression desugarer. `Desugar.respan_ty`
(`lib/desugar/desugar.ml:1093`) is the only place in desugar that touches
`A.TyRefine`, and it only respans; verified by grep, not assumed. So inside a
predicate `List.length` stays an `EField` chain, the alias never fires, and the
obligation is skipped — silently, because skipping is silence by default. The
contract reads as working and checks nothing, which is precisely the failure
mode this area keeps producing.

`warn_predicate_expr` now matches `A.EApp (A.EField _, …)` ahead of its generic
`EApp` case and warns once, rendering the chain back to a string via a new
`qualified_name` (which also handles the uppercase leading segment — `List`
parses as a zero-arg `A.ECon`, not an `A.EVar`) and naming the bare measure
that works, taken from `measure_alias` where one exists. Confirmed on both
qualified measures: `List.length` and `String.byte_size` each warn and each
suggest `len`.

**Warning, not error — deliberate.** This shape compiles today, so promoting it
would break working builds, and the defect is the *silence*, not a missing
capability: the bare spelling has always worked. Desugaring predicates properly
is the real fix and a much larger change with its own regression surface; it
stays open in `specs/todos.md` rather than being closed by this task.

**Sweep.** Zero of the stdlib's 111 modules warn. That zero is only worth
stating because the instrument was proved to fire first: the same grep on a
deliberately-qualified probe returns 1. A sweep that cannot produce a positive
is not evidence.

**Two defects the review caught, both in the remedy rather than the
detection.** First, the suggested spelling was derived from `measure_alias`,
which is *gated on the stdlib-ownership refs* — so in a unit that defines its
own `List.length` (alias withdrawn) it fell back to the last dotted segment and
advised `length`, which is not predicate vocabulary at all: following the advice
only swapped this warning for the unknown-name one, contract still enforcing
nothing. The remedy now comes from `qualified_measure_spelling`, which is
independent of withdrawal, because "what should the author write" and "does this
alias hold right now" are different questions — a withdrawn alias is a separate
problem with its own attribution machinery. Second, `qualified_name` accepted a
bare `A.EVar` receiver, which `flatten_module_path` deliberately does not, so an
ordinary record-field call (`{Cfg | c.cb(1) > 0}`) was reported as "a qualified
call" offering `cb` as a bare spelling — wrong on both counts. It enforces
nothing either way (`smt_of` has no arm for an applied field access), but a
false explanation costs more than silence. The `EVar` base case is gone.

Four new tests (`qualified-predicate` in `test/test_refinecheck.ml`),
non-vacuous — verified by reverting `refine_check.ml` alone against the kept
tests: case 1 (the warning) FAILED pre-fix, case 2 (the false-positive control,
that the bare spelling stays quiet) passed both before and after, and the two
regression cases for the defects above both FAILED against the pre-review code
and pass now. The warning-text assertion also pins the whole remedy clause
rather than `contains m "len"` — `"len"` is a substring of `"List.length"`, so
that conjunct was implied by the first and asserted nothing. Witnessed by
`accept/t136_refine_qualified_predicate_warns`, whose *exit code* is the
content: a warning does not change `--check`'s status, so t136 pins that the
qualified spelling stays exit 0 and guards against promoting it to an error by
accident. The warning text cannot be pinned in the corpus at all
(`check_types.sh` asserts only exit 0 for `accept/`, substrings for `reject/`
alone), so it lives in alcotest.
