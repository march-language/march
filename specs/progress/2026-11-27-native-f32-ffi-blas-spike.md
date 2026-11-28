# Zero-copy FP32 FFI and BLAS spike

Compiled C bindings can borrow a read-only view of a `NativeF32Arr` and
allocate an owned destination for direct writes. The mutable pointer is
limited to initialising fresh storage before the array reaches March.
The native regression tests the boundary through a blocking extern,
including empty arrays and invalid allocation lengths.

`examples/blas_spike` exercises the API with row-major FP32 matrix
multiplication through CBLAS. It uses Accelerate on macOS and provides a
build command for OpenBLAS on Linux.
