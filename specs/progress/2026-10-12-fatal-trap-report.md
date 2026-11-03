# SIGILL / SIGTRAP in a compiled program print a report (2026-10-12)

**Problem.** Nothing in the runtime handled SIGILL or SIGTRAP, so a compiled
program that executed an illegal instruction or a `brk` died with no output:
the only evidence was the shell's exit status. `native_actor_state_released`
died that way on macOS CI four times (status 132) and never locally, so each
sighting carried no location (specs/todos/2026-10-07-flake-actor-state-released-macos-exit.md).

**Change.** `runtime/march_scheduler.c`, `march_fatal_trap_handler`, installed
next to the SIGSEGV/SIGBUS stack-growth handler (only over a default
disposition, so a host or sanitizer handler is kept). It runs on the alt stack
and writes, with write(2) and hand-rolled hex only:

1. the existing `march_report_fatal_fault` line (now naming SIGILL/SIGTRAP):
   si_code, fault address, pc, scheduler, green-thread pid and status;
2. `march: fatal SIGILL static pc=... lr=... (runtime lr=... fp=... slide=...) insn=...`:
   pc and lr minus `_dyld_get_image_vmaddr_slide(0)` on macOS, so
   `lldb <binary>` + `image lookup -a <addr>` names them, and the 32-bit word
   at pc on arm64;
3. `march: fatal trap frames (static): ...`: a frame-pointer walk of the
   interrupted context, bounded to the running green thread's stack
   reservation (else the OS thread's stack), stopping at the first
   non-increasing fp.

With `MARCH_FATAL_BACKTRACE=1` (read once at install) it then symbolises the
walked frames with `backtrace_symbols_fd` (dladdr resolves local symbols of
the executable on macOS). That call is not async-signal-safe, hence opt-in;
`native_actor_state_released`'s dune rule sets it, because the binary that
traps on CI is not kept, so only names survive. Then `_exit(128 + sig)`, as
the SIGSEGV path does (re-raising can wedge a green-thread context in the
kernel).

On arm64 macOS, `brk` (`__builtin_trap`, `llvm.trap`, a trapping
`unreachable`) raises SIGTRAP (133); SIGILL (132) means the CPU fetched a word
that is not an instruction (`udf #0` = zeros). Both now report.

**Test.** `test/native/fatal_trap_report.{march,c,expected}`: the shim forks
and the child runs `udf #0` (arm64) / `ud2` (x86_64) on the calling green
thread; the parent checks the exit status and the three report lines. RED
before: `child exit status: 132` with all three false. Also passes under
ASAN+UBSAN on Linux arm64 (`march-ci-ubuntu-step6b`).
