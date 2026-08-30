# Counterexample surfacing for refinement failures — design

Date: 2026-08-30. Status: **implemented** (same day); see
`specs/progress/2026-08-30-counterexample-surfacing.md`.

Implementation deviations from the text below:

- **Effect denial** is a builtin-name guard at the evaluator's single
  `VBuiltin` application chokepoint (`Eval_prim.builtin_guard`, checked in
  `apply_inner`), vetoing the typechecker's capability-table names plus
  runtime-family prefixes (`tcp_`, `task_`, `actor_`, …) — not per-builtin
  stub replacement, which cannot reach closures that captured the original
  environment.
- **Division confirmation** checks that the divisor expression's variable is
  zero under an admissible assignment (params' refinements + path facts
  evaluated structurally), rather than executing to the panic — equivalent
  and cheaper.
- The **predicate evaluator** does not apply user measure functions in v1;
  an unknown application makes the obligation unconfirmable, never guessed.
- Under **`cap verified`**, a confirmed violation reports the strong
  Violated error INSTEAD of the "cannot verify" message — the planned
  appended "In fact…" sentence is unreachable, which is strictly better
  (one error, the decisive one).
- **Shrinking** required a strict structural-weight ordering to terminate
  (fixed probes 1 and -1 both confirm in symmetric cases and would
  otherwise oscillate); negatives weigh one more than their magnitude, so
  1 canonically beats -1.
- **`@[trusted]`** keeps rescuing skips (incompleteness) but does not
  suppress a witness-confirmed violation, matching the pre-existing rule
  that Violated is never rescued.

## Motivation

When Z3 refutes a refinement obligation, turning its model into a concrete
failing input *in source terms* is where refinement systems usually lose
users. March today is worse than that: for the most common real failure —
a function body that violates its return contract for **some** inputs —
no counterexample surfaces at all.

```march
fn clamp(x: Int): {Int | _ >= 0} do
  x - 1
end
```

This compiles in silence (or reports "solver-undecided" under `cap
verified`), even though `x = 0` is a trivially findable refutation. The
cause is deliberate conservatism in `lib/refinecheck/refine_post.ml`: the
first `Refine.discharge` **already returns `Refuted` with a model** for
clamp, but the verdict logic discards it unless the *negated* goal is
valid (i.e. the contract fails on every path). The reason is soundness of
blame: unreflectable path conditions are silently dropped from the SMT
query, so a raw SAT model can be spurious — it may violate a path
condition the solver never saw. Reporting spurious counterexamples is
exactly how the trust this feature exists to build gets destroyed.

The fix for both problems is the same mechanism: **validate every
candidate witness by executing it through the tree-walking interpreter**
before reporting it. A confirmed witness is a definite failure — it fits
the checker's existing "report only definite failures" philosophy; it is
just a stronger refutation search. That is why confirmed witnesses are
**errors by default**, not warnings.

## Scope

Two coupled problems, both in scope:

1. **Model extraction** — produce a candidate witness in the
   fails-for-some-input case (today: silence / undecided), and for
   obligations SMT cannot touch at all (unreflectable predicates such as
   `x * y` under a refinement — no query is ever made).
2. **Rendering** — present confirmed witnesses as a source-level failing
   call with concrete values (`clamp(0) returns -1`), not measure-speak
   (`len(xs) = 3`), dropped strings, or hedged `f$ret1` prose.

Four failure sites are covered:

| Site | Today | With this design |
|---|---|---|
| Return contracts (`refine_post.ml`) | silent, or bare "cannot verify" | error with confirmed failing call |
| Call-site preconditions (`refine_call.ml`) | inline `(e.g. b = 0)` from raw model | validated, shrunk, source-syntax values |
| Division/panic safety (`division_safety.ml`) | error without concrete input | "e.g. `safe_div(10, 0)` reaches this division with `b = 0`" |
| `cap verified` undecided obligations | "cannot verify (solver-undecided)" | same message + "In fact the contract is violated: …" when a witness confirms |

## Approach

Composition chosen: **A (validate the model the checker already has) +
eval-side shrinking + C (enumerative fallback for unreflectable
obligations)**. A dedicated solver-side witness-search/optimization query
(approach B) was considered and dropped: eval-side shrinking gives the
same `x = 0` UX without a second solver round-trip.

## Architecture

New module `lib/refinecheck/witness.ml`, entry point conceptually:

```
confirm             : fn_decl -> model:(string * string) list -> obligation_kind -> confirmed option
confirm_enumerative : fn_decl -> obligation_kind -> confirmed option   (* no model available *)
```

`march_refinecheck` gains a dependency on `march_eval` (verified acyclic:
`march_eval` depends only on ast/ctxesc/modules/scheduler/coverage/
doctest, none of which depend on refinecheck or typecheck).

Four stages:

### 1. Decode — SMT model → March values

- Ints, floats, bools: direct (including the `(- 1)` negative form).
- Records: via the existing `ctor_field_names` table
  (`refine_scope.ml`).
- ADT constructors: constructor name + decoded args.
- Lists: from `len` facts plus element facts when the model has them;
  otherwise zero-filled to the stated length (`len(xs) = 3` →
  `[0, 0, 0]`).
- Strings: from `len` facts (`len = 2` → `"aa"`). Today these are
  filtered as opaque `Str!val!N` witnesses and vanish entirely.
