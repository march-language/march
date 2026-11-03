# Design: inference-lite, proposing the refinements the checker can now verify, module-wide

**Date:** 2026-10-20
**Status:** approved 2026-10-20 (design only; no phase has landed). Decisions settled in §9.
**Builds on:** `--refine-suggest` / `--refine-suggest-all` (`lib/refinecheck/precond_infer.ml`),
`--refine-suggest-post` (`lib/refinecheck/postcond_infer.ml`), `forge refine [--apply] [--fixpoint]`
(`forge/lib/cmd_refine.ml`), the LSP `march.suggestRefinement` action (`lsp/lib/refine_command.ml`,
`lsp/lib/code_actions_diag.ml:224-293`), and the checker features that landed 2026-10-18/19
(`specs/progress/2026-10-18-*.md`): element slots, relational element slots, abstract refinements
(`Bool[p]`, `List(a[p])`, `!p`), tuple components, `Within` fields, fold accumulator invariants
(demand-driven and annotated), scalar demands through parametric single-element results.

The checker can now verify a lot of contracts that nobody writes, and none of the suggest tools
proposes them. Today's tools draw from a fixed sign grammar on scalar slots. This design extends
the existing *assume and re-check* loop (the real checker is the only oracle, so a suggestion can
never claim more than `march --check` will then report) to six new candidate kinds. It mines its
candidate vocabulary from the module and from the demands the ledger records, and it runs the
search as a module-wide fixpoint over the call graph.

---

## 0. Where things stand (probed 2026-10-20, compiler `_build/default/bin/main.exe` at `31ffb1685`)

Method: `march --check --refine-report --refine-report-sites`, `--refine-suggest-all` and
`--refine-suggest-post-all` on each program, under a private `HOME`, cwd a scratch dir. The
`_build` stdlib was byte-identical to `stdlib/` (`cmp` clean). "Hand-annotated" is the same
program with the annotation the tool *should* propose written by hand. That column shows what
the checker already proves, so it is the ceiling for "After". Every program has
`sum_pos(xs : List({Int | _ > 0}))` / `need_pos(k : {Int | _ > 0})` / `need_nn(k : {Int | _ >= 0})`
as callees where named.

| Row | Program (user code) | Today: ledger / suggest tools | Hand-annotated: ledger | After (this design) |
|---|---|---|---|---|
| S1 | `safe(a : Int, b : Int) = a + need_nz(b)` | 1 skip; **suggest-all: `b : {Int \| _ != 0}`, solved** (10 probes) | — | unchanged (regression row) |
| G0 | `go(n : Int) = need_pos(n)`; `caller() = go(0 - 5)` | **suggest-all proposes `n : {Int \| _ > 0}`, "discharges all"**, and does not mention that `caller` becomes a violation | — | **refused**, `caller-violation`, naming `caller`'s site (§5.1) |
| E1 | `total(xs : List(Int)) = sum_pos(xs)` | 1 skip `unreflectable-subject`; "no suggestions" | `xs : List({Int \| _ > 0})`: 3 proved, 0 skipped | element precondition proposed |
| E2 | `pos_only(xs : List(Int)) : List(Int) = List.filter(xs, fn y -> y > 0)`; `go(ys) = sum_pos(pos_only(ys))` | 1 skip; post-all: "no postcondition suggestions" | `: List({Int \| _ > 0})`: 2 proved, 0 skipped | element return proposed |
| A1 | `keep(xs : List(a), f : a -> Bool) : List(a) = List.filter(xs, f)`; `sum_pos(keep(ys, fn y -> y > 0))` | 1 skip `parametric-source-unproved`; both tools silent | `f : a -> Bool[p]`, `: List(a[p])`: 2 proved, 0 skipped | joint abstract candidate proposed |
| R1 | `g(n : Int, i : Int) = need_below(n, i)`, `need_below(n : Int, i : {Int \| _ < n})` | 1 skip `unconstrained-subject`; "no suggestions" | `i : {Int \| _ < n}`: 2 proved | relational precondition proposed |
| F1 | `List.fold_left(ys, 1, fn (acc, _x) -> let _u = need_pos(acc) … acc + 1)` | 1 skip `unconstrained-subject` on `acc`; "no suggestions" | `acc : {Int \| _ > 0}`: 2 proved | annotated accumulator proposed |
| R2 | `small(xs, n : Int) : List(Int) = List.filter(xs, fn y -> y < n)`; `sum_lt(small(ys, 10), 0)` | 1 skip | `: List({Int \| _ < n})`: **2 skips** (`abstract-refinement-uninstantiated` at the return, `unreflectable-subject` at the call). The closed variant (`fn y -> y < 10`, `: List({Int \| _ < 10})`) proves 2/2 | **rejected by the oracle** (not TRUE); reported, not proposed |
| O1 | `fidx(xs, pred)` = find_index with local `go(lst, i : {Int \| _ >= 0}) : Option({Int \| _ >= 0})`; `match fidx(…) do Some(i) -> need_nn(i)` | 1 skip | **3 skips**: `unreflectable-subject` at `return of go`, `return of fidx`, then the use | rejected (not TRUE) |
| C1 | `a(x : {Int \| _ > 0}) = x + 1`; `b(x : {Int \| _ > 0}) = a(x)`; `need_pos(b(3))` | 1 skip; both tools silent | both returns `{Int \| _ > 0}`: `a`'s post and `need_pos(a(3))` prove, **`b`'s post skips** (`unreflectable-subject` for the tail `a(x)`, `solver-undecided` for `let r = a(x); r`) | demand chain tried (§3.3), rejected at `b` |
| G1 | `inc(x : Int) = x + 1`; `go(n : Int) = need_pos(inc(n))`; `caller() = go(0 - 5)` | 1 skip; silent | `inc : {Int \| _ > x}`, `go(n : {Int \| _ >= 0})`: **1 violated** (`caller`), and `need_pos(inc(n))` still `solver-undecided` (also with `_ == x + 1`) | nothing proposed: the relational return is not TRUE-and-USEFUL, and the precondition would be refused anyway |

