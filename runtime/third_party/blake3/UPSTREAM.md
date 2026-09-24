# Vendored BLAKE3 C implementation

Source: https://github.com/BLAKE3-team/BLAKE3
Tag: 1.8.3
Commit: 8b829b697fa4cfe35de35e9aa8c20b56266cb091

Copied files:
- c/blake3.c
- c/blake3.h
- c/blake3_dispatch.c
- c/blake3_impl.h
- c/blake3_portable.c
- LICENSE_A2
- LICENSE_A2LLVM
- LICENSE_CC0

March compiles the portable path for every target with:
-DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2
-DBLAKE3_NO_AVX512 -DBLAKE3_USE_NEON=0

The portable-only build avoids target-specific assembly and runtime CPU feature dispatch.
