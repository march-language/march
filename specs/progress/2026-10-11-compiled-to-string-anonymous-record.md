`[P3]` - [x] **Compiled `to_string` of an undeclared record prints `#<tag:0>`.**

Filed 2026-10-11 while working on
`specs/progress/2026-10-11-compiled-to-string-newtype-niche.md`. Landed the
same day.

## What was wrong

```march
mod Main do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    println(to_string({ a: 1, b: "x" }))   -- interpreted { a: 1, b: "x" }, compiled #<tag:0>
  end
end
```

`Llvm_ctor_desc.id_for` matched a structural `TRecord` back to a declared
record by field names and slot kinds. With no declaration there was no
descriptor entry, so the call site fell back to `march_value_to_string`,
which has no field names for the cell. The same held for a tuple inside a
field of a described type: `T((1, "a"))` printed `T(#<tag:0>)`, and
`Box((1, "a"))` the same.

## The change

Built on the instance rows from
`specs/progress/2026-10-11-to-string-newtype-in-generic-slot.md`, which also
moved the descriptor's definition to the end of the module.

- `record_instance_id` (`lib/tir/llvm_ctor_desc.ml`): a `TRecord` that
  matches no declared record gets an `R*` row of its own, its fields from the
  static type in name order (the cell's slot order). An `R` row prints no
  type name, so nothing is lost by having no declaration. `field_token`
  resolves a `TRecord` field the same way, so a record nested in a record or
  in a constructor field is described too.
- `tuple_instance_id`: a tuple in a field gets a `U*` row, one `C` row whose
  fields are the elements. A tuple cell holds its elements in the erased
  convention (a tagged Int read as `3` for `1` with the raw token), so the
  element tokens are `erased_token`'s. Top-level tuples are untouched: they
  are rendered by their Show impl before the table is consulted.
- `runtime/march_extras.c`: `ctor_render` renders a `U` type as `(a, b)`,
  reading its one row whatever the cell's tag.
- Unit as a field (`u: ()`) printed `0`: `field_token` now answers `u` for
  all three spellings of Unit (`TUnit`, `TTuple []`, `TCon "Unit"`).

## Test

`test/native/to_string_structural.march` runs interpreted and compiled
against one `.expected` (13 lines: undeclared records with scalar, newtype,
niche, ADT, tuple, Unit, nested-record and list fields; tuples in declared
and generic fields; interpolation, `inspect`, `~H`).

## Left open

`specs/todos/2026-10-11-record-print-order-and-anon-record-show.md`:

- The interpreter prints a record's fields in the order the literal wrote
  them; compiled code prints them sorted by name (the cell's layout). This
  was already true of declared records. The fixture writes its literals in
  sorted order.
- `to_string(Some({ a: 1 }))` and `to_string([{ a: 1 }])` fail to compile
  ("ambiguous interface-method call to `show`") before codegen is reached.
