# Capability sandbox follow-ups (Phase 4 remainder)

Shipped 2026-08-03: `forge cap run [--allow-only CAPS] BINARY` — external,
OS-enforced capability sandbox (`forge/lib/cap_sandbox.ml`). Design:
`specs/2026-08-03-forge-cap-audit-design.md` §4.3 mechanism B.

The enforceable/advisory split below was **measured**, not assumed. Do not
"fix" an advisory capability by asserting it — confirm the denial actually
holds first, or the report becomes false assurance (design §8).

| capability | macOS (SBPL) | Linux (bwrap) |
|---|---|---|
| `IO.FileWrite` / `IO.FileSystem` | enforced | enforced (`--ro-bind`) |
| `IO.NetConnect` / TLS / WebSocket | enforced | enforced (`--unshare-net`) |
| `IO.NetListen` | enforced | **advisory** — netns isolates, `bind()` still succeeds |
| `IO.Process` | enforced (fork) | enforced (`--unshare-pid`) |
| `IO.FileRead` | **advisory** — dyld must map libs first | **advisory** — scopable but not yet wired |
| `IO.Clock`, `IO.Spawn`, `IO.Random` | advisory — indistinguishable from runtime baseline | same |
| `IO.Foreign` | outside the model entirely | same |

## Open items

- [ ] **Wire filesystem read scoping on Linux (Landlock).** This is the one
  advisory that is genuinely fixable. Measured working in a 6.12 container:
  `bwrap --tmpfs /etc` makes `/etc/hosts` unreadable while the program still
  runs, so read denial is achievable on Linux where it is structurally
  impossible on macOS (the loader reads `/usr/lib` before user code exists).
  `landlock.h` is present in the toolchain image. Wire path scoping, then flip
  `IO.FileRead` to `Enforced` on the Bwrap backend **only after** a test proves
  a read is actually denied while a granted read still succeeds.

- [ ] **`--cap-sandbox`: the self-imposed, in-binary variant** (plan Task 9).
  Deliberately not built yet — it is the *weaker* mechanism (a binary that
  installs its own sandbox can also be built not to) and requires a runtime
  `march_sandbox.c`, a compile-time define, and a `cas_flags` entry. The
  external `forge cap run` delivers the security property without any of that.
  Build this only if there is a concrete need for containment when forge is not
  the launcher; the value is defense-in-depth, not a new guarantee.

- [ ] **Deny-default profile on macOS.** The shipped SBPL profile is
  allow-default with per-class denies, which constrains the categories the
  capability lattice models but not novel resources (mach services, IPC). A
  true `(deny default)` allow-list was attempted and aborted the runtime
  (SIGABRT) even with hand-built allow-lists for `/usr/lib`, `/System`,
  `/dev/urandom` and the binary itself; `(trace ...)` mode did not produce a
  profile and unified-log denial queries returned nothing. Closing this needs a
  proper baseline characterization of what the March runtime touches at
  startup. Worth doing — it is the difference between "constrains the modelled
  categories" and "allow-list" — but it is not a small task.

- [ ] **`forge cap run` on a binary whose caps cannot be read.** Currently the
  policy falls back to the binary's claim, and an unreadable/stripped binary
  yields an empty cap set, i.e. the *tightest* policy. That fails safe, but it
  fails confusingly ("why did my program break?"). Report the reason explicitly
  rather than silently running with nothing granted.
