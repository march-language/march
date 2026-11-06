`[P1]` Compiled `==` on records calls another record type's equality.

Found 2026-11-05 writing test/test_reports/. In a program that declares
`type User = { name : String, tags : List(Role) }` (derive Eq, Show) and
`type Point = { x : Int, y : Int }` (derive Eq), compiled `p == { x: 1, y: 3 }`
with `p : Point` calls `@__march_eq_Ptr`, which is `User`'s field-by-field
equality. It runs `march_string_eq` on Point's `x` field and SIGSEGVs at
address 0x11. No `assert` is needed:

```march
mod T do
  needs IO.Console
  type Role = Admin | Guest | Owner(Int)
  type User = { name : String, tags : List(Role) }
  derive Eq, Show for Role
  derive Eq, Show for User
  type Point = { x : Int, y : Int }
  derive Eq for Point
  test "rec" do
    let p : Point = { x: 1, y: 2 }
    let b = p == { x: 1, y: 3 }
    println(to_string(b))
  end
end
```

`march --compile --test` it and run it: exit 139. Interpreted: `false`.
Without the `User` declaration (or the test that builds a `User`), it works.
The record equality helper seems to be keyed by its LLVM representation
(`Ptr`), so two record types' helpers share one name. Look at how
`__march_eq_*` helpers are named and deduplicated (lib/tir/llvm_emit_eq.ml).

test/test_reports/assert_records.march keeps the plain-record case in its own
file because of this; merge it back into assert_values.march once fixed.
