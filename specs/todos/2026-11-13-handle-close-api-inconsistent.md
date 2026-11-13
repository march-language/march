`[P3]` Handle close functions disagree on their result and on a second close (2026-11-13)

Found by the ocap phase 2b final review (M3,
`.superpowers/sdd/2026-11-10-ocap-p2-handles-plan/final-review.md`). `File.close`,
`File.close_dir`, `Socket.close` and `Socket.close_listener` return `Result((), E)`
with `Err(Closed)` on a second close (stdlib/file.march, stdlib/socket.march).
`Tls.close`, `Tls.ctx_free` and `Udp.close` return `()`, and a second close does nothing
(stdlib/tls.march, stdlib/udp.march). `Process` has no close at all: `wait_proc`
closes, and dropping the handle kills the child. Each is documented, but a user cannot
learn one rule.

Expected: one shape, probably `Result((), E)` with `Err(Closed)` on a second close,
and a `Process.close` that releases without waiting (what dropping does now); or the
split recorded as intended in the handles section of specs/lang/capabilities.md.
