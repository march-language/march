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

- [ ] **Two SBPL baselines can drift.** `forge/lib/cap_sandbox.ml`'s
  `sbpl_baseline` and `bin/main.ml`'s `cap_sandbox_define` construct the same
  deny-default profile independently. Both are short and commented as mirrors,
  but nothing mechanically enforces agreement. A drift test — compile a fixture
  with `--cap-sandbox`, extract the embedded profile, diff against
  `Cap_sandbox.profile_for` for the same cap set — would close it, in the same
  spirit as the `builtin_cap_table` accounting test.
