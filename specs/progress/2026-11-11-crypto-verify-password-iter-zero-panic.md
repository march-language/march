`[P2]` Crypto.verify_password panics in compiled code when the stored hash has an iteration count <= 0 (2026-11-11)

`verify_password` matches the `pbkdf2_sha256` result with a single `Ok` arm. For a stored hash whose iteration field is `0` or negative the compiled runtime returns an error, and the match fails with a panic instead of returning `false` like every other malformed hash. The interpreter returns `false` for the same input, so the backends disagree. A stored hash is data from a database, so one bad row crashes the login path.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(Crypto.verify_password("hunter2", "pbkdf2:sha256:0:30313233343536373839616263646566:a63e13df90f6bf8b58982d6c4c9d72e6d70c00339db67406bee1e6c980d08768")))
end
end
```

Expected: `false` on both backends

Actual (interpreted / compiled): `false` / panic `no pattern of this match matched`, exit 1

Source: `verify_password` in stdlib/crypto.march.

## Fixed 2026-11-18

Root cause: the two `pbkdf2_sha256` builtins disagreed. `march_pbkdf2_sha256`
(runtime/march_extras.c) returns `Err("pbkdf2_sha256: invalid parameters")` for
`iters <= 0` or `dklen` outside 1..1024; the interpreter's builtin
(lib/eval/eval_builtins.ml) had no check, so its loop ran one iteration and
returned `Ok`. `verify_password` only had an `Ok` arm, so only the compiled
build reached the missing `Err` case.

- lib/eval/eval_builtins.ml: the interpreter's `pbkdf2_sha256` applies the
  runtime's bounds and returns the same `Err`.
- stdlib/crypto.march: `verify_password` maps `Err(_)` to `false`; doc no longer
  says it panics, and gains a doctest for the iteration-0 hash.
  `hash_password` passes fixed valid constants (600000, 32), so its `Ok`-only
  match cannot reach `Err`; left as is.
- test/test_stdlib_suite.ml: "verify malformed hash is false, compiled +
  interpreted" (`Slow`, crypto stdlib group) runs one program on both backends:
  iterations 0 / 1 / negative / non-numeric / empty / past Int range, bad and
  odd-length salt hex, non-hex digest, too few and too many fields, wrong
  algorithm, empty string, plus the raw builtin's `Err` for iters 0 and -3 and
  dklen 0 and 2000.

Not covered: a stored iteration count that parses but is enormous (say 10^15)
is still honoured and makes `verify_password` run for a very long time on both
backends; capping it would be a policy change.
