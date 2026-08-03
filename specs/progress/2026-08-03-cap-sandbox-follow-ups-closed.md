# Capability sandbox follow-ups (Phase 4 remainder)

**Status 2026-08-03: all four items CLOSED.** Kept as the record of what was
measured, because three of the four originally-stated conclusions were wrong.

Shipped: `forge cap run [--allow-only CAPS] BINARY` (external enforcement) and
`march --cap-sandbox` (opt-in self-imposed profile).
Design: `specs/2026-08-03-forge-cap-audit-design.md` §4.3 mechanism B.

The enforceable/advisory split was **measured**, not assumed. Do not "fix" an
advisory capability by asserting it — confirm the denial actually holds first,
or the report becomes false assurance (design §8).

| capability | macOS (SBPL) | Linux (bwrap) |
|---|---|---|
| `IO.FileWrite` / `IO.FileSystem` | enforced | enforced (`--ro-bind`) |
| `IO.NetConnect` / TLS / WebSocket | enforced | enforced (`--unshare-net`) |
| `IO.NetListen` | enforced | **advisory** — netns isolates, `bind()` still succeeds |
| `IO.Process` | enforced (fork) | enforced (`--unshare-pid`) |
| `IO.FileRead` | **advisory** — dyld must map libs first | **enforced** — allow-list mount namespace |
| `IO.Clock`, `IO.Spawn`, `IO.Random` | advisory — indistinguishable from runtime baseline | same |
| `IO.Foreign` | outside the model entirely | same |

## Closed items

- [x] **Linux filesystem read scoping.** Done, and it went further than
  planned: rather than Landlock, bwrap's mount namespace gives a genuine
  allow-list — only the loader's paths and the binary are bound in, so
  everything else is *absent* rather than forbidden. Verified end-to-end in a
  6.12 container with the flags the code emits: `/etc/hosts` DENIED without the
  cap, OK with it, OK under a root `IO` grant. `IO.FileRead` is now `Enforced`
  on bwrap.

- [x] **Deny-default profile on macOS.** **The earlier conclusion was wrong.**
  Deny-default is entirely feasible; the first attempt failed because the
  baseline lacked `mach*`, `sysctl-read` and `ipc-posix-shm`, not because the
  approach was infeasible. The profile is now a true allow-list, so resources
  the capability lattice never modelled (IPC, IOKit, mach services) are refused
  too. Gating verified in both directions live.

- [x] **`--cap-sandbox` self-imposed variant.** Built, having found a concrete
  need the original note missed: a deployed server is launched by systemd or a
  supervisor, so `forge cap run` never reaches it. Its value is narrower than
  "containment" and is documented as such — the profile is derived from what
  the program *does*, so it cannot restrict the program's intended behaviour,
  only escalation beyond it (the Chrome-renderer threat model).

- [x] **Empty/unreadable capability policy.** `cap run` now names the reason —
  stripped symbols, an unstripped build whose list was withheld, a genuinely
  capability-free binary, or an empty `--allow-only`.

## Regression found and fixed after the fact

Putting the sandbox in its own `runtime/march_sandbox.c` broke **`march repl`
and 33 tests**: `march_spawn_main` calls `march_sandbox_install`
unconditionally, and every harness that links the runtime keeps its OWN source
list — `bin/main.ml`, four rules in `test/dune`, `test/test_helpers.ml`, and the
REPL's JIT `.so` builder. A new translation unit has to be added to all of them
or the link fails with an undefined symbol.

The fix was not to add it to each list but to delete the file and inline the
function into `march_runtime.c` behind `#ifdef MARCH_CAP_PROFILE`, which
removes the class of breakage. **A new runtime `.c` file is a multi-site
change; a new function in an existing one is not.** Note the failure was NOT
silent here only because a prior fix had made JIT link errors loud — the
comment in `test_helpers.ml` describing that exact vacuous-green class was
already there, warning about this.

## Open follow-ups

- [ ] **`IO.NetListen` on Linux.** A netns isolates rather than refuses, so a
  contained server binds a port nothing can reach. Closing this properly needs
  a seccomp filter on `bind`/`listen`, which is more machinery than the netns
  and only sharpens an already-contained case. Low priority; the exfiltration
  path (outbound connect) is enforced today.

- [ ] **Linux `--cap-sandbox`.** Self-sandboxing on Linux needs an in-process
  seccomp-bpf filter; the mount-namespace allow-list forge uses externally is
  unavailable to a process sandboxing itself post-exec. Currently refuses with
  a pointer to `forge cap run`. Build only if there is demand for deployed
  Linux binaries that self-contain without a supervisor.

- [ ] **Keep the two SBPL baselines in step.** `forge/lib/cap_sandbox.ml`'s
  `sbpl_baseline` and `bin/main.ml`'s `cap_sandbox_define` build the same
  profile independently. They are short and commented as mirrors, but nothing
  mechanically enforces it — a drift test (compile with `--cap-sandbox`, diff
  the embedded profile against `Cap_sandbox.profile_for`) would close it.
