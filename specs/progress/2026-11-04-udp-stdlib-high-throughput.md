# Udp: high-throughput UDP in the stdlib

**Landed:** 2026-11-04. User-facing digest: `CHANGELOG.md` `[Unreleased]`.

## What

`stdlib/udp.march` (`mod Udp`) over ten `udp_*` builtins:

| builtin | C (runtime/march_udp.c) | interpreter (lib/eval/eval_udp.ml) |
|---|---|---|
| `udp_open(host, port, opts, rcvbuf, sndbuf)` | nonblocking socket, options, bind | same, via `Unix` |
| `udp_resolve(host, port)` | `march_sched_getaddrinfo` (parks) | `Unix.getaddrinfo` |
| `udp_addr_to_string(addr)` | `inet_ntop` | `Unix.string_of_inet_addr` |
| `udp_connect`, `udp_close`, `udp_local_addr` | | |
| `udp_stats(fd)` | `(SO_RXQ_OVFL drops or -1, tx stalls)` | `(-1, 0)` |
| `udp_send_batch(fd, addr, payloads)` | `sendmmsg` + `UDP_SEGMENT` runs | `sendto` loop |
| `udp_send_many(fd, [(addr, payload)])` | same, run per destination | `sendto` loop |
| `udp_recv_batch(fd, max_msgs, max_size, timeout_ms)` | `recvmmsg` (+ GRO split) | `recvfrom` drain |

All carry `IO.NetConnect`. Not stdlib-only gated (the tcp builtins are not
either); the module is the documented API.

## Design decisions

- **Packets are `String`**, not `Bytes`: `march_string` is length-prefixed and
  binary-safe, it is what tcp uses, and it needs no wrapper allocation.
- **Addresses are an opaque binary String** `[4|6][port BE][4|16 bytes]`,
  produced byte-identically by both backends (IPv4-mapped IPv6 is folded to
  IPv4), so `UdpAddr` equality is the same compiled and interpreted. The hot
  path never parses text. Consecutive datagrams from one source share one
  address String (an incref, not an allocation).
- **Batch-shaped API** so that a later io_uring or AF_XDP backend fits under the
  same calls (see the two todos filed alongside).
- **Backpressure, not drops, on send:** EAGAIN parks on writability
  (`march_sched_wait_fd`), ENOBUFS (full interface queue, common on macOS)
  yields, then sleeps 1 ms if it persists. Each wait counts a `tx_stall`.
- **GSO self-heals:** EIO/ENOPROTOOPT/EOPNOTSUPP clear the socket's GSO flag;
  EINVAL (segment over path MTU) lowers that socket's GSO size ceiling (start
  1452). Either way the refused run is split and resent without GSO.
- **Receive arena** is per scheduler thread, fetched by a noinline getter under
  the preempt mask after any park (the TLS-address-across-park hazard, see
  `march_errno_now`). recv + copy-out happen under one mask.
- **Types are `UdpSocket` / `UdpAddr` / `UdpOptions` / `UdpStats`**: March has a
  global type namespace and `Addr` / `Socket` collide with existing stdlib types.

## Contracts (`cap verified`)

`mod Udp` declares `cap verified`: every refinement obligation inside it is
discharged or the build fails. `--refine-report` on the module: 23 proved,
0 violated, 0 trusted, 0 skipped.

- Preconditions, each conjunct with an `else` message: ports `0..65535`
  (`open`, `open_with`, `open_sharded`, `resolve`); `n > 0` shards;
  `recv_batch` `max_msgs` in `1..1024` and `max_size` in `1..65535` (also
  `recv`). These replace runtime clamps a caller could not see; a literal bad
  value is a compile error (`test/errors/refinement_violated_15`), an unknown
  one is not flagged.
- Postconditions: `addr_port` and `local_port` return a valid port (the byte
  decode guards its own range so the bound is provable, not assumed);
  `send_batch`, `send_batch_connected` and `send_many` return exactly
  `len(payloads)` / `len(pairs)` on `Ok`; `open_sharded` returns exactly `n`
  sockets; `opt_bits` stays within the five `UDP_OPT_*` bits.
- No lemma: no contract here needs induction except `open_sharded`'s count,
  and every inductive route to it hit a checker gap (Result payload facts out
  of recursion, reflection over `List(Result(..))`, reflection of
  metric-terminating functions). Filed with repros as
  specs/todos/2026-11-04-refine-result-payload-recursion.md; the module
  states the count with a runtime length test that cannot fail.

## Measured

Linux 7.0 (linuxkit, arm64, 14 cores), loopback, the C runtime driven by a
standalone harness:

| | 64 B | 1200 B |
|---|---|---|
| lockstep, GSO + recvmmsg (exact count) | 2.9M pps | 1.8M pps |
| lockstep, GSO + GRO | | 3.4M pps (~32 Gbit/s) |
| lockstep, GSO off | | 1.0M pps |

macOS loopback is kernel-bound at ~14-16k pps for plain C `sendto` on a loaded
machine (load average ~54 during measurement); March's path measured 20-37k pps
there, so March itself adds no visible overhead.
`bench/udp_flood.march` (gated, IgnoreTiming, lockstep counts anchored).

Known limit: under GRO the kernel's SO_RXQ_OVFL counts coalesced skbs, so
`rx_dropped` under-reports datagram loss when `gro: true`.

## Tests

- `test/native/udp_loopback.march`: compiled and interpreted against one
  golden. Covers round trip and source address, 500 in order, mixed sizes in one
  batch (empty, 1 B, 65000 B, short tail in an equal run), oversize refused,
  truncation, send_many, connected send, ICMP unreachable becoming
  `RecvFailed`, timeouts, IPv6, and shards on one port.
- `--rc-trace`: nothing live at exit except static closures.
- The Linux mmsg/GSO/GRO paths were exercised on a Linux kernel by the harness
  (order and content check across GSO runs, oversize error); CI's ubuntu legs
  run the fixture compiled.