What the probes establish, besides the gaps the table shows:

- **The oracle is sharper than intuition.** R2, O1, C1 and G1 are contracts a human would write and
  the checker does not prove today. A tool that trusted "not refuted" would propose all four, and
  each would be a dead annotation (an unproved return is gated away:
  `Refine_post.gate_unverified_posts`, `lib/refinecheck/refine_post.ml:2140`;
  `Refine_check.gate_elem_returns`, `refine_check.ml:6214`). Each gap becomes a `specs/todos/` entry
  in phase 0, not a workaround in the tool.
- **G0 is a live bug in the shipped tool.** `Precond_infer.infer_fn` (`precond_infer.ml:403`) walks
  only the pruned target (`prune`, `:274`). Its "no new violation" test (`:456`) therefore cannot
  see the callers that the new precondition breaks.
- **Debt is compared by count** (`count_debt`, `:304`). A hypothesis that proves one skip and turns
  an unrelated proved obligation into a skip scores 0, not −1 +1, which is benign. One that proves
  two and breaks one scores +1 and is accepted. Phase 0 replaces counts with a per-site diff.
- **Cost.** Plain `--check` of a 5-line program: 0.73-0.76 s. `--refine-suggest-all` on it,
  10 probes included: 0.70 s. Probes on a pruned tree are below measurement noise at this size;
  the run is dominated by stdlib registration. `--check stdlib/list.march`: 1.17-1.22 s cold;
  `--refine-suggest-all stdlib/list.march`: 1.16 s, "no suggestions". Its one user-code skip is
  `nth`'s partial conjunct, and `n` is already refined.

## 1. Candidate kinds, grammar, vocabulary

### 1.1 Slots

