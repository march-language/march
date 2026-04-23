/* Compile-time host triple detection for LLVM IR generation.
 * Returns the LLVM target triple string for the build host so that
 * llvm_emit.ml can emit correct IR for the native JIT/AOT path.
 */
#include <caml/mlvalues.h>
#include <caml/alloc.h>

CAMLprim value march_tir_native_triple(value v_unit) {
    (void)v_unit;
    return caml_copy_string(
#if defined(__APPLE__)
#  if defined(__aarch64__) || defined(__arm64__)
        "arm64-apple-macosx15.0.0"
#  elif defined(__x86_64__)
        "x86_64-apple-macosx15.0.0"
#  else
        "unknown-apple-macosx15.0.0"
#  endif
#elif defined(__linux__)
#  if defined(__aarch64__)
        "aarch64-unknown-linux-gnu"
#  elif defined(__x86_64__)
        "x86_64-unknown-linux-gnu"
#  else
        "unknown-unknown-linux-gnu"
#  endif
#else
        "unknown-unknown-unknown"
#endif
    );
}
