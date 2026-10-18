# A scalar demand on a single-element result (element-flow follow-ups, phase 2)

Landed 2026-10-18. Design: `specs/2026-10-18-element-flow-followups-design.md`, §3 and
phase 2 of §8 (rows s1-s14 of §0.1). Closes item 1 of
`specs/todos/2026-09-18-refine-element-flow-followups.md`. Built on phase 1
(`11fa2cdbf`). Also provides the return-tail hook that
`specs/2026-10-18-fold-accumulator-invariants-design.md` §3.1 asked sibling (a) for.

## What a user sees

```march
fn go(o : Option({Int | _ > 0}), xs : {List({Int | _ > 0}) | len(_) > 0}) : Int do
  need_pos(Option.unwrap_or(o, 1))                    -- was unreflectable-subject; proved
  need_pos(Option.unwrap_or(o, Option.unwrap_or(p, 2)))  -- proved, one obligation
  need_pos(Option.unwrap_or_else(o, fn () -> 1))      -- proved (a callback-codomain source)
  sum_pos([Option.unwrap_or(o, 1)])                   -- proved
  need_pos(List.fold_left(xs, 1, fn (acc, x) -> x))   -- proved (x has xs's fact, phase 1)
  need_pos(List.head(xs) + 1)                         -- proved (the assumption route)
  need_pos(Option.unwrap_or(o, 0))                    -- parametric-source-unproved skip
end
fn ret(o : Option({Int | _ > 0})) : {Int | _ > 0} do Option.unwrap_or(o, 1) end   -- proved
```

A closed scalar demand on a call subject that has no postcondition holds when the
callee's declared return is a bare type variable `v`, the callee is parametric in `v`
(P1/P2), and every source of `v` meets the demand: the container rule's judgment
(2026-09-18 design §4), applied to one value.

## Code

Two commits.

1. `f8db256dd`, inert: `demand_flow`'s source discharge split out as `discharge_pairs`
   (`refine_check.ml`), given the `(variable, demand)` pairs. `demand_flow` keeps its
   contract (it computes the pairs and checks P1/P2, then calls it). Refine-oracle
   identical against `11fa2cdbf`, the existing groups unchanged.
2. The feature:
   - `Refine_call.call_ctx.demand` (design §3.2), an optional closure
     `call_ctx -> span -> subject -> demand -> [ `Na | `Proved | `Unproved ]`. In
     `check_call`'s `None` arm, when the mode is `` `Other ``, the subject is a call
     and its self-reflection failed, the closure runs: `` `Proved `` is noted
     `Proved`, `` `Unproved w `` a `Parametric_source_unproved w` skip, `` `Na `` the
     old skip byte-for-byte. `note` records once and escalates under `cap verified`.
   - `Refine_check.scalar_demand`: `` `Na `` unless the demand is closed
     (`classify_pred b [] p = Closed`) and the callee is a top-level definition
     (`resolve_key`); a bare `TyVar` return that fails `parametric_ok` is
     `` `Unproved `` "not known to be parametric"; otherwise `discharge_pairs … [(v,
     Refined d)]`, with the channels the closure was CALLED with (`cx.path`,
     `cx.lets`, `cx.sc`, `cx.re`, `cx.binds`).
   - `Refine_check.cx_of`: builds the walk's `call_ctx` (`postcond_param` and the
     closure, capturing `ctx`/`cb`/`ce`). Used at every site inside the
     `check_elements`/`visit` chain that has a container env: `check_elements`,
     `discharge_pairs`' `cx0`, `visit`'s call, constructor and record arms. The
     pre-chain sites (pass-site domain/codomain checks, the abstract scratch checks,
     the actor-state literal) set `demand = None`.
   - `postcond_param` (§3.5, the assumption route): a proved declared return first,
     else `parametric_return`'s `` `Scalar `` (every source an element agreeing on
     one slot). `need_pos(List.head(xs) + 1)` proves through it.
   - `check_let_annotation ?ext`: the walk passes the postcondition lookup and the
     closure built from the env SHADOWED by the binding's names (`local_shadow`,
     `cb_shadow`, `cont_shadow`), so s13 proves.
   - Return tails: `Refine_post.tail_demand` (a cell, like `post_lookup`), set by
     `visit_fn` around `check_fn_post` and by `gate_unverified_posts` around its
     pre-pass check (through `tail_demand_of`, which `Refine_check` sets at module
     init), so a proved return also propagates to callers. `check_fn_post_verdict_core`
     now enumerates `tails_bound` and hands each scalar-return tail
     `(path, bound, params, sc)`; `check_post`'s unreflectable-tail arm consults it.
     `Refine_check.tail_demand_impl` builds the env from the clause's parameters
     (`cont_of_fnparams`, `cb_add_fnparam`, `recenv_add_fnparam`, every parameter a
     local for resolution) and calls `scalar_demand` directly.