- Parameters absent from the model (Z3 don't-cares): zero-value for the
  type (`0`, `0.0`, `false`, `""`, `[]`, first nullary ctor / recursively
  zero-filled ctor).
- Undecodable parameter types (function-typed params, opaque handles):
  skip validation for the obligation → today's behavior.

### 2. Execute — fuel-limited, effect-inert interpretation

Call the function with decoded args through `march_eval` under:

- **Effect stubs**: effectful builtins (IO, net, spawn, clock, random)
  replaced by stubs raising a private `Witness_effect` exception. Hitting
  one → *unconfirmable* → fall back to today's behavior for that
  obligation. Dynamic denial, not a static cap check — simpler and exact.
- **Fuel**: a step-budget hook added to `Eval` (optional countdown
  checked at call/loop points, raising `Witness_fuel` at zero).
  ~100k steps per execution, plus a per-module wall cap so pathological
  modules cannot stall compiles. Exhaustion → unconfirmable.
- **Environment**: the function may call module helpers, so execution
  needs the full module's declaration environment. The refine pass
  already holds the whole module; this is plumbing, not redesign.

A March panic during execution is an *outcome*, not a harness failure:
for a division-safety obligation, panicking at the guarded site **is**
the confirmation. For a return-contract obligation, a panic en route is
not a confirmation of that contract → unconfirmable (surfacing such
panics is a v1 non-goal).

### 3. Check — confirm the actual violation

Evaluate the violated predicate against the actual result (return
contracts), or confirm the failing condition held (preconditions:
argument value violates the predicate; division: the panic occurred at
the obligation's site). Only a real violation confirms. This is what
makes it sound to report models the current code discards.

### 4. Shrink — deterministic, eval-oracle-driven

QuickCheck-style, re-confirming each candidate through stages 2–3:

- Ints: try `0`, then halve toward zero.
- Lists: drop elements, then shrink elements.
- Strings: shorten.
- Bounded (~64 total attempts) and fully deterministic (fixed order, no
  randomness).

So `x = -7719` reaches the user as `x = 0`.

### Enumerative fallback (C)

For obligations with **no model** — unreflectable predicates and
undecided-without-model verdicts — run a fixed, ordered small-value
battery through stages 2–4: per parameter position roughly
`0, 1, -1, 2, …, [], [0], "", "a", false, true, …` (≤ ~12 per position),
with the shared fuel cap. This is the only path that will ever produce a
counterexample for the nonlinear/unreflectable class (`x * y`). It runs
only on the failure paths the checker already visits — it is not a
general fuzzing pass over accepting code. Note that a confirmed witness
here upgrades today's silent accept to an error; that is intended (the
witness is a validated real bug), and budgets keep the cost bounded.

## Diagnostics

A shared source-syntax value printer (eval value → March literal syntax:
`[0, 0]`, `"a"`, `Some(3)`, `{ port: 0 }`) feeds all four sites.
Confirmed witnesses lead with the executed fact; **unconfirmed models
keep today's hedged rendering untouched** (`format_cx` / `cx_block` in
`refine_scope.ml`).

Return contract:

```
`clamp` does not satisfy its return type constraint on all code paths.

The return type requires:

    _ >= 0

but clamp(0) returns -1.
```

Call-site precondition (inline, as today, but validated/shrunk and
source-syntax): `(e.g. this call with xs = [] violates len(_) > 0)`.

Division safety:

```
this expression can panic: divide by zero
    e.g. safe_div(10, 0) reaches this division with b = 0
```

`cap verified` undecided: keep the existing "cannot verify
(solver-undecided)" message, and when a witness confirms, append:
`In fact the contract is violated: clamp(0) returns -1.` — turning "the
checker is weak" into "your code is wrong".

Multi-parameter calls print the full call with all decoded args
(`scale(1, 1) returns 1`) so the line is paste-able into a REPL as-is.

## Severity and behavior change

Outside `cap verified`, a **confirmed** witness is an **Error** — no new
false positives are possible because every reported counterexample was
executed and observed to fail. Clamp-class code that compiles silently
today becomes an error; this gets a CHANGELOG entry (`### Changed`) and
the usual `specs/todos/` → `specs/progress/` lifecycle.

Unconfirmed candidates change nothing: today's verdicts and today's
rendering stand.

## Testing

Reject witnesses are mandatory; accept-only tests prove nothing here
(established project lesson from the capability-walk holes).

- **Reject fixtures** at all four sites asserting the *exact* diagnostic
  text including concrete witness values — this doubles as the
  determinism test: a flaky model, battery order, or shrink order breaks
  the assertion immediately.
- **Spurious-model fixture**: a function whose path condition is
  unreflectable (dropped from the SMT query) where the raw Z3 model
  violates that dropped condition — asserting **no** error, proving
  validation actually rejects spurious models rather than rubber-stamping
  them.
- **Harness units**: decode round-trips (including negatives, records,
  zero-fill); effect stub → unconfirmable; fuel exhaustion →
  unconfirmable; panic-as-confirmation for division; shrink convergence
  (`-7719` → `0`).
- **`refine-oracle`**: baseline before the change, check after; the diff
  over the ~297 fixtures must show *only* the intentional new errors.
  Prove the oracle goes RED on a perturbation before trusting GREEN; run
  under a private `HOME`; clear `.march/cas/vc` once before the verdict
  run.
- **CI text checks**: `@types-check` / `@grammar-check` assert diagnostic
  text and are only meaningful with `--force` (a targetless run exits 0
  with a zero-byte log — assert on the log's contents). Fixture updates
  are deliberate, reviewed diffs.

## Non-goals (v1)

- Emitting runnable repro test cases / `main()` snippets.
- Witnesses for functions that require real effects to execute.
- Surfacing panics discovered while checking a *return* contract.
- LSP-specific presentation (LSP inherits the diagnostic text for free).
- Solver-side optimization/minimization queries.
- Any guarantee of *minimal* witnesses — just small, deterministic ones.
