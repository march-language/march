`[P2]` **A discarded `send` result leaks 24 bytes per send (compiled).**

Filed 2026-09-29 from the observe quick wins
([`progress/2026-09-29-observe-quick-wins-results.md`](../progress/2026-09-29-observe-quick-wins-results.md), QW4).

`march_send` returns a heap-allocated `Some(())` on success
(`void *some = march_alloc(16 + 8)` in `runtime/march_runtime.c`, `march_send`).
In a loop that uses `send(p, Poke(1))` as a statement, the result is never freed.

Evidence: Linux LeakSanitizer (Docker, `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`)
on a loop of 50 000 spawn + send + kill reports
`Direct leak of 1200000 byte(s) in 50000 object(s)` allocated from `march_send`.
The same count appears on the runtime **before** the quick-win patches, so it is
pre-existing. `bench/actors/fanin_flood.march` sends 400 000 messages as statements,
which would be ~9.6 MB.

To decide first: is the leak the discarded statement value (Perceus not dropping an
unused call result), or `send`'s ownership contract at the call boundary? A variant
with `let _ = send(...)` separates the two. Either way, add a native RC-probe test
that sends N messages as statements and asserts live allocations return to baseline.