## Where this departs from the design

- **Return tails are covered here** (design §7 put them out of scope; the task and the
  fold design's §3.1 asked for the hook). The ledger has one entry per tail as before:
  the hook runs inside `check_post`'s `note`, not as a second obligation. On
  `` `Unproved `` the enumerative witness still runs first, so a tail that a concrete
  call breaks is still a violation, exactly as before.
- **Lambda tails build their own context.** `discharge_pairs`' `lambda_ok` checked a
  scalar tail with `{ cx0 with … }`. With a closure in `cx0` that would discharge a
  nested call in the tail against the CALLER's container env: `need_pos(ap(p, fn o ->
  Option.unwrap_or(o, 1)))` with a caller `o : Option({Int | _ > 0})` proved (false,
  `p = Some(0 - 5)`). The tail now uses `cx_of` over the lambda's shadowed
  `ctx'`/`cb'`/`ce'`/`sc'`. Pinned by the test group and `reject/t362`.
- **The `let` arm is kept.** §3.5 says to delete the block walk's `let h =
  List.head(xs)` arm once `postcond` carries the same fact. `scope_add_binding` still
  takes `postcond_of`, so deleting the arm would have needed a second change to the
  `let` path with no new behaviour; it stays, and the inline route is added beside it.
- **No `cx_of` commit of its own.** The design's commit 1 (constructor, `demand =
  None` everywhere, oracle identical) is folded into the feature commit; the inert
  refactor commit is the `discharge_pairs` split only.
- **Conservative calls (each a skip, never a proof):**
  - A callee that is a callback parameter or a local (`resolve_key = None`) is
    `` `Na ``: it keeps its `unreflectable-subject` text.
  - A return tail that mentions any name bound on the way down to it (`let o = p;
    Option.unwrap_or(o, 1)`) is `` `Na ``: the env is the parameters', so the name
    would be read as the parameter. Without the guard that case proved (perturbation
    below).
  - A block-level `fn`'s return tail gets no hook (both in `check_fn_post_verdict`'s
    locals loop and at `visit_local_fn`, where the cell is the default): its env
    includes sibling locals and captures, and its own name is not yet a local. Filed
    implicitly with design phase 3.
  - A relational return demand (`: {Int | _ >= lo}`) is `` `Na `` (closed only, as
    §3.1 for preconditions). The fold design's f5 needs this widened.
  - The gate pre-pass resolves names under `{ rctx0 with modpath }` (no aliases or
    `use`s), the same context its `postcond_of` already uses; a tail whose callee
    resolves only through an alias is proved in the walk but does not propagate.

## Tests

`test/test_refinecheck.ml`, group `elemflow-scalar-demand` (16 cases, ledger triples,
skip reasons and detail text; never exit codes). "Before" is the group run, every
assertion non-fatal, on `11fa2cdbf`:

| Case | Before | After |
|---|---|---|
| s1 `need_pos(uor(o, 1))` | (0, 0, 1) unreflectable-subject | (1, 0, 0) |
| s2 `uor(o, 0)`, `uor(o, 0 - 1)` | (0, 0, 1) unreflectable-subject | (0, 0, 1) parametric-source-unproved, "argument 2 of `uor` can fail it for some input" |
| s3 unrefined `o` | (0, 0, 1) unreflectable-subject | (0, 0, 1) parametric-source-unproved, "the elements of argument 1" |
| s4 `uor(o, k)`, `k > 0` / `k : Int` | (0, 0, 1) / (0, 0, 1) | (1, 0, 0) / (0, 0, 1) |
| s5 `uor(o, uor(p, 2))` / inner `0` | (0, 0, 1) / (0, 0, 1) | (1, 0, 0), one obligation / (0, 0, 1) |
| s6 `sum_pos([uor(o, 1)])` / `[uor(o, 0)]` | (0, 0, 1) / (0, 0, 1) | (1, 0, 0) / (0, 0, 1) |
| s7 `uore(o, fn () -> 1)` / `fn () -> 0` | (0, 0, 1) / (0, 0, 1) | (1, 0, 0) / (0, 0, 1) |
| s8 `foldl(xs, 1, fn (acc, x) -> x)` | (0, 0, 1) | (1, 0, 0) |
| s9 `fn (acc, x) -> acc + x` (the fold boundary) | (0, 0, 1) unreflectable-subject | (0, 0, 1) parametric-source-unproved |
| s10 `need_pos(hd(xs))` | (1, 0, 1) | (2, 0, 0) |
| s11 `let h = hd(xs); need_pos(h)` | (2, 0, 0) | same |
| s12 `need_pos(hd(xs) + 1)` / unrefined elements | (1, 0, 1) / (1, 0, 1) | (2, 0, 0) / (1, 0, 1) |
| s13 annotated `let` / default `0` | (0, 0, 2) / (0, 0, 2) | (2, 0, 0) / (0, 0, 2) |
| P1 (`from_json` body) / P2 (`[a : Eq]`) | (0, 0, 1) / (0, 0, 1) | same; P1 now "is not known to be parametric" |
| relational `at(ys, uor(o, 0))` against `_ < len(xs)` | (0, 0, 1) unreflectable-subject, "the argument `uor(o, 0)`" | same, byte for byte |
| lambda tail `let k = 0 - 5; k`, lambda param `k`, `let o = p` | (0, 0, 1) each | same |
| lambda param `o` shadowing the caller's `o` / control `fn q -> …` | (0, 0, 1) / (0, 0, 1) | (0, 0, 1) / (1, 0, 0) |
| `cap verified`: s1 / s2 | rejected / rejected | accepted / rejected |
| s14 return tail `uor(o, 1)` / `uor(o, 0)` | (0, 0, 1) / (0, 0, 1) unreflectable | (1, 0, 0) / (0, 0, 1) parametric-source-unproved |
| return `if b do uor(o, 1) else 5 end` | (1, 0, 1) | (2, 0, 0) |
| caller `need_pos(go(o))` of s14 | (1, 0, 2) | (3, 0, 0) |
| return tail under `let o = p` / relational return / local `fn`'s tail | (0, 0, 1) each | same |

Perturbations (each against the whole group, non-fatal, then restored):

- `cx_of`'s `demand = None`: exactly the precondition-side cases go red (s1-s9, s13,
  the P1 detail, the shadow control `fn q`, `cap verified` s1); every return-position
  case stays green (its hook calls `scalar_demand` directly) and s10/s12 stay green
  (the assumption route).
