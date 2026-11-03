`[P3]` - [x] **Compiled `to_string` prints a one-field `Bool` record's field as `1`.**

Filed 2026-10-12 while fixing the undeclared record inside a container
(`specs/progress/2026-10-11-record-print-order-and-anon-record-show.md`).

```march
mod Main do
  needs IO.Console
  type P = { n : Bool }
  fn main(_c : Cap(IO.Console)) : Unit do
    println(to_string({ n: true }))        -- interpreted { n: true }, compiled { n: 1 }
    let p : P = { n: true }
    println([p])                           -- interpreted [{ n: true }], compiled [{ n: 1 }]
    println(to_string({ m: 1, n: true }))  -- both print { m: 1, n: true }
  end
end
```

This happens only when `Bool` is the record's ONLY field. `{ n: 1.5 }` and
`{ n: "s" }` print correctly. It happens for declared and undeclared records,
at top level and inside a list. The likely cause is that a one-field record
of a scalar uses a different layout (unboxed or newtype-shaped), and the
printing descriptor still reads the field as an untyped word. Start with
`lib/tir/llvm_ctor_desc.ml`'s structural-record row and `Kind`'s unboxing
decision for a one-field record.

**Fixed 2026-10-12.** It was not a layout question. A one-field record is an
ordinary boxed cell. `Llvm_ctor_desc.declared_record_id` maps a structural
record back to a declared one, so that a `ptype` alias prints through its
declaration's row. It matched by field names and `Llvm_data.shape_kind_char`,
and that function maps Int, Bool, Unit and Atom all to `'i'`. So
`{ n: true }` matched the stdlib's `SessionNode.ApInbox.State = { n : Int }`
and printed through its `i` token. The declared `P = { n : Bool }` lost the
same way, because the match is first-wins over a hash table. Only the
one-field case showed it, because no declared record had fields `{m, n}`.
Any field name shared with a declared record of a different field type is hit
the same way: `{ k: true }` against a user `{ k : Int }` printed `{ k: 1 }`,
and `{ v: "x" }` against a `{ v : List(Int) }` printed the String unquoted.

The match now compares the field types themselves, with the scalar spellings
normalised (`TCon "Bool"` = `TBool`, `TCon "Unit"` = `TTuple []` = `TUnit`).
A record with no exact declared match gets its own structural row
(`record_instance_id`), which prints each field by its own type.

The other shapes in the sweep were already right: one-field Float, Char, `()`
and String records, a declared one-field Float record, and `W(Bool)`, at top
level and inside a List or an Option. The Char case prints `{ c: "a" }` in
both backends.

Gate: `test/native/to_string_one_field_record.march`, interpreted and compiled
against one `.expected`. Without the fix the compiled run differs on 9 lines.
