`[P3]` # A `[ffi.rust]`-only project still cannot run interpreted

Follow-up to `specs/progress/2026-08-18-forge-run-interpreted-drops-ffi-sources.md`,
which fixed the C-source half of this (`forge run` now passes `--ffi-c`).

A project that declares **only** `[ffi.rust]` and no `[ffi] sources` remains
broken under the interpreter:

- `Cmd_build.ffi_flags_full` contributes only `--ffi-link <archive>` for a Rust
  crate (`forge/lib/cmd_build.ml:464`).
- The compiler's interpreter-FFI shim gate keys on `ffi_c_files` alone
  (`bin/main.ml:1003`). With no C source there is nothing to `cc -shared`, so
  `Eval.ffi_shim_so` stays `None` and every extern fails to resolve.

Fixing it needs more than a flag: `cargo build --release` produces a **static**
`lib<name>.a`, and a `.a` cannot be `dlopen`ed. Options:

1. Have `[ffi.rust]` also emit a `cdylib` and dlopen that under the interpreter
   (needs a `crate-type` requirement on the user's crate, or a generated
   wrapper).
2. Generate a tiny C shim that links the archive and `cc -shared` that, so the
   existing `ffi_c_files` path is reused.
3. Document it as compile-only and make the diagnostic say so explicitly
   instead of the generic "symbol not found for interpreter FFI".

Option 3 is the cheap honest floor and should land regardless — right now the
failure mode is indistinguishable from a genuinely missing symbol.

Related: `forge bench` hardcodes `~ffi_flags:""` (`forge/lib/cmd_bench.ml:61`),
so benchmarks of any FFI code have the same gap as `forge run` did.
