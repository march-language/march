# `[P2]` Two nested-module types with the same short name are one type to the typechecker

**Logged:** 2026-10-13, found while writing the design proposal in
`specs/todos/2026-10-03-derive-json-same-short-name-two-modules.md` (section of the
same date), which covers the fix.

A value of `A.Note` is accepted where `B.Note` is expected when both are declared in
nested modules of one program. No `derive` is involved. `march --check` is clean; the
program then fails at run time in both backends.

## Repro

```march
mod Mix do
  needs IO.Console
  mod A do
    type Note = NA(Int) | NB(String)
    fn make() : Note do NA(3) end
  end
  mod B do
    type Note = NC(Bool) | ND(Int, Int)
    fn describe(n : Note) : String do
      match n do
        NC(b) -> if b do "NC true" else "NC false" end
        ND(x, y) -> "ND " ++ int_to_string(x + y)
      end
    end
  end
  fn main(c : Cap(IO.Console)) do
    print_line(B.describe(A.make()))
  end
end
```

- `--check`: exit 0.
- Interpreted: `panic: match failure — Non-exhaustive pattern match: no branch matched the value NA(3).`
- Compiled: `non-exhaustive pattern match` panic.

Expected: a type error at `B.describe(A.make())` (`A.Note` is not `B.Note`).

## Cause and fix

The typechecker collapses a written `A.Note` to the bare `Note`
(`typecheck_unify.ml`, `typecheck_env.ml`) and constructors record a bare parent type,
so both declarations are the same nominal type. The staged fix (qualified identity for
variant types whose short name is declared at two or more module paths, stdlib
excluded) is the design proposal in the derive-Json todo; this todo is its reject case.
Landing it makes previously-accepted programs that mixed the two types into type
errors (a Changed entry).
