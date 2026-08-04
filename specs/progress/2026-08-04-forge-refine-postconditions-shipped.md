# `forge refine` should suggest postconditions, not just preconditions

`[P2]` - [x] **Shipped.** Verified 2026-08-04, after this todo was written: the feature
described below now exists, built to the architecture this todo prescribed.

- `lib/refinecheck/postcond_infer.ml` exists and uses `RC.check_fn_post_verdict ~emit:false`
  (`postcond_infer.ml:183`) as the truth oracle — the same real-checker postcondition oracle
  `gate_unverified_posts` uses. It explicitly does **not** use `Return_infer`'s parallel Z3
  probing; `postcond_infer.ml:25` says so in as many words, honoring the "no parallel prover"
  constraint this todo called out.
- It is wired into the compiler at `bin/main.ml:996` (`print_refine_postconditions`) behind
  `--refine-suggest-post` / `--refine-suggest-post-all`.
- `forge refine --postconditions` is a documented flag (`forge/lib/cmd_refine.ml:443`).
- **Smoke test** (this todo's own worked example), run against a freshly built compiler with
  caches cleared:

  ```march
  mod P do
    fn need_pos(n : {Int | _ > 0}) : Int do n end
    fn produce(x : {Int | _ > 0}) : Int do x end
    fn go(x : {Int | _ > 0}) : Int do need_pos(produce(x)) end
    fn main() do println(int_to_string(go(3))) end
  end
  ```

  `march --check --refine-suggest-post-all p.march` emits, for `produce`:

  ```
  produce (p.march:3)
      returns Int  ->  returns {Int | _ > 0}
    discharges all 1 obligation(s) across 1 caller(s)
  ```

  — exactly the composition case this todo's "payoff" section predicted.

- **`--fixpoint` composition (this todo's open question):** `forge/lib/cmd_refine.ml:443-503`
  shows `Cmd_refine.run`'s `once ()` closure (line 465-469) dispatches on the `postconditions`
  flag to call `run_posts` instead of `run_once` *inside* the fixpoint `loop` (line 486-503).
  Because the fixpoint loop calls `once ()` every round regardless of which mode it dispatches
  to, `--fixpoint --postconditions` now repeats postcondition inference round over round the
  same way it already repeated precondition inference — the todo's claim that "`--fixpoint`
  today walks only the first direction" no longer holds; both directions now fixpoint. (A
  live end-to-end `forge refine --postconditions --fixpoint --apply` run against a scratch
  project was inconclusive in this environment only because `forge` shells out to the `march`
  on `PATH`/`MARCH_HOME` rather than this worktree's freshly built binary — a known toolchain-
  resolution trap, not a gap in this feature. The code-level composition finding above does
  not depend on that run.)

## Why this existed

`return_infer.ml` was written 2026-06 and has never been called by the product. Its own
header says it is "used by the IDE and documentation generator"; neither ever used it. It
is reachable only from `test/test_compiler.ml`. This is dead code that describes a feature
nobody can run.

## The payoff is real, and measured

A declared postcondition discharges obligations in the *caller*. Same module, only
difference is whether the return is refined:

```march
fn need_pos(n : {Int | _ > 0}) : Int do n end
fn produce(x : {Int | _ > 0}) : Int do x end                 -- 1 proved, 1 SKIPPED
fn produce(x : {Int | _ > 0}) : {Int | _ > 0} do x end       -- 3 proved, 0 skipped
```

That is the whole case for building this. `gate_unverified_posts` in
`lib/refinecheck/refine_check.ml` already lets a **positively verified** postcondition be
assumed at call sites; nothing else in the toolchain helps an author discover which
postcondition to write.

## The composition argument

`forge refine` currently proposes preconditions only, and those propagate **up** the call
graph — a caller must promise more. Postconditions propagate **down**: a callee guarantees
more, so its callers prove. `--fixpoint` today walks only the first direction.

With both, one sweep reaches debt neither direction reaches alone. It is also the obvious
answer to the `Partial` status ("discharges 2 of 3"): the stuck obligation is often a fact
about a *callee's return*, not about a parameter, and today the tool has nothing to say
about it.

## Architecture — and the one place the existing design does NOT transfer

`precond_infer` is assume-and-recheck: hypothesise a refinement, re-run the real checker on
**this function**, keep the candidate if this function's debt shrank. That model does not
carry over unchanged, because **a postcondition does not discharge its own function's
debt** — it discharges *callers'*. Two separate questions have to be answered, and
conflating them is how this feature would ship as noise:

**(a) Is the candidate TRUE?** Use `check_fn_post_verdict ~root errctx ~emit:false fd`,
which already exists and is the real checker's own postcondition oracle — the same one
`gate_unverified_posts` uses to decide whether a declared postcondition may be assumed.

  Do **not** use `return_infer`'s Z3 probing for this. It builds its own VCs, which is
  precisely the parallel-VC-generator hazard `precond_infer` was designed to avoid: a
  second prover that can drift from the real one, where the drift shows up as a suggestion
  the checker then refuses. Its own header already hedges the results as "informational".

**(b) Is the candidate USEFUL?** Measure the ledger delta over the function's **callers**,
not itself. A true-but-useless postcondition (nothing anywhere needed it) is noise, and
proposing it would repeat the mistake `contradicts_handled_case` exists to correct:
provable is not the same as good advice.

This means the pruning strategy changes. `Precond_infer.prune` reduces the walk to the
target function plus context-bearing decls, which is what makes probing affordable. For
(b) the walk must include the callers, so either:

- reuse `forge search --callers` to find them and prune to *target + callers*, or
- accept a whole-module re-walk per candidate and rely on the VC cache.

Measure before choosing. `precond_infer`'s probes are ~free relative to the one pipeline
run; if a caller-inclusive walk is not, the budget mechanism already exists to bound it.

## What survives of `return_infer`

Realistically, its **candidate list** — the six sign predicates. Its VC construction should
be retired in favour of (a), and its `infer_module` entry point has no callers to keep
compatible. Say so explicitly when landing this rather than leaving a second inference
engine in the tree; a module that exists but is never called is what produced this todo.

## Known limitation to design around

`clause_refined_params` filters to **Int-refined** parameters, and `infer_fn` returns
`None` when a function has none. So the existing inference only fires on functions that
*already* carry Int contracts — it cannot bootstrap from an unannotated codebase, and a
sweep over today's stdlib would mostly return nothing.

That is compatible with the composition story (refine parameters first, then returns
follow) but it must be stated in the UI: a `no-candidate` here often means "this function
has no refined parameters to reason from", which is a different fact from "no postcondition
holds". `precond_infer`'s status vocabulary (`No_debt` / `Solved` / `Partial` /
`No_candidate` / `Budget_exhausted` / `Not_found`) already sets the precedent that these
outcomes must be distinguishable rather than collapsed into silence.

