#include "march_ffi.h"
#include <limits.h>
#include <string.h>

#ifdef __APPLE__
#define ACCELERATE_NEW_LAPACK
#include <Accelerate/Accelerate.h>
#else
#include <cblas.h>
#endif

static march_value blas_error(const char *message) {
    return march_err(march_str_new((const uint8_t *)message, strlen(message)));
}

/* Row-major (m by k) × (k by n), producing a fresh (m by n) array. */
march_value march_blas_matmul_f32(march_value a, march_value b,
                                int64_t m, int64_t k, int64_t n) {
    if (m < 0 || k < 0 || n < 0 || m > INT_MAX || k > INT_MAX || n > INT_MAX) {
        return blas_error("BLAS dimensions must fit in a nonnegative C int");
    }
    march_f32_slice lhs = march_f32_arr_borrow(a);
    march_f32_slice rhs = march_f32_arr_borrow(b);
    if (lhs.len != m * k || rhs.len != k * n) {
        return blas_error("BLAS dimensions do not match the input lengths");
    }

    float *output;
    int64_t len = m * n;
    march_value result = march_f32_arr_alloc(len, &output);
    if (result == 0) return blas_error("BLAS output array is too large");
    if (len == 0) return march_ok(result);
    if (k == 0) {
        memset(output, 0, (size_t)len * sizeof(*output));
    } else {
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                    (int)m, (int)n, (int)k,
                    1.0f, lhs.ptr, (int)k, rhs.ptr, (int)n,
                    0.0f, output, (int)n);
    }
    return march_ok(result);
}
