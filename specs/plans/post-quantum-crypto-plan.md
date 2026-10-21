# Post-quantum cryptography: plan

Status: phases 1-2 landed (2026-10-21: `specs/progress/2026-10-21-post-quantum-crypto-phase1.md`,
`specs/progress/2026-10-21-post-quantum-crypto-phase2-tls.md`); phase 3 open
(`specs/todos/2026-10-21-post-quantum-crypto-cluster.md`). Phase 2 as built detects ML-KEM
at run time (the group list is tried, and an older OpenSSL keeps its defaults) rather
than by `OPENSSL_VERSION_NUMBER`.

As built, phase 1 differs from the sketch below in two ways: the modules are top-level
`MlKem` / `MlDsa` (one module per stdlib file), and every random input is a builtin
argument drawn by the stdlib (`mldsa65_sign(sk, msg, rnd)`), not by the C side.

## Where we are

| Surface | Primitive | Quantum-safe? |
|---|---|---|
| `Crypto.sha256` / `sha512` / `hmac` / PBKDF2 | SHA-2 | Yes (Grover only halves the margin) |
| TLS (`runtime/march_tls.c`, OpenSSL) | OpenSSL default groups | Probably: we never call `SSL_CTX_set1_groups`, and OpenSSL >= 3.5 puts hybrid `X25519MLKEM768` first. Unverified, and depends on the linked OpenSSL. |
| Node certificates (`stdlib/node_cert.march`) | ed25519 (TweetNaCl, `runtime/march_nacl.c`) | No |
| Cert-mode cluster handshake (`NetKernel.handshake_cert`) | ephemeral X25519 -> HKDF -> per-direction frame MAC keys | No |
| User-facing KEM / signature API | none | n/a |

Threat note: cluster frames are **MAC'd, not encrypted** (`ClusterAuth.frame_keys`).
So "harvest now, decrypt later" does not apply to the cluster plane today. The
quantum risk there is an attacker forging certificates or hijacking a handshake
*in real time*, which is a long-horizon threat. The urgent item is TLS
confidentiality, and that is mostly handled by OpenSSL already.

## Goals

1. Expose NIST PQC primitives to March programs: ML-KEM (FIPS 203) and ML-DSA (FIPS 204).
2. Make TLS's PQ key exchange explicit and tested rather than an accident of OpenSSL defaults.
3. Give the cluster handshake and node certificates a hybrid (classical + PQ) mode.

