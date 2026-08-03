# A caller's own parameter refinement is dropped whenever it mentions anything but its binder

**Filed:** 2026-08-02 — surfaced while building `forge refine`
(`specs/progress/2026-08-02-forge-refine-precondition-suggestion.md`).

**REVISED 2026-08-02.** This was first filed as "`len` facts don't propagate caller →
callee", which is wrong: `len` is incidental, and measure propagation on its own works
fine. Measurements below. The original framing would have sent someone into
`resolve_measure` when the defect is one resolver in `reflect_scalar`.

## The measurement

Four shapes, each checked alone with `--refine-report`:

| # | Shape | Result |
|---|---|---|
| A | `fn at2(n : Int, i : {Int \| _ < n})` called as `at2(n, i)` from a caller with the **same** refinement on `i` | **skipped** |
| B | `fn need_ne(ys : {List(Int) \| len(_) > 0})` forwarded from a caller with the same refinement | **proved** |
| C | `fn at3(xs : List(Int), i : {Int \| _ < len(xs)})` forwarded likewise | **skipped** |
| D | the fact of A arriving as a **path guard** — `if i < n do at2(n, i) else 0 end` | **proved** |

B proves, so measure composition is not the problem. D proves, so the solver, the
cross-parameter goal reflection and the VC machinery are all fine. A and C differ from D
only in the *channel* the fact arrives through.

The VC for A is complete in four lines — the caller's own promise is simply absent:

```smt
(declare-const i Int) (declare-const n Int)
(assert (not (< i n)))     ; only the negated goal
(check-sat)
```

Nothing constrains `i` or `n`, so it is satisfiable both ways → `solver-undecided` → the
call is silently unchecked.

## Root cause

`lib/refinecheck/refine_check.ml`, in `reflect_scalar`'s `EVar` arm (~line 2593) — the
code that carries a caller-scope refined local's own refinement across as an assumption:

```ocaml
| Some (b, q, m) when scalar_sort_of_marker m = Some sort ->
  let rv n = if n = b || n = "_" then Some xc else None in
  let assumptions =
    match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None) q with
```

Two independent gaps, both silent:

1. `rv` returns `None` for every name that is not the self-binder. For `{Int | _ < n}`
   the sub-term `n` fails, so `smt_of` returns `None` for the WHOLE predicate and
   `assumptions = []`. Case A.
2. `~resolve_measure:(fun _ _ -> None)` drops any measure in the predicate the same way.
   Case C fails for this reason independently of (1).

The same function already knows how to do this correctly on the other channel:
`path_resolve_var` reflects a caller variable to `Const name` at `caller_scalar_of name`,
with explicit guards so a `Str`-sorted or record-sorted name is not re-declared at `Int`
(one symbol at two sorts makes z3 emit an error line, which desynchronises the shared
`z3 -in` channel and silently disables refinement checking for the rest of the run).

## Sketch of the fix

In that arm, replace the two stub resolvers with caller-namespace ones mirroring
`path_resolve_var` / `measure_of_var`:

- `rv n` — self-binder spellings (`b`, `_`, and the variable's own name `x`) → `xc`;
  any other name → `Const n`, declared at `caller_scalar_of n`, subject to the same
  `str_names` / `is_recvar` guards. The new declaration must be appended to the `decls`
  list `reflect_scalar` already returns, not just asserted.
- `resolve_measure m n` → route through the existing memoized `measure_of_var m n` so the
  assumption and the goal meet on the one `m$n` symbol. `reflect_scalar` currently has no
  access to that cache, so either thread it in or hoist the arm to the call-site builder
  that owns it — the latter is probably cleaner and is where `load_scope_measure_facts`
  already lives.

Note that `reflect_scalar` is called for BOTH the goal side and the assumption side; only
the assumption side (this arm) should change. Check the postcondition arm just below it,
which has the identical `rv` restriction and is likely the same bug for a returned value.

## Acceptance

- A, C proved; B, D still proved.
- REJECT witness (non-negotiable): `fn bad(n : Int, i : Int) do at2(n, i) end` — with no
  promise about `i` at all — must STILL be skipped. If it starts proving, the fix is
  laundering the goal rather than carrying a fact.
- A second REJECT witness for shadowing: a caller whose predicate mentions `n` where `n`
  is rebound between the parameter and the call must not use the outer `n`. The
  shadow-retirement discipline in `specs/progress/…refinecheck_shadow_discipline` applies
  — attributing an outer fact to an inner binding is the cardinal false-positive.
- `forge refine` then proposes `{Int | _ >= 0 && _ < len(xs)}` for the `pick` shape in
  the sibling todo, which its grammar already contains.

## Related

- `specs/todos/2026-08-02-match-arm-does-not-refute-a-measure-fact.md` — a genuinely
  separate gap (a fact that is never *derived*, rather than one derived and then dropped).
