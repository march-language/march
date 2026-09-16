`[P0]` # An `if` never released a value that was dead on one side

Found 2026-09-16 while chasing
`specs/todos/2026-09-16-simd-box-in-an-aggregate-field-is-never-released.md`,
which turned out to be this bug wearing a SIMD costume. It is not a SIMD bug,
not a `Drop` bug, and not new: every `if`/`else` in the language whose two
sides disagree about a heap value leaked that value, once per evaluation.

## The bug

Perceus's cross-branch dead-variable pass (`insert_rc_expr`'s `ECase` arm,
`lib/tir/perceus_core.ml`) releases a variable in the arms where it is dead,
provided it is live in some other arm. "Live in some other arm" was computed as

```ocaml
let union_live_br = List.fold_left (fun acc (_, _, lb, _) ->
  StringSet.union acc lb) StringSet.empty branches_processed in
```

— a union over `branches_processed`, the TAGGED branches. The `default` arm was
processed afterwards and its live set never entered the union. So a value used
only in the default arm was invisible to every tagged arm's `dead_here` set and
was released nowhere.

An `if` lowers to exactly that shape: one tagged branch (the `then` side) and a
default (the `else` side). A `match` over a variant has all of its arms tagged
and was always correct. That asymmetry is why a gap this wide survived: every
targeted Perceus test asks the question with a `match`.

## Measured

`test/native/if_branch_dead_value_probe.march`, 20,000 iterations each, live
objects before/after:

| shape | before | after |
|---|---|---|
| owned parameter, consumed by a `Cons` on one side only | 20,002 | 2 |
| the same for an `ELet`-bound local | 20,003 | 3 |
| the live side RETURNS the value instead of storing it | 20,004 | 4 |
| recursive: every call but the base one consumes its argument | 20,002 | 2 |
| control: the same question asked with a `match` | 3 | 3 |

And the SIMD leg that opened this, `test/native/simd_nontco_leak_probe.march`'s
third: **60,000 -> 1**. Its `keep(v, k)` is the recursive row above; the box had
an owner on paper (the `Cons` cell) and the base case dropped the reference it
was handed. Nothing in `Drop`, `Kind.needs_rc_of` or the synthesized
`__drop$List_F32x4` was wrong — the generated drop releases the head field
correctly, and always did.

## The fix

Process the default arm before computing the union and include its live set in
it. The `insert_rc_expr` calls still run branches-then-default, so the
fresh-name counter sees the order it always did and no TIR shape moves except
where a release is now emitted.

The exclusion list `dead_here` subtracts (`live_after`, arm-bound vars,
`closure_fvs`, `moved_vars`, `borrowed_field_vars`, the scrutinee itself) is
untouched: this makes the existing rule symmetric across the arms rather than
adding a new rule, so the double-release hazards it already guards against are
guarded identically on the default arm's account.

**Why this cannot release a borrowed value.** `insert_rc` seeds the function's
INITIAL `live_after` with the borrowed set (borrowed parameters union the
closure free variables), and `dead_here` subtracts `live_after`. A borrowed
parameter is therefore live at every point in the function by construction and
can never be chosen here — the same guarantee the tagged-branch half of this
rule has always relied on.

## What it displaces

`Perceus.insert_apply_fn_clo_drop` carried a comment reading

> KNOWN RESIDUAL — a self-recursive capturing apply function still leaks one
> reference per materialization. Its self-binding `let f = inc_rc $clo; $clo`
> hands the alias a reference that is consumed only on the recursive path; on
> the base-case branch nothing drops `f`. That is an independent dead-alias gap
> in the `ECase` branch handling, not something this drop introduces or can fix.

That residual is this bug: the base case is the tagged branch of an `if`, and
the alias is live only in the default arm. `insert_dec_on_dead_paths` exists as
the workaround for it, and it now finds the alias already released at the head
of such an arm — its `Dce.free_vars` test sees the new `dec_rc f` and steps
aside — so the two mechanisms emit one release between them, not two. Visible
in two TIR snapshots as `dec_rc $clo` becoming `dec_rc go`: the same pointer
through the alias name, one release per path before and after. The workaround
is kept for the shapes the cross-branch pass excludes.

## Snapshot review

Five `test/snapshots/perceus/*.expected` moved; each hunk is a release that was
missing:

- `guard_match`: the join-point closure `$jp_clo` is called on the else side and
  dead on the true side.
- `mixed_owned_borrowed_args`: `both(owned, borrowed, n)` returns one or the
  other; each side now releases the one it does not return. Both parameters are
  owned — each is returned on some path, so neither is borrowed, and the
  snapshot shows no `inc_rc` on either return.
- `scrutinee_borrowed_conservatism`: the scrutinee `xs`, whose ownership
  `add_scrutinee_free_for` handed into the `Cons` arm, is consumed on the else
  sub-path and was leaked on the true one. `h` carries its own `inc_rc`, so the
  release frees the cell and not the returned value. The br_vars conservatism
  the fixture exists to pin is unchanged.
- `nested_cons_ctor_heap`, `trmc_modulo_cons`: the alias swap described above.

## Verification

- `test/native/if_branch_dead_value_probe.march`, five legs, with the RED
  control taken against a compiler built from the parent commit: the four
  `if` legs read `flat: false` there and `flat: true` here, and the `match`
  control reads `flat: true` in both.
- `test/native/simd_nontco_leak_probe.march`'s third leg, upgraded from
  printing its length to asserting flatness now that it can be.
- `scripts/run-tests.sh` full: green (the refine audit baseline grows by the
  two lines the new fixture adds, regenerated here).
- `dune build --root . @test/runtest`.
- The ASAN gate in `march-sbx-test-ubuntu`: **81 programs swept, 81 clean, 0
  failed** — 47 golden, 29 curated native, 5 two-node (`partition` skips
  without root). `two-node[skew]` is the scenario that caught the last RC
  change's use-after-free, so it is the one that matters most here: this change
  ADDS releases on paths that never had one, and an over-eager release is a
  use-after-free rather than a leak.
- Benchmarks, interleaved five rounds against a pre-fix compiler on the same
  box and runtime — `tree_transform` 630 vs 641 ms, `list_ops` 67 vs 68 ms,
  `binary_trees` 221 vs 219 ms (medians), peak RSS identical on all three.

## Also closed

- `specs/todos/2026-09-16-simd-box-in-an-aggregate-field-is-never-released.md`,
  removed: it was this bug misdiagnosed. Its two suggested causes were both
  ruled out — `Kind.needs_rc_of` answers `true` for a SIMD type (they are not in
  `k_unboxed`), and the generated `__drop$List_F32x4` does emit a
  `march_decrc_local` for the head field. Nothing was wrong downstream of the
  missing release.
- Item 5 of `specs/todos/2026-09-06-closure-capture-release-widening.md`
  (`node_discovery` as a poor oracle), on independent evidence: 60/60 clean
  locally, plus the ASAN sweep above.
