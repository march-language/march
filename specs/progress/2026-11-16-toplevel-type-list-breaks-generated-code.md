`[P2]` Typecheck: a top-level user `type List` breaks the module's generated code

```march
mod Main do
  needs IO.Console
  type List = Link(Int, List) | End
  fn total(l : List, acc : Int) : Int do
    match l do
      End -> acc
      Link(n, rest) -> total(rest, acc + n)
    end
  end
  fn main(c : Cap(IO.Console)) do
    print_line(int_to_string(total(Link(1, Link(2, Link(3, End))), 0)))
  end
end
```

`march --check`: ``List` expects 0 type argument(s) but got 1. [type_arity]`` "in code generated
for this file by a `derive`, `@[endpoints]` or `@[remote]` declaration", although the program
has none of those. Some generated declaration spells the builtin `List(a)` by its bare name and
resolves to the user's type. A `type Result` or `type Option` at the same place does not trip it
(`test/test_codegen.ml` "user type named like a builtin ADT keeps its identity"). The compiled
backend's naming fix covers `List` as well (`Lower_types.builtin_adt_names`), but no program with a
top-level `type List` gets past the typechecker to exercise it.
Found while fixing `specs/progress/2026-11-11-compiled-derive-on-user-type-named-like-prelude-type.md`;
reproduces on `bd2ff7958`.

## Fixed 2026-11-19

The program in the report checks clean on `main` by now: nothing in it spells the builtin
`List(a)` through the bare type table. Adding `derive Eq for List` (or any use that reaches an
unresolved `List(a)`) still failed, and the root cause is shared with
`2026-11-16-nested-type-named-like-builtin-leaks-to-parent-scope.md`.

**Root cause.** `Typecheck_nominal` gives a user variant named like a base type its own identity
(`Main.List`), and every reference the lexical rule sends to the user's declaration resolves to
it. But the declaration was ALSO registered under the bare key in `env.types`, unconditionally
(`lib/typecheck/typecheck.ml:8204` in `check_decl`, and the two pass-1 prebinds at `:12557` and
`:12978` on `2805ec479`), overwriting the builtin `List`'s arity 1 with
the user's 0. Every reference that does NOT resolve to the user's declaration falls through to
`surface_ty`'s generic path (`lookup_type`): the dummy-span types of builtin signatures that the
derived `==` instantiates, and every lazily loaded stdlib signature (`cluster_node.march`,
`node_send.march`, ...; their diagnostics are filtered as stdlib spans, so only the generated
ones were reported).

**Fix.** `Typecheck_env.add_decl_type` is now the one way a type declaration enters
`env.types`: it registers the bare name and the nominal identity, except that a user variant
named like a base type (`Typecheck_nominal.shadows_base`, a new table filled by `compute` for
identities whose short name is `forced_at` its path) is registered under its identity only. The
bare key stays the base type's, which is what the lexical rule says it means.

Regression: `test/test_codegen.ml` "top-level `type List` + derive Eq keeps the builtin List"
(interpreted, and compiled with `MARCH_VERIFY_TIR=1` at `--opt 0` and `2`). RED before the fix
with the reported `type_arity` error.
