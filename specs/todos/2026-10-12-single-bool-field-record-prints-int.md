`[P3]` - [ ] **Compiled `to_string` prints a one-field `Bool` record's field as `1`.**

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
