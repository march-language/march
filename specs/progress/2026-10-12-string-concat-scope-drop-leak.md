# A scope ending in `a ++ b` over an aggregate's fields leaked the aggregate

**Fixed** 2026-10-12. Found by the LSan pass of the native sanitizer sweep
(`scripts/native-sanitize-sweep.sh -l`): `tuple_destructure_rc` reported a
32-byte pair from `march_main`, listed as one-shot under "in `march_main`" in
`specs/todos/2026-10-12-lsan-sweep-remaining-leaks.md`. In a loop it is two
objects per call.

## The bug

```march
fn dup_pair(s : String) : String do
  let t = (s, s)
  let (a, b) = t
  a ++ b
end
```

Perceus's aggregate scope-end drop (`Perceus_core.drop_agg_at_tails`) releases
`t` at each tail of its scope. A tail call that reads a field of `t` at a
BORROWED position (`++` borrows both operands) cannot have the release in front
of it, so the tail is bound first, `let tmp = a ++ b in dec_rc t; tmp`, and that
needs the tail's type. `tir_expr_ty` types a call from its callee's `TFn` type,
or for an untyped primitive from `builtin_op_result_ty`, which knew arithmetic
and comparisons but not `++`. Unknown type means the drop is refused, so the
pair cell leaked with both references to `s`. A record read the same way
(`r.left ++ r.right`) leaked its cell and fields.

## The fix

`builtin_op_result_ty` types `++` as `String` when every operand is a String
(a String variable or literal).

## Verification

- `test/native/string_concat_scope_drop_leak_probe.march`, 200 calls each: a
  fresh tuple, a tuple of a String the caller keeps and reads after the call,
  and a record: 400 / 400 / 600 leaked objects before, 0 after.
- Linux arm64 ASAN error pass and LSan pass on the probe and
  `tuple_destructure_rc`: clean (`tuple_destructure_rc` no longer reports).
