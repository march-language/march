Added `int_div_floor` / `int_mod_floor` (Phase 2 of
`specs/2026-10-29-floor-division-and-const-divisors-design.md`), and switched
`DateTime.from_timestamp` to them.

- Semantics: quotient rounds toward -infinity, remainder takes the divisor's sign, zero divisor
  panics `int_div_floor: division by zero` / `int_mod_floor: ...` on every backend. For a positive
  divisor they equal the Euclidean pair; they differ only for a negative divisor.
- Sites: typecheck `builtin_bindings`, interpreter (`eval_builtins`), C runtime
  (`march_checked_ifloordiv` / `march_checked_ifloormod`), `llvm_builtins` row + `PDeclare`,
  `Builtin_name` constructors, `llvm_emit` (`builtin_group` + the shared `emit_checked_int_div`),
  `alloc_contract`, `defun`, `policy_dce`, `purity`, `division_safety`, `js_emit` + `march_runtime.mjs`.
- Compiled fast path: a positive literal divisor is emitted inline (`sdiv`, `srem`, one `icmp`, one
  `select`) instead of a helper call. A negative literal does not take it: `-2` reaches codegen as
  `negate(2)`, not as an `ALit`, so it uses the helper.
- `datetime.march`'s private `floor_div`/`floor_mod` are gone. They were wrong for a negative divisor
  (`floor_div(7, -2)` gave `-3`; the floor is `-4`); the callers only used 86400, so nothing observable
  changed.
- Not done (still open): inlining `/ % int_div int_mod` and the Euclid pair for literal divisors, and
  the sign-selected multiplier. See the two open items in `specs/todos/`.
