# Abstract refinements, the leftovers: phase C (tuple element returns, `List.partition`)

**Date:** 2026-10-18
**Design:** `specs/2026-10-18-abstract-refinements-leftovers-design.md` §5, §6.3, §9.3
**Base:** `1ef3d4b76` (branch `claude/refinement-todos-73b0dc`: both soundness fixes, phases A and B,
element-flow phase 1)

## What a user sees

| Program (design row) | Before | After |
|---|---|---|
| `let (pos, neg) = List.partition(ys, fn y -> y > 0)`; `sum_pos(pos) + sum_nonpos(neg)` (P1) | 2 × `unreflectable-subject` | **proved, proved** |
| `match List.partition(ys, fn y -> y > 0) do (pos, _) -> sum_pos(pos) end` (Z3) | `unreflectable-subject` | **proved** |
| user natural-style `part(xs, pred : a -> Bool[p]) : (List(a[p]), List({a \| !p(_)}))` with `let (yes, no) = part(t, pred)` (P2) | return never checked; calls `unreflectable-subject` | body **proved** (tuple self-hypothesis); calls **proved** |
| `sum_pos(neg)` (C5) | `unreflectable-subject` | `abstract-refinement-too-weak`, "in the element slot `!p(_)` (read as `!(y > 0)`)" |
| a wrong `part` (halves swapped, an element in both, the negation dropped, the Nil tail's components swapped, a wrong natural body) | the tuple return was **never checked**: no violation for the return-side mistakes | a **violation** at the wrong push or tail; no caller proved. **Not** true of the first commit for a body that recurses with another predicate; see the review follow-up below |
| `fn split_pos(xs : List(Int)) : (List({Int \| _ > 0}), List(Int))`, destructured (C9) | return never checked, call `unreflectable-subject` | **proved**; with a wrong body a violation and the caller skips |

`List.partition` is now

```march
fn partition(xs : List(a), pred : a -> Bool[p]) : (List(a[p]), List({a | !p(_)})) do
  partition_go(xs, pred, Nil, Nil)
end
pfn partition_go(lst : List(a), pred : a -> Bool[p], yes : List(a[p]), no : List({a | !p(_)}))
    : (List(a[p]), List({a | !p(_)})) do …  -- one pass, two accumulators, two reverses
```

the same algorithm as before with `pred` passed instead of captured by a local `fn`. Both halves are
proved on the definition side under phase B's self-call induction gate (every element obligation at
both recursive calls is PROVED, so the gate never clears); nothing is `@[assume]`d.

## Implementation

- `Refine_scope`: `type ret_elems = Single of entry | Tuple of entry option list`,
  `ret_elems_of_ty` (a tuple under any container-level refinement, one `elem_refinement` per
  component; nested tuples read `None`), `ret_entries`.
- `Refine_param.elem_ret_hyp` carries a `ret_elems`; `container_entry_of_expr`'s hypothesis arm
  matches only `Single`.