A **slot** is one refinable position: `(fn, path)`, where `path` is `param x`, `return`,
`… / elem` (a container's type argument; repeated for nesting), `… / tuple.i`, or
`lambda@line:col / param acc` (a fold call site). `already_refined` (`precond_infer.ml:145`)
looks only at the top constructor, which is wrong for slots: `List({Int | _ > 0})` is not
"refined" by that test. The new enumerator asks per slot, and a slot whose type is already a
`TyRefine` is never a candidate. The rule stands: *this tool proposes contracts, it does not
second-guess declared ones.* A slot is enumerable only when `ty_text` (`:116`) can re-spell its
whole enclosing annotation. An unannotated parameter (`fn filter(m, pred)`) has no base to refine
and reports `unannotated-signature`.

### 1.2 The kinds

| Kind | Slot | Shape test (decides whether to *spend* probes; never decides acceptance) | Grammar |
|---|---|---|---|
| K1 scalar param | `param x : Int/Float/List/String` | existing (`candidates_for`, `:387`) | existing signs, `len(_) > 0`, index forms, **plus mined (§1.3)** |
| K2 scalar return | `return : Int/Float/…` | existing | existing signs, **plus mined** |
| K3 element param | `param xs / elem` of a registered container (List, Option, Deque, tuples of them) | some skip in the body names a demand whose subject is `xs`, or a `match` component of `xs` | mined only (demand-first) |
| K4 element return | `return / elem`, `return / tuple.i / elem` | some caller skip has a call to this fn as its subject (or a `let`-bound result of one) | mined only |
| K5 relational | K1/K3/K4 slots, predicates naming another parameter `n` (earlier in the list for a param slot; any param for a return) or `len(ys)` | `n` appears in the body's comparisons, or a demand transports to it (§1.3) | `_ OP n` for OP in `< <= > >= !=`, `_ < len(ys)`, `_ <= len(ys)`, `len(_) <= len(ys)` (returns) |
| K6 abstract | **joint**: callback `f : a -> Bool` → `a -> Bool[p]`, plus every return slot whose element type is `a` → `a[p]` | a one-argument, uncurried callback param with an unrefined `Bool` codomain, *and* the return mentions `a` in an element slot, *and* some tail either passes `f` unchanged to a callee whose matching param is already a definer, or tests `f(h)` on a branch that conses `h` | `(List(a[p]))`; for a 2-tuple return also `(List(a[p]), List(a))`, `(List(a), List({a \| !p(_)}))`, `(List(a[p]), List({a \| !p(_)}))` (partition/reject); `Option(a[p])` (find) |
| K7 accumulator | `lambda@… / param acc` of a fold-shaped call (callee's return is a bare tyvar `b` and `acc`'s domain is exactly `b`: the rule in `specs/progress/2026-10-18-fold-invariants-phase4.md`) | a skip inside the step names `acc` as its subject | mined from that demand, then signs |

Out of v1 (each is a declined shape in an existing todo or a checker limitation): local `fn`s
(O1's inner `go`; they are not module-level and `enum_fns` does not reach them), record element
slots (`specs/todos/2026-10-18-record-element-slot-refinements-unchecked.md`), multi-arg and
curried callbacks (`specs/todos/2026-09-20-abstract-refinements-multi-arg-callbacks.md`), `Within`
fields on a *type declaration* (a type, not a function signature), and `elts`/`subset` set
measures (hand-written on `List.filter` already; a later kind).

### 1.3 The mined vocabulary

The fixed grammar stays as a fallback. The primary source is **what the program already says**:

1. **Demands (rank 1).** Every `Skipped` obligation in user code carries `callee` and `predicate`
   (`Obligation.t`, `obligation.ml:183`), written in the *callee's* formals (`_ < n` for
   `need_below`). Phase 0 adds one record-only field, `inst : string option`. It holds the
   predicate re-spelled in the caller's scope when every free formal maps to an actual that is a
   plain variable or a literal, and it is `None` otherwise. Verdicts are unchanged. This "demand
   transport" is what turns R1's skip into the candidate `_ < n` for `g`'s `i`.
2. **House vocabulary (rank 2).** Every refinement predicate already written in a signature of
   the compilation unit (user code, plus the stdlib signatures the unit calls), alpha-normalised
   to `_`.
3. **Body comparisons (rank 3).** Every comparison `e OP e'` in the slot's function where one
   side is the slot's binder (or, for an element slot, a lambda/match binder ranging over its
   elements, such as `y` in `fn y -> y > 0`) and the other side is a literal, a parameter or
   `len(param)`.
4. **Fixed grammar (rank 4).** Today's lists (`precond_infer.ml:63-99`, `postcond_infer.ml:47-75`).

Filters, all syntactic and before any probe: the candidate must be in the checker's predicate
vocabulary (the same `is_known` the unknown-application warning uses); its free variables must be
in scope for the slot; it must contain no `p(_)` unless the kind is K6. Every candidate keeps
`c_text` and `c_pred` built side by side, with the existing parse-back test
(`precond_infer.ml:44-49`). The vocabulary is capped at 12 candidates per slot, by rank, with a
`vocabulary-truncated` note when the cap bites.

### 1.4 Ordering and tie-breaks

Candidates for one slot are ordered **weakest first** by implication, not by list position.
The order comes from one Z3 query per pair, `c1 ⇒ c2`, over the binder and the parameters as free
constants. These queries are pure, cached in-process, and go through the ordinary VC cache. The
order is a topological sort of that partial order. Equivalent candidates are deduplicated (the
shortest text is kept). Incomparable candidates go by source rank (demand first), then by text.

- **Preconditions (K1, K3, K5 on params, K7)** follow the greedy rule of `infer_fn`: take the
  candidate with the best *net* module-wide gain (§2), then the weaker one, then the higher rank.
  The weakest contract rejects the fewest callers.
- **Returns (K2, K4, K5 on returns, K6)**: among TRUE candidates, take the one that discharges the
  most caller obligations, then the weaker one (my call). Today `postcond_infer.ml:263` stops at
  the first TRUE-and-useful candidate. With signs that is fine. With mined candidates it would let
  `_ != 0` win where `_ > 0` closes three more callers.
