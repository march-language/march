# Observe R7: the `forge observe` TUI, `WATCH`, crash dumps

Plan item R7 of `specs/plans/2026-09-28-observe-recon-shell-plan.md` (design
`specs/2026-09-24-observe-recon-shell-design.md` §5.1, §5.5). User docs:
`docs/observe.md` ("WATCH", "The interactive view", "Crash dumps").

## What landed

### `WATCH <sections> <interval_ms> <max>` (runtime/march_observe.c)

A streaming verb on the observe socket. `conn_thread` recognises it before the
one-reply path and hands the connection to `watch_stream`, which runs
`SNAPSHOT <sections>` through the ordinary `handle_line` once per interval and
writes each envelope (plus `"seq"`/`"of"`) as a line.

- `max` mandatory, 1..3600 (`bad_max`); `interval_ms` 250..60000 (`bad_interval`);
  malformed -> `bad_args`.
- Holds one of the 8 connection slots for its whole life (it is just a longer
  connection thread). **At most 4 streams at once** (`watch_busy`): not in the
  plan, added so eight watchers cannot lock out every other client.
- Never on a scheduler or green thread, so it cannot block the scheduler; the
  other verbs run on their own connection threads. A slow frame is followed by
  the next at once, never by a catch-up burst (deadline = frame start +
  interval).
- Client disconnect: between frames the thread `poll`s the socket (POLLIN/HUP,
  `recv` == 0 ends it); sends use `MSG_NOSIGNAL` and the 5 s send timeout, so a
  client that stops reading also frees the slot. A bad section is the stream's
  only frame (the error envelope).
- In-process (`observe_query`) it answers `watch_needs_socket`.
- `march_jw_raw` (splice already-valid JSON) is new public API of the writer.
- The interpreter serves no socket, so there is nothing to do there.

### `forge observe` interactive view (forge/lib/observe_tui*.ml, cmd_observe_view.ml)

- `notty`, `notty.unix` added to `forge/lib/dune`, `dune-project`, `forge.opam`
  (C15). `forge` and `march-lsp` link it (lsp links `march_forge`).
- `observe_tui.ml`: pure `render : ?ctx -> panel -> reply -> Notty.image` for
  System, Load, Actors, Actor, Supervision, Names, Epochs, Cluster, Crashes;
  `text_of_image` (Notty `Cap.dumb`) for tests and `--panel`. Adding the Trace
  panel (R8) is one constructor plus one case each in `title`, `live_only`,
  `request_of`, `render`; the loop enumerates `all_panels`.
