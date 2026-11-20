# `random_bytes` is still callable from user code, unchecked (2026-11-17)

Found by ocap phase 4 Task 8. The gate todo
(specs/progress/2026-11-10-ocap-p1-gate-raw-capability-builtins.md) left
`println` and `random_bytes` out of the stdlib-only table because "the stdlib
shadows them". `println` is shadowed (`Prelude.println`, checked). `random_bytes`
is not: a bare `random_bytes(4)` in a user module resolves to the raw builtin
(`Int -> Bytes`), not to `Crypto.random_bytes` (`Result(Bytes, CapError)`), so it
skips `Authority.check("IO.Random", "")`:

```march
mod B do
  needs IO.Random
  fn main() do
    let b : Int = random_bytes(4)   -- "expected `Int` but got `Bytes`": the raw builtin
    b
  end
end
```

What to do: drop `random_bytes` from `Cap_ops.shadowed_by_stdlib`, so the gate
covers it (hint: use `Crypto.random_bytes`, rename fix offered), migrate its
direct callers, and fix the todo's claim.

## Done (2026-11-19, ocap phase 4 PR B final review fix wave)

`random_bytes` is out of `Cap_ops.shadowed_by_stdlib` (now `["println"]`), so the
gate covers it like the other gated rows: a user reference is a `stdlib_internal`
error, "use `Crypto.random_bytes`", whose fix rewrites `random_bytes(n)` to
`Authority.must(Crypto.random_bytes(n))`. Callers migrated: the embedded programs in
test/test_codegen.ml (`test_main_adapter_three_caps`) and test/test_stdlib_suite.ml
(hmac bytes typecheck, base64 round trip) and scripts/error-cards/src/tokens.march.
The builtin-level tests in test/test_compiler.ml that pin how a check treats a direct
`random_bytes` call (`cap pure`, the body scan) run under
`with_raw_capability_builtins`; test/errors/pure_violation_2 keeps its raw call and
now also draws `stdlib_internal`, like pure_violation_1. `Io_ops_gen.shadowed_by_stdlib`
(which builtins can be a mock-dictionary field) still lists `random_bytes`: there the
point is that `Crypto` defines a March function of that name, which is still true.
Tests: `test_stdlib_only` `raw_capability_builtins_gated` (the shadowed list is
`["println"]`, and a user `random_bytes(4)` is refused with the hint).
Deliberately left raw: about ten cap_infer/chain programs in test/test_compiler.ml
(around lines 14887-15038) still call `random_bytes` directly with the gate on. Their
assertions read only hints, so they pass, but they pin output no user program can now
produce (the same holds for the earlier raw `file_write` tests).
