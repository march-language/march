# `--cap-sandbox` runtime enforcement test — design

Closes the gap filed in
[specs/todos/2026-08-10-cap-sandbox-no-runtime-enforcement-ci.md](../../../specs/todos/2026-08-10-cap-sandbox-no-runtime-enforcement-ci.md):
`test/test_cap_sandbox_profile.ml` and `test/test_cap_strip.ml` verify the
embedded SBPL (macOS) / seccomp `-D` flag (Linux) **strings** are correct and
agree between the two builders. Nothing verifies the **runtime behavior**
those strings are supposed to produce — neither the seccomp-bpf deny classes
in `runtime/march_runtime.c`'s Linux `march_sandbox_install` (hand-assembled
`sock_filter`/`BPF_JUMP`/`BPF_STMT`, fixed jump offsets) nor the macOS
Seatbelt profile's `sandbox_init()` call have ever had a test that compiles a
program, runs it under the real sandbox, and asserts a withheld capability's
syscall actually fails while a held one still succeeds. Covers both
platforms.

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

## The macOS process asymmetry

The macOS embedded profile (`bin/main.ml`'s `cap_sandbox_define`) gates a
**different** operation for the `IO.Process` class than Linux does:
`(allow process-exec)` is unconditional baseline (`bin/main.ml:3527`); only
`(allow process-fork)` is conditioned on `holds "IO.Process"`
(`bin/main.ml:3580`). Linux is the reverse — `execve`/`execveat` are denied,
`fork`/`clone` never are. So the macOS "process" probe has to be **fork**,
not exec — testing exec on macOS would pass unconditionally regardless of
capability, which would make the test vacuous for that axis. This asymmetry
is filed separately as
[specs/todos/2026-08-12-cap-sandbox-macos-process-exec-not-gated.md](../../../specs/todos/2026-08-12-cap-sandbox-macos-process-exec-not-gated.md)
— out of scope to change here; this test documents current behavior
(including exec succeeding regardless of `IO.Process`) rather than changing
it.

## Components

### 1. C shim (`--ffi-c`), embedded as an OCaml string constant, shared by both platforms

Portable POSIX, no `#ifdef`s needed. Each probe returns `0` on success or the
syscall's raw `errno` on failure (`EPERM` = `1` on both Linux and macOS):

```c
int64_t sbx_probe_socket(void);        /* socket(AF_INET, SOCK_STREAM, 0) */
int64_t sbx_probe_execve(void);        /* fork(); child execve("/bin/true", …) — Linux's process probe */
int64_t sbx_probe_fork(void);          /* fork(); child _exit(0) immediately — macOS's process probe */
int64_t sbx_probe_write_open(void);    /* open("/tmp/march_sbx_probe_<pid>", O_WRONLY|O_CREAT, 0644) */
int64_t sbx_probe_exec_inplace(void);  /* execve("/bin/echo", ["/bin/echo","exec=0"], NULL) — see below */
```

`sbx_probe_execve` forks first (`fork`/`clone` is never gated on Linux — the
scheduler needs threads, per the existing runtime comment) so the parent
process survives regardless of outcome. The seccomp filter is inherited
across both `fork` and `execve`, so if `IO.Process` is withheld the child's
`execve` call itself fails with `EPERM` and `_exit`s with a sentinel
(`200 + errno`) that the parent decodes back to a plain errno; if `execve`
succeeds the child becomes `/bin/true` and exits `0`.

`sbx_probe_fork` is simpler — macOS gates `fork` directly, so no exec is
needed to observe the denial; the child (if fork succeeds at all) just exits
immediately, and the parent reports `0` or `fork`'s own `errno`.

`sbx_probe_exec_inplace` is the informational macOS check for the asymmetry
above: it calls `execve` **in the calling process itself**, no fork — deny is
moot here since `process-exec` is never gated regardless of capability, so
this always succeeds and is only ever called as the *last* action of a
fixture. It replaces the current process image with `/bin/echo`, which prints
`exec=0` to the same stdout the March program was already writing to — the
OCaml test reads it as just another line of the same captured output, even
though a different binary produced it.

`open()` on modern glibc/Linux and on macOS issues the `openat`/`open`
syscall via the flag-checked path both platforms' filters target — any
writable-looking path works; the PID-suffixed path just avoids collisions
across the fixture runs.

### 2. March fixtures, embedded as OCaml string constants

One per deny class per platform, each holding the other two classes +
`IO.Foreign` + `IO.Console`, printing all applicable probe results:

**Linux** (process class = exec):
- `SbxDenyNet`: `needs IO.Console, IO.Foreign, IO.Process, IO.FileWrite` (no `IO.Network`)
- `SbxDenyExec`: `needs IO.Console, IO.Foreign, IO.Network, IO.FileWrite` (no `IO.Process`)
- `SbxDenyWrite`: `needs IO.Console, IO.Foreign, IO.Network, IO.Process` (no `IO.FileWrite`)

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

**macOS** (process class = fork; the deny-process fixture additionally probes
the always-allowed exec, as the *last* statement since it replaces the
process image):
- `SbxDenyNetMac`: `needs IO.Console, IO.Foreign, IO.Process, IO.FileWrite` (no `IO.Network`)
- `SbxDenyProcessMac`: `needs IO.Console, IO.Foreign, IO.Network, IO.FileWrite` (no `IO.Process`)
- `SbxDenyWriteMac`: `needs IO.Console, IO.Foreign, IO.Network, IO.Process` (no `IO.FileWrite`)

```march
extern "raw" : Cap(IO.Foreign) do
  fn probe_socket() : Int = "sbx_probe_socket"
  fn probe_fork() : Int = "sbx_probe_fork"
  fn probe_write_open() : Int = "sbx_probe_write_open"
  fn probe_exec_inplace() : Int = "sbx_probe_exec_inplace"   -- only called by SbxDenyProcessMac
end

fn main(...) : Unit do
  println("socket=" ++ int_to_string(probe_socket()))
  println("fork=" ++ int_to_string(probe_fork()))
  println("write=" ++ int_to_string(probe_write_open()))
  -- SbxDenyProcessMac only, and only after the above three lines print:
  println("exec=" ++ int_to_string(probe_exec_inplace()))
end
```

### 3. `test/test_cap_sandbox_runtime.ml`

Follows `test_cap_sandbox_profile.ml`'s exact shelling-out pattern:
`Filename.temp_file` the fixture `.march` source and the shim `.c` source,
invoke `<compiler_exe> --cap-sandbox --compile --ffi-c <shim> -o <bin> <src>
> <log> 2>&1`, fail loudly (not skip) on nonzero compile exit, run `<bin>`,
parse the `key=N` stdout lines, assert:

**Linux:**

| Fixture | socket | execve | write |
|---|---|---|---|
| `SbxDenyNet` | `1` (EPERM) | `0` | `0` |
| `SbxDenyExec` | `0` | `1` (EPERM) | `0` |
| `SbxDenyWrite` | `0` | `0` | `1` (EPERM) |

**macOS:**

| Fixture | socket | fork | write | exec |
|---|---|---|---|---|
| `SbxDenyNetMac` | `1` (EPERM) | `0` | `0` | — |
| `SbxDenyProcessMac` | `0` | `1` (EPERM) | `0` | `0` (always allowed — documents the asymmetry) |
| `SbxDenyWriteMac` | `0` | `0` | `1` (EPERM) | — |

Each platform's test group skips (loudly, via a named `Alcotest.skip` test
case, not a silent no-op) when `uname -s` doesn't match, mirroring
`test_cap_sandbox_profile.ml`'s `is_macos` gate (and its inverse for the
Linux group). Both groups live in the one file, sharing the embedded C shim
string. Tagged `` `Slow `` (native compile+run per fixture), matching the
sibling sandbox/strip tests.

### Wiring

- `test/dune`: add `test_cap_sandbox_runtime` to `march_test_compiler`'s
  `(modules ...)` list (same library as `test_cap_sandbox_profile`,
  `test_cap_strip`) — no new dune stanza, no new CI YAML. It rides
  `run_compiler`'s existing deps (`bin/main.exe`, `(source_tree ../runtime)`,
  `(source_tree ../stdlib)`).
- `test/test_compiler.ml`: add `("cap_sandbox_runtime",
  Test_cap_sandbox_runtime.tests);` to `compiler_suites`.
- Runs automatically via `dune runtest` / `scripts/run-tests.sh` on **both**
  legs of CI's existing `test` matrix job (ubuntu-24.04 runs the Linux group,
  macos runs the macOS group; each skips the other's tests).

### Docs

- `git mv specs/todos/2026-08-10-cap-sandbox-no-runtime-enforcement-ci.md`
  → `specs/progress/` (new content describing what actually shipped: the 3
  currently-implemented deny classes per platform — Linux NET/EXEC/WRITE,
  macOS NET/FORK/WRITE — explicitly not `IO.NetListen`/Landlock, which stay
  open per the Tier 5 investigation doc and should extend this same test file
  when they land).
- `specs/todos/2026-08-12-cap-sandbox-macos-process-exec-not-gated.md` stays
  filed as a separate, still-open follow-up (not closed by this change).
- `CHANGELOG.md`: one bullet under `### Added` (testing) — first CI
  verification that `--cap-sandbox`'s Linux seccomp filter and macOS Seatbelt
  profile enforce the syscall denials they claim to, not just that the
  embedded flag strings/SBPL look right.

## Out of scope

- Changing macOS's `process-exec`-always-allowed behavior — tracked
  separately in
  `specs/todos/2026-08-12-cap-sandbox-macos-process-exec-not-gated.md`. This
  change tests and documents current behavior only.
- `IO.NetListen` (`bind`/`listen`) and Landlock (`IO.FileRead`) — not
  currently implemented deny classes on either platform; the Tier 5
  investigation doc explicitly recommends extending this test file, not
  writing a separate one, once either lands.
- `IO.FileRead` on macOS staying advisory (dyld must map libraries before
  user code exists) — pre-existing, documented, unrelated to this change.
