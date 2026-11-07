`[P1]` Compiled `==` on records called another record type's equality. FIXED
2026-11-07 (GitHub #1171).

Filed 2026-11-05 writing test/test_reports/. In a program that declares
`type User = { name : String, tags : List(Role) }` (derive Eq, Show) and
`type Point = { x : Int, y : Int }` (derive Eq), compiled `p == { x: 1, y: 3 }`
with `p : Point` called `@__march_eq_Ptr`, which was `User`'s field-by-field
equality. It ran `march_string_eq` on Point's `x` field and SIGSEGVed at
address 0x11 (exit 139). Interpreted: `false`. #1171 added the silent cases:
`Pair` compared first made `Triple`'s `==` skip its third field (`true` for
unequal values); `Triple` first made equal `Pair`s compare unequal (the helper
loaded offset 32 from a 32-byte cell); and `eq()` reached the shared helper
through nesting (`derive Eq` compares each field with `==`, and
`impl Eq(List(a))` compares elements with `==`).

## Cause

`Llvm_eq.mangle_ty_for_eq` (lib/tir/llvm_eq.ml; the todo named
`llvm_emit_eq.ml`, which does not exist) had no `Tir.TRecord` case, so every
record fell through to `| _ -> "Ptr"`. `ensure_adt_eq_fn` names its helper
`__march_eq_<mangled>` and returns any helper already registered under that
name in `emitted_eq_fns`, so the first record type compared got the helper
and every later one reused it against its own layout.

Tuples had the same failure in a narrower form: they were mangled
(`Tup_` + elements joined by `_x_`) but not injectively, because tuple arity
was not recorded. `((Int, Int), Int, Int)` and `((Int, Int, Int), Int)` both
mangled to `Tup_Tup_Int_x_Int_x_Int_x_Int`, so whichever was compared second
ran the other's helper (a wrong `true` was confirmed natively).

## Fix

`mangle_ty_for_eq` now mangles every type it can be handed, and the composite
forms record their arity so a nested shape cannot be read as a different one:

- `TTuple ts` → `Tup<N>_` + elements joined by `_x_` (`Tup2_Int_x_Int`).
- `TRecord fs` → `Rec<N>_` + `<field>_<type>` joined by `_x_`, in slot order.
  Field names are length-prefixed (`{ a_b : Int }` → `Rec1_3a_b_Int`), so an
  underscore in a field name is never read as a separator; a name with a
  character outside `[A-Za-z0-9_]` is hex-encoded behind `h`.
- `TFn (ps, r)` → `Fn<N>_` + params and result; `TPtr t` → `Ptr_<t>`. Neither
  reaches `ensure_adt_eq_fn` at the top level (it returns `None` for them),
  but both can appear as a record or tuple field type inside a mangled name,
  and they no longer collapse to one "Ptr".

The other callers of `mangle_ty_for_eq` (`llvm_case.ml`, `llvm_emit_alloc.ml`)
only use it for `MARCH_REPR_AUDIT` report strings; no code depends on the old
spellings. Named `TCon` types keep their existing mangling: each type name has
a fixed arity, so the prefix form stays unambiguous for them. One theoretical
gap is left: `.` in a qualified name and `_` inside a name both become `_`, so
`A.B` and a type literally named `A_B` would still share a spelling. Type
names are CamelCase by convention and no such pair has been seen.

## Tests

- test/test_codegen.ml, group `newtype_derived_method_crash`, five
  compiled-vs-interpreter parity cases (`#1171 …`): Pair then Triple, Triple
  then Pair, record of Strings then record of Ints (the SIGSEGV), `eq()` on a
  nested record field and on a `List` of records, and the two nested tuple
  shapes. All five failed before the fix and pass after.
- test/test_reports/assert_records.march was split out to keep the plain
  `Point` record away from `User`. The todo asked to merge it back once this was
  fixed, but it stays separate: the `test_reports` suite now also runs each
  fixture on `--target js` (#1176), and `to_string` on a record without Show has
  no JS mapping, so this file is in `js_unsupported` while `assert_values`
  keeps its JS coverage. Its header comment now gives that reason.
