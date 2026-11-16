`[P3]` Crypto.verify_password rejects a stored hash whose hex digest is uppercase (2026-11-11)

The salt is hex-decoded (either case), but the digest is compared as a lowercase hex string. A stored hash whose digest was uppercased by another tool or a database collation never verifies. The doc string says so; decoding both sides to bytes before the constant-time compare would remove the trap.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(Crypto.verify_password("hunter2", "pbkdf2:sha256:1000:30313233343536373839616263646566:a63e13df90f6bf8b58982d6c4c9d72e6d70c00339db67406bee1e6c980d08768")))
  println(to_string(Crypto.verify_password("hunter2", "pbkdf2:sha256:1000:30313233343536373839616263646566:A63E13DF90F6BF8B58982D6C4C9D72E6D70C00339DB67406BEE1E6C980D08768")))
  println(to_string(Crypto.verify_password("hunter2", "pbkdf2:sha256:1000:30313233343536373839616263646566:A63e13df90f6bf8b58982d6c4c9d72e6d70c00339db67406bee1e6c980d08768")))
  println(to_string(Crypto.verify_password("hunter2", "pbkdf2:sha256:1000:30313233343536373839616263646566:a63e13df90f6bf8b58982d6c4c9d72e6d70c00339db67406bee1e6c980d08768")))
end
end
```

Expected: `true`

Actual (interpreted / compiled): `false` / same

Source: `verify_password` in stdlib/crypto.march.
