# Capability sandbox — remaining refinements

The four items of `2026-08-03-cap-sandbox-follow-ups.md` are closed; see
`specs/progress/2026-08-03-cap-sandbox-follow-ups-closed.md` for the measured
enforceability matrix and what each conclusion turned out to be. These three
are what is left, all narrow.

- [ ] **`IO.NetListen` on Linux is advisory — re-scoped 2026-08-10, see
  `specs/2026-08-10-cap-tier5-investigation.md`.** Traced the exact cause:
  `bin/main.ml`'s `holds` check is bidirectional, so holding `IO.NetConnect`
  alone clears the seccomp NET-deny flag entirely (since NetConnect is a
  descendant of Network), which allows `socket()` outright — and nothing
  denies `bind`/`listen` specifically, so a NetConnect-only program can also
  listen. This is a small, well-understood extension of the EXISTING
  `DENY_NR`/`MARCH_CAP_DENY_*` pattern in `runtime/march_runtime.c`
  (`march_sandbox_install`) — NOT a new mechanism, contrary to how this was
  filed. The investigation doc has a near-complete code sketch. What's
  actually blocking it: no Linux machine was available to verify, and more
  importantly `specs/todos/2026-08-10-cap-sandbox-no-runtime-enforcement-ci.md`
  — NOTHING in CI verifies any of this sandbox's runtime behavior today, on
  either platform, so landing this without that job first would be another
  plausible-looking-but-unverified diff. Land the CI job first.

- [ ] **`IO.FileRead` under the Linux self-sandbox needs Landlock — re-scoped
  2026-08-10, see `specs/2026-08-10-cap-tier5-investigation.md`.** Confirmed
  this one really is a bigger lift than NetListen, not just filed at the same
  priority by convenience: Landlock is a path-based LSM, structurally unlike
  seccomp-bpf (three new syscalls, not a BPF program), needs a kernel-version/
  availability probe with an explicit fail-closed-or-degrade decision, and
  needs a design decision on the path-scoping DECLARATION surface (does it
  reuse `@[scope]`, today write-only, or need its own read-scope annotation?).
  `forge cap run`'s existing bwrap mount-namespace allow-list
  (`cap_sandbox.ml`'s `bwrap_args`) is probably the right model to port from.
  Needs its own design doc before code — do not bundle with the NetListen fix.

- [x] **Two SBPL baselines can drift** — CLOSED 2026-08-08 by
  `test/test_cap_sandbox_profile.ml` (normalized clause-set equality plus
  both polarities of the conditional grants); see
  `specs/progress/2026-08-08-cap-attrib-owner-fixes.md`.
