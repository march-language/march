- ✅ **LLVM allocation and closure-trampoline attributes (2026-07-25).**
  `march_alloc` is declared `noalias nonnull` with `allocsize(0)`, matching
  its fresh-`calloc`/exit-on-OOM runtime contract. Canonical `$clo_wrap`
  trampolines are `alwaysinline`, removing their ABI-adaptation call boundary
  when optimization runs. Exact preamble/wrapper tests and the native LLVM IR
  corpus verifier pin both facts. No `nounwind` attributes were added.
