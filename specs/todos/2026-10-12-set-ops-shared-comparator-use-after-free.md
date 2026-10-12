`[P2]` - [ ] **Compiled: `Set.union` then `Set.intersection`/`Set.difference` with one comparator closure is a use-after-free.**

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

Interpreted: `[1, 2, 3]` / `[2]` / `[1]`, exit 0. Compiled (`--opt 2`): the
same three lines, then SIGSEGV at exit (exit 139). Each operation alone, or
union alone, is clean.

`scripts/triage.sh`: `MARCH_NO_UNBOX=1`, `MARCH_NO_HOF_SPEC=1` and `--no-opt`
each make it pass; `MARCH_NO_INLINE_RC=1` does not. ASAN:

```
heap-use-after-free ... in march_incrc
  #1 Set.node_contains$SEntry_Int$Int$Int$Fn_Int_Int_Bool$Int$hspec$3__lam0_Set_contains_apply_0_...
freed by:
  #1 march_decrc_freed
  #2 go$apply$1_Set_node_fold_Set_Int_SEntry_Int_Fn_Set_Int_Int_Set_Int
```

So the closure (or the `eq` closure built over it) that `union`'s local `go`
captures is released one time too many by the HOF-specialised/unboxed
`node_fold` apply, and the next user of the shared comparator (`contains`
inside `intersection`) touches freed memory. Start from the `compiler-rc` skill; dump the post-Perceus TIR of `go$apply$1_Set_node_fold_…`.
