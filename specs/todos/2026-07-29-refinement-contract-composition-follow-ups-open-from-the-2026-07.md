# Refinement contract composition follow-ups (OPEN, from the 2026-07-29 call-boundary composition work)


- **A caller-established runtime GUARD is a different mechanism** from a
  caller's declared contract. `if List.length(ys) > 0 do head(ys)` already
  worked (the `len` alias, 2026-07-28) and is untouched. Which shape you have
  decides which machinery you get.
- **Postconditions compose no measure through a return refinement.** Narrowed
  2026-07-30: `check_post` now *files* an obligation at every exit (so
  `--refine-report` counts return refinements) and `cap verified` escalates an
  undischarged one. What remains open is composition — a list or ADT measure
  still does not carry through a return refinement to a caller's goal.
- **The measure-alias gates are still unit-global**, except the selector-less
  `use X.List` arm, which since 2026-07-31 resolves its target and withdraws
  only if some match can provide the aliased member. The member gate,
  `alias … as List`, `import X.{List}` and the glob fuel bound stay coarse on
  purpose — no measurement implicated them.

**Follow-ups.**
- ~~**A tag refinement still does not forward.** `{Option(Int) | is_Some(_)}`
  passed on to a callee with the identical contract stays skipped
  (`1 proved, 1 skipped`, the proof being the outer literal). Tag facts are
  established at the call site by a constructor literal or a `match` narrowing,
  not carried by a binding, so this is the one refined form composition does not
  cover.~~
  **CLOSED 2026-07-29** — `load_scope_tester_facts` (`lib/refinecheck/refine_check.ml`,
  the tester analogue of `load_scope_measure_facts`, wired into `check_call`'s
  `resolve_tester` before it reflects the actual) loads the caller's own tag
  promise over the same `Const x` datatype term the goal side builds, so
  `fn outer(p : {Option(Int) | is_Some(_)}) do inner(p) end` now reports
  `2 proved, 0 violated, 0 skipped`. All three spellings of the refined value
  compose (`_`, a declared binder, the parameter's own name). Deliberately
  narrow: the loader fires only when the caller promises the SAME constructor
  the goal tests — a caller promising `is_None(_)` into a callee wanting
  `is_Some(_)` loads nothing and stays skipped (assuming it verbatim would also
  be sound and would report the call, but it is a wider claim than "the caller
  already promised the goal"). Rebinding (`let p = None`) or a `match`-arm
  binder of the same name retires the fact. Bracketed by `accept/t129` /
  `reject/t130`; +6 refinecheck tests (352 → 358).
- **No local `let` carries a value forward into a later goal, for ANY type.**
  `let u = 5` then `take_pos(u)` against `{Int | _ > 0}` is skipped, and the
  `List` analogue behaves identically. Pre-existing and general (it is also why
  rebinding a refined parameter leaves the call skipped rather than reported);
  the workarounds are to pass the value directly or restate the fact with
  `assert`.

---

## 2026-08-03 — Task 6 Step 0 findings: postcondition composition through an unannotated `let`, RELATIONAL ADT-measure case (STILL OPEN, no code shipped)

Investigated the "Postconditions compose no measure through a return
refinement" item above, specifically for the shape:

```march
type Tree(a) = Leaf | Node(Tree(a), a, Tree(a))

@[measure]
fn size(t : Tree(a)) : Int do
  match t do
    Leaf -> 0
    Node(l, _, r) -> 1 + size(l) + size(r)
  end
end

fn push(t : Tree(Int), x : Int) : {Tree(Int) | size(_) == size(t) + 1} do
  Node(t, x, Leaf)
end

fn needs_bigger(before : Tree(Int), after : {Tree(Int) | size(_) > size(before)}) : Int do 0 end

fn go(t : Tree(Int)) : Int do
  let r = push(t, 5)
  needs_bigger(t, r)      -- solver-undecided; r's contract is not carried
end
```

Confirmed still `0 proved, 0 violated, 0 trusted, 1 skipped` (`skipped
(solver-undecided): 1`) against unmodified HEAD (`688144dc`), with
`.march/cas/artifacts-v2` and `.march/cas/vc` cleared before measuring.

**A consumer for a caller-scope ADT variable's own carried measure predicate
DOES already exist** — `load_scope_measure_facts`
(`lib/refinecheck/refine_check.ml`, defined just above `check_call`'s
`resolve_tester`/`reflect_dt`, called from `resolve_measure`'s
axiom-measure branch on every bare-name measure argument, e.g. from `_`
resolving to `self_actual`). It is wired to read `sc` (the refinement
scope) for an entry marked with the `$Meas:` prefix (`is_meas_sort`) —
today that marker is produced only by `refined_scope_ty` for an EXPLICITLY
ANNOTATED refined parameter or `let`. `scope_add_binding`'s postcond-derived
arm (the one that seeds a scope entry from an UNANNOTATED `let x = f(...)`)
never produces this marker for a plain multi-constructor ADT return — its
final `| Some _ | None -> sc` catch-all silently drops it, exactly as the
task-6 brief predicted.

**A prototype fix was built, tested, and then REVERTED (not shipped).** It
widened `scope_add_binding`'s postcond arm to also store a `$Meas:`-marked
entry for a general non-record, non-String ADT sort. This part of the Step 0
guess was correct and verified in isolation:

```
fn grow(t : Tree) : {Tree | size(_) > 0} do
  match t do
    Leaf -> Node(Leaf, 1, Leaf)
    Node(l, y, r) -> Node(Node(l, y, r), 1, Leaf)
  end
end
fn needs_nonempty(x : {Tree | size(_) > 0}) : Int do 1 end
fn go(t : Tree) : Int do
  let r = grow(t)
  needs_nonempty(r)        -- PROVES with the prototype fix (was: skipped)
end
```

— a **Closed** (self-only) measure postcondition (`size(_) > 0`, mentioning
no other parameter) composes through an unannotated `let` with the widened
producer + the pre-existing consumer. This is real, but it is NOT the shape
in the repro above.

**The repro above needs a RELATIONAL postcondition** (`size(_) == size(t) +
1`, mentioning the caller's OTHER parameter `t` — `classify_pred` calls this
shape `Relational`, distinct from `Closed`), and for that shape the existing
consumer does NOT suffice, even with the widened producer. Root cause,
confirmed by reading `load_scope_measure_facts`'s body directly (its own doc
comment already says this, in different words):

```ocaml
let rm m' n =
  if not (is_self_spelling n) then None   (* <-- HERE *)
  else if is_axiom_measure m' then ...
  else measure_of_var m' x
```

`is_self_spelling n` is `n = b || n = "_" || n = x` — i.e. it accepts ONLY
the scope entry's own three self-spellings. `push`'s stored predicate,
substituted into the caller's namespace, is `size(_) == size(t) + 1`
(equivalently `App(size,[_]) = App(size,[t]) + 1`); translating it requires
resolving `size(_)` (a self-spelling — fine) AND `size(t)` (NOT a
self-spelling — `t` is an unrelated caller variable). `rm "size" "t"`
returns `None`, `smt_of` fails to translate the sub-term, and (per this
codebase's established "untranslatable predicate stays silently unasserted"
convention, not a crash) the WHOLE predicate is dropped: no assumption is
added, `r`'s "own" fact never reaches the call site's VC, and the goal stays
satisfiable both ways — silently skipped, exactly as observed.

Verified this is the actual failure mode, not scope shadowing/dropping: the
entry itself IS found and read correctly (confirmed by testing the Closed
case above, which uses the identical scope-lookup path and does compose);
the failure is strictly inside the resolver's inability to translate a
predicate that mentions a second variable.

**A second, independent, and equally blocking gap exists in the SAME
repro, upstream of the above**: `push`'s own postcondition is never proven
at its definition. `check_fn_post_verdict` (`lib/refinecheck/refine_check.ml`)
routes any refined-ADT-return function to `check_post_induction` (Tier 2)
UNLESS `return_refine_ext` handles it directly (Int/Bool/Float/record only —
a multi-constructor ADT like `Tree` is deliberately excluded). But
`check_post_induction` recognizes exactly one clause-body shape: a top-level
`A.EMatch (A.EVar sv, branches, _)` scrutinizing a structural parameter.
`push`'s body, `Node(t, x, Leaf)`, is a direct constructor application with
NO match at all — the simplest possible case (no induction needed, just one
unfolding of `size`'s definition) — and `check_post_induction` returns
`false` immediately for it, silently (Tier 2 is documented as VERDICT-ONLY,
never emitting a diagnostic either way). Confirmed empirically: giving
`push` a deliberately WRONG postcondition (`size(_) == size(t) + 2`) with the
same non-match body produces `0 proved, 0 violated, 0 trusted, 0 skipped —
by kind: 0 postcondition` — i.e. the checker never even attempted to verify
it, correct or not. Rewriting `push`'s body as an equivalent `match t do ...
end` (still non-recursive) lets `check_post_induction` succeed and
propagation to a DIRECT call site (`needs_bigger(t, push(t, 5))`, no
intervening `let`) then reports `1 proved` — confirming Tier 2 itself, and
direct-call propagation (`reflect_dt`'s `EApp` arm), both work fine once the
body is match-shaped. Only the `let`-mediated path plus a relational
predicate remains broken (see above).

**Net: closing the exact brief repro needs THREE independent things, only
one of which (the scope_add_binding producer widening) was actually
prototyped here:**
1. `scope_add_binding` must seed a `$Meas:`-marked scope entry for a plain
   ADT return from an unannotated `let` (prototyped, verified, reverted).
2. `load_scope_measure_facts`'s resolver must be widened to resolve OTHER
   caller-scope names appearing in a Relational predicate (i.e. `t`, not
   just the entry's own self-spellings) to the SAME term the goal side would
   build for them — this is real, non-trivial new work, not a small filter
   tweak, and is exactly the risk the task-6 brief flagged and asked to be
   re-scoped rather than built under this task's budget.
3. `check_post_induction` must handle a non-match, non-recursive
   constructor-literal clause body for a refined ADT return (trivial case:
   no induction, no recursive IH needed — but it is currently a completely
   separate, unhandled shape) — this is unrelated to composition/consumption
   and belongs to the "postcondition proof, definition side" half of this
   backlog's first bullet, not the "composition" half.

No code was kept from this investigation (the prototype patch to
`scope_add_binding` plus its regression tests were reverted cleanly after
confirming (2) still blocks the target repro) — per the task-6 brief's own
guidance, a producer-only change that cannot yet be exercised by the
repro it was written for risks being misread later as "this is fixed" when
it is not. `lib/refinecheck/refine_check.ml` and `test/test_refinecheck.ml`
are unchanged from `688144dc`.

Recommended next steps for whoever picks this up, in order of leverage:
- (3) first, since it is self-contained, low-risk (VERDICT-ONLY, cannot
  regress an existing diagnostic), and unblocks BOTH direct-call and
  let-mediated propagation for the simple non-recursive case, which is
  probably the MORE common real-world shape (a constructor/builder function)
  than a self-recursive one.
- (1) + (2) together, since (1) alone is inert without (2) for any
  Relational shape, and (2) needs (1) as its producer regardless — this
  should be its own task with its own budget, given the brief already sized
  it as "much larger" and this investigation confirms that sizing.
- Keep the accept/reject pair pattern (`compose_adt_let_suite` in this
  investigation's now-reverted diff shows a usable template: a Closed
  accept, a weaker-fact reject control, and an explicit "known limitation,
  stays skipped" pin for the Relational shape) so the next attempt has a
  regression net from the start.

---
