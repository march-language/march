# Fixed: macOS JIT miscompiled short string literals via flat-namespace linking (2026-08-09)

The stdlib doctest checker (`scripts/check-stdlib-doctests.py`) surfaced a macOS
miscompile: in the JIT REPL, `String.starts_with`/`ends_with` returned `false`
when they should be `true`, a 1-char string literal read length 0
(`String.byte_size("/") = 0` vs `byte_size("/etc") = 4`), and
`Path.is_absolute("/etc")` was `false`.

## Root cause

REPL/JIT only — the AOT `--compile` path was always correct. The JIT compiled the
stdlib **prelude `.so`** and each **fragment `.so`** with macOS flat-namespace
`-undefined dynamic_lookup`, deferring ALL runtime-symbol resolution to `dlopen`
(RTLD_GLOBAL). macOS's dyld resolves that flat scheme WRONG for the short-string
runtime path (`march_string_lit_static`/`march_string_starts_with` …), so the
prelude/fragment called the wrong thing and got a bad string. The runtime C
itself is correct (compiled standalone by the same clang at every `-O` it returns
1), and `march` emits identical `.ll` text (it links no LLVM) — it was purely the
cross-dylib link/resolution.

It reproduced only intermittently across environments (clean on macOS 26 and
Linux for a long stretch, then consistently broken on macOS 26 after a system
update, and on the GitHub `macos-15` runner), which is why it first looked like
JIT nondeterminism — see the closed investigation in PR #224.

## Fix (`lib/jit/repl_jit.ml`)

On macOS, pass the runtime `.so` as an explicit link input (new macOS-gated
`ctx.rt_link`) when building both the prelude `.so` and each fragment `.so`, so
their runtime references bind **two-level** to that exact dylib instead of flat
`dynamic_lookup`. `dynamic_lookup` is kept for prelude/prior-fragment symbols, so
incremental compilation is unchanged. Linux (`undef_flag=""`) is untouched. The
prelude `.so` cache key was bumped (`stdlib_prelude_O1_` → `_tln_`) so the new
link scheme invalidates stale caches.

Verified locally on macOS 26.5.2 (where it now reproduces): `Path.is_absolute("/etc")`
`false`→`true`, doctest checker `73 run / 1 failed` → `80 run / 0 failed`.

## Remaining (open)

The GitHub `macos-15` runner shows a *residual* nondeterminism even with this fix
(the runtime `.so` built first in a CI job could still miscompile), so the doctest
CI check is scoped OFF macOS (`.github/workflows/ci.yml`, `conformance` job — hard
gate on Linux where it is deterministic and clean). That runner-specific residual
still needs a macOS 15 host to reproduce and root-cause; re-enable the macOS
doctest check once it is resolved.
