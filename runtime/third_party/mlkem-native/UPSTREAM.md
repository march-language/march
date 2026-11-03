# Vendored mlkem-native (ML-KEM, FIPS 203)

Source: https://github.com/pq-code-package/mlkem-native
Tag: v2.0.0
Commit: d1b2fe782888bdb761a50336012923180be7f502
License: Apache-2.0 OR ISC OR MIT (see LICENSE)

Copied files:
- LICENSE
- mlkem/mlkem_native.c, mlkem_native.h, mlkem_native_config.h
- mlkem/src/**, EXCEPT every `native/` directory (the AArch64/x86-64/RISC-V/
  PPC64 assembly backends)

March compiles it through one translation unit, `runtime/pqc.c`, which sets
the configuration before including `mlkem/mlkem_native.c`: ML-KEM-768 only,
the portable C backend only, `MLK_CONFIG_NO_RANDOMIZED_API` (no randombytes();
callers pass seeds and coins), and every internal symbol `static`.

Updating: copy the same set from a new tag, update this file, and re-run
`test/stdlib/test_pqc.march` (its vectors come from OpenSSL, independently).
