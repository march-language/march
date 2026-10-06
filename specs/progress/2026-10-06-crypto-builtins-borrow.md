# Hash, MAC, signature and base64 builtins leaked their arguments

**FIXED 2026-10-06.** Found by allocation-site tracing: after the record fixes, ~480 of
the cluster session's ~730 leaked objects per session were strings built by
`GlobalRegistry.entry_to_bytes` and `Merkle.branch`.

## Cause

`Merkle.leaf`/`branch` hash a freshly built string with `Crypto.sha256`, and the
registry rebuilds its Merkle tree for `root_hash` on every update. `sha256` and its
neighbours sat in `lib/tir/borrow.ml`'s `extern_owned_builtins`, the "not audited yet"
default, so the call took ownership of the string; their C entries only read it. Every
hashed string leaked: one per registry entry and one per Merkle branch, per update.

## Fix

Audited and moved to `extern_borrow_table`: `iolist_hash_fnv1a`, `md5`, `sha256`,
`stdlib_sha256`, `sha512`, `stdlib_sha512`, `hmac_sha256`, `stdlib_hmac_sha256`,
`hmac_sha256_bytes`, `pbkdf2_sha256` (its two Int parameters stay unborrowed),
`ed25519_seed_keypair`, `ed25519_sign`, `ed25519_verify`, `x25519`, `base64_encode`,
`stdlib_base64_encode`, `base64_decode`, `stdlib_base64_decode`. Each C entry
(`march_extras.c`, `march_nacl.c`, `march_runtime.c`) copies or reads its arguments and
returns a fresh value; none stores, returns or releases one. `bytes_to_u8_arr` and
`u8_arr_to_bytes` stay owned (not audited: no C entry found under those names).

## Effect

Cluster session on one node (the probe from
specs/progress/2026-10-05-dropped-closure-captures.md, 40 measured sessions): ~730 →
~157 objects per session.

## Test

`test/native/record_ownership_drops.march`, leg 4 (`Crypto.sha256` of a fresh string).
