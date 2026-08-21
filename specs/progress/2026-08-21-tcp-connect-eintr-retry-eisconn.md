# `tcp_connect` reported EISCONN for connections that had actually succeeded

Landed 2026-08-21. Found in a March application (Envoy) that drives several
concurrent outbound HTTPS requests from one process: four sessions started at
the same moment, three failed immediately with

```
DeepInfra TCP connection failed: tcp_connect: Socket is already connected
```

while the same code with a single session in flight worked every time.

## Root cause — retrying `connect()` after `EINTR`

`march_tcp_connect` (`runtime/march_http.c`) recovered from an interrupted
`connect()` the same way it recovers from an interrupted `recv()`/`send()`:

```c
int crc;
do { crc = connect(fd, res->ai_addr, res->ai_addrlen); }
while (crc < 0 && errno == EINTR);   /* preemption signal — retry */
```

That is correct for `recv()`/`send()` and wrong for `connect()`. POSIX says an
interrupted `connect()` completes **asynchronously in the kernel**: the
handshake keeps running, and a second `connect()` on the same fd reports the
state of that in-flight attempt — `EALREADY` while it is still going,
`EISCONN` once it has landed — instead of starting a new one.

So the loop took a connection that had **succeeded** and turned it into a hard
error. The `EISCONN` branch then `close()`d the fd and returned
`Err("tcp_connect: Socket is already connected")`.

## Why it looked like a concurrency bug

`march_tcp_connect` holds no shared state — fresh `socket()`, local `fd`, no
statics — so the usual suspects (per-process socket state, a shared TLS
context, non-zeroed `march_alloc` headers) were all ruled out by inspection.
What concurrency actually changes is **signal pressure**:

* The preemption daemon sends `SIGUSR1` to every active scheduler thread every
  `MARCH_QUANTUM_US` (1ms).
* A process running one green thread is mostly idle and almost never takes a
  signal inside the microseconds `connect()` is on the stack.
* A process running several concurrent outbound requests takes them constantly.

`march_block_preempt()` is supposed to mask `SIGUSR1` across
`getaddrinfo()`/`connect()`, and it does run — but instrumentation showed the
mask does not reliably hold (see "Loose end" below), and `EINTR` was observed
even on iterations where `SIGUSR1` *was* masked. The retry has to be correct
regardless of which signal fires, so that is what was fixed.

## Evidence

Instrumenting the loop and issuing two concurrent requests reproduced it
directly:

```
[MCHDBG] enter fd=199 thr=0x1f8db9d80 usr1_blocked=0
[MCHDBG] try=1 fd=199 rc=-1 errno=4  (Interrupted system call)
[MCHDBG] try=2 fd=199 rc=-1 errno=56 (Socket is already connected)
```

## The fix

Issue `connect()` once. On `EINTR` (and on `EINPROGRESS`, should the fd ever
arrive non-blocking) wait for the socket to become writable and read the true
outcome out of `SO_ERROR`, which is the standard recovery. A bare `EISCONN`
is also now treated as success rather than failure.

Verified against the reporting application: 24 sessions started concurrently,
0 failures, all completing with real provider responses. Before the fix, 4
concurrent sessions failed reliably.

## No automated regression test — deliberately

A deterministic C test was written and then dropped. Reproducing the bug needs
a signal to land inside `connect()`; a loopback `connect()` completes in
microseconds, so the signal storm has to be dense (~50µs). At that density the
storm also lands inside `getaddrinfo()`, which `march_http.c` already documents
as not async-signal-safe on macOS — the test wedged the resolver and hung
before its first iteration. Making `connect()` slow enough to widen the window
(dialling a non-routable address) removes the completion that the assertion
depends on.

A test that can hang CI is worse than no test, so the behaviour is recorded
here instead. If this is worth automating later, a Linux-only test using a
`SOCK_STREAM` peer with a deliberately stalled `accept()` plus `AI_NUMERICHOST`
(to keep `getaddrinfo()` out of the signal path) is the most promising shape.

## Loose end — `march_block_preempt()` does not reliably hold

The probe above recorded `usr1_blocked=0` on threads that had just called
`march_block_preempt()`. The mask is per-OS-thread (`pthread_sigmask`) while
green threads multiplex over those threads, so a mask set by one green thread
is not scoped to it — and `swapcontext` carries a signal mask of its own. This
did not need to be resolved to fix the `EINTR` handling, and the other
`EINTR`-retrying call sites in `march_http.c` (`recv`/`send`/`writev`) are
correct as written, but the masking itself is not currently trustworthy and is
worth a separate look.
