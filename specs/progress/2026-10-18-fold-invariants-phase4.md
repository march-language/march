# Accumulator invariants for fold-shaped calls, phase 4: the annotated accumulator

Landed 2026-10-18. Design: `specs/2026-10-18-fold-accumulator-invariants-design.md`, phase 4 of
§8 (option iii; the user's decision 1 ships it as its own PR). Built on `56be54964` (fold
phases 1-2, abstract-refinement leftovers A-E, element-flow phases 0-3). Independent of phase 3
(stdlib fold signatures): everything here runs through `List.fold_left`/`fold_right` and local
folds, which phases 1-2 already handle.

## What a user sees

```march
fn count(ys : List(Int)) : Int do
  let s = List.fold_left(ys, 1, fn (acc : {Int | _ > 0}, _x) ->
    let _u = need_pos(acc)        -- was unconstrained-subject; proved (acc assumes it)
    acc + 1)
  need_pos(s) + need_nn(s)        -- was unconstrained-subject twice; proved (s carries it)
end
List.fold_left(ys, 0, fn (acc : {Int | _ > 0}, _x) -> acc + 1)  -- skip, accumulator-base-unproved
List.fold_left(ys, 1, fn (acc : {Int | _ > 0}, _x) -> acc - 1)  -- skip, accumulator-step-unproved
```

Before, the annotation was silently neither checked nor assumed (f18): no obligation, so a
`cap verified` module with a false annotation and no demand on the fold was accepted.

## The rule, and the verdict when the annotation fails

`g(…, fn (acc : {T | I}, x) -> step)`, where `g`'s declared return is a bare type variable `b`
and `acc`'s arrow-chain domain is exactly `b`, is an explicit invariant:

- **Obligation** (one per call, on the parameter's name, callee `g`, kind precondition): the
  phase-1 judgment with `I` for the demand. Base: every source of `b` meets `I` (the initial
  value). Step: `I` of every `b`-typed parameter gives `I` of every tail. Run by the existing
  `discharge_pairs` over the arguments with that one annotation ERASED, so `invariant_params`
  hypothesises `I` instead of declining on an own annotation.
- **Proved**: (1) the lambda's body is walked with `acc` ASSUMING `I` (its siblings take their
  element fact or nothing, as any lambda argument); (2) the call's result carries `I`: a
  per-lambda-span table (`Refine_resolve.annotated_acc_facts`) that `postcond_of` consults,
  filled when the walk visits the call, so a `let` binding the call gets `I` as a scope fact.
- **Not proved: a SKIP, never a violation**, with `accumulator-base-unproved` /
  `accumulator-step-unproved` and phase 1's detail; an error under `cap verified` (its own
  message: "cannot verify the accumulator invariant `I` annotated on `acc` (passed to `g`)").
  The annotation is then assumed nowhere: not in the body, not of the result. This is the
  design's §8 phase-4 text ("recorded with the `accumulator-*` reason and not assumed") and its
  §3.5 stance: a failing base is data dependent (harmless on `[]`), and a refuted step is a fact
  about the candidate invariant, not the program. The annotation is a user claim the checker
  could not establish, which is exactly what a skip records; `cap verified` makes it an error.
- **With a demand `D` on the call too** (an argument, a return tail; both reach
  `scalar_demand`): check `I`, then `I ⇒ D` (one query over a fresh `$r` carrying `I`). If
  either fails, `D` is tried as the invariant on its own (phase 1) over the arguments with the
  annotation erased. Both routes are sound on their own: the second never assumes the
  annotation, only `D`, by phase 1's argument. So t385 (`acc : {Int | _ > 100}`, base 1) stays
  rejected: the annotation's base fails (its own skip), and `D = _ > 0` fails its step
  `acc - 50` (the demand's skip).

Gates (`annotated_acc_of`): `g` resolves to a top-level definition, `parametric_ok ctx g [b]`
(P1/P2) and `invariant_callee_ok` (not an adopted `impl` method, not `@[assume]`, not
`@[trusted]`), the same gate as the demand rule. Shape: the lambda's parameters (peeled to the
chain if curried) number exactly the chain; exactly one `b`-typed parameter carries a
refinement, and it is a scalar one (`refined_param_ty`), not a wildcard; the lambda is one no
pass site obliges (`pass_site_obligation = None`). Anything else declines and the annotation
stays inert, exactly as before. The existing guards apply unchanged inside the discharge: the
capture/shadowing guards (a lambda parameter spelled like a name `I` mentions declines), the
`let?`/`let*` decline, `lambda_tail_rebinds`.