- `tail_demand_impl` answering `` `Na ``: exactly the five return-position assertions
  go red.
- `lambda_ok`'s scalar tail back on `{ cx0 with … }`: only "fn o -> uor(o, 1) under a
  caller o" goes red, as (1, 0, 0), a false proof.
- the return-tail `bound` guard removed: only "let o = p; uor(o, 1)" goes red, as (1,
  0, 0), a false proof.
- `postcond_param` replaced by `postcond_of`: only s12 goes red.

Conformance: `specs/lang/types/accept/t360_refine_scalar_demand_single_element_result`
(stdlib `Option.unwrap_or`, `unwrap_or_else`, `List.fold_left`, `List.head` and a return
tail under `cap verified`; rejected on `11fa2cdbf` with 9 skips, 10/0/0 now),
`reject/t361_refine_scalar_demand_refuted_default` (s2; rejected before too, now with
the parametric-source reason) and `reject/t362_refine_scalar_demand_lambda_shadow` (the
shadowing lambda; rejected before too). The two rejects pin verdicts, not fixed bugs,
and are new to the march-lean oracle. The corpus is 458/458 (194 accept, 264 reject).

## Verification

- `test_refinecheck.exe -e`, private `HOME`, `.march/cas/vc` cleared once: 1122 tests,
  all pass, 0 skipped (z3 4.16.0), 487 s. `audit-baseline` included: no baseline moved.
- `scripts/run-tests.sh -q compiler`: 1348 tests, all pass.
- `specs/lang/types/check_types.sh`: 458 passed, 0 failed.
- `scripts/refine-oracle.sh`: baseline from a detached `11fa2cdbf` worktree at the same
  directory depth, check on each commit, both under the script's private `HOME`:
  **identical** both times, 7786 lines over 549 fixtures. The oracle is blind to this
  rule: its only `unreflectable-subject` skips are the three stdlib `List.nth(sorted,
  clamp_idx(…))` calls in `stats.march`, whose demand `_ >= 0 && _ < len(xs)` is
  relational (and `clamp_idx` returns `Int`, not a type variable), and no `test/native`
  or stdlib fixture puts a closed demand on an `unwrap_or`-shaped call. No stdlib or
  test line moved, so there was nothing to list. The evidence is the group and the
  corpus files.
- `stdlib/list.march`'s `--check --refine-report`: byte-identical to the base (21
  proved, 0 violated, 1 skipped for user code); the CI ratchet does not move.
- Timing, `--check --refine-report stdlib/list.march`, private `HOME`, VC cache cleared
  before the first of three runs, two interleaved rounds, staged `_build/default/stdlib`
  set aside, load average 15-16: base medians 1.112 / 1.119 s, this change 1.111 /
  1.130 s. Within the design's 10% budget (noise). The `elemflow-scalar-demand` group
  ran in 0.138 s against `demand-flow`'s 0.104 s (VC cache cleared before the pair),
  within the 2x budget.

## Review follow-up: a tail's inner binders (third commit, same day)

An independent review of `3d02bf5e7` found a false proof under `cap verified`
whose root cause predates this phase (reproduced on `11fa2cdbf`) and which the
new hooks widened:

```march
fn g2(n : {Int | _ < 0}, p : Option(Int)) : {Int | _ > 0} do
  match p do
    Some(n) -> if n > 5 do 0 - 7 else 1 end   -- proved; g2(0 - 1, Some(10)) = -7
    None -> 1
  end
