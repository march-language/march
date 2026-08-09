# Capability sandbox — remaining refinements

The four items of `2026-08-03-cap-sandbox-follow-ups.md` are closed; see
`specs/progress/2026-08-03-cap-sandbox-follow-ups-closed.md` for the measured
enforceability matrix and what each conclusion turned out to be. These three
are what is left, all narrow.

- [ ] **`IO.NetListen` on Linux is advisory.** A network namespace isolates
  rather than refuses, so a contained server still binds a port — nothing can
  reach it, but `bind()` succeeds. Closing this needs a seccomp filter on
  `bind`/`listen`, more machinery than the netns for a case that is already
  contained. The exfiltration path (outbound connect) IS enforced today. Low
  priority.

- [ ] **`IO.FileRead` under the Linux self-sandbox needs Landlock.** seccomp
  filters syscall numbers and scalar args, never pointer contents, so it cannot
  tell WHICH path an `openat` targets — read scoping is therefore not enforced
  by `--cap-sandbox` on Linux (write is, via the O_* flag bits, which are
  scalar). Landlock closes this; `forge cap run` already scopes reads
  externally via a mount-namespace allow-list. Until then `IO.FileRead` is
  advisory for the self-imposed variant on BOTH platforms.

- [x] **Two SBPL baselines can drift** — CLOSED 2026-08-08 by
  `test/test_cap_sandbox_profile.ml` (normalized clause-set equality plus
  both polarities of the conditional grants); see
  `specs/progress/2026-08-08-cap-attrib-owner-fixes.md`.