**The element parameter's annotation** (`fn (acc, x : {Int | _ > 0})`) is not an invariant of
anything: `x`'s domain is `a`, so the annotation is a claim about the list's elements, which
nobody checks. It stays neither checked nor assumed (no obligation; erased in the discharge, as
before). Beside a proved accumulator annotation it is still erased (pinned).

## Code

- `lib/refinecheck/refine_check.ml`
  - `type annotated_acc`, `annotated_acc_of ctx defs cb ~span g sg args` (the shape and gates
    above; returns the arguments with the annotation erased, wherever the curried peel found
    the parameter).
  - `record_acc_invariant`: the obligation, and its `cap verified` error.
  - `annotated_invariant` (in the recursive group): `discharge_pairs` with
    `[(b, Refined I)]` over the erased arguments.
  - `implied_by`: `I ⇒ D`, scratch ledger and throwaway error context like
    `discharge_pairs`' sub-checks.
  - `scalar_demand`: the phase-4 route before the demand route (above).
  - `visit`'s `EApp` arm: the obligation once per call, the table entry (added on proof,
    removed otherwise), and a first lambda-argument arm that walks a proved accumulator's body
    with its annotation assumed.
  - `visit_fn` and `check_module` reset the table: an entry is read only by the walk that
    proved it, after the call was visited. An inline use (`need_pos(fold(…))`) is checked
    before its arguments are visited, so it never reads the table; it goes through
    `scalar_demand`, which checks `I` itself. Deterministic either way.
- `lib/refinecheck/refine_resolve.ml`: `annotated_acc_facts` (keyed by the lambda's span AND
  checked against the lambda node by physical equality, so a substituted copy of the lambda
  in another scope never matches), `annotated_acc_fact`, and `postcond_of` = the old body
  (`postcond_of_declared`) then the table. Still solver-free.
- `Refine_audit` is unchanged: it already classifies a scalar `Lambda_param` refinement as
  `Enforced` (the classification predates this; phase 4 is what makes it true for the
  accumulator shape). No audit baseline moved.

## Tests

`test/test_refinecheck.ml`, group `fold-invariants-4` (33 cases, ledger triples, the
(callee, verdict, reason) sequence where it matters, reasons and detail text). On `56be54964`
(the final test file built against the base library in a detached worktree) **25 of 33 were
RED**: the 13 proof rows (f18 body assumption, a `let`-bound result, used twice, inline demand
equal / implied, the fallback to `D`, a return tail, `x`'s element fact beside the annotation,
`fold_right`, a curried inner accumulator, a relational `_ >= lo` over a capture, a sibling
`b` parameter, f18 under `cap verified`), and 12 controls whose triple changed because the
annotation is now an obligation of its own (t385's shape (0, 0, 1) -> (0, 0, 2), base fails,
step breaks, `acc + x` over unrefined `x`, the holds-but-does-not-imply row, the element
annotation beside a proved one, both retirement rows, another call of the callee, the VC pair,
the shadowing guard, the `@[trusted]` row's unmarked control). GREEN on both, as pins: the
element-parameter annotation, two annotated `b` parameters, the one-parameter lambda (still a
pass-site violation), a `let`-bound lambda, and the impostors (constant, step fed a built `b`,
unannotated `f`, interface method).

`fold-invariants-1`'s "guard: an accumulator's own refinement …" (the t385 shape) is
updated: (0, 0, 1) with the decline detail becomes (0, 0, 2), the demand's step skip then the
annotation's base skip. Still no proof.

Perturbations (each applied, built, the three fold groups run, restored, rebuilt):

| Perturbation | Goes red |
|---|---|
| table lookup off (`annotated_acc_fact` never matches) | the 12 rows that need a `let`-bound result's fact: let-bound, used twice, `x`'s element fact, `fold_right`, curried, relational, sibling `b`, `cap verified`, the element annotation beside a proved one, another call of the callee, the VC pair, the `@[trusted]` row's unmarked control. The inline, tail and fallback rows stay green (the demand route), and so do the retirement rows (nothing to retire) |
| body assumption off (no assumed walk) | f18 and f18 under `cap verified` |
| `annotated_invariant` always `Proved` | t385's shape, base fails, step breaks, `acc + x` over unrefined `x`, the VC pair's second half, the shadowing guard, and fold-1's t385 row: each would assume or carry a false annotation |
| phase-4 branch of `scalar_demand` off | the inline, implied, fallback and return-tail rows |
| fallback over the UN-erased arguments | the fallback row (the demand route declines on the own annotation) |
| `implied_by` always true | the holds-but-does-not-imply row, `(1, 0, 0)` would be a FALSE proof: `foldl([], 0, …)` is 0 |
| P1/P2 gate off in `annotated_acc_of` | the constant, built-`b` and interface impostors (the unannotated-`f` impostor is blocked by the shape: `f` has no declared arrow) |
| `invariant_callee_ok` off | the `@[trusted]`/`@[assume]` row |
| pass-site exclusion off | the one-parameter row |
| two annotated `b` parameters: take the first | the two-annotation row (its triple; the second annotation still declines the hypothesis, so not a false proof) |
| physical-equality check off, table reset off, table removal off | nothing: belt-and-braces (no corpus or test walks one lambda twice in different contexts) |

Conformance: `accept/t450_refine_fold_annotated_accumulator` (`List.fold_left` with body
assumption and a twice-used `let` result, a relational capture, `List.fold_right`, an inline
implied demand, a return tail, under `cap verified`; REJECTED on `56be54964`: seven skips),
`reject/t451` (base fails; rejected on the base too, for `need_pos(s)`; pins the annotation's
message) and `reject/t452` (step breaks, no demand; ACCEPTED on the base: the annotation filed
nothing). `reject/t385`'s comment updated (still rejected). The corpus is 485/485 (203 accept,
282 reject).

