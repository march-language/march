# `forge refine` is blind to the one obligation the compiler tells you how to fix

**FIXED 2026-08-04.** `[P2]` **A `cap no_panic` division produced no suggestion, even
though the compiler's own error names the exact annotation.** `--refine-suggest-all`
printed `no suggestions` for the case a user is most likely to hit first.

## Repro

```march
mod Probe do
  cap no_panic

  fn safe_div(n : Int, d : Int) : Int do
    n / d
  end
end
```

```bash
rm -rf .march/cas/vc .march/cas/artifacts-v2
march --refine-suggest-all probe.march
```

`--check` on that file says, in as many words:

> division by `d` in `cap no_panic` module may be by zero — no refinement proves `d ≠ 0`.
> […] annotate the divisor parameter with `{v : Int | v != 0}` (or `v > 0`) to prove it is safe.

`--refine-suggest-all` on the same file prints:

```
no suggestions
```

The compiler names the fix; the tool built to propose that exact fix stays silent.

## Cause

Confirmed by reading, not inferred:

1. `precond_infer.walk_debt` measures debt by calling `RC.visit_decls` and then counting
   the obligation ledger (`Obligation.all ()`).
2. `Obligation.kind` is `Precondition | Postcondition` only
   (`lib/refinecheck/obligation.ml:54`), and the only two `Obligation.record` sites in the
   tree are the precondition one (`refine_check.ml:3106`) and the postcondition one
   (`refine_check.ml:4460`).
3. Division safety is a **separate pass**: `Division_safety.check_module` is invoked from
   `bin/main.ml` (two call sites, 1341 and 1973), entirely outside
   `Refine_check.visit_decls`. It records nothing into the ledger.

So for a division-only module `walk_debt` counts **zero**. Assume-and-recheck has nothing
to shrink, `infer_fn` returns `No_debt`, and `suggest_all` drops it — it keeps only
results with `rs_suggestions <> []` (`precond_infer.ml:579`), so the sweep prints the
generic `no suggestions` rather than even the misleading "nothing to prove".

The call-site path is fine and must stay fine. This is the control:

```march
fn safe_div(n : Int, d : { Int | _ != 0 }) : Int do n / d end
fn wrapper(x : Int) : Int do safe_div(10, x) end
```

```
wrapper (probe.march:6)
    x : Int  ->  x : {Int | _ != 0}
  discharges all 1 unproven obligation(s)
```

The gap is narrow and specific: **the propagation case works, the originating case does
not.**

## The fix is feasible — verified

Annotating the parameter really does discharge the obligation, so the candidate the
suggester would have proposed is correct and the assume-and-recheck loop would converge on
it:

```march
fn safe_div(n : Int, d : { Int | _ != 0 }) : Int do n / d end
```

`march --check` on that: **exit 0, no diagnostics.** `Division_safety` already consults
refinements — that is what "no refinement proves `d ≠ 0`" is reporting the absence of.

## Two changes, and the second is the one that is easy to forget

1. **`Division_safety` records its verdicts into the ledger.** Needs a new
   `Obligation.kind` (say `Division`) rather than reusing `Precondition`, because
   `cap verified` escalation and `--refine-report` both branch on kind and would otherwise
   silently change behaviour for existing modules.

2. **`walk_debt` must also *run* `Division_safety` inside its probe walk.** Recording
   alone achieves nothing: `walk_debt` only calls `RC.visit_decls`, so a hypothesised
   refinement would never cause the division pass to re-run and the count would not move.
   A change that does (1) without (2) looks correct in review, leaves every test green,
   and still prints `no suggestions`.

## Watch out for

- **`postcond_infer.prune_with_callers` counts ledger debt across callers.** Adding a
  third obligation kind changes what that sees. A division in a caller must not start
  perturbing postcondition suggestions — assert existing postcondition output is
  unchanged on a module that contains both.
- **The `Skipped` verdict is already counted as debt** (`count_debt` counts everything
  that is not `Proved`/`Trusted`). A solver-undecided division would therefore become
  debt the suggester tries to discharge. That is probably right, but it means a module
  full of undecidable divisions will now spend probe budget where it previously spent
  none — check the per-function budget still terminates on a realistic file.
