# `--target-cpu <cpu>` passthrough

Sub-item (S) of `specs/todos/2026-08-04-x86-benchmark-findings.md` (item 4 of its
suggested order).

`bin/main.ml` used to hardcode `-msse4.2` for x86 (`arch_cflags`). `--target-cpu <cpu>`
(flag in `bin/flags.ml`) replaces it:

- x86_64 target: `-march=<cpu>`; arm64 target: `-mcpu=<cpu>`. The spelling follows the
  ARCH, not the host: `Native` asks `uname -m` (`host_is_arm64`), so an arm64 host never
  receives an x86 flag (and previously received a stray `-msse4.2` that clang ignored with
  a warning). Wasm/JS targets ignore it.
- Default unchanged: `-msse4.2` on x86_64, nothing on arm64.
- CAS: `cpu:<cpu>` is added in `build_cas_key`, the single function both compile-cache
  sites call, so no separate second edit was needed.

Verified on an arm64 Mac with `MARCH_DEBUG_CASFLAGS=1`: default / `native` / `apple-m1`
give three distinct keys; `--target-cpu bogus_cpu` reaches clang
(`unsupported argument 'bogus_cpu' to option '-mcpu='`); valid CPUs compile and run.
The CLI is not documented under `specs/lang/`, so the `--help` line is the doc.
