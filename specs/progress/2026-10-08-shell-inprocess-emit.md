# Shell fragments: in-process object emission, linker only

Logged 2026-10-08. Follows the latency gate
(`2026-10-07-shell-latency-linux-gate.md`), which left clang as ~46 ms of a
Linux input's ~66 ms compile and ~90 ms on macOS.

## What changed

`Repl_jit.shell_compile` used to run
`clang -shared -fPIC -O1 -x ir shell_N.ll -o shell_N.so <target> <exports>`
for every input. Almost all of that is fixed cost: the driver, the
compile, and then the link, each started as its own process.

Now:

1. **Object in-process** (`lib/jit/jit_emit_stubs.c`, `Jit_emit`). The
   fragment's IR is parsed into a fresh `LLVMContext`, retargeted to the
   node's triple, run through `default<O1>` (clang `-O1`'s pipeline, so
   mutual tail calls are still optimised; R5.1 ruled out `-O0`), and written as
   a PIC object with `CodeGenOptLevel::Less`, as clang `-O1` does. The CPU is
   the one clang picks for the triple: `apple-m1`, `generic` (aarch64 Linux),
   `x86-64`, and `core2` (x86-64 macOS).
2. **Linker only.** The link argv is clang's own. Once per process and per
   target, `clang -### <target flags> -shared -fPIC probe.o -o probe.so
   <exports>` is run and its single job line is parsed. The probe paths and
   the entry name are then substituted for each input. That keeps everything
   clang decided: `ld` with `-platform_version`, `-syslibroot`, `-lSystem`
   and `libclang_rt` on macOS; `-exported_symbol` for the entry and
   `___march_cap_manifest`; `-undefined dynamic_lookup`; the ELF version
   script and `-Bsymbolic`; crt files and libc on native Linux; and
   `ld.lld -nostdlib` from a Mac to a Linux node. The linker is started
   directly (`Unix.create_process`), with no `/bin/sh`.
3. **Fallback.** Any of the following runs the full clang command, so its
   diagnostic is the one the user sees: libLLVM missing, an entry point
   unresolved, the node's backend not compiled in, an architecture other than
   aarch64 or x86-64, no triple from the node, a failed emit, no single job
   line from `clang -###`, or a failed link. `MARCH_SHELL_CLANG=1` forces
   clang. Under `MARCH_JIT_PROFILE=1` the phases print as `emit-obj`,
   `link-probe` (once) and `link`, and a fallback prints its reason.

Every LLVM function is looked up with `dlsym` rather than linked. A
static-LLVM musl release build (`orcjit native` components only, nothing
exported) therefore still links, and simply falls back to clang. A backend
is initialised by name (`LLVMInitialize<Arch>Target…`), so an LLVM built
without it reports the backend unavailable instead of failing to link.

On macOS the object now comes from Homebrew's LLVM (22), the same libLLVM the
REPL's ORC backend uses, rather than Apple clang (17). The linked `.so` files
match structurally: same exports (entry + manifest only), same
`LC_BUILD_VERSION` minos and libSystem dependency on Mach-O, and the same
`SYMBOLIC` flag and undefined-symbol counts on ELF. `.text` was within 2%.

## Measurements

Method: a 15-input workload (arithmetic, `let`, `List.map`/`filter`/`zip`/
`reverse` with lambdas and `limit:`, a record, `String.split`,
`to_string`, `Json.parse`, a program function) against
`test/native/shell_node.march`'s node, with `MARCH_JIT_PROFILE=1
MARCH_SHELL_TIMING=1`. In-process and `MARCH_SHELL_CLANG=1` sessions were
interleaved, with a fresh node per session. The p50 below is over every
input except each session's first (the first is listed separately; it
pays `link-probe` once).

| | load avg | rounds | compile p50, clang → in-process | p95 | first input |
|---|---|---|---|---|---|
| macOS arm64 (M-series), local node | 16-27 | 6 + 6 | **112 → 56 ms** | 259 → 143 | 124 → 88 |
| macOS, same, at higher load | 38-50 | 5 + 5 | 144 → 76 ms | 208 → 122 | 143 → 121 |
| Linux aarch64 (Docker `march-amdr-repro`, 14 cpus) | 1.6-4.6 in VM | 5 + 5 | **60 → 36 ms** | 112 → 87 | 57 → 30 |
| macOS client → Linux aarch64 node (cross) | ~15 | 4 + 4 | **87 → 42 ms** | 134 → 70 | 77 → 75 |

Phase split at p50: on macOS, `clang` 104 ms becomes `emit-obj` 12 + `link`
31. On Linux, `clang` 50 ms becomes `emit-obj` 18 + `link` 8. Cross, `clang`
77 ms becomes `emit-obj` 12 + `link` (lld) 21. `link-probe` costs 11-45 ms
once per session (one `clang -###`).

On macOS the round trip barely moved: total p50 went from 326 to 304 ms,
because the node's `dlopen` of each new file still costs ~150 ms there.

### What was tried and not kept

- **Dropping `-lSystem` / `-syslibroot` from the macOS link** would halve
  `ld` (~27 → ~14 ms standalone). It fails: `ld` needs `dyld_stub_binder`
  from libSystem.
- **`ld64.lld` instead of `ld` on macOS** was slower in every variant: 41 ms
  vs 37 ms with libSystem, and 29 ms vs 20 ms without.
- **Dropping `-lto_library` / `-mllvm`** from the `ld` line saved nothing
  measurable.

## Verification

- Shell goldens `native_shell_{session,node,skew,link}` pass unchanged on
  macOS and in the Linux container, both with the in-process path.
- The session inputs (`test/shell/session.txt`) give byte-identical output
  in-process and under `MARCH_SHELL_CLANG=1`, on macOS and on Linux.
- Fallback: `MARCH_LLVM_LIB=/nonexistent` on macOS (libLLVM not loadable)
  compiles every input with clang, with correct results.
- Cross: a Mac shell drove a Linux aarch64 node in the container, through a
  socat-to-`docker exec` bridge to its shell socket. All inputs gave the
  same output in-process and under clang. For x86-64 Linux (no node
  available), fragments were compiled from macOS both ways and their ELF
  headers, exported dynamic symbols, `FLAGS SYMBOLIC` and undefined-symbol
  counts compared: identical.
- `test_jit` gains `shell emit_object targets`: an object for aarch64 Linux,
  x86-64 Linux and arm64 macOS has the right ELF machine or Mach-O CPU type,
  bad IR is an `Error`, and an unhandled architecture gets no target.
  Perturbing the expected machine number turns it red.
