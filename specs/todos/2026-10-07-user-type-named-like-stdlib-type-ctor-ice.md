`[P2]` A user type named like a stdlib type (`Tree`) breaks the stdlib's own matches when compiled

Found 2026-10-07 while fixing
[../progress/2026-10-07-nested-pattern-ctor-name-collision-miscompile.md](../progress/2026-10-07-nested-pattern-ctor-name-collision-miscompile.md).
Present before that change.

```march
mod Main do
  needs IO.Console
  type Tree = Leaf | Node(Tree, Int, Tree)
  fn main(_c : Cap(IO.Console)) : () do
    let m = OrderedMap.put(OrderedMap.new(fn (a, b) -> a - b), 5, "five")
    println(int_to_string(OrderedMap.size(m)))
  end
end
```

Interpreted: `1`. Compiled: internal compiler error
`LLVM emit: constructor Tree.Node has 3 field(s) but field index 3 was requested`.

stdlib `OrderedMap` declares `type Tree(k, v) = Leaf | Node(Tree(k, v), k, v, Tree(k, v), Int)`.
Its functions' scrutinees are typed with the BARE `TCon "Tree"` (the "TCon stays bare"
invariant), so `Llvm_case.qualified_br_key` builds `"Tree.Node"`, which exact-matches the
USER's 3-field `Tree.Node` instead of `OrderedMap.Tree.Node`. This is a type-NAME collision
(`Collision_set` reports `Tree`), not the ctor-name collision fixed above; the
construction side and the match side of OrderedMap need to agree on the qualified
`OrderedMap.Tree` key (or the user's type needs its module-qualified key) whenever the
short type name collides.
