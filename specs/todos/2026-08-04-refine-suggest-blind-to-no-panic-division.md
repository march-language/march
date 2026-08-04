# `forge refine` is blind to the one obligation the compiler tells you how to fix

`[P2]` - [ ] **A `cap no_panic` division produces no suggestion, even though the
compiler's own error names the exact annotation.** `--refine-suggest-all` prints
`no suggestions` for the case a user is most likely to hit first.

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
