# `dns_resolve` answers the same list interpreted and compiled

Filed 2026-09-25 (as `specs/todos/2026-09-25-dns-resolve-interp-compiled-divergence.md`,
found while closing `specs/progress/2026-09-25-runtime-symbol-naming-and-uncompiled-caps.md`).
Fixed 2026-09-25.

## The divergence

| host          | interpreted (before)          | compiled (before)                 |
|---------------|-------------------------------|-----------------------------------|
| `localhost`   | `Ok([127.0.0.1, 127.0.0.1])`  | `Ok([127.0.0.1, ::1])` (macOS)    |
| `127.0.0.1`   | `Ok([127.0.0.1, 127.0.0.1])`  | `Ok([127.0.0.1])`                 |
| `::1`         | `Err(cannot resolve ::1)`     | `Ok([::1])`                       |
| `""`          | `Err(cannot resolve )`        | `Err(nodename nor servname ...)`  |

- Interpreter (`lib/eval/eval_builtins.ml`): `Unix.getaddrinfo host "" [AI_FAMILY PF_INET]`
  with no socktype hint, so getaddrinfo answers once per socket type (two on macOS,
  three on glibc), and nothing deduplicated.
- Runtime (`march_dns_resolve`, `runtime/march_runtime.c`): `AF_UNSPEC` + `SOCK_STREAM`,
  deduplicated, and a failure returned `gai_strerror`'s text, which `Dns.resolve` read as
  `ResolveError` where the interpreter's "cannot resolve" reads as `NotFound`.

The todo said a numeric host would not show the difference. It does: the socket-type
fan-out duplicates a numeric IPv4 literal too, and an IPv6 literal separated the two
family choices. Both are deterministic, with no resolver or `/etc/hosts` involved.

## The contract chosen

The todo leaned towards the C behaviour (both families). The documented contract says
otherwise: `stdlib/dns.march` promises "IPv4 addresses", `Dns.resolve_one` "its primary
IPv4 address", and `Dns.is_ip` only recognises dotted quads. It also matches the rest of
the stack: every `tcp_connect` / HTTP client path in both backends opens an `AF_INET`
socket, so an IPv6 answer (and `resolve_one` could return one when a resolver lists it
first) is an address nothing in March can dial. So:

- IPv4 only;
- one entry per address, in resolver order (SOCK_STREAM hint + dedup);
- `"cannot resolve <host>"` when the host has no IPv4 address (C maps `EAI_NONAME`,
  `EAI_FAMILY`, `EAI_NODATA`, `EAI_ADDRFAMILY`, and an empty IPv4 result to it). Other
  resolver failures (`EAI_AGAIN`, `EAI_FAIL`, ...) keep `gai_strerror`'s text in compiled
  code; OCaml's `Unix.getaddrinfo` returns `[]` for every failure, so the interpreter cannot
  tell them apart and still says "cannot resolve". That difference only shows on a
  transient resolver failure.

Both backends changed (a one-line family change plus the error mapping in C; the socktype
hint plus dedup in the interpreter). The contract is written on `stdlib/dns.march`'s
module header and `Dns.resolve` doc.

## Test

`test/native/dns_resolve_parity.march` runs interpreted and compiled against one golden
(`test/dune`, `native_dns_resolve_parity{,_interp}.out`). Exact lists are pinned only for
numeric hosts (`127.0.0.1`, `10.1.2.3`, `Dns.resolve_one("127.0.0.1")`); `::1` is checked
as "no IPv4 answer"; `localhost` prints only properties that hold on every CI host (no
duplicates, all IPv4, contains `127.0.0.1`).

- RED with origin/main's two implementations (fixture unchanged):
  compiled diff `::1 has no IPv4 answer: false`, `localhost all IPv4: false`;
  interpreted diff `Ok([127.0.0.1, 127.0.0.1])`, `Ok([10.1.2.3, 10.1.2.3])`,
  `localhost no duplicates: false`.
- GREEN with the fix on both backends; `native_uuid_v7_dns_parity` still GREEN (its
  200-call no-leak check covers the rewritten C function's borrowed host).
