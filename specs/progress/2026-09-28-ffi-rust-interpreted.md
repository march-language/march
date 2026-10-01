# `[ffi.rust]` projects run interpreted (and link compiled on Linux)

Done 2026-09-28. Was `specs/todos/2026-08-18-ffi-rust-only-projects-cannot-run-interpreted.md`
(P3), a follow-up to `specs/progress/2026-08-18-forge-run-interpreted-drops-ffi-sources.md`
and `specs/progress/2026-09-22-ffi-rust-only-interpreted-diagnostic.md`, whose
compile-only warning this removes.

## The problem

`cargo build --release` produces a static `lib<name>.a`, and forge passes it to
`march` as `--ffi-link <archive>`. The interpreter's FFI shim
(`setup_interpreter_ffi` in `bin/main.ml`) was built only from `--ffi-c` sources,
so a `[ffi.rust]`-only project got no shim and every Rust extern failed with
"symbol not found for interpreter FFI". A mixed project (`[ffi] sources` plus
`[ffi.rust]`) had the same failure unless its C shim happened to call the Rust
symbols, because `cc -shared` pulls in only archive members that resolve an
already-undefined symbol.

## Approach chosen: option 2, force-load in the compiler

Of the todo's options, the fix makes the compiler's interpreter shim carry the
archive whole:

- every `--ffi-link` flag naming an existing `.a` is force-loaded into the shim:
  `-Wl,-force_load,<a>` on macOS, `-Wl,--whole-archive <a> -Wl,--no-whole-archive`
  on Linux;
- with no C sources, the shim is built from a generated empty stub;
- the shim's cache key includes each archive's contents, so a rebuilt crate
  (same path) rebuilds the shim.

Option 1 (a `cdylib`) was not taken: it needs a `crate-type` requirement on the
user's crate or a generated wrapper crate, and it would load a second copy of
Rust std next to anything else. Force-loading needs nothing from the crate and
works for any prebuilt static library passed with `--ffi-link`, not only forge's.
The fix lives in the compiler, not forge, so plain `march --ffi-link lib.a
file.march` works too.

Measured before coding (2026-09-28), with a `forge ffi add-rust` crate using the
`march` binding crate (`#[march]` functions `hello(&str) -> String` and
`checked_div -> Result`), whose code calls March runtime symbols that stay
undefined until dlopen:

| platform | shim | interpreted output |
|---|---|---|
| macOS 26 arm64 | none (origin/main) | `symbol not found for interpreter FFI` |
| macOS 26 arm64 | empty stub + `-force_load` | `Hello, March!` / `10/2 = 5` / `error: divide by zero` (same as compiled) |
| Ubuntu 24.04 arm64 (Docker) | none | `symbol not found for interpreter FFI` |
| Ubuntu 24.04 arm64 (Docker) | empty stub + `--whole-archive` | same three lines |

## Found on the way: compiled `[ffi.rust]` did not link on Linux

The compiled link line put `ffi_link` before the program's own object. GNU ld
resolves an archive only against symbols already undefined when it reaches it,
so the Rust archive contributed nothing: `undefined reference to 'rusty_add'`.
macOS's ld64 does not care about order, which is why it went unnoticed.
`ffi_link` now follows the object.

## Removed

`Cmd_build.interpreted_rust_ffi_diagnostic`, `Cmd_build.warn_interpreted_rust_ffi`,
their call sites (`cmd_run.ml`, `cmd_test.ml`, `cmd_interactive.ml`), the
`~interpreted` parameter that only fed them, and the four diagnostic tests in
`forge/test/test_forge.ml`. The "Interpreter mode" section of `docs/ffi.md`
now describes the force-load.

## Tests

`forge/test/test_forge.ml`, `interp_command` group, two `Slow` cases: a
`[ffi.rust]`-only project and a `[ffi.rust]` + `[ffi] sources` project each run
through `forge run` (interpreted) and `forge run --compiled`, and must print the
same `add=42` / `roundtrip=-7`. The crate has no dependencies (cargo never needs
the network), and `rusty_tag_roundtrip` calls `march_make_int`/`march_get_int`
from the runtime. Without `cargo` on PATH each case prints
`SKIP [ffi.rust] interpreted/compiled parity: no Rust toolchain` and skips.

- RED (origin/main compiler, new forge): both cases fail with
  `extern rusty_ffi:rusty_add — symbol not found for interpreter FFI`.
- GREEN on macOS 26 arm64, and on Ubuntu 24.04 arm64 in Docker
  (`march-ci-ubuntu` image, rustup-installed cargo), where the compiled leg also
  failed before the link-order fix.
