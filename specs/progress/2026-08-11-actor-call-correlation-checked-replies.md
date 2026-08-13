# Actor.call: correlation-checked replies (late replies discarded, not misdelivered)

Part of the actor-system-hardening series (`.superpowers/sdd/2026-08-11-actor-system-hardening/`,
Task 4). Builds on Task 3's `march_sched_recv_until`-based timed wait for
`march_actor_call`.

## The bug

`march_actor_call`'s reply channel was just the caller's raw green-thread
proc pointer. A call that timed out gave up waiting, but the handler could
still deliver a reply later — that reply landed in the (still-alive) caller's
mailbox with no way to tell it apart from the reply to whatever call the
caller issues *next*. A long-lived green thread mixing multiple `Actor.call`s
to the same actor could receive a stale reply from call N as the answer to
call N+1.

## The fix

`runtime/march_runtime.c`:

- `MARCH_CALL_REPLY_TAG` (`0x00CA11ED`) — a new heap-struct tag, chosen to
  sit below the F19 global ctor-tag floor (`0x01000000`) so it can never
  collide with a real constructor tag, and distinct from the other reserved
  sentinel tags (`MARCH_STRING_TAG`/-1, `MARCH_RESOURCE_TAG`/-2,
  `MARCH_FLOAT_TAG`/-3, `MARCH_MIGRATE_TAG`/0x4D494752 — different tag field
  entirely).
- `march_actor_call` mints a monotonic `_Atomic int64_t` correlation id per
  call and builds a heap-allocated **reply-ref** (`{proc, corr}`, rc=1)
  instead of passing the raw caller proc pointer as the call message's field
  0. The reply-ref is opaque (int-shaped pointer) to March code in both
  backends already, so widening what it points to is ABI-invisible.
- `march_actor_reply(ref_ptr, result)` keeps its signature. If `ref_ptr` is
  tagged `MARCH_CALL_REPLY_TAG` it unpacks `{proc, corr}`, wraps `result` in
  a fresh envelope `{corr, result}` (same tag), `march_decrc`s the reply-ref
  (its one reference is retired here), and sends the envelope. If `ref_ptr`
  is *not* one of our envelope-tagged refs (a raw proc pointer from an older
  caller, or interpreter-parity code), it falls back to sending `result`
  directly — the legacy, uncorrelated path, kept exactly as before.
- A shared `march_actor_call_unwrap(msg, corr, &payload)` helper is called
  from both of `march_actor_call`'s receive loops (wait-forever via
  `march_sched_recv`, and the deadline-bounded `march_sched_recv_until` loop
  added in Task 3). It returns 1 (matched — return `payload`), 0 (stale —
  already discarded, keep waiting), or -1 (not an envelope — pass the raw
  message through unchanged, preserving compatibility with any non-`Actor.call`
  sender of this proc's mailbox).
- The two loops are **not** merged into one `march_sched_recv_until(INT64_MAX)`
  path: `march_sched_recv_until` registers a timer-heap entry for its
  deadline, and an `INT64_MAX` deadline would never fire and never be
  removed — a leaked heap slot per wait-forever call, unbounded for a
  call-heavy long-lived server. Two branches sharing one unwrap helper is the
  right split; documented inline at the call site.
- The wait-forever branch also loops on a stale correlation (not just the
  deadline branch) — a wait-forever call on a green thread that previously
  made a timed-out call could otherwise receive that earlier call's leftover
  envelope.

## RC audit

- **Reply-ref**: `march_alloc`'d with rc=1 by `march_actor_call`, handed to
  the actor inside `call_msg`. `march_actor_reply`'s envelope path is the
  only place that reference is ever retired (`march_decrc(ref_ptr)`). A
  handler that never calls `Actor.reply` leaks the reply-ref along with the
  unhandled call message — no new hazard versus today's leaked raw result.
- **Envelope**: `march_alloc`'d with rc=1 by `march_actor_reply`, owns one
  reference to `payload` (field 1) via a direct pointer store (no incrc —
  the handler's Perceus instrumentation already owned that reference and
  transfers it in). On a correlation match the caller's `march_decrc(msg)`
  (envelope) + `mk_ok(payload)` moves ownership of `payload` out to the
  `Result` return value. On a mismatch, both `msg` (envelope) and `payload`
  are `march_decrc`'d — the stale reply is fully dropped, nothing leaks.
- **Legacy path**: unchanged — `march_actor_reply` sends `result` directly,
  transferring the caller's existing reference, exactly as before this
  change.

## Tests

`test/native/actor_call_late_reply.march` + `.expected`, wired into
`test/dune` (compile+run+diff rule cloned from the `native_ring_buf_ops`
pattern, `(source_tree ../stdlib)` included for `List`/`Range`). A first
`Actor.call` with a 1ms timeout races a handler that burns ~50k loop
iterations before replying — the call times out and the late reply lands
after the fact. A second call (10s timeout) must observe `n=1` (the second
reply), not the stale `n=0` from the first. See the task report for the
exact interpreter-parity result and the ASAN sweep result.
