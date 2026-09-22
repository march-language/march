# CAS key carries the MARCH_SANITIZE mode, not just its presence (2026-09-22)

## Bug

`codegen_cas_tags ()` in `bin/main.ml` added the tag `"sanitize"` whenever
`MARCH_SANITIZE` was set, but the link step chose the sanitizer from its
value: `thread` gives `-fsanitize=thread -g`, and any other value gives
`-fsanitize=address,undefined`. Two different binaries therefore shared one
cache key. Compiling a program with `MARCH_SANITIZE=thread` and then the same
program with `MARCH_SANITIZE=1` printed `compiled ... (cached)` and copied
out the TSAN binary. This was reproduced on 2026-09-22 in the
march-sbx-test-ubuntu container: `nm` on the supposedly-ASAN binary showed
`__tsan_init` and no `__asan_init`. Any sanitizer evidence collected in a
directory whose cache already held the other mode's build came from the wrong
sanitizer. The reverse order had the same problem.

## Fix

- **`bin/main.ml`**: new `sanitize_mode ()` (`None` / `Some "thread"` /
  `Some "address"`) is the only place `MARCH_SANITIZE` is read. Both the CAS
  tag (`"sanitize=thread"` / `"sanitize=address"`) and the link flag
  (`sanitize_clang_flag ()`, which replaces the inline match in the link step)
  come from it, so the key cannot be coarser than the build again. The key
  changes once for every sanitized build. Unsanitized builds are unaffected
  because they carry no tag.

## Other CAS-key sites checked

- **`bin/toolchain.ml`** (the interpreter/JIT runtime `.so`) does not have this
  bug. Its cache key is a digest of the full `flags_sig` string, which
  includes the actual `-fsanitize=...` flag, so the key always matches the
  build. It does build ASan+UBSan for every value, `thread` included. That is
  a separate question and does not make it serve the wrong artifact.
- `build_cas_key` is the only place `--compile` flags enter the key. Both
  cache layers (the source-level check and the post-TIR check) go through it,
  so the fix covers both. `MARCH_DEBUG_CASFLAGS=1` now shows
  `sanitize=thread` or `sanitize=address`.

## Regression test

`test_sanitize_modes_do_not_share_cas_artifact` (`test/test_stdlib_suite.ml`,
run_stdlib `adversarial-regressions`, `Slow`) compiles one program in a fresh
directory. The CAS lives in cwd's `.march/cas`. It builds with `thread`, then
`1`, then `thread` again, and asserts:

- the `=1` build does not print `(cached)`;
- the `=1` build adds entries under `.march/cas/artifacts-v2`;
- control: the repeated `thread` build does print `(cached)` and adds no
  entries, which proves the test really observes the cache.

It counts artifact entries instead of comparing the binaries, because two
fresh links always differ on macOS (random `LC_UUID`). If clang cannot link
both `-fsanitize=thread` and `-fsanitize=address,undefined` (for example on
musl), the test is recorded as a tool-absence skip.

To check the test itself, the tag was reverted to a bare `"sanitize"`. The
test then failed on `MARCH_SANITIZE=1 after =thread misses the cache`
(expected `false`, got `true`), and passed again once the fix was restored.
