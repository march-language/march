# `--jit` exit 138 on json_stream (bench/interp/json_stream.march)

Filed: 2026-08-25
Updated: 2026-08-25 — four `--jit` defects root-caused and FIXED; the headline
repro still exits 138 for a fifth, **non-JIT-specific** reason. Kept open for
that residual. See "Residual" at the bottom for the remaining decision.

## Repro

```bash
./_build/default/bin/main.exe --jit bench/interp/json_stream.march
# rc=138, no output, on both MARCH_JIT_BACKEND=orc (default) and =clang
```

`--compile` (default `--opt 2`) is green (checksum=28000), as is the
interpreter.

## What exit 138 actually is

Not a kernel signal death and not a core dump — so `lldb` and
`~/Library/Logs/DiagnosticReports` are both dead ends. `march_sigsegv_handler`
(runtime/march_scheduler.c) is installed for SIGSEGV **and** SIGBUS to
implement lazy green-thread stack growth. A fault it cannot attribute to a
growable stack region falls to its `fatal:` label, which deliberately does
`_exit(128 + sig)` rather than re-raising (re-raising wedges the thread
un-killably from an altstack + swapcontext'd ucontext). So 138 = SIGBUS, 139 =
SIGSEGV, both via that `_exit`.

**Debugging notes for whoever picks this up.**
* `lldb` is useless here without `process handle SIGBUS -n false -p true -s
  false`: *every* lazy stack-growth page fault is a SIGBUS, so the debugger
  stops thousands of times and appears to hang.
* Do **not** get the diagnostic by defining `MARCH_DEBUG` in
  `runtime/march_scheduler.c` alone — `MARCH_DEBUG` adds two fields to
  `struct march_proc` in `runtime/march_scheduler.h`, so one TU seeing it and
  the rest not is an ABI mismatch that manufactures its own fake corruption.
  Define it in the header, or add a temporary unconditional `fprintf` +
  `dladdr()` on the `ucontext` `pc` in the `fatal:` path. The `dladdr` line is
  what turns this from guesswork into a one-shot answer.
* `si_addr` versus `sp` is the whole diagnosis: `si_addr` within ~16 bytes of
  `sp` is a stack overflow (guard-page hit); a small constant `si_addr` is a
  representation bug.

## Root causes found (all four FIXED)

### 0. `run_program` never pruned unreachable functions, so the module failed to link

`bin/main.ml` runs `Dce.prune_unreachable` immediately before LLVM emit, and
its own comment says why: reachability pruning is a *linkability* requirement,
because an unreachable prelude function reaching the linker drags in externs
nothing defines. `Repl_jit.run_program` had no such step.

`Lower.lower_module` pulls stdlib in at **module** granularity — the first
qualified reference to `JsonStream.feed` lowers every function in
`stdlib/json_stream.march`, including `typed_events`, whose body calls the bare
`from_json` that a caller's `derive Json` is supposed to supply. With no
`derive Json` in the program, nothing defines it, and the JIT died with
`JIT session error: Symbols not found: [ _from_json ]` (ORC) /
`symbol not found in flat namespace '_from_json'` (clang) — rc=1, before any
code ran. The AOT build never noticed because DCE dropped `typed_events` first.
`stdlib/json_stream.march` even documents the link gap in a comment on
`typed_line`, describing it as unreachable — under `--jit` it was not.

Fixed in `lib/jit/repl_jit.ml`. Confirmed load-bearing: removing just this hunk
puts the regression test back to `Symbols not found: [ _from_json ]`.

### 1. `emit_fns_fragment` never emitted mutual-TCO groups — the actual 138

`Llvm_toplevel.emit_module` calls `Llvm_tco.find_mutual_tco_groups` /
`emit_mutual_tco_group`, which collapses a cycle of mutually **tail**-recursive
functions into one combined dispatch function plus thin wrappers — i.e. into a
loop. `Llvm_repl.emit_fns_fragment` did not: it emitted every function
individually. So on the fragment path (which is what `--jit` uses, via
`Repl_jit.run_program`) every mutual tail call stayed a real native call.

`JsonStream`'s tokenizer is exactly such a cycle — `go` → `free_byte` /
`lit_byte` / `str_byte` / `num_byte` / `value_start` / … → `go` — advancing one
input byte per mutual tail call. One native frame per input byte, against a
green thread capped at `MARCH_STACK_MAX` (1 MiB, runtime/march_scheduler.h),
died once a single `feed` chunk passed roughly 6 KiB (~6.5k frames).

Evidence: `si_addr` 16 bytes above `sp` inside `march_incrc_local`; feeding the
same total input in 4 KiB chunks instead of 64 KiB survived, which is the tell
that depth tracked *frames per `feed` call* and not anything about the data.
Decisive control: with the other two fixes in place but this one reverted,
`--jit bench/interp/json_stream.march` still exits 138.

Fixed in `lib/tir/llvm_repl.ml`.

### 2. A failed prelude-cache load claimed to recompile, and didn't

`Repl_jit.precompile_stdlib` had the cache load in the `then` arm of an
if/else. On a `dlopen` failure it caught the exception, printed
`stdlib cache load failed (…), recompiling`, and then fell out of the whole
conditional with `ctx.compiled_fns` still **empty** — never reaching the
`else` arm that does the recompile the message promised.

That is a miscompiling path, not a slow one. With no prelude adopted, every
stdlib module reaches the fragment through `Lower`'s lazy
`_ensure_module_lowered` hook, which re-reads the module **without a
type_map** and therefore gives every function all-`TVar "_"` signatures.
Caller and callee then disagree about representation. Caught in the emitted
IR: `JsonStream.is_ws` was emitted as `ptr -> ptr` comparing via
`march_poly_eq` and returning a **tagged immediate**, while its call site in
`JsonStream.free_byte` did `getelementptr i8, ptr %r, i64 8` + `load i32` —
reading a heap tag out of tagged `false` (`1`), i.e. a load from address
**0x9**. Exit 139, no diagnostic.

This fired on essentially every warm session — see 3.

Fixed in `lib/jit/repl_jit.ml` (`loaded` flag; a failed load resets
`compiled_fns` and falls through to the compile branch).

### 3. The prelude cache key omitted the compiler's identity

`content_hash` digests only `stdlib_decls`, so a compiler whose codegen changed
while the stdlib text did not happily reused the previous build's `.so`. Hit
twice while fixing 1: a compiler that emitted the combined dispatch function
loaded a cached prelude that did not, and json_stream went on failing exactly
as if the fix had not landed. The prelude is compiled code, not data, so this
is a mismatched-codegen hazard rather than a stale-but-valid cache.

Fixed in `lib/jit/repl_jit.ml` by folding the compiler executable's size+mtime
into the cache key (not `Digest.file` — the binary is ~15 MB and this is on
every `--jit`/REPL startup).

## Still open, NOT fixed: the prelude `.so` records a dead install name

`bin/main.ml` builds the cached runtime at `<name>.<pid>.tmp` and renames it
into place, so on macOS its `LC_ID_DYLIB` still names the temp file:

```
$ otool -D ~/.cache/march/libmarch_runtime_<hash>.so
/Users/.../libmarch_runtime_<hash>.so.56237.tmp
```

Every prelude `.so` linked against it records that now-nonexistent path, so
**every session after the one that built it** fails to dlopen the prelude and
recompiles the whole stdlib (seconds per `--jit` run and per REPL start). With
fix 2 in place that is now merely slow instead of miscompiling, but it means
the prelude cache currently never hits on macOS.

Fix is a one-liner — pass `-install_name <so_path>` (the final path, not the
temp) when linking the runtime `.so` around `bin/main.ml:1016`. Not done here
only because `bin/main.ml` was owned by another agent at the time.

## Residual: the filed repro still exits 138, for a non-JIT reason

With all three fixes, `bench/interp/json_stream.march` under `--jit` still
exits 138. This one is **not** a `--jit` bug — the same unmodified file, on the
ahead-of-time path, on a clean build:

| mode | result |
| --- | --- |
| `--compile --opt 0` | **rc=138** |
| `--compile --opt 1` | **rc=138** |
| `--compile --opt 2` | rc=0, checksum=28000 |
| `--jit` (fragments are compiled at `-O0`) | **rc=138** |

The cause is the benchmark's own accumulator:

```march
pfn count_list(evs) do
  match evs do
  Nil -> 0
  Cons(_, t) -> count_list(t) + 1      -- NOT a tail call
  end
end
```

The compiler already warns about precisely this function ("structurally
recursive but not tail-recursive … may use O(depth) stack space"), and TRMC
does not apply because the recursive call feeds an arithmetic operator rather
than a constructor. At the default 64 KiB chunk a single `feed` yields ~13k
events, so this needs ~13k native frames — past the 1 MiB green-thread cap. It
survives *only* under `--compile --opt 2`, where clang's own optimizer
loopifies it.

Confirmed by substitution: replacing `count_list` with an
accumulator-passing `count_go` makes `--jit` produce `checksum=28000`, matching
interpreted and compiled. (Verified, then reverted — the benchmark is a
checksum-validated corpus file and was deliberately left untouched.)

So the residual is a policy call for the owner, not a compiler bug:

1. Make the benchmark's `count_list` tail-recursive. One line, checksum-neutral
   (counting is incidental to what the benchmark measures — `JsonStream.feed`
   throughput), and it also silences a warning the file currently emits. This
   is the recommended option.
2. Raise `MARCH_STACK_MAX` (1 MiB). Backend-agnostic and would close it for
   every program, but every green thread reserves `MARCH_STACK_MAX` of address
   space, so this trades against actor density — a deliberate design tradeoff
   that should not be changed as a side effect of a crash fix.
3. Give the JIT an LLVM optimization pipeline. Note that raising the clang
   fragment flag from `-O0` would fix only the `clang` backend: the **default**
   ORC backend hands IR straight to LLJIT and runs no IR passes at all, so this
   is a feature in `lib/jit/jit_orc_stubs.c`, not a flag change.

## Status

`bench/interp` under `--jit` is now 9/10 (`http_server` excluded — it is a
server and does not terminate), with json_stream the only failure and only for
the residual above. Before these fixes it was 9/10 with json_stream failing for
reasons 1–3, and the class of bug in 1 affected any mutually tail-recursive
code under `--jit`, not just this file.

Regression coverage: `test/test_jit.ml`, `jit_file` group, "march --jit loops
mutual tail calls instead of overflowing the stack" — drives the JsonStream
tokenizer at the benchmark's own 2000 records / 64 KiB chunk size through its
own test-owned fixture and asserts exit 0 **and** `checksum=28000`. Verified
non-vacuous: it is the only failure when the fixes are reverted by file-copy
swap.
