# Every `MARCH_SANITIZE=1` binary hangs on macOS 26 (toolchain, not March)

Observed 2026-10-07 on an Apple M3 Max, macOS 26.6.1 (25G76), Xcode 26.3: with
`MARCH_SANITIZE=1` every compiled binary, including a one-line `println("hi")`,
printed nothing and never exited. Non-sanitized builds and Linux sanitizer builds
(CI sanitize-gate, Docker sweeps) were fine.

## Where it hangs

`sample` on the hung process: one thread, 100% inside dyld's initializer pass, before
March's `main` or any runtime code runs:

```
libSystem_initializer -> __malloc_init -> wrap_malloc_default_zone
 -> __asan::AsanInitFromRtl -> AsanInitInternal -> InitializeShadowMemory
 -> MemoryRangeIsAvailable -> MemoryMappingLayout::Next -> get_dyld_hdr
 -> dyld_shared_cache_iterate_text_swift -> _Block_copy -> malloc
 -> __sanitizer_mz_malloc -> __asan::AsanInitFromRtl
 -> StaticSpinMutex::LockSlow -> internal_sched_yield   (forever)
```

ASAN init calls into dyld, which allocates through ASAN's own malloc zone, which
re-enters ASAN init and spins on the init lock its caller already holds.

## Root cause: the C toolchain's compiler-rt on this macOS

A plain C program shows it with no March involved:

| compiler | `-fsanitize=address(,undefined)` hello.c | `-fsanitize=thread` hello.c |
|---|---|---|
| Apple clang 17.0.0 (clang-1700.6.4.2, Xcode 26.3) | hangs (timeout) | SIGSEGV at startup (139) |
| Homebrew LLVM 21.1.8 | hangs (timeout) | not tried |
| Homebrew LLVM 22.1.8 | prints, exit 0 | prints, exit 0 |
| Apple clang, `-fsanitize=undefined` only | prints, exit 0 | |

The scheduler, ucontext stacks, fiber annotations, preemption ticks and mimalloc are
all irrelevant: the process never gets that far. The driver runs `clang` from `PATH`,
which is the Apple one.

## Fix (driver)

`bin/main.ml` (`native_cc`, `sanitizer_runtime_works`, `sanitize_cc_tag`): on a macOS
host, a native sanitizer build first compiles and runs a trivial C program with the
same `-fsanitize` flags, under a 10 s deadline (SIGTERM, then SIGKILL). Candidates:
`MARCH_SANITIZE_CC` if set (only it), otherwise `clang`, then
`/opt/homebrew/opt/llvm/bin/clang`, `/usr/local/opt/llvm/bin/clang`. The first that
passes compiles the runtime objects and links the program; switching away from the
default prints a one-line note. If none passes, the driver exits 1 with an explanation
and the fix (`brew install llvm`, or `MARCH_SANITIZE_CC`), instead of producing a
binary that hangs silently.

Verdicts are cached in `~/.march/cache/sanitizer-probe/`, keyed on the compiler's
`--version` text, the flags and `uname -r`, so the probe runs once per
toolchain/OS combination (the first compile pays about 10 s for a hanging default,
later ones nothing). The chosen compiler's identity is folded into the CAS key
(`sancc:` tag), because the whole-binary CAS did not key on the C compiler at all:
without it, switching compilers would have kept serving the old hanging binary.
Runtime objects were already keyed on `cc --version`. Linux hosts are not probed.

LLVM 22 accepts the emitted IR (it warns that it overrides the module triple).

## Evidence

- hello world: `MARCH_SANITIZE=1 march --compile` now notes the fallback to
  Homebrew LLVM 22 and the binary prints `hi`, exit 0 (was exit 142 under a 15 s alarm).
- `MARCH_SANITIZE_CC=/usr/bin/clang` exits 1 at once with the message (cached verdict).
- ASAN+UBSan, copied to a scratch dir: `test/native/hof_spec_closures.march`,
  `nativearray_builtin_borrow_leak_probe.march`, `actor_counter.march`: all exit 0,
  no sanitizer report, `actor_counter` output matches its `.expected`.
- TSAN (`MARCH_SANITIZE=thread`) now starts too; `hof_spec_closures` is clean, but
  `actor_counter` and `nativearray_builtin_borrow_leak_probe` report data races on the
  refcount word in `march_decrc` across green threads and abort. Not investigated here:
  TSAN with ucontext green threads and no `__tsan_switch_to_fiber` annotations is
  expected to be noisy, and this is the first time TSAN has run at all on this host.

## Regression check

CI's macOS jobs do not run sanitizer builds, so there is no CI test. By hand on a Mac:

```
rm -rf ~/.march/cache/sanitizer-probe
MARCH_SANITIZE=1 ./_build/default/bin/main.exe --compile -o /tmp/h hello.march > /tmp/h.log 2>&1
perl -e 'alarm 30; exec @ARGV' /tmp/h     # expect output and exit 0, never 142
```

Once Apple ships a fixed compiler-rt the probe passes for plain `clang` and the
fallback goes quiet on its own (the cache key includes `--version` and `uname -r`).