## Verification

- `test_refinecheck.exe -e` in one run (private `HOME`, VC cache cleared once): 1342 tests, all
  pass, 499 s (`audit-baseline` and `z3-well-formed` included).
- `scripts/run-tests.sh -q compiler`: 1348 tests, all pass.
- `specs/lang/types/check_types.sh` (private `HOME`): 485 passed, 0 failed.
- `scripts/check-docs.sh`: passes.
- `scripts/refine-oracle.sh`: baseline from a detached `56be54964` worktree at the same
  directory depth (stdlib staged), check here: **identical**, 8726 lines over 549 fixtures.
  Blind to this change by construction: no file in `stdlib/`, `test/native/` or `test/stdlib/`
  annotates a lambda parameter with a refinement at all (grep), so no fixture reaches the rule.
- `stdlib/list.march` `--check --stdlib-source --refine-report` (CI's ratchet): byte-identical
  to the base (35 proved, 0 violated, 1 skipped for user code; 37 user + stdlib skips).
- Timing, the same command, private `HOME`s, VC caches cleared once, a first pair then five
  interleaved A/B rounds, load average 8.9 (15-min 23): first pair 1.147 / 1.170 s; base median
  1.120 s, this change 1.101 s (noise; well within the 110% budget). The rule costs one
  discharge per annotated fold call, plus the `I ⇒ D` query and possibly the `D` discharge at
  a demand; `list.march` has none.

## Where this departs from the design, or decides what it left open

- **Inline demands go through `scalar_demand`, not the table.** The design says the result
  fact is a table `postcond_of` consults; that covers a `let`-bound result. An inline use is
  checked before its arguments are visited, so the scalar entry checks `I` itself (the same
  discharge, scratch ledger) and then `I ⇒ D`; the annotation's own obligation is recorded
  once, when the walk visits the call.
- **The fallback to `D` alone** when `I` fails or does not imply `D` is a decision this PR
  made (the design says "check I, then I ⇒ D" only); it loses no proof phase 1 had.
- **A return tail through a `let`** (`let s = fold(…); s` against a declared return) carries
  nothing: the postcondition walk runs before the body walk fills the table. A direct tail
  proves. Filed.
- **Container annotations, one-parameter lambdas (and the outer lambda of a curried
  `Enum.fold` step), two annotated `b` parameters, `Option(b)` returns, `let`-bound lambdas,
  and annotations passed to non-parametric callees** are declined and stay inert: filed as
  `specs/todos/2026-10-18-refine-annotated-accumulator-declined-shapes.md`. The last one means
  a `cap verified` user still gets no error for an annotation on an impostor fold's step.
- **A named step's parameter refinement** is not read as the invariant (decision 4 of the
  design: a named step contributes only its closed return, with its preconditions checked by
  `named_preconds`).

## Left open

- Phase 3 (stdlib fold signatures), concurrently with another builder; nothing here depends
  on it, and `Map.fold`/`Set.fold`/`Array.fold_left` will take an annotated accumulator once
  they declare `b`.
- The declined shapes above.
