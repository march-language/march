# Distributed deploys step 11a: node certificates, cert handshake, per-frame MAC, revocation

**Plan:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
section 3 (Identity, Threat model), 7.4, II.9, D3, D4. The authorization half
(11b: the two-way role check, raw-send denial) is still open:
[../todos/2026-09-22-dd-step11-certificates-segregation.md](../todos/2026-09-22-dd-step11-certificates-segregation.md).

## 1. Certificates

- **Crypto builtins.** `ed25519_seed_keypair(seed)`, `ed25519_sign(sk, msg)`,
  `ed25519_verify(pk, msg, sig)`, `x25519(scalar, point)`, all over `Bytes`.
  Native: `runtime/march_nacl.c` over the vendored `runtime/tweetnacl.c`, which
  gained `crypto_sign_seed_keypair` and TweetNaCl's `crypto_scalarmult`
  (X25519, the same radix-2^16 field code the ed25519 half uses). Interpreter:
  `lib/eval/eval_builtins.ml` through `lib/ed25519` (the OCaml bindings forge
  already used, which link the same C). A wrong-length argument returns empty
  Bytes (verify: `false`), never an abort; `x25519` also returns empty Bytes for
  an all-zero result (a low-order peer point). Checked against RFC 8032 section
  7.1 tests 1-2 and RFC 7748 sections 5.2 and 6.1, natively and interpreted.
- **Runtime manifest.** `tweetnacl.c` moved from role `hcr` to `core`+`jit`
  (it was skipped under `--compile-so`; the builtins need it everywhere), and
  `march_nacl.c` is new (`core`, `jit`). The wrappers are a separate file
  because `tweetnacl.c` is also compiled standalone into `lib/ed25519` and C
  test harnesses with no March runtime to link.
- **`NodeCert`** (`stdlib/node_cert.march`): `Cert { node, roles, flags,
  not_after, issuer, pubkey, serial }`; canonical MessagePack body; signed form
  `[Bin(body), Bin(signature)]`, base64 as text; `verify(signed, operator_pub,
  now)`; signed revocations (by serial, or by node with an empty serial).
  SPIFFE-style URIs: `spiffe://<td>/pool/<pool>/node/<name>` and
  `spiffe://<td>/operator/<16 hex of the operator key>`.
- **Deviation from the requested record:** two fields were added to the five
  asked for. `pubkey` (hex of the node's ed25519 public key) is what the
  handshake's proof of possession checks against, and `serial` is what a
  revocation names. `not_after` is unix seconds, inclusive.
- **`forge cluster keygen | cert | revoke`** (`forge/lib/cmd_cluster.ml`,
  registered in `forge/bin/main.ml` and `known_builtin_names`). The operator
  key is its own file (`operator.key`, 0600), not the hot-reload deploy key
  (plan section 3: separate keys). `cert` writes `<node>.key` and
  `<node>.cert`; `--seconds` exists for short-lived certificates in tests;
  `--node-key` renews with an existing key.
- **Byte compatibility** between forge's OCaml MessagePack encoder and
  `Msgpack.encode` is pinned by one vector asserted in both
  `test/stdlib/test_node_cert.march` and `forge/test/test_cluster.ml`
  (perturbing one digit of the March copy fails the test).