- At most one predicate per slot per round. A candidate is never conjoined onto a slot that
  already has a proposal, so the tool cannot synthesise a vacuous `_ > 0 && _ < 0`. A mined demand
  may itself be a conjunction (`_ >= 0 && _ < len(xs)`), and that is allowed as one candidate.

## 2. The acceptance oracle (always the real checker)

Every probe installs the hypothesis on a pruned tree and re-runs `RC.visit_decls` plus
`Division_safety.check_module`, exactly as `walk_debt` (`precond_infer.ml:321`) does, under
`Ob.with_scratch`. The pruned tree is **the target plus its callers**, using
`Postcond_infer.prune_with_callers` (`postcond_infer.ml:122`), extended to callers in other
modules of the same unit. The probe yields a **ledger diff** keyed by
`(span, callee, predicate, kind)`, with each site classified as *closed* (skip/violated →
proved), *opened* (proved → skip/violated), *new* (an obligation the hypothesis created) or
*unchanged*.

A candidate is **admissible** only when all of the following hold:

| Kind | TRUE (the contract holds) | USEFUL (it pays for itself) |
|---|---|---|
| K1/K3/K5 param | n/a (a precondition is assumed) | ≥ 1 closed site in the body; no opened site anywhere; no new *violated* site at a caller (§5.1); net = closed − new-skips ≥ 0 |
| K2/K5 scalar return | `RC.check_fn_post_verdict ~emit:false` (`refine_post.ml:1957`, via `post_holds`, `postcond_infer.ml:181`) | ≥ 1 closed caller site, with `defs_with_post` (`:174`) so only a verified post is lent; no opened site |
| K4 element return | new `elem_ret_holds ~root fd`: runs the `gate_elem_returns` round (`refine_check.ml:6214`) over the pruned tree and reads `Refine_param.elem_ret_proved` (`refine_param.ml:178`) for the key | ≥ 1 closed caller site |
| K6 abstract (joint) | the K4 judgment with `p` uninterpreted (definition side, `refine_abstract.ml`); the recursive-call rule (own callback passed unchanged) applies as in the checker | ≥ 1 closed caller site with `p` instantiated. Passing a callable for a definer never owes an obligation, so K6 adds no caller burden and is a pure fact, like a return |
| K7 accumulator | the invariant's own obligation (base and step) is **Proved**; an `accumulator-base-unproved` / `accumulator-step-unproved` skip rejects | ≥ 1 closed site in the step or on the fold result |

The rules that are never relaxed:

- **"Not refuted" is not TRUE.** A `Skipped` verdict of any reason (`solver-undecided`,
  `refuted-unconfirmed`, `abstract-refinement-too-weak`, …) on the hypothesis's own obligation is
  a rejection. R2, O1, C1 and G1 are the rows that pin this.
- **No opened site.** A hypothesis that makes any previously proved obligation anything else is
  rejected, whatever it closes elsewhere.
- **Satisfiability.** A param proposal must leave the conjunction of the function's parameter
  refinements satisfiable (one Z3 query). Otherwise the body is vacuously proved and every caller
  is a violation in waiting. The existing `contradicts_handled_case` (`precond_infer.ml:223`) stays.
