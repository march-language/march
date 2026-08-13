# `--cap-sandbox` runtime enforcement test — design

Closes the gap filed in
[specs/todos/2026-08-10-cap-sandbox-no-runtime-enforcement-ci.md](../../../specs/todos/2026-08-10-cap-sandbox-no-runtime-enforcement-ci.md):
`test/test_cap_sandbox_profile.ml` and `test/test_cap_strip.ml` verify the
embedded SBPL (macOS) / seccomp `-D` flag (Linux) **strings** are correct and
agree between the two builders. Nothing verifies the **runtime behavior**
those strings are supposed to produce — the seccomp-bpf deny classes in
`runtime/march_runtime.c`'s `march_sandbox_install` (hand-assembled
`sock_filter`/`BPF_JUMP`/`BPF_STMT`, fixed jump offsets) have never had a test
that compiles a program, runs it under the real sandbox, and asserts a
withheld capability's syscall actually fails while a held one still succeeds.

## Why FFI, not a plain March program

A pure March program cannot call a capability-gated builtin (`tcp_connect`,
`System.cmd`, `file_write`) without holding that exact capability — the type
checker rejects the call at compile time. So a fixture that "holds capability
X but not Y" can never reach Y's syscall through ordinary March code; there is
no such program to compile.

The way around this is exactly the boundary the sandbox exists to backstop:
`extern` / `IO.Foreign`. Per `specs/lang/capabilities.md`'s "IO.Foreign —
calling unverified C" section, an `extern` block's declared `Cap(X)`
annotation is **self-declared and unverified** — the compiler cannot see what
the linked C code actually does. A module can hold `IO.Foreign` (+ two of the
three IO classes under test) and NOT hold the third, declare its extern block
`Cap(IO.Foreign)` (trivially satisfied — no claim about Network/Process/Write
is made or needed), and have that C code call `socket()`/`execve()`/`open()`
directly. This is precisely the "C bypasses every March type guarantee" case
the docs describe, and precisely why `--cap-sandbox` exists as OS-level
defense in depth beneath the capability type system. Testing through this path
exercises the real end-to-end pipeline (`bin/main.ml`'s capability→`-D`-flag
derivation, the compiled binary, `march_sandbox_install`) rather than calling
`march_sandbox_install` in isolation.

## Components

### 1. C shim (`--ffi-c`), embedded as an OCaml string constant

Three probes, each returning `0` on success or the syscall's raw `errno` on
failure (`EPERM` = `1` on Linux, all architectures):

```c
int64_t sbx_probe_socket(void);       /* socket(AF_INET, SOCK_STREAM, 0) */
int64_t sbx_probe_execve(void);       /* fork(); child execve("/bin/true", …) */
int64_t sbx_probe_write_open(void);   /* open("/tmp/march_sbx_probe_<pid>", O_WRONLY|O_CREAT, 0644) */
```

`sbx_probe_execve` forks first (`fork`/`clone` is never gated — the scheduler
needs threads, per the existing runtime comment) so the parent process
survives regardless of outcome. The seccomp filter is inherited across both
`fork` and `execve`, so if `IO.Process` is withheld the child's `execve` call
itself fails with `EPERM` and `_exit`s with a sentinel (`200 + errno`) that the
parent decodes back to a plain errno; if `execve` succeeds the child becomes
`/bin/true` and exits `0`.

`open()` on modern glibc/Linux issues the `openat` syscall (with `AT_FDCWD`),
matching what `march_sandbox_install`'s `MARCH_CAP_DENY_WRITE` block actually
filters (flag-based, not path-based) — any writable-looking path works; the
PID-suffixed path just avoids any accidental collision across the 3 fixture
runs.

### 2. Three March fixtures, embedded as OCaml string constants

One per deny class, each holding the other two classes + `IO.Foreign` +
`IO.Console`, and printing all three probe results:

- `SbxDenyNet`: `needs IO.Console, IO.Foreign, IO.Process, IO.FileWrite` (no `IO.Network`)
- `SbxDenyExec`: `needs IO.Console, IO.Foreign, IO.Network, IO.FileWrite` (no `IO.Process`)
- `SbxDenyWrite`: `needs IO.Console, IO.Foreign, IO.Network, IO.Process` (no `IO.FileWrite`)

Each:

```march
extern "raw" : Cap(IO.Foreign) do
  fn probe_socket() : Int = "sbx_probe_socket"
  fn probe_execve() : Int = "sbx_probe_execve"
  fn probe_write_open() : Int = "sbx_probe_write_open"
end

fn main(...) : Unit do
  println("socket=" ++ int_to_string(probe_socket()))
  println("execve=" ++ int_to_string(probe_execve()))
  println("write=" ++ int_to_string(probe_write_open()))
end
```

### 3. `test/test_cap_sandbox_runtime.ml`

Follows `test_cap_sandbox_profile.ml`'s exact shelling-out pattern:
`Filename.temp_file` the fixture `.march` source and the shim `.c` source,
invoke `<compiler_exe> --cap-sandbox --compile --ffi-c <shim> -o <bin> <src>
> <log> 2>&1`, fail loudly (not skip) on nonzero compile exit, run `<bin>`,
parse the 3 `key=N` stdout lines, assert:

| Fixture | socket | execve | write |
|---|---|---|---|
| `SbxDenyNet` | `1` (EPERM) | `0` | `0` |
| `SbxDenyExec` | `0` | `1` (EPERM) | `0` |
| `SbxDenyWrite` | `0` | `0` | `1` (EPERM) |

Linux-only: skips (loudly, via a named `Alcotest.skip` test case, not a
silent no-op) when `uname -s` isn't `Linux`, mirroring
`test_cap_sandbox_profile.ml`'s `is_macos` gate inverted. Tagged `` `Slow ``
(native compile+run per fixture), matching the sibling sandbox/strip tests.

### Wiring

- `test/dune`: add `test_cap_sandbox_runtime` to `march_test_compiler`'s
  `(modules ...)` list (same library as `test_cap_sandbox_profile`,
  `test_cap_strip`) — no new dune stanza, no new CI YAML. It rides
  `run_compiler`'s existing deps (`bin/main.exe`, `(source_tree ../runtime)`,
  `(source_tree ../stdlib)`).
- `test/test_compiler.ml`: add `("cap_sandbox_runtime",
  Test_cap_sandbox_runtime.tests);` to `compiler_suites`.
- Runs automatically via `dune runtest` / `scripts/run-tests.sh` on the
  ubuntu-24.04 leg of CI's existing `test` matrix job.

### Docs

- `git mv specs/todos/2026-08-10-cap-sandbox-no-runtime-enforcement-ci.md`
  → `specs/progress/` (new content describing what actually shipped: the 3
  currently-implemented deny classes, NET/EXEC/WRITE — explicitly not
  `IO.NetListen`/Landlock, which stay open per the Tier 5 investigation doc
  and should extend this same test file when they land).
- `CHANGELOG.md`: one bullet under `### Added` (testing) — first CI
  verification that `--cap-sandbox`'s Linux seccomp filter enforces the
  syscall denials it claims to, not just that the flag strings look right.

## Out of scope

- macOS Seatbelt runtime enforcement (this todo and the existing
  `test_cap_sandbox_profile.ml` are Linux/`-D`-flag and macOS/SBPL-string
  respectively; a macOS *runtime* enforcement test is a separate, unfiled
  concern).
- `IO.NetListen` (`bind`/`listen`) and Landlock (`IO.FileRead`) — not
  currently implemented deny classes; the Tier 5 investigation doc explicitly
  recommends extending this test file, not writing a separate one, once
  either lands.