Non-goals: SLH-DSA / Falcon (add later if anyone asks), PQ certificates in TLS
(the WebPKI isn't there yet), encrypting cluster frames (separate decision).

## Phase 1: primitives

### Backend choice (decide first)

- **A. Vendor portable C** (`mlkem-native`, `mldsa-native` from PQ Code Package;
  Apache-2.0/MIT/ISC, constant-time, formally checked). Role `core` in
  `runtime/sources.list`, same as TweetNaCl. Works in every binary, the JIT and
  `--static`, with no OpenSSL dependency. **Recommended.**
- B. OpenSSL >= 3.5 EVP (`EVP_PKEY_ML_KEM_768`, `EVP_PKEY_ML_DSA_65`). No vendored
  code, but `libcrypto` is only linked for the `http` role today. Every program
  using `Crypto.ml_kem_*` would need a link-time dependency and an OpenSSL >= 3.5
  floor, and the static/musl build would be affected (`bin/static_link.ml`).

### Builtins

Same conventions as the ed25519/x25519 builtins: everything is `Bytes`. A
wrong-length input returns EMPTY `Bytes` / `false`, never an abort, and the
stdlib wrapper turns that into a `Result`. Follow the `compiler-builtin` skill
(typecheck table, eval, LLVM emit, runtime symbol, JIT).

| Builtin | Type | Sizes (ML-KEM-768 / ML-DSA-65) |
|---|---|---|
| `mlkem768_keypair(seed)` | `Bytes -> Bytes` | 64-byte seed -> dk 2400 (pk embedded at offset 1152, 1184 bytes) |
| `mlkem768_encaps(pk, coins)` | `Bytes -> Bytes -> Bytes` | -> ct 1088 \|\| ss 32 |
| `mlkem768_decaps(dk, ct)` | `Bytes -> Bytes -> Bytes` | -> ss 32 (implicit rejection; never "fails") |
| `mldsa65_keypair(seed)` | `Bytes -> Bytes` | 32-byte seed -> sk 4032 \|\| pk 1952 |
| `mldsa65_sign(sk, msg)` | `Bytes -> Bytes -> Bytes` | -> sig 3309 (hedged; randomness from runtime CSPRNG) |
| `mldsa65_verify(pk, msg, sig)` | `Bytes -> Bytes -> Bytes -> Bool` | |

Randomness is passed in as seeds/coins from `Crypto.random_bytes`. That keeps
the C side deterministic and makes the KAT tests trivial.

### Stdlib API (`stdlib/crypto.march`, or a new `stdlib/pqc.march` if it gets big)

```march
mod Crypto.MlKem do
  type KeyPair = { public_key : Bytes, secret_key : Bytes }
  fn keypair() : KeyPair
  fn encapsulate(pk : Bytes) : Result((Bytes, Bytes), String)   -- (ciphertext, shared_secret)
  fn decapsulate(sk : Bytes, ct : Bytes) : Result(Bytes, String)
end

mod Crypto.MlDsa do
  type KeyPair = { public_key : Bytes, secret_key : Bytes }
  fn keypair() : KeyPair
  fn keypair_from_seed(seed : Bytes) : KeyPair
  fn sign(sk : Bytes, msg : Bytes) : Bytes
  fn verify(pk : Bytes, msg : Bytes, sig : Bytes) : Bool
end
```

Only one parameter set each (768 / 65). The module names leave room for others.

### Tests

- NIST ACVP known-answer vectors (a handful each) in `test/stdlib/`, interpreted **and** compiled.
- Round-trip and tamper properties with `Check.all` (flip a bit in ct/sig -> ss mismatch / verify false).
- Wrong-length inputs -> `Err`, no crash. Run under ASAN once (`MARCH_SANITIZE=1`).
- JIT parity: the new symbols are resolvable from the REPL.

## Phase 2: TLS

- In `march_tls.c`, call `SSL_CTX_set1_groups_list(ctx, "X25519MLKEM768:X25519:P-256")`
  when the linked OpenSSL supports it (check at build time with `OPENSSL_VERSION_NUMBER >= 0x30500000L`),
  and keep the defaults otherwise.
- Add an `Http`/`Tls` option to override the group list.
- Test: a loopback March client <-> March server handshake asserts the
  negotiated group (`SSL_get_negotiated_group`) is `X25519MLKEM768` when it's available.
- Document the OpenSSL floor in `specs/lang/` (networking chapter) and in the CHANGELOG.

## Phase 3: cluster hybrid mode

- **Handshake KEM:** the initiator's hello carries an ML-KEM-768 public key alongside
  the X25519 ephemeral key. The responder encapsulates and the ciphertext travels
  in its hello. The frame-key IKM becomes `x25519_ss || mlkem_ss` into the existing
  HKDF (`ClusterAuth.frame_keys`). The transcript already covers both hellos, so
  the binding is automatic.
- **Certificates:** `march-node-cert-v2` carries an ed25519 **and** an ML-DSA-65
  operator signature, and the node proves possession with both. A v2 verifier
  requires both. A v1 cert keeps working until an operator flag
  (`require_pq`) turns it off.
- **Wire versioning:** a hybrid-capable node advertises it in the hello, and
  both sides fall back to classical only when `require_pq` is off.
  Downgrade protection comes from the signed transcript covering the
  advertisement.
- Size: hellos grow by about 1.2 KB, certs by about 5.3 KB. Check `hs_recv`'s frame limit.
- Update `specs/lang/clustering.md` ("Node certificates", handshake section) and
  regenerate `docs/`.

## Open questions

1. Backend A vs B (recommend A).
2. Should cluster frames also get *encrypted* now that the KEM is in place? That's
   a separate todo; it changes the threat model and needs an AEAD.
3. Should `Crypto` grow a generic `Kem`/`Signature` interface, or stay
   concrete per algorithm? Recommend concrete until a second algorithm exists.

## Order of work

Phase 1 (one PR: vendored C, builtins, stdlib, tests) -> Phase 2 (small, independent; can go first) -> Phase 3 (needs Phase 1).