## Surface

Extend the existing command rather than adding one:

```sh
forge refine <fn>                  # preconditions (today)
forge refine <fn> --postconditions # returns as well
forge refine --all --apply --fixpoint
```

`--apply` needs a splice for the **return** position. `March_refactor.Refine_edit`
currently locates a *parameter's* annotation; the return annotation is a different scan
(after the `)` of the parameter list, before `do`). Same discipline applies: textual, exact
byte range, re-parse before writing, shared with the LSP so both produce identical edits.

## Acceptance

- The `produce`/`need_pos` pair above: `forge refine produce --postconditions` proposes
  `{Int | _ > 0}`, and applying it takes the module from 1 proved / 1 skipped to 3 proved /
  0 skipped — verified with `--refine-report`, not by the tool's own say-so.
- **REJECT witness (usefulness):** a function whose postcondition is provable but which no
  caller needs must produce NO suggestion. Without this the sweep fills up with true
  irrelevancies, and there is no way to tell that from working.
- **REJECT witness (truth):** a function whose candidate postcondition does not hold must
  produce no suggestion — i.e. `check_fn_post_verdict` is genuinely consulted. Mutate it to
  return `true` unconditionally and confirm a test fails.
- **REJECT witness (no parallel prover):** the suggestion and `march --check` must agree.
  A proposed postcondition that `gate_unverified_posts` then strips is the exact drift this
  design is meant to prevent.
- A stdlib sweep reports its outcome honestly: given the Int-refined-params limitation,
  "few or no suggestions" is the expected result and must be distinguishable from "the
  feature did not run".

## Related

- `specs/progress/2026-08-02-forge-refine-precondition-suggestion.md` — the precondition
  half, including why assume-and-recheck was chosen and what it cannot catch.
- `specs/progress/2026-08-03-caller-refinement-survives-mentioning-another-name.md` and
  `…-match-arm-exclusion-refutes-a-measure-fact.md` — two checker gaps found by running the
  precondition half over real code. Expect the postcondition half to surface more of the
  same; that is a feature of pointing a suggester at a prover.
