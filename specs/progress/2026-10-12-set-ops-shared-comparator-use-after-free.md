`[P2]` - [x] **Compiled: `Set.union` then `Set.intersection`/`Set.difference` with one comparator closure is a use-after-free.** Fixed 2026-10-12.

Filed 2026-10-12 by the interpreter-vs-compiled differential sweep (group V).
Present before that sweep's local-fn generalization fix (checked with the
comparator annotated, which sidesteps the type bug that fix closed).

```march
mod Main do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    let lt = fn (x : Int) -> fn (y : Int) -> x < y
    let a = Set.from_list([1, 2], lt)
    let b = Set.from_list([2, 3], lt)
    println(to_string(Set.to_list(Set.union(a, b, lt))))
    println(to_string(Set.to_list(Set.intersection(a, b, lt))))
    println(to_string(Set.to_list(Set.difference(a, b, lt))))
  end
end
```

Interpreted: `[1, 2, 3]` / `[2]` / `[1]`, exit 0. Compiled: the same three
lines, then SIGSEGV at exit (exit 139), at the default opt level and `--opt 2`.

## Which side over-released

Not the comparator: a shared tree NODE of `b`. ASAN (macOS and Linux, 1 and 14
schedulers) put the freed 32-byte cell's allocation in `make_branch` under
`from_list` (an `SBranch` of `b`), its free in union's
`go$apply$1_Set_node_fold_…` and the stale read in the next operation's
`node_contains` on `b`.

## Root cause

`node_fold`'s `SBranch` arm reuses the node's cell for its local `go`
closure (`reuse node as $Clo_go$1…`) and moves `children` into it. Codegen
(`llvm_case.ml`, `Case_handoff.body_reuses_scrut`) finds that reuse BY NAME
against the `case` scrutinee and, when the cell is shared (RC > 1), IncRCs the
extracted fields first. After `node_fold` was inlined into `Set.union`, the body
read `let node_i2 = node_i1 in case node_i2 of … reuse node_i1 as …`:
`cprop` (`--disable-pass opt.cprop` cleared it; `--bisect-pass` named it)
copy-propagated the EReuse token from the alias to its source, while it
kept the scrutinee (an arm leads with `dec_rc node_i2`, which its existing
guard protects). The names no longer matched. The shared-path IncRC was
skipped, and the children of `b`'s still-live node moved into the fold
without a dup. The fold freed them.

## The fix

`lib/tir/cprop.ml`:
- The `EReuse` token is never substituted, like `EAllocHole`'s token already
  was (the comment there said so; the code disagreed).
- The `case` scrutinee is kept un-substituted when an arm reuses it
  (`Case_handoff.body_reuses_scrut`), not only when an arm leads with its dec,
  so the two names cannot come apart in the other direction either.

## Tests

`test/native/set_ops_shared_comparator.march` (+ `.expected`, rule in
`test/dune`, refine audit baseline regenerated): one comparator and two
pairs of sets (small, and 60-element sets with branch nodes) shared across
union / intersection / difference in both argument orders, each run twice,
plus contains / is_subset / insert / remove, then the originals printed again.
Compiled output equals the interpreter's. Before the fix it was SIGSEGV
(exit 139) at the default opt level and `--opt 2`. Linux ASAN
(`march-ci-ubuntu-step6b`): before the fix, heap-use-after-free at 1 and 14
schedulers. After it, clean at both. The full `test/native` ASAN error pass
after the fix (348 fixtures × 1 and 14 schedulers) has 588 OK and no ASAN or
UBSAN report. The only SIGNAL is `ffi_blocking`, which also crashes with the
base compiler.