end
```

A return tail is checked in the parameters' env (`check_post`'s `sc`), with the
path conditions collected on the way down. `tails_bound` path-shadows the facts
collected BEFORE an inner binder, so every mention of a `bound` name still in the
path or tail is about the inner binding, but it reached the solver under the
parameter's SMT name: `n < 0` from `sc` and `n > 5` from the path, a
contradiction. The plain walk was never affected (it shadows at the binder).
Same flaw, three more places: `tail_demand_impl` (`Option.unwrap_or(o, 0 - 7)`
as the tail), `discharge_pairs`' `lambda_ok` and `check_pass_site_elements`'
lambda tails (path facts over a lambda-body binder named like a caller
variable, read in the lambda-level env), and `visit_fn`'s element-return
fallback. `Some(n) -> n` with a refined parameter `n` (no path condition at all)
was a second false proof of the same cause, found while writing the controls.

Fix (`Refine_post.rename_free` / `rename_path`): the inner binding is renamed
apart (`n` → `n$in`) in the path and in the tail. No fact is dropped: the inner
`n > 5` still constrains the inner `n`, so `if n > 5 do n else 1 end` keeps
proving. Where the clash set comes from:

- `check_fn_post_verdict_core`: the `bound` names that are clause parameters,
  in the path and the tail (the tail displays as written, `?shown`); the demand
  hook gets the renamed path and the renamed `bound`, so its "the tail mentions a
  bound name" decline still fires.
- `check_post_induction`'s `check_tails`: its `outer` names (parameters and the
  arm's pattern binders), in the path only (a tail mentioning one is already a
  skip). Other inner names are left alone, so structural sub-variables keep
  their names for the induction hypothesis.
- lambda tails: every `bound` name, in the path only (a tail mentioning one is
  already declined).
- the element fallback: clashing parameters, path and tail; the in-walk
  identity match still uses the original tail.

`rename_free` leaves application heads (a local `fn` is looked up by name) and
binding forms alone; the SMT translation reflects no binding form, so a fact or
tail containing one is dropped or unreflectable, never read.

Tests: group `post-inner-binders` (8 cases). On `3d02bf5e7` (the group run with
every assertion non-fatal), seven assertions were false proofs: h2 (3, 0, 0) and
its `cap verified` acceptance, `Some(n) -> n` (2, 0, 0), the call tail h1
(3, 0, 0), the two lambda-tail forms (1, 0, 0) each, and the pass-site element
lambda (3, 0, 0). Now (2, 1, 0) / rejected / (1, 0, 1) / (2, 0, 1) / (0, 0, 1) /
(0, 0, 1) / (2, 1, 0). Controls green on both: the correct twins (`do n`,
`do 7`), a fresh binder, the call tail `uor(o, 1)`, the multi-clause pair
(desugar gives the clauses fresh names, so it was never affected), a `match`
binder shadowing an option in the walk, and `pick(xs, z)` with an unrefined /
refined bare `z`. Perturbation: `rename_free` made the identity turns exactly
those seven assertions red. Conformance: `reject/t363` (h2 under `cap verified`;
accepted with 3 proved on `3d02bf5e7`). The corpus is 459/459.

Verification: `test_refinecheck.exe -e` 1130 tests, all pass, 0 skipped
(549 s); `scripts/run-tests.sh -q compiler` 1348 pass; `check_types.sh`
459/459; `refine-oracle.sh check` against the `11fa2cdbf` baseline, staged
stdlib set aside: identical (7786 lines, 549 fixtures). No corpus fixture binds
an inner name that clashes with a parameter on a path the post engine reads.

## Left open

- A relational scalar demand, at a call (`_ < len(xs)`) or a return
  (`{Int | _ >= lo}`, the fold design's f5): the phase 0 substitution plus the z5
  capture guard.
- A block-level `fn`'s return tail (design phase 3's territory).
- The accumulator invariant: `specs/2026-10-18-fold-accumulator-invariants-design.md`,
  whose phase 1 can now put `invariant_params` inside `discharge_pairs`' `lambda_ok`.
- Phases 3-4 of the design (items 3 and 4 of the todo).
