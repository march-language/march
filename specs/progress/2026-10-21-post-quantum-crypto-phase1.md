# Post-quantum primitives: ML-KEM-768 and ML-DSA-65 (phase 1)

**Plan:** [../plans/post-quantum-crypto-plan.md](../plans/post-quantum-crypto-plan.md), phase 1.
Phase 2 (PQ TLS groups) landed later ([2026-10-21-post-quantum-crypto-phase2-tls.md](2026-10-21-post-quantum-crypto-phase2-tls.md)); phase 3 (hybrid cluster handshake) remains open:
[../todos/2026-10-21-post-quantum-crypto-cluster.md](../todos/2026-10-21-post-quantum-crypto-cluster.md).

- **Vendored** mlkem-native v2.0.0 and mldsa-native v2.0.0 (PQ Code Package,
  Apache-2.0/ISC/MIT) under `runtime/third_party/{mlkem,mldsa}-native/`:
  portable C only, every `native/` assembly backend left out. `UPSTREAM.md` in
  each names the tag, commit and the copied set.
- **One translation unit**, `runtime/pqc.c`, includes both monobuilds with the
  configuration set first (768 / 65 only, `*_NO_RANDOMIZED_API`, ML-DSA
  `CORE_API_ONLY`, internals `static`) and exposes the six deterministic
  functions in `runtime/pqc.h`. It has no March runtime dependency, like
  `tweetnacl.c`, so `lib/pqc` (the interpreter's OCaml bindings) compiles the
  same file. Manifest: `pqc.c` and `march_pqc.c`, both `core` + `jit`.
- **Builtins** (`runtime/march_pqc.c`), all over `Bytes`, randomness always an
  argument: `mlkem768_keypair(seed64)` -> dk (pk at 1152..2336),
  `mlkem768_encaps(pk, coins32)` -> ct || ss, `mlkem768_decaps(dk, ct)` -> ss,
  `mldsa65_keypair(seed32)` -> sk || pk, `mldsa65_sign(sk, msg, rnd32)`,
  `mldsa65_verify(pk, msg, sig)`. Failure convention as `march_nacl.c`: wrong
  length or a rejected key gives empty Bytes / `false`. Registered in
  typecheck_builtins, eval_builtins (through `lib/pqc`), llvm_builtins (entry +
  `PDeclare`), defun's builtin list, borrow (all arguments borrowed), and the
  codegen preamble golden.
- **Stdlib:** `MlKem` (`stdlib/ml_kem.march`) and `MlDsa`
  (`stdlib/ml_dsa.march`), each `needs IO.Random`; random entry points draw from
  `Crypto.random_bytes`, seeded ones (`keypair_from_seed`,
  `encapsulate_with_coins`, `sign_deterministic`) are for vectors. Pure ML-DSA,
  empty context.
- **Vectors:** `test/stdlib/test_pqc.march` pins key pairs, ciphertext, shared
  secret and a deterministic signature that OpenSSL 4.0.3 produced from the
  same seeds (`genpkey -pkeyopt hexseed`, `pkeyutl -encap -pkeyopt hexikme`,
  `pkeyutl -sign -pkeyopt deterministic:1`), so the check is against an
  independent implementation. Proven red on a perturbed vector. The same
  program gives identical output interpreted and compiled.
- **Stack:** ML-DSA-65's largest operation needs well under 100 KB of stack
  (upstream's `MLD_TOTAL_ALLOC_65_*`), inside a green thread's 1 MiB maximum.
