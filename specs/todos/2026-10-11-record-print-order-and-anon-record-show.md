`[P3]` - [ ] **Record printing: field order differs between interpreter and compiled; an undeclared record inside a List/Option does not compile.**

Filed 2026-10-11 while fixing
`specs/progress/2026-10-11-compiled-to-string-anonymous-record.md`.

## 1. Field order

```march
mod Main do
  needs IO.Console
  type R = { b : Int, a : Int }
  fn main(_c : Cap(IO.Console)) do
    let r : R = { b: 1, a: 2 }
    println(to_string(r))                -- interpreted { b: 1, a: 2 }, compiled { a: 2, b: 1 }
    println(to_string({ z: 1, y: 2 }))   -- interpreted { z: 1, y: 2 }, compiled { y: 2, z: 1 }
  end
end
```

The interpreter keeps the order each literal wrote, so two values of one type
can print differently. Compiled records are laid out sorted by field name and
the static type (`TRecord`) is sorted, so compiled code cannot recover the
literal order. Needs a decision: make the interpreter print records sorted
(or in declaration order for a declared type, which compiled code could
match from the `TDRecord`), or carry the order at run time.

## 2. Undeclared record inside a prelude container

```march
println(to_string([{ a: 1 }]))      -- interpreted [{ a: 1 }]
println(to_string(Some({ a: 1 })))  -- interpreted Some({ a: 1 })
```

Compiled, both fail with "ambiguous interface-method call to `show`: 6
implementations are in scope (Show$Unit.show, ...)". The List/Option Show
impl's element `show` has no impl for a structural record type, and the
dispatch reports the ambiguity instead of falling back to `to_string`. This
happens before codegen; the descriptor would print the element correctly
once it is reached.

**Fixed 2026-10-12.** The cause was in mono's interface dispatch
(`lib/tir/mono.ml`, the `EApp` arm). For a `TRecord` argument it looks up a
nominal name, and an undeclared record has none, so the type name was
`None`. Six `Show` impls meant the single-impl fallback did not apply
either, so the bare `show` reached codegen. Now, for `show`/`to_string`
only, an unnamed record gets the sentinel type name `$Record`. No impl
matches it, so the call takes the existing `show` → `to_string` fallback
that a declared type without a `Show` impl already took, and the descriptor
prints it. Other methods keep the single-impl fallback. Fixture:
`test/native/to_string_anon_record_container.march` (interpreted and
compiled against one `.expected`). While writing it, I found that a
one-field `Bool` record prints its field as `1` when compiled, in any
position. That is unrelated and filed as
`specs/todos/2026-10-12-single-bool-field-record-prints-int.md`.
