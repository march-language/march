# `native_signal_watch` SIGSEGV 40/40 on linux/aarch64: handler lacked SA_ONSTACK

Fixed 2026-09-21.

## Symptom

`test/native/signal_watch.march` (`MARCH_NUM_SCHEDULERS=1 ./native_signal_watch`)
printed `before raise` and then died on every run in the `march-amdr-repro`
container (ubuntu, glibc 2.39, linux/aarch64 on an arm64 Mac):

```
march: fatal SIGSEGV si_code=128 addr=0x0 pc=0xffff... sched=0 pid=0 status=1 fault outside its stack
```

It reproduced with origin/main's runtime too, so the bug predates the branch it was
found on.

## Why CI never saw it

No workflow runs the test suite on linux/aarch64. `ci.yml` tests on `ubuntu-24.04`
(x86_64) and `macos-15` (arm64 Darwin); the only aarch64 Linux leg is `build.yml`'s
`ubuntu-24.04-arm` release build, which runs `--version` in bare Alpine/Debian
containers and nothing else. glibc version and the altstack setup are not the
difference. The difference is the architecture's signal-frame size (below).

## Root cause

`si_code=128` is `SI_KERNEL` with `si_addr` 0: the signal Linux force-sends when it
cannot write a signal frame (`setup_rt_frame` fails, then `force_sigsegv`). It is not
a user-mode fault.

- `march_signal_watch` installed `march_signal_dispatch` with plain `signal()`, so
  without `SA_ONSTACK`. The self-raised SIGUSR2 is delivered on the raising thread's
  current stack, which is main's green-thread stack.
- A green stack has only `MARCH_STACK_INITIAL` (4 KiB) committed. The rest is
  PROT_NONE and grows lazily through the SIGSEGV handler, but the kernel cannot use
  that path while it builds a frame.
- On arm64 Linux, `struct rt_sigframe` holds a `uc_mcontext` with a fixed 4096-byte
  `__reserved` area plus siginfo and ucontext headers, about 4.6 KiB in total. That
  can never fit in a fresh 4 KiB green stack. x86_64's xsave frame and Darwin's arm64
  frame are small enough to fit in the remaining headroom, so those platforms passed
  because of the frame size, not because the code was correct.
- The forced SIGSEGV goes to the lazy-growth handler, which finds `addr=0` outside
  the stack and reports it as fatal.

`http_signal_handler` (SIGTERM/SIGINT while `march_http_server_listen` runs) was
installed the same way, so it had the same latent crash for an external signal that
lands on a scheduler thread running a green thread.

## Fix

New `march_install_async_signal(sig, handler)` in `runtime/march_runtime.c`:
`sigaction` with `SA_ONSTACK | SA_RESTART` (`SA_RESTART` keeps `signal()`'s BSD
semantics). Both `march_signal_watch` and `march_http_server_listen` now use it.
Every scheduler thread already has a 64 KiB altstack (`setup_alt_stack`; under ASAN,
ASAN's own). A thread without one gets the frame on its ordinary stack, which is
safe.

## Evidence (container, linux/aarch64)

| runtime | `signal_watch` at 1 scheduler |
|---|---|
| before fix | 0/20 pass, identical SI_KERNEL fault every run |
| fix | 40/40 pass |
| fix with only `SA_ONSTACK` removed (`sa_flags = SA_RESTART`) | 0/20 pass, identical fault |

The last row shows the flag itself is the fix, not the switch from `signal()` to
`sigaction`. After the fix, `signal_term_suppress` passed 20/20 and the multisched
variant (default schedulers, 14 CPUs) passed 20/20. On macOS the
`native_signal_watch` and `native_signal_term_suppress` goldens still match.

## Possibly related, not closed

`specs/todos/2026-09-17-flake-signal-watch-capturing-handler-25x.md` is a CI (x86_64)
flake whose failure mode is unknown. If it was a crash, a frame that fit only because
of headroom could explain it, since a deeper green stack leaves less room. That link
is unproven, so the todo stays open.
