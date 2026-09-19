# A session heartbeat starts with the connection

Shipped 2026-09-19. Finding 3 of the choreography deadlock review (the others are
[[2026-09-18-session-frames-never-dropped]] and [[2026-09-18-session-accept-deadline]]),
with the review's two documentation gaps.

## The bug

`SessionNode` started each connection's heartbeat in `serve_outcome`, and the runner
calls that only after driving the role to its first suspension. A role that worked
longer than `MARCH_SESSION_TIMEOUT_MS` before its first send or receive sent no pings
meanwhile, so a peer that was already serving took it for dead: with a 2 s timeout, a
role that spent 4 s before its first send had its peer cancel with "no heartbeat", and
then found that peer gone itself. With the default 10 s timeout, any role that computed
for more than 10 s before its first message ended the session.

## The fix

- The heartbeat is spawned in `start_link`, when the connection is made, so pings go
  out through setup and the drive to the first suspension.
- A side counts silence only once it reads the connection: `serve_outcome` marks each
  link `reading` before starting its reader, and `heartbeat` counts a tick only then.
  Before that the peer's frames, pings included, are not read, so nothing could reset
  the count, and the slow role would take its peers for dead instead.
- The loop still ends when its reader does (`link_done`); `abort_links` (failed setup)
  and `finish` set `link_done` too, for a connection that never reached `serve`.
- `heartbeat_config` reads the two settings in one place.

## Tests

`test/two_node/slow_start`: A spins the CPU for 4 s (one scheduler thread, so the
heartbeat runs by preemption) before its first send, with a 2 s timeout. Both roles
close normally. On main's `session_node`, B cancels with "no heartbeat" and A with
"connection lost"; with the `reading` gate removed, A's own heartbeat takes B for dead
("every peer is gone").

## Documentation

`docs/choreography.md` (and `specs/lang/choreography.md`):
- the heartbeat runs from the moment nodes connect;
- every callback, and every cancel handler, has to return: while one runs, the node
  handles nothing else for the session, and the no-deadlock promise assumes it returns;
- `host_<Role>` is called from `main` or a task, never from one of the host actor's own
  handlers, whose mailbox the session's deliveries go to.