- `Actors` reuses `forge top`'s row/header (`Cmd_observe.top_row_line`, new
  `top_header`) and the `TOP` verb (supervision columns, `mbox|stack|crashes|
  slices|msgs_in|msgs_out`); counters are cumulative in the TUI (a window would
  hold the node's connection thread for its length on every refresh). With no
  `TOP` reply (a crash dump) the snapshot's `actors` rows are ranked client-side.
- `observe_tui_live.ml`: single-threaded `select` loop over the keyboard and the
  WATCH socket. One ssh tunnel per selected host (own `ssh -N -L`, stdout/stderr
  to /dev/null so it cannot draw over the screen), used for the stream and for
  the panel's own request (`TOP`, `ACTOR`, `CLUSTER`) on short second
  connections. A finished/dropped stream is reopened. `n` cycles `--env` hosts.
  Keys: q/Esc, 1-9/Tab, arrows/j/k/PgUp/PgDn/Home/End, Enter (open actor), s
  (sort), n, r.
- `forge observe` with no request on a terminal opens the TUI; pipes, `--json`,
  a request or `--section` behave as before. New flags: `--tui`, `--panel NAME`,
  `--interval`, `--sort`, `--pid`, `--dump FILE` (alias `--from-dump`).
- The Cluster panel renders a `CLUSTER` reply; **no `CLUSTER` verb exists yet**
  (`specs/todos/2026-10-02-observe-r1-cluster-section.md`), so on today's nodes
  it says so. The panel is exercised over a fixture of the planned shape.
- The Actor panel shows `ACTOR` only. `STATE`/`MESSAGES` (debug tier, signed)
  are not wired into the TUI: it points at `forge observe --state PID`.

### Crash dumps (runtime/march_observe_snapshot.c, march_reclaim.c, march_runtime.c)

`MARCH_CRASH_DUMP=<path>`: one JSON document written to `<path>.tmp` (mode 0600),
fsynced, renamed. Format `march.observe.dump/1`: `reason`, `at_ms`, `pid`,
`snapshot` (the full SNAPSHOT envelope), `crashes_total`, `crashes_full` (the
ring with `message` text; same null conventions as `CRASHES`).

- **Triggers:** `march_panic`'s unsupervised path (before its `exit(1)`), and the
  runtime's 28 own `abort()` sites in `march_runtime.c` (11), `march_scheduler.c`
  (13), `march_reclaim.c` (4), now `march_abort(__func__)`.
  (The plan calls the wrapper `march_fatal`; that name is taken by the FFI's
  `march_fatal` in `march_ffi.c`, which is untouched.)
- **Gate** (`march_fatal_dump`, in `march_reclaim.c`, which every scheduler test
  harness already links): skipped when no writer is installed, when the caller
  is inside a reclamation critical section (`march_reclaim_depth() != 0`), or
  on a signal stack (`sigaltstack` reports `SS_ONSTACK`). Then `abort()`
  regardless.
- **No signal handler writes a dump.** SIGSEGV/SIGBUS/SIGILL/SIGFPE, SIGKILL,
  OOM kills and libc/sanitizer aborts produce none. Documented.
- **Why a helper thread:** the writer allocates (JSON) and takes the actor-table
  lock, which the dying thread may hold. So the dying thread never writes: a
  helper created at startup (`snapshot_install`, main OS thread, never from a
  green thread) is woken through a pipe; the dying thread waits at most
  `MARCH_CRASH_DUMP_TIMEOUT_MS` (default 3000) in 1 ms sleeps, then dies
  anyway. A helper stuck behind a held lock costs the dump, not the exit; the
  `.tmp` is renamed only after a complete write. Only the first fatal thread
  requests; later ones wait too. A fatal error inside the writer returns at once
  (it cannot wait for itself). The dump document is built with ordinary
  `malloc` (no pre-allocated buffer): if the heap itself is the failure, the dump
  may be missing; this is a stated limit.
- Readers: `forge observe --dump FILE` (panels as text / TUI on a tty / `--json`)
  and **`forge diagnose --from-dump FILE`**. The plan says `forge diagnose
  --dump FILE`, but `--dump` on `diagnose` already means *write* the
  before/after fixture pair (documented, used by tests), so the reader is
  `--from-dump`; `observe --dump` has both spellings. Live-only panels (Actor,
  Cluster) are greyed. Diagnose over one snapshot finds crash loops, over-limit
  mailboxes, saturated schedulers and stuck epochs; the two-snapshot checks
  (growth, climb) cannot.

## Tests

- `forge/test/test_observe_tui.ml` (22 cases): golden text per panel
  (`forge/test/fixtures/observe_tui/*.expected`) from fixtures recorded off a
  real node (`snapshot.json`, `top.json`, `actor.json`) and a real dump
  (`crash_dump.json`), plus empty-node, narrow-width, hostile-text (escape and
  control bytes in names and panic text never reach the terminal), dump merge and
  malformed-dump cases. Regenerate with `UPDATE_OBSERVE_TUI=1`.
- `test/test_observe.c`: WATCH bounds, numbering, pacing, disconnect frees the
  slot and stops the work, 4-stream cap with PING still answering, bad section,
  in-process refusal, HELP.
- `test/test_fatal_hook.c`: the gate (hook runs on a clean abort; not in a
  critical section; not on a signal stack; always aborts).
- `test/native/crash_dump.march` + rule `native_crash_dump`: a supervised child
  panics three times, main panics; the dump exists, no `.tmp` left,
  `forge diagnose --from-dump` -> `crash.loop` critical, exit 2, the panic text
  in `forge observe --dump --panel crashes`; no dump without the variable; an
  unwritable path still exits 1.
- `test/shell/observe_tui_pty.py`: drives the TUI under a pty against a live
  node, feeding output through a small VT100 emulator; 15 checks (not in
  `dune runtest`: it needs a live node).
- `test/observe_snapshot_check.ml`: HELP now lists WATCH.

RED proofs (reverted by file copy): WATCH without hang-up handling leaks the
slots (cascading `watch_busy`, the run then times out); `max` bound removed ->
the bound cases hang; panel header edited -> `names` and `every panel` fail;
`march_panic` without the dump call -> the native diff loses 8 lines; the gate
without the two checks -> both gate cases fail.

## Not done / limits

- No dump from fatal signals, by design.
- The dump's snapshot is capped like SNAPSHOT (100 actors by mailbox).
- Trace panel (R8), `STATE`/`MESSAGES` inside the TUI, the `CLUSTER` verb.
- The abort-site -> helper-thread path is covered by the native test only through
  `march_panic` (the abort sites need a corrupted runtime to reach); the gate and
  the writer are tested separately.
