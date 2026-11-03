# Vendored mldsa-native (ML-DSA, FIPS 204)

Source: https://github.com/pq-code-package/mldsa-native
Tag: v2.0.0
Commit: 834a90d5e846ffa1e1611bd24e160bb2e9b86d35
License: Apache-2.0 OR ISC OR MIT (see LICENSE)

Copied files:
- LICENSE
- mldsa/mldsa_native.c, mldsa_native.h, mldsa_native_config.h
- mldsa/src/**, EXCEPT every `native/` directory (the AArch64/x86-64 assembly
  backends)

March compiles it through one translation unit, `runtime/pqc.c`, which sets
the configuration before including `mldsa/mldsa_native.c`: ML-DSA-65 only, the
portable C backend only, `MLD_CONFIG_NO_RANDOMIZED_API` and
`MLD_CONFIG_CORE_API_ONLY` (keypair_internal / signature_internal /
verify_internal; callers pass the seed and the signing randomness), and every
internal symbol `static`.

Updating: copy the same set from a new tag, update this file, and re-run
`test/stdlib/test_pqc.march` (its vectors come from OpenSSL, independently).
