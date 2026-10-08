`[P1]` Nested constructor pattern on a name the stdlib also uses matches wrongly in compiled code

Found 2026-10-07 while writing `test/native/static_nullary_ctor.march`. A user
type whose constructors share short names with stdlib constructors (`Leaf`,
`Node` -- `stdlib/map.march`, `set.march`, `hamt.march` and others define them)
miscompiles a NESTED pattern on those constructors. The interpreter is right;
the compiled binary takes the wrong arm. It reproduces with and without the
static-nullary-cell change (checked against the unmodified `llvm_emit_alloc.ml`),
so it predates it.

```march
mod Main do
  needs IO.Console
  type Tree = Leaf | Node(Tree, Int, Tree)
  pfn make(d : Int) : Tree do
    if d == 0 do Leaf else Node(make(d - 1), d, make(d - 1)) end
  end
  pfn leaves(t : Tree) : Int do
    match t do
      Leaf -> 1
      Node(l, _, r) -> leaves(l) + leaves(r)
    end
  end
  pfn shrink(t : Tree) : Tree do
    match t do
      Leaf -> Leaf
      Node(Leaf, _, Leaf) -> Leaf
      Node(l, v, r) -> Node(shrink(l), v, shrink(r))
    end
  end
  fn main(_c : Cap(IO.Console)) : () do
    println(int_to_string(leaves(shrink(make(2)))))
  end
end
```

Interpreted: `2`. Compiled: `4` (the `Node(Leaf, _, Leaf)` arm never matches).
The same program with the constructors renamed `T`/`L`/`N` prints `2` both
ways. The post-lower TIR is correct (`case $f of Leaf() -> ...` on the field
binder), so the mismatch is in codegen: the nested case's constructor tag is
most likely resolved by short name to a stdlib type's `Leaf`. Compare the
"ambiguous ctor -> current-module preference" fix, which covered the
top-level scrutinee; a field binder's case evidently takes a different path.
Look at how `emit_case` resolves the tag when the scrutinee is a field binder,
and add this program as a fixture.
