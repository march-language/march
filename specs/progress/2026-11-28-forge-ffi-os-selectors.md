# Forge C FFI tables can select an operating system

An `os` key on `[ffi]` or `[[ffi]]` accepts `macos` or `linux`. Forge keeps
the common tables and the matching OS tables in manifest order. Native
commands use the host OS. Explicit Linux cross-targets use the Linux tables.
JavaScript and WebAssembly receive the common tables.

This lets the standalone BLAS package share one C shim and select Accelerate
or OpenBLAS through its manifest. The Forge tests cover native selection,
Linux cross-target aliases, portable targets, old manifests and invalid
selectors.
