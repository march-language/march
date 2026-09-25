# `dns_resolve` answers differently interpreted and compiled

Filed 2026-09-25, found while closing
`specs/progress/2026-09-25-runtime-symbol-naming-and-uncompiled-caps.md`.

```march
println(to_string(dns_resolve("localhost")))
```

- interpreted: `Ok([127.0.0.1, 127.0.0.1])`
- compiled: `Ok([127.0.0.1, ::1])`

The interpreter (`lib/eval/eval_builtins.ml`, `dns_resolve`) calls
`Unix.getaddrinfo host "" [AI_FAMILY PF_INET]`. That is IPv4 only, with no
socktype hint, so one address comes back once per socket type, and nothing is
deduplicated. The runtime (`march_dns_resolve` in `runtime/march_runtime.c`)
uses `AF_UNSPEC` with `SOCK_STREAM` and deduplicates.

Pick one contract and make both backends follow it. The C behaviour (both
families, deduplicated) is probably the right one, since `Dns.resolve_one`
takes the head and a duplicated list is never useful. Then add a
`localhost`-free parity case, because a numeric host does not exercise either
difference.
