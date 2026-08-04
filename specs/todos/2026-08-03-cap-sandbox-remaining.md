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

- [ ] **`--cap-sandbox` on Linux is rejected at compile time.** Self-sandboxing
  there needs an in-process seccomp-bpf filter; the mount-namespace allow-list
  forge uses externally is unavailable to a process sandboxing itself
  post-exec. The flag now exits 2 at COMPILE time pointing at `forge cap run`,
  rather than accepting the flag and emitting a binary that exits 70 on first
  run — a trap found only when CI executed the test on Linux for the first
  time. Build the real thing only if there is demand for deployed Linux
  binaries that self-contain without a supervisor.

- [ ] **Two SBPL baselines can drift.** `forge/lib/cap_sandbox.ml`'s
  `sbpl_baseline` and `bin/main.ml`'s `cap_sandbox_define` construct the same
  deny-default profile independently. Both are short and commented as mirrors,
  but nothing mechanically enforces agreement. A drift test — compile a fixture
  with `--cap-sandbox`, extract the embedded profile, diff against
  `Cap_sandbox.profile_for` for the same cap set — would close it, in the same
  spirit as the `builtin_cap_table` accounting test.
