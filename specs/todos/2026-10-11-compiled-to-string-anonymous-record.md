`[P3]` - [ ] **Compiled `to_string` of an undeclared record prints `#<tag:0>`.**

Filed 2026-10-11 while working on
`specs/progress/2026-10-11-compiled-to-string-newtype-niche.md`.

A record literal whose shape matches no declared record type prints its tag
compiled, whatever its fields are:

```march
mod Main do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    println(to_string({ a: 1, b: "x" }))   -- interpreted { a: 1, b: "x" }, compiled #<tag:0>
  end
end
```

The same record with a declared type (`let r : R = { ... }` where
`type R = { a : Int, b : String }`) prints correctly.

## Why

`Llvm_ctor_desc.id_for` matches a structural `TRecord` back to a declared
record by field names and slot kinds. With no declaration there is no
descriptor entry, so the call site falls back to `march_value_to_string`,
which has no field names for the cell.

## Fix direction

Give structural records their own descriptor entries (field names are in the
static type). The descriptor is built at the first call site that needs it,
so this needs the same "collect first, or emit at the end of the module"
change as `specs/progress/2026-10-11-to-string-newtype-in-generic-slot.md`
(which made it: the descriptor is now defined at the end of the module).
