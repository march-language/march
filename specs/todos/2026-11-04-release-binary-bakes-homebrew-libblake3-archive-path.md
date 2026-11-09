# `[P3]` Release macOS binaries bake `/opt/homebrew/lib/libblake3.a` into the interpreter's FFI link

Found 2026-11-04. On a Mac whose Homebrew blake3 (1.8.6) ships only `libblake3.dylib`, every
interpreter-mode call into project FFI code fails: `march: failed to compile runtime .so
(clang exit 1)`, with clang reporting `no such file or directory: '/opt/homebrew/lib/libblake3.a'`.
In depot, `MARCH_TEST_INTERPRETER=1 forge test test/test_sqlite_live.march` fails 12 of 12;
compiled, the same tests pass. The v0.5.0, v0.6.0 and v0.7.0 release binaries all carry the
path.

Cause: `lib/cas/discover.ml` prefers a static `libblake3.a` on macOS when one exists on the
*build* machine, and writes the result into the generated `March_cas.Blake3_flags`.
`bin/toolchain.ml`'s `blake3_link_flags` then reuses those build-time flags verbatim when the
installed compiler links the runtime `.so` on the *user's* machine.

Fix direction: at link time, check that a baked archive path exists and otherwise fall back
(Homebrew/`/usr/local` `-L… -lblake3`, then pkg-config). Or link the runtime `.so` against
the copy of blake3 the compiler binary already carries.
