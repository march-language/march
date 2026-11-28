# Package the FP32 BLAS spike

Turn `examples/blas_spike` into a standalone Forge library with platform
link configuration for Accelerate on macOS and OpenBLAS on Linux. Validate
both builds and benchmark representative projection and attention shapes.
Use those benchmarks to decide when to dispatch through the blocking FFI
pool and how to configure backend threading.
