`[P2]` Native equality on a newtype wrapping a generic named record uses pointer identity.

Found 2026-11-06 while fixing record equality helper collisions. This is a
separate failure: the generated `__march_eq_Wrap_String` calls
`march_poly_eq` on its raw record payload, rather than a structural record
helper. The payload remains `TCon("Cell", [TString])`; the equality generator
cannot resolve the named generic record into its fields.

```march
mod GenericRecordEq do
  needs IO.Console
  type Cell(a) = { value : a }
  type Wrap(a) = Wrap(Cell(a))
  derive Eq for Cell
  derive Eq for Wrap
  fn main(_cap_console : Cap(IO.Console)) do
    let a : Cell(String) = { value: "ann" }
    let b : Cell(String) = { value: "bob" }
    let c : Cell(Int) = { value: 1 }
    let d : Cell(Int) = { value: 2 }
    println(bool_to_string(Wrap(a) == Wrap({ value: "ann" })))
    println(bool_to_string(Wrap(a) == Wrap(b)))
    println(bool_to_string(Wrap(c) == Wrap({ value: 1 })))
    println(bool_to_string(Wrap(c) != Wrap(d)))
  end
end
```

Interpreted output: `true`, `false`, `true`, `true`.
Compiled output: `false`, `false`, `false`, `true` (exit 0).
Reproduced with the compiler based on b7c963d74. Inspect the named-record
resolution used by `lib/tir/llvm_eq.ml` before changing the runtime comparator.

## 2026-11-09: fixed

`Llvm_eq.ensure_adt_eq_fn` now resolves a `TCon` that names a nominal record of the module
(`Kind.record_fields`, or exactly one by short name via `Kind.record_fields_short`) to the
structural `TRecord` it names and compares it field by field with the record helper. The type
arguments are substituted against the record's DECLARED parameters, which
`Lower_decls.lower_type_def` now records in `Lower_types.record_type_params` (a `TDRecord`
carries no parameter list, and its field order is not its parameter order). A generic record
whose parameters are unknown keeps the old `march_poly_eq` fallback. Pinned by the codegen
parity test "== on a newtype over a generic named record is structural", which also covers a
two-parameter record declared with its fields in the opposite order.
