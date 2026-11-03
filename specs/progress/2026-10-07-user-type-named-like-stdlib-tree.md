# `[P2]` A user type named like a stdlib type (`Tree`) breaks the stdlib's own matches when compiled

**FIXED 2026-10-07.** Found while fixing the nested-pattern ctor-name collision (PR #868,
`specs/todos/2026-10-07-user-type-named-like-stdlib-type-ctor-ice.md` on that branch).

## Problem

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
`LLVM emit: constructor Tree.Node has 3 field(s) but field index 3 was requested`
(`lib/tir/llvm_emit_alloc.ml`, `emit_alloc_ctor`'s multi-field arm).

## Root cause

Two places resolved OrderedMap's own `Tree(k, v)` to the user's `Tree`, both because the
static type stays the bare `TCon "Tree"` for both declarations (`Collision_set`'s
"TCon stays bare" invariant) and the entry module's types are registered under the BARE
name while a stdlib module's are module-qualified (`OrderedMap.Tree`):

1. **Constructor keys** (`lib/tir/lower_expr.ml`, the `ECon` arm; `lib/tir/lower_match.ml`,
   `pat_tag_and_subs`'s bare-tag branch). Inside OrderedMap a `Node(..)` construction
   lowered to the key `"Tree.Node"` and a `Node(..)` pattern on a `Tree`-typed scrutinee
   to a branch keyed `"Tree.Node"` (`Llvm_case.qualified_br_key`). With no user type that
   key has no exact `ctor_info` hit and `Llvm_data.ctor_entry`'s suffix resolver finds
   `OrderedMap.Tree.Node`; with the user's `type Tree` it is an EXACT hit on the user's
   3-field `Node`, so the 5-field construction asked for field index 3 (the ICE), and the
   matches tested the user's tags. The narrow collision qualification that already exists
   (`Lower_state.shared_ctor_collision_tbl`) is gated on public, impl-bearing collisions,
   and the user's `Tree` has no `impl`.
2. **The drop** (`lib/tir/drop.ml`, `colliding_union`). With the constructor keys fixed the
   binary ran and segfaulted: `__drop$Tree_Int_String` switched on the USER's two tags.
   The collision union refused both candidates of `Tree(Int, String)` (the user's type has
   no parameters, so "params do not line up with ty_args"; and the shared `Node` has
   different fields, so the "consistent" check failed), and the fallback exact lookup of
   `Tree` is the user's type. An `OrderedMap.Tree` cell reached the drop's `unreachable`
   default.

## Fix

- `Lower_state.own_module_ctor_key`: a constructor of type `T`, constructed or matched
  bare inside module `P` (or written `P.Ctor`), is keyed `P.T.Ctor` when `P` declares `T`
  itself AND a bare-named `T` also exists (the entry module's own type, or a builtin
  Option/Result/List). Only then is the bare key an exact hit on the wrong type; every
  other case (including the cross-module `ptype` hand-offs that rely on the suffix
  resolver) keeps its bare key. Used at the `ECon` arm, the bare-tag pattern branch (with
  the pattern span's recorded type when a nested pattern's scrutinee var is erased), and
  the module-qualified pattern reading.
- `Drop.colliding_union`: a candidate whose fields mention more type variables than the
  use site supplies cannot be that type and is skipped; a parameterless candidate needs
  no substitution and is taken as is. The "same-named constructors must have the same
  fields" guard exempts pairs with the bare-named candidate, whose constructions, and
  its twins' (now module-qualified), each carry their own tag.

## Verification

- `test/native/user_type_named_like_stdlib_tree.march` (+ `.expected`, the interpreter's
  output; dune rule `native_user_type_named_like_stdlib_tree`): a user `Tree` beside
  OrderedMap, both built, matched (including a nested pattern), dropped, with no
  live-object growth across 200 iterations of each. RED on `origin/main`: the ICE above,
  `--compile` exit 3. With only the constructor-key half: SIGSEGV (exit 139) in
  `__drop$Tree_Int_String`. GREEN with both.
- `test/native/{local_colliding_type,colliding_type_drop,aggregate_drop_erased_fields}`
  still match; `niche_ctor_ambiguity` compiled still matches the interpreter.

## Note for PR #868

#868's `pat_tag_and_subs` change qualifies a bare tag on an erased scrutinee with the
pattern's type (`"Tree.Leaf"`), which inside OrderedMap is again an exact hit on a
user's `Tree`. When the two are merged, the `own_module_ctor_key` check must run before
that `type_name ^ "." ^ tag` fallback.
