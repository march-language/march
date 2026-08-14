# macOS `--cap-sandbox`: `IO.Process` gates `fork`, not `exec` — unlike Linux

Found 2026-08-12, while designing
`specs/2026-08-12-cap-sandbox-runtime-enforcement-test-design.md` (runtime
enforcement tests for `--cap-sandbox`).

## The gap

The embedded macOS Seatbelt profile (`bin/main.ml`'s `cap_sandbox_define`,
~line 3493) unconditionally allows `process-exec`:

```
bin/main.ml:3527:  Buffer.add_string b "(allow process-exec)";
...
bin/main.ml:3580:  if holds "IO.Process"   then Buffer.add_string b "(allow process-fork)";
```

Only `process-fork` is conditioned on `IO.Process`. `process-exec` is part of
the unconditional baseline, alongside `file-read*`/`mach*`/`sysctl-read`/etc.

On **Linux**, the equivalent capability class gates the opposite operation:
`MARCH_CAP_DENY_EXEC` denies `execve`/`execveat` specifically, and `fork`/
`clone` are never gated ("the scheduler needs threads" — see
`runtime/march_runtime.c` ~line 2140). So on Linux, withholding `IO.Process`
blocks launching a new program; on macOS, withholding `IO.Process` blocks
forking but a program can still call `execve()` (directly, or via `extern`
FFI bypassing the type-checked capability surface — see `specs/lang/
capabilities.md`'s "IO.Foreign" section) to launch an arbitrary new program
image.

`specs/lang/capabilities.md`'s OS-level enforcement section documents macOS
as `"IO.Process` allows fork" and doesn't mention exec at all — consistent
with current behavior, but easy to misread as symmetric with the Linux
description ("no `IO.Process` blocks `execve`/`execveat`") two bullets above
it in the same doc.

## Why it wasn't fixed here

`forge/lib/cap_sandbox.ml` (a **different**, externally-imposed enforcement
mechanism — `forge cap run`, not `--cap-sandbox`) explains why ITS profile
allows `process-exec` unconditionally: `sandbox-exec` (forge's own external
wrapper) must itself `exec` the target binary, so denying `process-exec`
there means "target cannot launch" (measured: exit 71). That reasoning is
about the **external wrapper's own exec of the target**, not about syscalls
the **target's own running code** makes afterward.

`--cap-sandbox`'s embedded profile is a different case: `march_sandbox_install`
runs from **inside** the already-started process (called from
`march_spawn_main`, after the binary is already running) — nothing needs to
`exec` this process again for it to keep running. Whether `bin/main.ml`'s
unconditional `(allow process-exec)` was a deliberate choice for the embedded
case too, or an imprecise carryover from mirroring forge's external-baseline
reasoning ("Baseline mirrors forge/lib/cap_sandbox.ml's sbpl_baseline" per
the comment at `bin/main.ml:3506`), is unclear and worth investigating.

## Suggested next step

Investigate whether the embedded profile can safely gate `process-exec` on
`IO.Process` the same way Linux gates `execve`/`execveat` — i.e. whether
`(allow process-exec)` can move from the unconditional baseline into the
`if holds "IO.Process"` block alongside `process-fork`. If some baseline
`process-exec` use is structurally required even for an `IO.Process`-less
program (analogous to why `file-read*` stays advisory — dyld needs it before
user code exists), measure and document that the same way
`forge/lib/cap_sandbox.ml`'s header comment measures its own
enforceable/advisory split, rather than leaving the asymmetry unstated.

`test/test_cap_sandbox_runtime.ml` (once landed per the design doc above)
documents today's actual behavior — `exec` succeeding regardless of
`IO.Process` on macOS — as a passing assertion, not a bug the test itself
flags; this todo is the tracked follow-up for whether that behavior should
change.
