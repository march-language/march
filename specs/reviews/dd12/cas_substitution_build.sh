#!/bin/bash
# Builds the C-level CAS-substitution repro (corroborates the P1 CAS finding):
# an operator-signed ACTIVATE5 over a cas_hash runs SUBSTITUTED bytes staged at
# that hash. Run from the repo root; MARCH_HCR_TRIPLE below is macOS/arm64 and
# may need adjusting per host. The pubkey is taken from the reload-test keypair
# (dune build --root . test/test_reload_activate4.exe stages reload_keys.txt).
# Not run in CI (no dune under specs/).
set -e
cd "$(git rev-parse --show-toplevel)"
S=specs/reviews/dd12
PK=$(head -n1 _build/default/test/reload_keys.txt)

cc -std=gnu11 -Wall -I runtime -I runtime/third_party/blake3 -O2 \
  -DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512 -DBLAKE3_USE_NEON=0 \
  -DMARCH_HCR_TRIPLE=arm64-apple-macosx26.0.0 -DMARCH_HCR_TARGET='"native"' -DMARCH_HCR_PREFIX='"Test"' \
  -DMARCH_SIGNING_PUBKEY_HEX="\"$PK\"" \
  -o $S/repro_cas_substitution $S/repro_cas_substitution.c \
  runtime/march_reload.c runtime/march_dispatch.c runtime/march_cap_lattice.c runtime/march_blake3.c runtime/march_hcr_identity.c \
  runtime/third_party/blake3/blake3.c runtime/third_party/blake3/blake3_dispatch.c runtime/third_party/blake3/blake3_portable.c \
  runtime/tweetnacl.c runtime/march_runtime.c runtime/march_scheduler.c runtime/march_reclaim.c runtime/march_message.c \
  runtime/march_heap.c runtime/march_gc.c runtime/march_monitor_registry.c runtime/march_observe.c runtime/march_observe_snapshot.c \
  runtime/march_extras.c runtime/march_ctx_escape.c runtime/march_compress.c runtime/base64.c runtime/sha1.c runtime/march_ffi.c \
  runtime/march_remote_registry.c -lpthread -lm -lz
echo "BUILD DONE"
ls -la $S/repro_cas_substitution
