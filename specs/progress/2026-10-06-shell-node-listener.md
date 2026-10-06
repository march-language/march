# Shell, node side: the listener and signed EVAL

**Date:** 2026-10-06
**Plan:** [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md),
R6 items 2-5 and 7 (node half); design §6.4 and §6.9.
**Tracking todo:** [`todos/2026-09-24-observe-recon-shell.md`](../todos/2026-09-24-observe-recon-shell.md).

The client half (compiling March input into fragments, `forge shell`) is the
next piece; this pins the node's half of the protocol with hand-written C
fragments.

## What exists now

`runtime/march_shell.c` (role `hcr`), started by `march_reload_server_start`
on `<reload socket>.shell`:

- **Its own listener.** One thread per connection, at most 4 sessions (a
  fifth gets `ERR busy`). The reload socket is untouched, so an open shell
  session never blocks a deploy (C19).
- **`HELLO`** attaches the session at the current code epoch and gives it
  256 of `march_repl_set`'s 4096 slots. When the connection closes, the
  values in that range are released and the range is freed (C20).
- **`EVAL <sig> name: epoch: nonce: not_after_ms: timeout_ms: caps: src_b64:
  so_b64:`**, the fragment's bytes inline, so one input is one round trip.
  The signature covers the whole line minus itself, bytes included. Checks
  run in this order:
  1. a key is compiled in;
  2. the fields parse;
  3. the signature;
  4. the nonce and expiry (`march_sig_admit`, as for the debug verbs);
  5. the session's epoch is still current;
  6. every cap in `caps` is listed in `$MARCH_SHELL_POLICY` (no file: deny
     all).

  Every attempt is audited with `"type":"shell"` and the decoded source.
- **Running a fragment.** The fragment is written to a private file under
  `$TMPDIR/march-shell-<pid>/`, opened with `dlopen(RTLD_NOW | RTLD_LOCAL)`,
  and its entry (a zero-argument function returning the rendered String) runs
  as a task at the current epoch. The task runs with a crash trap
  (`crash_jmp`) and a cancellation landing (`task_jmp`). The reply is one of:
  - `OK <b64 result> out:<b64>`;
  - `PANIC <b64 message> out:<b64>`;
  - `TIMEOUT out:<b64>`;
  - `TIMEOUT uncancellable`, for a fragment that never reaches a
    cancellation point within a second of being cancelled.
- **Timeout.** It cancels the task the way a drain's hard deadline does:
  `cancel_requested` plus `march_preempt_request`. `timeout_ms` is at most
  30 s.
- **Captured output.** `march_proc.out_capture` (new): while set, `print`,
  `println`, `print_int` and `print_float` append to a 256 KiB buffer instead
  of writing to stdout. Results are cut at 1 MiB.
- **A deploy ends the session.** An `EVAL` from a session whose epoch is no
  longer current gets `ERR epoch_changed <old> <new>`. An idle session is
  checked every second and sent `BYE epoch_changed <old> <new>`.

## Tests

`test/native/shell_node.march` with `test/shell_check.ml`: a `--hot-reload
--signing-pubkey` node, a fresh keypair, and three C fragments
(`test/shell/frag_{ok,panic,loop}.c`). Twenty checks cover:

- `HELLO` gating;
- a result with its captured `println`;
- a replay, and another key's signature;
- the shell policy refusing, then allowing after an edit;
- a panic with its earlier output;
- an endless loop cancelled within the timeout plus a second, and the node
  serving afterwards;
- a missing entry, a stale epoch, an unknown field;
- four concurrent sessions with distinct slot ranges and a refused fifth;
- the audit lines in order, with the source.

Red controls: without the capture pointer, both output checks fail. Without
the cancel, the loop answers `TIMEOUT uncancellable`.

## Deviations from the plan

1. **No `so_blake3` field.** The signature covers the inline bytes
   themselves, which is what the digest was for (R5.2's `CAS_PUT` hashing
   still applies to ACTIVATE uploads).
2. **The capability check trusts the signed `caps` list.** The node does not
   yet read the fragment's own cap manifest (R5.6), so a client that
   under-declares caps is caught only by the compiler's ceiling on the
   operator's machine. R5.6 closes this before the shell is called
   production-ready.
3. **Fragments are never unloaded.** A `let` can store a closure whose code
   lives in the fragment; reference-counted unloading (R6.3) comes later.
4. **The idle-session `BYE` is polled once a second**, not pushed at the
   moment of the deploy.
