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
