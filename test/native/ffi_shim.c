/* test/native/ffi_shim.c — user FFI shim for ffi_interp_shim.march
 * Tests Gap 1: user shim .so loaded into the interpreter via --ffi-c.
 * Compiled to a shared library by the dune test rule; the interpreter
 * compiles it to a temp .so and dlopens it automatically. */
#include <stdint.h>
#include "march_ffi.h"

/* Simple arithmetic that lives in the shim, not the runtime */
int64_t shim_add(int64_t a, int64_t b) { return a + b; }
int64_t shim_mul(int64_t a, int64_t b) { return a * b; }

/* String length via borrow — exercises shim using a runtime symbol */
int64_t shim_strlen(march_value s) {
    return (int64_t)march_str_borrow(s).len;
}
