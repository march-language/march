# Shell: replay binding, fail-closed audit, socket hardening (review F1-F4)

Logged 2026-10-08. Findings F1-F4 of
`specs/reviews/2026-10-07-shell-r5-review-packet.md`, found while preparing
the R5 security review and fixed before it.

## What changed (`runtime/march_shell.c`, `bin/shell_cmd.ml`)

- **F1/F2, replay of a captured EVAL.**
  - The problem: the nonce ring is in memory, a restarted node starts at the
    same epoch, and an EVAL named no node. A line captured up to 60 s
    earlier ran again after a restart, or on another node trusting the same
    key.
  - The fix: `HELLO` now returns `session:<32 hex>`, 16 random bytes
    (`arc4random_buf` on macOS, `/dev/urandom` elsewhere; `ERR no_random`
    if neither works). Every EVAL must carry it as a signed `session:`
    field, else `ERR bad_session`, checked right after the signature.
  - The client refuses a node whose `HELLO` has no challenge.
- **F3, the audit log failing open.** `audit()` reports whether its line was
  written (`fflush`, `ferror`). An input about to run whose line cannot be
  written gets `ERR audit_unavailable` and does not run. Refusals are still
  audited best-effort.
- **F4, the socket.** The shell socket's 0600 mode is now set between
  `bind` and `listen`, as the reload socket's is, so no connection is
  accepted under the umask's mode. A peer whose uid is neither the
  process's nor root's is dropped at `accept` (`getpeereid` /
  `SO_PEERCRED`).

## Tests (`test/shell_check.ml`, `native_shell_node.out`)

New checks:
- `HELLO` carries a 32-hex challenge, and each session gets its own;
- a line replayed on another connection gets `bad_session`;
- a line signed for another session's challenge gets `bad_session`;
- with the audit log made read-only, the input gets `audit_unavailable` and
  nothing runs (skipped as root, who writes through the mode);
- the shell socket is mode 0600;
- the expected audit sequence gains the two `bad_session` lines.

RED: with the session check and the fail-closed audit disabled in the
runtime, the three behaviour checks and the audit-sequence check fail. The
peer-uid drop needs a second user to test, and has no check.
