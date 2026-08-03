# A caller's own parameter refinement now survives mentioning another name

**Filed:** 2026-08-02 · **Fixed:** 2026-08-03 — surfaced while building `forge refine`
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

## The fix as landed

`reflect_scalar` gained two optional resolvers, `~foreign_var` and `~foreign_measure`,
both defaulting to the old `None` behaviour so every other caller is byte-identical. Only
the call-site VC builder passes them, because only it owns the caller namespace (scalar
sorts, the string/record registries, the measure memo):

- `foreign_var n` → `Const n` declared at `caller_scalar_of n`, guarded by `str_names` and
  `is_recvar` so a String- or record-sorted name is never re-declared at `Int`. One symbol
  at two sorts makes z3 emit an error line, which desynchronises the shared `z3 -in`
  channel and silently disables refinement checking for the rest of the compilation.
- `foreign_measure` routes through the existing memoized `measure_of_var`, so a promise
  about `len(xs)` and a goal about `len(xs)` land on the one `len$xs` symbol. Two
  independently-declared constants would be unrelated integers and the fact would connect
  to nothing — a skip indistinguishable from a proof.
- `measure_of_var` and its cache were hoisted above `resolve_var` so the new resolver can
  reach them (no behaviour change; OCaml let-ordering only).
- The self-spellings accepted by the assumption side are now `_`, the declared binder, and
  the variable's own name — matching `load_scope_measure_facts`'s `is_self_spelling`. The
  two sides of one fact must accept the same spellings or they meet on different symbols.

### The shadowing hole this opened, and closed

Making cross-parameter promises live exposed a second defect immediately — caught by the
REJECT witness, not by review:

```march
fn bad(n : Int, i : {Int | _ < n}) do
  let n = 0
  at(n, i)              -- `at` needs `i < n`
end
```

`i` is not rebound, so its scope entry survived — but its predicate's `n` means the
PARAMETER while `n` at the call site is `0`. The stale fact and the fresh goal collapsed
onto one `n` symbol and the call "proved", which is unsound: `i < n_param` does not give
`i < 0`.

`scope_shadow` now retires an entry on TWO triggers, not one: its own name being rebound
(as before), **or** its predicate mentioning a rebound name. `expr_mentions` — already used
by `path_shadow` for exactly this — is deliberately over-approximate, so it errs toward
dropping a fact rather than inventing one.

This is the third direction the same cardinal error has arrived from in this subsystem.
The lesson holds: only a test asserting SILENCE catches it.

## Verification

All six cases live in `test/test_refinecheck.ml` under `caller-promise`, asserting the
LEDGER rather than silence — a skip and a proof are indistinguishable from outside.

| Case | Before | After |
|---|---|---|
| A cross-parameter scalar | skipped | **proved** |
| C cross-parameter measure | skipped | **proved** |
| B self-measure (regression guard) | proved | proved |
| D fact via path guard (regression guard) | proved | proved |
| REJECT unpromised caller | skipped | skipped |
| REJECT shadowed name | skipped | skipped (failed mid-fix; see above) |

B and D are kept precisely because they already passed: a fix that broke them would
otherwise have looked like a win.

Downstream, the sibling `pick`/`at` shape from
`specs/todos/2026-08-02-match-arm-does-not-refute-a-measure-fact.md`'s related section now
proves with a hand-written contract, and `forge refine pick` proposes
`{Int | _ >= 0 && _ < len(xs)}` where it previously reported `no-candidate`.

False positives — the direction that matters, since this makes more facts live:

- **0** refinement violations across all 112 stdlib modules.
- **0** refinement diagnostics on conduit (43 files).
- 424 refinecheck, 641 compiler, 256 eval, 22 refine, 829 stdlib tests pass. (The single
  stdlib failure is the pre-existing `MARCH_SANITIZE` environment issue: a trivial
  `printf` C program built with `-fsanitize=address` hangs on this machine while the same
  program without ASAN runs in 0.25s.)

Not measured: a quantified before/after of total proved obligations across the corpus.
That needs a control compiler built from the pre-fix commit, and the targeted evidence
above already establishes the behaviour change.

## Original acceptance criteria

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
