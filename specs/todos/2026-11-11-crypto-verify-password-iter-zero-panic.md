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
