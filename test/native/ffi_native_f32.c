#include "march_ffi.h"

march_value ffi_test_f32_scale(march_value xs) {
    march_f32_slice input = march_f32_arr_borrow(xs);
    float *output;
    if (march_f32_arr_alloc(INT64_MAX / 4, &output) != 0 || output != NULL ||
        march_f32_arr_alloc(-1, &output) != 0 || output != NULL) {
        march_fatal("invalid FP32 allocation succeeded");
    }
    march_value ys = march_f32_arr_alloc(input.len, &output);
    for (int64_t i = 0; i < input.len; ++i) {
        output[i] = 2.0f * input.ptr[i];
    }
    march_f32_slice result = march_f32_arr_borrow(ys);
    if (result.ptr != output || result.len != input.len) {
        march_fatal("FP32 borrow did not expose the original storage");
    }
    return ys;
}