- `Refine_check`:
  - `visit_fn`, `has_elem_return`, `last_elem_return_proved`, `ret_elem_demand` and the final
    unreached-tail loop use `ret_elems_of_ty`; the `Single` path is the old code. The rebinding-tail
    rule (row z2) and the hypothesis's closedness check apply to every component.
  - `check_ret_elems` (a tuple tail): an `ETuple` of the right arity component by component; a call
    through `tuple_self_hyp` (the structural condition of the container hypothesis), else
    `abstract_flow ~component:i`, else `declared_tuple_return` (proved, closed, free of the callee's
    abstracts); anything else a skip ("the tuple's components are not traced here").
    `check_ret_shape` dispatches.
  - `abstract_return_slot ?component` / `abstract_flow ?component`: the slot of component `i`.
  - Destructuring: `push_tuple_projs` records `(x_i, $tuple_proj(i, n, g(args)))` in `lets` for
    `let (x₁, …) = g(…)` (the `lets'` `PatTuple` arm) and for a single-arm, guard-free tuple `match`
    on a call (the `EMatch` arm, after the binders' `launder_shadow`).
  - `check_elements`' `via_let` gains the `$tuple_proj` arm before the generic `EApp` one, guarded by
    `tuple_arity`: the tuple self-hypothesis, then `abstract_flow ~component`, then the declared
    proved tuple return, each component entry compared Refined-vs-Refined.
- `Refine_audit`: a `Return` site under a tuple is classified against its OWN component
  (`type_arg_subject`), and a `Param` site now carries `origin_fn` so an abstract slot
  (`yes : List(a[p])`) is read under the function's own abstract refinements, as the checker reads it
  at a self-call. Without the second, `partition_go`'s parameter slots were reported unenforced (a
  gap since phase B's accumulator slots; no stdlib function had one before).
- `stdlib/list.march`: §5.5, plus a doc string stating the contract.

### `lets` consumers, re-grepped (`grep -n 'assoc_opt .* lets' lib/refinecheck/*.ml`)

- `Refine_check.local_lambda_of`: matches `ELam` only.
- `check_elements`' `via_let`: the new arm precedes the generic one, so a projection never reaches
  `abstract_flow` as a call to `$tuple_proj`.
- the `lets'` alias arm (`let p2 = pos`): copies a projection forward unchanged (tested).
- `Refine_call` (`:425`, and `alias_withdrawal_cause`'s `List.exists` over `lets`): compares a head
  against a withdrawn measure spelling, which `$tuple_proj` never is; a projection's inner call can
  match exactly as the same call bound by a plain `let r = g(…)` always could. Wording only; the
  oracle shows no line moved.

## Conservative calls (beyond, or not settled by, the design)

- **The marker carries the arity**: `$tuple_proj(i, n, call)` rather than §5.4's `$tuple_proj(i, e)`,
  and a reader requires the callee's declared tuple to have arity `n`.
- **A destructuring whose call mentions one of its own binders records nothing**
  (`let (ys, neg) = part(ys, …)`): the entry would name the NEW `ys` (the §3.4 incoming fact reads
  it). Tested.
- **Only a direct call** on the right of `let (…)` or as a single-arm `match` subject; a tuple bound
  whole and taken apart later carries nothing (design §7).
- **A callback parameter with a tuple codomain** carries nothing (`declared_tuple_return` declines a
  `cbenv` name); `declared_elem_return`'s callback route has no tuple counterpart.
- **Ledger labels follow the container-env convention**: a component compared Refined-vs-Refined is
  recorded under the variable or sub-call (`pos`, `part_go(…)`, `rev(…)`), an abstract instantiation
  under the demanding function (`sum_pos`).
- **A wrong body that is only unconstrained** (`(Cons(h, a), b)` with no test on `h`) is a skip at
  the push, not a violation, as for any container return; the C9 control uses a literal `0`.

## Tests (`test/test_refinecheck.ml`, group `abstract-leftovers-c`, 20 cases)

Every case asserts the whole module's ledger triple as well as the moved callees' verdicts.

RED by verdict on `1ef3d4b76` (this test file built in a detached base worktree), GREEN after:
C1 (inline `part_go`), C1 against the shipped `List.partition` (user `(2, 0, 0)`, partition's
own definition side `(14, 0, 0)`), C2, C3, C4e (Nil tail swapped: no violation on the base), C4f
(wrong natural body: no violation on the base), C5, C6 (`sum_nonpos(neg)` untouched and proved),
C9, C10 (three: inline and shipped compile under `cap verified`; a swap is an error), the alias
control, the §3.4 control (`part(pos0, fn y -> y > 5)` gives `small` `_ > 0 && !(y > 5)`), and the
audit case. RED only by ledger triple (the verdicts were already "not proved" on the base, which
recorded nothing for the return): C4 swapped, C4 both halves, C4 negation dropped (two shapes), C7,
C8 (two-arm, and a refutable single arm), the binder-mention case, C11 (a caller declaring its own
`p`: `let (pos, neg) = part(ys, keep)` returning `neg` as `List(a[p])` is not proved, `pos` is).

**Perturbation** (each a one-line change; every `abstract-*` group re-run each time; nothing
outside `abstract-leftovers-c` moved. The seven checker rows were run before the audit case was
added, over the 19 checker cases; the two audit rows after):

| Change | Reddens exactly |
|---|---|
| no `PatTuple` arm in `lets'` | C1, C1L, C3, C5, C6, C9, C10, alias, §3.4, C11 |
| no single-arm `match` entries | C2 |
| `tuple_self_hyp` always `None` | every checker case but the five C4 cases (the wrong bodies stay unproved) |
| no component slot (`abstract_return_slot ~component` → `None`) | C1, C1L, C2, C3, C5, C6, C7, C8, C10, alias, §3.4, binder, C11 |
| no declared tuple return | C9 |
| no `ETuple` tail arm | all 19 checker cases |
| no binder-mention guard in `push_tuple_projs` | the binder-mention case |
| audit: `Param` sites without `origin_fn` | the audit case |
| audit: a tuple `Return` site asked about the whole tuple | the audit case |

**Runtime** (`test/stdlib/test_list.march`, pinned on the OLD body first, green before and after):
each half in input order, the empty list, all-pass, all-fail, the halves' union is the input. A
deliberate wrong expectation was seen to fail first.

**Conformance corpus.** `accept/t370_refine_abstract_partition_tuple` (P1, Z3 and C9 under
`cap verified`; exit 1 on the base) and `reject/t371_refine_abstract_partition_component_swap` (C5,
pinned on the slot-reading text; the base rejects it with a different message).
`check_types.sh`: 459 passed, 0 failed; `INDEX.md` 195 accept, 264 reject.

## Verification

- `dune build --root . bin/main.exe test/test_refinecheck.exe test/run_compiler.exe
  test/test_stdlib_march.exe`: ok.
- `./_build/default/test/test_refinecheck.exe -e` (VC cache cleared once): 1147 tests, all passed,
  0 `[SKIP]`.
- `scripts/run-tests.sh -q compiler`: 1348 passed. `scripts/run-tests.sh -q stdlib`: 825 passed.
  `./_build/default/test/test_stdlib_march.exe -e`: 80 passed. `scripts/check-docs.sh`: passed.
- **Refine oracle**: baseline from a detached `1ef3d4b76` worktree at the same depth
  (`.claude/worktrees/phc-base-1ef3d`), check from this worktree, private HOME, no
  `_build/default/stdlib` in either: 549 fixtures, every one changed in exactly one way: the
  `(user + stdlib)` line `+14 proved` and its `by kind` line `+14 precondition`, with violated,
  trusted and skipped unchanged (for `stdlib_list`, where `list.march` is the user file, the
  `(user code)` lines move by the same 14). The 14 are partition's new definition-side proofs:
  `partition_go`'s two pushes × three slots (the head, `yes`/`no` passed on), the `Nil` tail's two
  components (`reverse(…)`), the two recursive tails' two components each (the tuple hypothesis), and
  `partition`'s tail's two (`abstract_flow ~component`). Nothing moved from proved.
- `stdlib/list.march` CI ratchet: 37 skipped (user + stdlib) on base and branch; ceiling 37. Proved
  63 → 77.
- `test/refine_audit` baselines regenerated: every fixture `135 → 145 enforced` (`partition` and
  `partition_go`: 4 return components, 2 accumulator slots, 2 × `Bool[p]`'s domain and codomain),
  `stdlib_list`'s user line `23 → 33`, 0 unenforced everywhere but the holes fixture's deliberate 1.
- **Perf** (cold `--check --stdlib-source --refine-report stdlib/list.march`, private HOME rebuilt
  per run, VC cleared once, base and branch interleaved, load ~22-38): base 1.32 (cold) / 1.23 / 1.22
  / 1.22 s, median **1.22 s**; branch 1.35 (cold) / 1.23 / 1.23 / 1.21 s, median **1.23 s** (101%,
  within 110%).
- **Runtime** (`--compile --opt 2`, 200k-element list partitioned ×50, interleaved warm runs, load
  ~26): base 0.187 / 0.190 / 0.190 / 0.197 / 0.188 s (median 0.190), branch 0.191 / 0.177 / 0.194 /
  0.180 / 0.193 s (median 0.191): parity, identical output. `bench/list_ops.march` compiled: output
  identical (`333333666666`), 0.056-0.071 s on both.
- Ecosystem repos: `conduit`/`depot` contain no `partition` call (grepped); not re-run.

## Review follow-up (second commit): the hypothesis ignored the definer argument

An independent review of `a2f9fb2a5` found a CRITICAL false proof, runtime-confirmed (the checker
reported every obligation proved; the program then divided by zero):

```march
fn part(xs : List(a), pred : a -> Bool[p]) : (List(a[p]), List({a | !p(_)})) do
  match xs do
  Nil -> (Nil, Nil)
  Cons(h, t) ->
    let (yes, no) = part(t, fn y -> true)      -- not `pred`
    if pred(h) do (Cons(h, yes), no) else (yes, Cons(h, no)) end
  end
end
```

The structural induction hypothesis (`tuple_self_hyp`, and `container_entry_of_expr`'s arm for a
single container) was taken whenever some argument was a structural subvariable, whatever the call
passed for the definer. `fn y -> true` makes the recursive result's elements satisfy `true`, not
the caller's `p`. Also through a single-arm `match`, a direct tail `part(t, fn y -> true)`, two
definers passed swapped, and a name rebound to another lambda.

**Pre-existing for a single container.** Probed on `1ef3d4b76` (a real build of the base):
`filt(xs, pred : a -> Bool[p]) : List(a[p])` recursing as `filt(t, fn y -> true)` had its return and
the caller's `sum_pos(filt(ys, fn y -> y > 0))` proved (4 proved, 0 skipped). Phase C copied the
condition into the tuple path. CHANGELOG `### Fixed` names it.

**Fix.** `elem_ret_hyp` carries, per abstract refinement of the function, its definer parameter's
position, name and the `cbenv` entry the clause starts with. `hyp_applies` (shared by both paths)
additionally requires each such position to receive a bare variable of that name whose current
`cbenv` entry is that very entry (physical equality: every rebinding of the name, `let`, `match`
binder or lambda parameter, retires or replaces it). A definer the env holds no signature for
leaves no hypothesis at all. **Conservative call:** an alias (`let q = pred`, then `part(t, q)`) is
declined; it would need alias tracking for no stdlib or test use.

The `abstract_flow` route the declined calls fall back to instantiates the callee's `p` with
whatever the call passes, so `filt(t, pred)` after the function is proved still reads as `p` and
`filt(t, fn y -> true)` as `true`.

**Tests (group `abstract-leftovers-c`, 6 new; RED on `a2f9fb2a5` by verdict unless noted):**
H1 (the single-container shape; RED by verdict on `1ef3d4b76` too), H2 (four shapes: destructured,
single-arm `match`, direct tail, a rebound name before a direct tail), H3 (two definers swapped),
H5 (the alias, pinned as declined). H4 (an accumulator recursing with `fn y -> true` /
`fn y -> false`) was already not proved on `a2f9fb2a5` (its `no` push fails under `!true`) and is
a guard, RED there only by ledger triple. Control, green on both: recursion passing `pred` itself
still proves, single and tuple.

**Perturbation.** Dropping the definer requirement reddens exactly H1, H2, H3, H5; keeping the name
check but dropping the `cbenv` identity check reddens exactly H2 (its rebound-name shape). No other
`abstract-*` group moved under either.

**Verification (second commit).** `test_refinecheck.exe -e` (VC cleared once): 1153 tests, all
passed, 0 `[SKIP]`. `scripts/run-tests.sh -q compiler`: 1348 passed. Refine oracle against the same
`1ef3d4b76` baseline: the same diff as the first commit, line for line (every fixture `+14 proved`,
nothing else); the fix moves no corpus line, since `partition_go` recurses with `pred` itself.
`list.march` ratchet 37 (ceiling 37), proved 77. Audit baselines unchanged.

## Still open

Phases D and E of the design, and the String-callback todo from phase B. Out of scope by design
(§7): a tuple component through `Tuple.first`, a tuple bound whole and destructured later, nested
tuples, a tuple inside a container.
