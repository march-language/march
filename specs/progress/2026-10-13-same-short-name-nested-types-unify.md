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

2026-11-06: the refinement checker now tells two same-named types apart when their arities
differ (the typechecker never unifies those), so a user `type Tree` beside the stdlib's
`OrderedMap.Tree(k, v)` works in predicates (`specs/progress/2026-11-06-predicate-names.md`).
Same-arity names still make the checker skip, and wait on this todo.

## 2026-11-09: fixed (stage 1 of the design)

`lib/typecheck/typecheck_nominal.ml` gives every VARIANT type whose short name the checked
program declares at two or more module paths its own identity (`A.Note`; the bare name at the
entry module's top level). Each written type is resolved once, by its lexical scope, and the
answer is recorded against its span, so `surface_ty`, the env-less fn-signature prebind
(`prebind_fn_scheme`) and impl heads (`register_impl_shape`) all read the same identity, and a
constructor's argument types mean what its declaration meant from every use site. Constructors
carry the identity as `ci_type` (all seven registration sites go through
`Typecheck_nominal.decl_identity`), so exhaustiveness and pattern checks see exactly one
type's constructors. `canon_type_name` leaves an identity alone. Backends stay bare:
`Lower_types.convert_ty` maps an identity back to its short name, so TIR, mangling and the CAS
are unchanged (ir-oracle: 0 changed). A short name declared once has no entry, so programs
without a collision typecheck exactly as before. Stdlib declarations are not counted.

The repro is now `expected `B.Note` but got `A.Note``, pinned by
`specs/lang/types/reject/t457_same_short_name_variants_do_not_unify.march`.

Still open, in `specs/todos/2026-11-02-typecheck-conflates-same-short-named-types.md`: a user
type named like a built-in or stdlib type (design stage 3).
