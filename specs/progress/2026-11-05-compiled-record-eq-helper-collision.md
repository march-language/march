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

## Resolution — 2026-11-06

`lib/tir/llvm_eq.ml` now assigns records a structural helper identity rather
than falling through to `Ptr`. The key includes field names and recursively
encodes every field type; counted lists and length-prefixed hex names preserve
nested tuple/generic boundaries and distinguish qualified names from
underscore spellings. The original non-record helper names are unchanged.

The plain-record report now lives alongside the nested User record in
`test/test_reports/assert_values.march`; the standalone `assert_records`
fixture is removed. Codegen regressions exercise equal and unequal mixed
record shapes, nested records, direct generic record instantiations, and
adversarial structural helper keys.

Before the fix, `scripts/triage.sh` reproduced native exit 139, and all four
optional-pass switches still failed. The sanitizer traced the failure to a
String comparison loading Point's Int field as a pointer at address 0x11.
The native mixed-shape regression failed the same way, while the key test
found only one unique helper key for thirteen distinct record types.

The separate native equality failure for a newtype wrapping a generic named
record is tracked in
`specs/todos/2026-11-06-compiled-generic-record-newtype-equality.md`.

Verification: all three `record_equality` cases pass, and all thirteen
neighboring `newtype_derived_method_crash` cases pass. The consolidated
rendered-report corpus also passes interpreted/native parity.
