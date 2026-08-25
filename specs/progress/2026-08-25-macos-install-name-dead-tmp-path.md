# macOS: cached `.so`s recorded a dead `.tmp` install name, defeating the JIT prelude cache

**Filed / fixed:** 2026-08-25
**Files:** `bin/main.ml` (`install_name_flag`, `ensure_runtime_so`, interpreter FFI shim),
`lib/jit/repl_jit.ml` (`precompile_stdlib`)

## Symptom

Every REPL / `march --jit` start silently paid a full stdlib precompile (~9.5s here)
instead of hitting the cached `stdlib_prelude_*.so`. No error was printed: the
cache-hit path catches the `dlopen` failure and falls through to lazy per-fragment
compilation, so the only visible effect was slowness.

## Root cause

Every cached `.so` under `~/.cache/march/` is compiled to a pid-suffixed temp
(`<name>.<pid>.tmp`) and then `rename(2)`d into place, so a concurrent session can
never `dlopen` a half-written file. On macOS the linker stamps `LC_ID_DYLIB` with
the path the file was **built** at — i.e. the `.tmp` path, which stops existing the
instant the rename publishes the file:

```
$ otool -D ~/.cache/march/libmarch_runtime_3c580084218e327b.so
/Users/…/libmarch_runtime_3c580084218e327b.so.98212.tmp
```

`precompile_stdlib` links the prelude against the runtime `.so` explicitly
(`ctx.rt_link`, needed since the macOS-15 flat-namespace miscompile fix), so the
prelude recorded that dead path as its `LC_LOAD_DYLIB` dependency. Any later
process therefore fails to load it:

```
dlopen(…/stdlib_prelude_O1_tln_382a8a91d0907b7f.so): Library not loaded:
  …/libmarch_runtime_3c580084218e327b.so.98212.tmp  (no such file)
```

The prelude `.so` had the same self-inflicted `.tmp` ID (harmless today — we
`dlopen` it by absolute path — but the same trap for anything that links it).

Found while root-causing the `json_stream --jit` SIGBUS
(`specs/todos/2026-08-25-jit-whole-program-json-stream-sigbus.md`, PR #349, whose
fix 2 makes this merely slow rather than miscompiling).

## Fix

Pass `-install_name <final path>` when linking, so the ID matches where the file
actually lands. macOS only — Linux `ld` records the link-line path (or
`DT_SONAME`) and needs nothing. Applied at all three rename-into-place `.so` sites:
the runtime `.so`, the JIT stdlib prelude, and the interpreter's FFI shim `.so`.

Spelled `-Xlinker -install_name -Xlinker <path>`, **not** `-Wl,-install_name,<path>`:
clang splits a `-Wl,` argument on commas, so a cache path containing one (a home
directory named `Doe, J`) is torn into two bogus linker arguments and the link
fails outright. Verified:

```
$ clang -shared -o x.dylib "-Wl,-install_name,/tmp/a,b/x.so" t.c
ld: file cannot be open()ed, errno=2 path=b/x.so in 'b/x.so'
$ clang -shared -o x.dylib -Xlinker -install_name -Xlinker '/tmp/a,b/x.so' t.c
$ otool -D x.dylib
/tmp/a,b/x.so
```

Two cache-key bumps so already-poisoned artifacts are not silently reused:

- `ensure_runtime_so`'s content key gets a `|install_name=v1` stamp. It cannot go
  in `flags_sig` itself, because the `-install_name` argument *is* the `.so` path,
  which is derived from that very key — circular.
- the prelude filename prefix goes `stdlib_prelude_O1_tln_` → `stdlib_prelude_O1_tln2_`.
  Nothing else would ever replace a stale prelude: its hash keys on stdlib source
  content, not on the runtime, and the load-failure path does not rebuild.

## Verification

```
$ otool -D ~/.cache/march/libmarch_runtime_002854a39e5e2cb0.so
/tmp/mh/.cache/march/libmarch_runtime_002854a39e5e2cb0.so      # real path, not .tmp

$ otool -L ~/.cache/march/stdlib_prelude_O1_tln2_*.so
  …/stdlib_prelude_O1_tln2_ecdaa655a470151f.so
  …/libmarch_runtime_002854a39e5e2cb0.so                        # real path
```

Control — the pre-fix prelude still in the real cache genuinely cannot be loaded,
while the post-fix one can (`ctypes.CDLL`):

```
pre-fix : FAILED: dlopen(…): Library not loaded: …libmarch_runtime_….so.98212.tmp
post-fix: LOADED
```

Three consecutive sessions under a private `HOME` (`printf '1+1\n:quit\n' | march`):

```
run1 real 9.54    # cold: full stdlib precompile
run2 real 0.28    # [timing] precompile: 0.014s — cache hit
run3 real 0.28
```

Zero `stdlib cache load failed` messages across all three.

Regression test: `test/test_jit.ml` → `jit / "prelude .so loads cross-process"`.
It runs a REPL session in a subprocess to populate a private-`HOME` cache, then
`dlopen`s the published prelude `.so` from the test process itself — a different
process than the one that linked it, which is exactly what the bug broke.

The two platforms need opposite handling, because the runtime symbols the
prelude leaves undefined (e.g. `native_float_arr_sum`) resolve differently:

- **macOS** — the prelude records an `LC_LOAD_DYLIB` dependency naming the
  runtime `.so` by its install-name, and *that* is what the bug corrupts. The
  test must NOT preload the runtime: dyld matches an already-loaded image by
  install-name, and on a pre-fix binary both the runtime's own ID and the
  prelude's dependency are the same dead `.tmp` string — so preloading would
  satisfy the dependency and mask the regression. The prelude has to stand on
  the recorded install-name path, which is the property under test.
- **Linux** — the prelude has no recorded path dependency on the runtime at
  all, only undefined symbols resolved via `RTLD_GLOBAL`. The macOS bug can't
  occur, so the test preloads the runtime `.so` first (mirroring a real
  `Repl_jit` session), or a *healthy* prelude would fail under `RTLD_NOW`
  purely for the missing symbol. This surfaced as the CI-only failure
  `undefined symbol: native_float_arr_sum` on `test (ubuntu-24.04)` and
  `trmc-suite`; the platform-split load order fixes it.

Non-vacuousness confirmed against a pre-fix binary on macOS (still fails after
the split, since macOS does not preload):

```
[FAIL] jit  2  prelude .so loads cross-process.
  … Library not loaded: …/libmarch_runtime_0dcdf81fd90a73b6.so.35259.tmp
```

Full suite green afterwards: compiler 936, eval 273, codegen 591, stdlib 878,
stdlib_march 61, test_jit 22 — zero failures.