- Probes that throw cost the candidate, not the command (`walk_debt`'s guard, unchanged).

## 3. Module-wide fixpoint

### 3.1 Order

`check_module` runs **once** (`refine_check.ml:6274`), which populates the registration globals
(ADT tables, measure preamble, alias gates). Then:

1. Build the user call graph (`Postcond_infer.calls_name`/`fn_calls`, `postcond_infer.ml:91-115`,
   lifted to qualified names). Compute SCCs (Tarjan) and a callees-first topological order.
2. **Round** r = 1..R:
   - **F-phase (facts: K2, K4, K6, K5-return)**, demand-driven. Seed a worklist with every user
     skip whose subject is a call to (or a `let` bound to a call of) a user function `h`, or a
     fold call site (K7). Each item proposes on `h` from the demand's predicate (rank 1) plus `h`'s
     own vocabulary.
   - **D-phase (demands: K1, K3, K5-param)**, over the topological order, callees first. A
     precondition on `f` moves debt into `f`'s callers, which come later in the order and get
     their turn in the same round.
   - **A-phase (K7)** per fold call site in the remaining skips.
   - Stop when a round accepts nothing.
3. Facts go before demands (my call). A return or abstract refinement discharges caller debt and
   puts no burden on anyone. A precondition only relocates debt. So within a round, a skip is
   first offered to the callee's return, and only then to the caller's parameters.

### 3.2 Recursion

A self-recursive function needs no special case. The hypothesis is installed on the function
itself, so its self-calls see it, and the checker's own structural induction
(`Refine_param.elem_ret_hyp`, `refine_param.ml:204`) decides. For an SCC of size > 1, v1 tries
one **uniform** hypothesis (the same predicate on the corresponding slot of every member, as one
atomic probe), then each member alone with the others unchanged. If neither is accepted, the SCC
reports `scc-unsupported`. Joint per-member search is out of v1 (my call).

### 3.3 Demand chains

C1 shows the shape: `need_pos(b(3))` needs `b`'s return, and `b`'s post needs `a`'s. When a
return candidate on `h` is USEFUL but not TRUE, and `h`'s *own* post obligation under the
hypothesis is a skip whose subject is a call to a user function `h'`, the item `(h', pred)` is
pushed as a **tentative** child. The chain is accepted atomically: every link TRUE, with the
outermost link USEFUL. Otherwise it is discarded. Depth cap 3 (my call). Today C1 is rejected at
`b` because the checker does not prove `b` from `a`'s proved post. The chain machinery is still
needed for the cases the checker does prove, and it turns C1 into a recorded gap instead of a
silent miss.

### 3.4 Termination and budget

Every accepted proposal turns one unrefined slot into a refined one, and slots are never
un-refined. The number of unrefined slots is a strictly decreasing natural number, so the fixpoint
terminates even when a round only *moves* debt (net 0). R defaults to 10 (forge's `max_rounds`,
`cmd_refine.ml:440`). Budgets are per function (existing defaults: 200 for preconditions,
`precond_infer.ml:523`; 60 for posts, `postcond_infer.ml:221`) plus a global
`--refine-infer-budget` (default 3000 probes). Exhaustion reports `budget-exhausted` per function,
as today (`:361`, `:485`). It is never folded into `no-candidate`.

### 3.5 VC cache and cost model

Probes go through the content-addressed VC cache (`lib/refine/refine.ml:127`;
`<root>/.march/cas/vc`, `vc_cache.ml:35`). A hypothesis cannot poison a verdict, because the key
is the VC itself. Every probe's VCs are written (my call), so a rerun after `--apply`, or an LSP
re-invocation, is mostly cache hits. Growth is bounded by the probe budget times a handful of VCs.
Tests must use a fresh `root`/`HOME`: a warm VC cache masks regressions (MEMORY:
`project_refine_vc_cache_masks_tests`).

Cost model: T = T_check (≈ 1.2 s for a `list.march`-sized unit, ≈ 0.75 s for a 5-line one, almost
all stdlib registration) + Σ probes × t_probe. Each probe walks only the target and its callers,
and t_probe was below noise in the probes (S1: 10 probes, whole run 0.70 s vs 0.73-0.76 s plain).
The in-process fixpoint replaces `forge refine --fixpoint`, which re-executes the compiler cold
once per round (`cmd_refine.ml:442-500`), so R rounds today cost R × T_check before any probing.

## 4. Output and application

### 4.1 CLI

- New **`march --refine-infer`**: all kinds, module-wide fixpoint, human output by default.
  `--refine-infer-json` gives the schema of §4.2. `--refine-infer-kinds k1,k4,…` restricts the
  kinds, `--refine-infer-budget N` sets the global budget, `--refine-infer-stdlib` also targets
  stdlib spans (off by default; the `is_user` filter of `precond_infer.ml:534`).
- Existing flags keep their meaning and schema (forge parses them, `cmd_refine.ml:66`).
  `--refine-suggest-all` becomes `--refine-infer --refine-infer-kinds k1 --rounds 1`, with the
  phase-0 guards applied. `--refine-suggest-post-all` becomes `… --refine-infer-kinds k2`.
- `forge refine --infer [--apply] [--diff]` drives `--refine-infer-json`. `--fixpoint` becomes an
  alias of `--infer` once phase 5 lands.

### 4.2 JSON (v1)

```json
{ "version": 1,
  "summary": { "user_skips_before": 7, "user_skips_after": 2, "violations_before": 0,
               "violations_after": 0, "accepted": 5, "rejected": 9, "refused": 1,
               "probes": 212, "rounds": 3, "budget_exhausted": [] },
  "proposals": [
    { "id": "P3", "round": 1, "kind": "element-return", "fn": "M.pos_only",
      "file": "lib/m.march", "line": 3, "col": 5, "slot": "return/elem",
      "base": "List(Int)", "predicate": "_ > 0", "annotation": "List({Int | _ > 0})",
      "source": "demand", "depends_on": [],
      "closes": [ {"file":"lib/m.march","line":4,"col":33,"callee":"sum_pos","predicate":"_ > 0"} ],
      "caller_impact": { "new_proved": 0, "new_skipped": 0, "new_violated": 0, "sites": [] },
      "edit": { "file": "lib/m.march", "start": 118, "end": 127, "text": "List({Int | _ > 0})" } } ],
  "rejected": [ { "fn": "M.small", "slot": "return/elem", "predicate": "_ < n",
                  "reason": "not-true", "detail": "abstract-refinement-uninstantiated" } ],
  "refused":  [ { "fn": "M.go", "slot": "param n", "predicate": "_ > 0",
                  "reason": "caller-violation", "sites": [ {"fn":"M.caller","line":4,"col":24} ] } ] }
```

`reason` is a closed set: `not-true`, `not-useful`, `opens-site`, `caller-violation`,
`unsatisfiable`, `handled-case`, `unannotated-signature`, `scc-unsupported`, `budget`, and (added
2026-10-23) `vacuous-branch`. Every array
is sorted by `(file, line, col, slot, kind, predicate)`, so the output diffs stably in review.

### 4.3 `--apply`

- Dry-run is the default. `--diff` prints a unified diff of every edit, and `--apply` writes it.
- Edits come from `March_refactor.Refine_edit` (`lib/refactor/refine_edit.ml`), which today splices
  a parameter's annotation (shared by forge and the LSP so both produce identical bytes). It is
  extended to replace a **whole** param or return annotation (an element slot is written as the
  full re-spelled type, never as an in-place splice inside nested parens) and to annotate a
  parenthesised lambda parameter (K7). An unparenthesised `fn acc -> …` is reported as "apply by
  hand" (my call; rewriting lambda syntax is out of scope).
- After writing, the tool re-parses (existing `parses`, `cmd_refine.ml:143`) **and re-checks**.
  If the real ledger differs from the predicted one (`summary.*_after`), every edit is reverted and
  the run exits non-zero: that is a tool bug, never something for the user to reconcile.
- Idempotent: a second run proposes nothing, because applied slots are refined and closed sites
  are proved. A test pins this.
- Stdlib files are never written unless `--refine-infer-stdlib` *and* `--apply` are both given.

### 4.4 LSP

- Per function: "Infer refinements for `f`" (command `march.inferRefinements`, fn argument), offered
  where `march.suggestRefinement` is offered today (`code_actions_diag.ml:234-293`), and on a
  function with any skip in its body or at its call sites.
- Per file: "Infer refinements in this file (N)". The count comes from the last cached run and is
  never computed on cursor movement, the same discipline `refine_command.ml:1-15` documents.
- Both go through the JSON and `Refine_edit`. A precondition with `caller_impact.new_skipped > 0`
  is sent as a `WorkspaceEdit` change annotation with `needsConfirmation`, labelled "adds an
  unproven obligation at k callers".

### 4.5 `cap verified` and `--refine-report`

- Under `cap verified` every skip is an error. The summary line says "closes k of m
  `cap verified` errors" for modules carrying the cap.
- `--refine-report --refine-infer` prints the ordinary report twice, *as is* and *if applied* (the
  ledger of the final hypothesis tree), so "how many skips would the suggestions close" is answered
  in the report's own format. The per-reason buckets show which reasons the tool can and cannot
  reach.

## 5. Soundness and UX guards

1. **Caller impact (fixes G0).** A precondition is admitted only after walking every in-unit
   caller. A new *violated* site at any caller means `refused / caller-violation`, with the sites
   listed, unless `--allow-caller-violations` is given. New *skipped* sites are allowed and
   reported as `caller_impact.new_skipped`: that is debt moving up, and the next D-phase can work
   on it there.
2. **Public functions with no in-unit callers.** For a library entry point the callers are
   external, so the impact is unknown. Such proposals are marked `external-callers` (§9 D3).
3. **Never `@[assume]`, never `@[trusted]`.** No proposal adds either attribute. No slot of a
   function carrying `trusted` (`refine_check.ml:5108`), `assume` (`refine_param.ml:552`) or an
   adopted `impl` method (`refine_param.ml:171`), or of an extern or builtin, is a candidate.
   `Trusted` is not debt (`count_debt`, unchanged).
4. **Never weaken, never replace.** Refined slots are not candidates (§1.1). The tool only adds.
5. **Prediction equals verdict.** This is the §4.3 post-apply re-check. It is also a test
   invariant: for every corpus run in §6, applying every proposal and running `--check` must
   reproduce `summary.*_after` exactly.
6. **Stable output.** There is one sort order everywhere (§4.2). Candidate order depends only on
   the program text, never on hash-table iteration (`Hashtbl` walks are sorted before use).
7. **No silent caps.** `vocabulary-truncated`, `budget-exhausted` and `scc-unsupported` are
   reported per function, never folded into "no candidate".

## 6. Evaluation plan

**Corpora:** (1) the stdlib, 133 modules, dry-run with `--refine-infer-stdlib`, never applied by
this series; (2) `test/native/*.march`, 416 files; (3) `~/code/conduit/lib` and `~/code/depot/lib`,
77 `.march` files between them, run through `forge refine --infer` in each repo, dry-run.

**The rediscovery benchmark is the primary signal.** The stdlib already carries the contracts this
tool should find: `List.filter` (`stdlib/list.march:304`), `find` (`:507`), `take_while` (`:626`),
`partition` (`:663`, the `!p` component), `Option.filter` (`option.march:113`), `Deque.filter`
(`deque.march:135`), `Enum.filter`/`find`/`take_while` (`enum.march:81,210,581`). A fixture copies
each function with its refinements stripped (signature only, body unchanged) next to a caller that
needs the fact. The tool must re-derive exactly the hand-written annotation, or a weaker one that
still closes the caller's site. Each phase adds its rows, written RED first.

**Expected stdlib outcomes (hypotheses to measure, not claims):**

| Function | Expected proposal | Expected oracle outcome |
|---|---|---|
| `List.pfilter` (`list.march:373`) | K6 `Bool[p]` + `List(a[p])` (passes `pred` to `filter`) | likely **rejected**: the `chunks`/`task_spawn`/`concat` path loses the element fact. Measure |
| `List.find_index` (`:515`) | K4 `Option({Int \| _ >= 0})` | **rejected** today (row O1's local-`go` gap) |
| `List.drop_while` (`:637`), `any`/`all` (`:526`, `:534`) | none: no element fact is expressible (`drop_while`) or the return is `Bool` | no proposal |
| `HashMap.filter` (`hash_map.march:573`), `Seq.filter`/`find` (`seq.march:84,434`), `Flow.filter` (`flow.march:79`) | none: unannotated signatures | `unannotated-signature` |
| `Gen.filter` / `tree_filter` (`gen.march:363,131`) | K6 shape only if `GenTree` is a registered container | measure |
| the stdlib skips reachable from a trivial program (S1's report: 44 skips; 25 `unconstrained-subject`, 9 `partial-conjunct`, 7 `solver-undecided`, 3 `unreflectable-subject`; e.g. `List.nth` from `hamt.march:206,291,331`) | K1/K5 index preconditions on the enclosing `hamt` helpers | measure: how many close, and how many are refused for caller impact |

**Metrics, per corpus:** user skips before/after (by reason); proposals accepted, by kind;
rejected, by reason; refused for caller violation; probes; rounds; wall time as a ratio to plain
`--check`; prediction mismatches (must be 0, a hard gate); rediscovery hit rate (target: every row
of the table above that the checker proves by hand). Every rejection whose `detail` is a checker
skip reason becomes a candidate todo. Rows R2, O1, C1 and G1 are filed in phase 0.

## 7. Phases, one PR each

Each phase: RED-first rows in `test/test_refinecheck.ml` (z3-gated; run with
`scripts/run-tests.sh refinecheck`; fresh `root` per test), a `specs/progress/` record, a CHANGELOG
bullet, and docs in `specs/lang/refinement-types.md` §"Getting a contract proposed for you"
(regenerated with `scripts/gen-lang-docs.py`). The perf budget is measured on `stdlib/list.march`
as the entry file and on the probe corpus under a private `HOME`.

| # | PR | RED rows first | Perf budget |
|---|---|---|---|
| 0 | **Guards for the shipped tools.** Per-site ledger diff (replacing `count_debt`), callers in the pruned tree for preconditions, `caller-violation` refusal, satisfiability check, `Obligation.inst` (record-only), file todos for R2/O1/C1/G1 | G0 refused (today: proposed); a "proves 2, opens 1" hypothesis rejected; S1 unchanged | `--refine-suggest-all` ≤ +10% on the existing suggest tests |
| 1 | **Candidate framework + mined vocabulary + implication order**; K5 on scalar params | R1 proposes `i : {Int \| _ < n}`; weakest-first among mined (`_ <= n` before `_ < n` when both close) | ≤ 1.3 × T_check on `list.march` |
| 2 | **Element slots**, K3 + K4 (+ tuple components), `elem_ret_holds` | E1, E2 proposed; R2, O1 rejected with `not-true` | ≤ 1.5 × T_check |
| 3 | **Abstract K6** (joint) incl. `!p` / partition / `Option(a[p])` | A1 proposed; rediscovery of `filter`, `find`, `take_while`, `partition`, `Option.filter`, `Deque.filter` | ≤ 1.5 × T_check |
| 4 | **Accumulator K7** + the `Refine_edit` lambda-parameter splice | F1 proposed; base-failing (`0` with `_ > 0`) and step-failing variants rejected | ≤ 1.5 × T_check |
| 5 | **Fixpoint `--refine-infer`**: SCCs, F/D/A phases, demand chains, budgets, JSON v1, `--apply`/`--diff`, post-apply re-check, `forge refine --infer` | a two-hop chain the checker proves (a chain built on element returns, which do lend, unlike C1) is found in one run where today's `--fixpoint` needs two cold rounds; idempotence; prediction-mismatch revert | ≤ 2 × T_check for `list.march`; ≤ 3 × per file on `test/native` |
| 6 | **LSP + report integration** (`march.inferRefinements`, the file action, change annotations, `--refine-report --refine-infer`) | LSP action produces the CLI's bytes; report "if applied" line equals the post-apply report | no per-keystroke cost (command only) |
| 7 | **Evaluation run** (§6): a `specs/progress/` record with the metrics and one todo per checker gap found. No product code | — | — |

## 8. Out of scope: Liquid-style Horn-constraint inference

Real liquid inference puts a κ-variable on every unknown refinement (every binder, `let`, local
function and slot), generates subtyping constraints from the program, and solves the Horn system by
predicate abstraction over a qualifier set. This design deliberately does not do that, because:

- **It needs a second constraint generator.** The March checker is a walk that emits a verdict
  ledger. It is not a constraint generator. Building one beside it is exactly the drift hazard
  `precond_infer.ml:4-17` exists to avoid: every checker rule (abstract instantiation, fold
  invariants, `Within` roles, gating) would need a second, constraint-shaped implementation that
  can disagree with the first.
- **The checker's encoding is quantifier-free by design** (abstract-refinements design §2). Global
  Horn solving over recursive datatypes wants quantified or datatype reasoning the checker avoids.
- **A fixed point of κs assumes every annotation site is legal and checked.** Several aren't yet:
  local returns (O1), relational lending (G1), and call-tail posts (C1).

What a later Liquid-style engine would **reuse** from this design: the mined vocabulary (§1.3 is a
qualifier set), the implication order (§1.4), the call-graph/SCC scheduling (§3), the per-site
ledger diff and the oracle as a **final validator** of any solution it produces, the JSON schema,
`--apply`, `Refine_edit` and the LSP surface. Only §3's search would be replaced.

## 9. Decisions

### Settled by the user (2026-10-20): D1-D5 accepted as recommended

- **D1. New flag or extend?** Recommendation: a new `--refine-infer` (+ `forge refine --infer`).
  Keep `--refine-suggest*` and their JSON byte-compatible as kind-restricted aliases, so `forge
  refine` and the LSP keep working through the transition.
- **D2. Caller-violation policy.** Recommendation: refuse by default and list the sites;
  `--allow-caller-violations` to override.
- **D3. Preconditions on public functions with no in-unit callers.** Recommendation: propose them,
  marked `external-callers`, and have `--apply` skip them unless `--apply-public` is given.
  Libraries such as conduit and depot are where this matters most, and it is where an unseen
  caller breaks.
- **D4. Phase 0 changes what the shipped `--refine-suggest-all` prints** (G0 stops being proposed).
  Recommendation: ship it as a bug fix with a CHANGELOG `### Fixed` entry.
- **D5. Landing stdlib annotations the evaluation finds.** Recommendation: not in this series. One
  reviewed PR per stdlib module afterwards, each with the rediscovery-style caller test.

### Settled here (my calls; revisit in review if wrong)

- Facts before demands within a round (§3.1).
- Return selection: maximum discharge, then weakest (§1.4). This changes `--refine-suggest-post`'s
  first-useful rule.
- SCCs > 1: uniform hypothesis, then single members, else `scc-unsupported` (§3.2).
- Demand-chain depth 3 (§3.3). Vocabulary cap 12 per slot (§1.3). Global probe budget 3000 (§3.4).
- The VC cache is written for every probe (§3.5).
- K7 edits only parenthesised lambda parameters (§4.3).
- Local `fn`s, record slots, multi-arg/curried callbacks and set measures are out of v1 (§1.2).
