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
