# FP32 BLAS spike

`Blas.matmul_f32(a, b, m, k, n)` multiplies contiguous row-major `m × k` and
`k × n` March arrays. It returns a fresh `m × n` array in `Ok`, or an `Err`
for invalid dimensions or mismatched lengths. An empty inner dimension
produces zeros. The C shim borrows both inputs and gives CBLAS the destination
inside the fresh March array. The blocking extern runs on March's FFI pool.

Build the example from the repository root with a native March compiler that
includes the FP32 FFI helpers. On macOS, use Accelerate:

```sh
march --compile --ffi-c examples/blas_spike/blas.c \
  --ffi-link '-framework Accelerate' examples/blas_spike/demo.march \
  -o /tmp/march-blas-spike
/tmp/march-blas-spike
```

On Linux with OpenBLAS headers and libraries installed, substitute
`--ffi-link '-lopenblas'`. If they are in non-default paths, use the flags from
`pkg-config --cflags --libs openblas`.

The demo prints `[58., 64., 139., 154.]`. The `native_ffi_native_f32` regression
checks the FP32 boundary independently of the BLAS library.