- **The obligation ledger is process-global** (`Ob.reset ()` at the top of `walk_debt`).
  Running `Division_safety` inside the probe must not disturb the ledger the *real*
  compile later builds.

## Acceptance

- `--refine-suggest-all` on the repro suggests `d : Int -> d : {Int | _ != 0}` and reports
  `discharges all 1 unproven obligation(s)`.
- Applying it with `--apply` yields a file that passes `--check` with exit 0.
- **REJECT witness, required:** a `cap no_panic` module whose division is *already* proved
  safe — either by an existing refinement or by a guard such as
  `if d != 0 do n / d else 0 end` — must still produce **no** suggestion for that
  parameter. Without this, a change that simply proposes `_ != 0` for every divisor-shaped
  parameter passes the positive test while being useless noise on real code.
- A second REJECT witness: the existing call-site propagation case above must produce the
  same output it does today. The two paths must not merge into one that double-counts a
  single obligation.
- Weakest-first ranking still holds: `_ != 0` must be preferred over `_ > 0`, since both
  discharge the obligation and the former is weaker.

## Measurement note

Clear **both** caches before any run that is meant to prove a refinement verdict —
`.march/cas/vc` content-addresses solver verdicts and `.march/cas/artifacts-v2` lets
`--check` exit on an artifact hit *before* refinecheck runs. A stale either way makes this
repro appear to pass or fail at random.


---

# Implementation (2026-08-04)

Both changes the spec called for, and the second one is the one that matters:

1. **`Obligation.kind` gains `Division`**, and `Division_safety.check_var_divisor` records
   one obligation per variable divisor. The verdict is read off the error context
   (`did this call report?`) rather than threaded back through the function's many exit
   paths — under `cap no_panic` anything short of proof *is* an error, so there is no
   `Skipped` middle ground to lose. `Err.report` suppresses exact duplicates, but two
   divisions never share a span, so a real second obligation cannot be swallowed.

2. **`Precond_infer.walk_debt` now runs `Division_safety.check_module`** on the pruned
   tree, in addition to `Refine_check.visit_decls`. `context_decls` already keeps `DOpts`,
   so the probe tree still carries the `cap no_panic` that makes the obligation exist.

**The spec's warning was correct and is now demonstrated.** Reverting only step 2 — keeping
the recording, dropping the probe re-run — puts the output straight back to
`no suggestions` while every other test stays green. That mutation is what the new positive
test catches, and nothing else catches it.

## Result

```
$ march --refine-suggest-all probe.march
safe_div (probe.march:4)
    d : Int  ->  d : {Int | _ != 0}
  discharges all 1 unproven obligation(s)
```

`forge refine --all --apply` rewrites the parameter, and the applied file passes `--check`
with **exit 0**.

`--refine-report`'s by-kind line gained a third counter.

## Tests

`test/test_compiler.ml`, group `precond_infer`:

- `suggests for a cap no_panic division` — the positive case, asserting the weakest
  candidate (`_ != 0`, not `_ > 0`).
- `silent on an already-safe division` — **REJECT witness**, two shapes: a divisor already
  refined, and one guarded by `if d != 0`. A change that proposes `_ != 0` for every
  divisor-shaped parameter passes the positive test and fails this one.
- `division kind leaves the call-site path alone` — second REJECT witness, and it asserts
  `rs_debt_before = 1`. Folding `Division` into `Precondition` would have double-counted a
  single call as two obligations; only this assertion sees that.

Mutation-checked both ways: dropping the probe re-run fails only the positive test;
recording `Violated` unconditionally fails the positive test *and* the already-safe
witness.

## What did NOT change, verified

`Postcond_infer` has its **own** `walk_debt` which does not run `Division_safety`, so no
division obligation enters postcondition probing and its counts are untouched. Confirmed on
a module containing a postcondition candidate and a division together: both surfaces
produce exactly the answer each did before.

675 → 678 compiler tests, all passing.
