# Post-quantum TLS key exchange by default (phase 2)

**Plan:** [../plans/post-quantum-crypto-plan.md](../plans/post-quantum-crypto-plan.md), phase 2.
Phase 3 (cluster handshake) remains open:
[../todos/2026-10-21-post-quantum-crypto-cluster.md](../todos/2026-10-21-post-quantum-crypto-cluster.md).

- **Default groups.** `runtime/march_tls.c` sets
  `X25519MLKEM768:X25519:P-256:P-384:P-521` on every client and server
  context (`ctx_set_default_groups`). Before, it set none and inherited
  OpenSSL's defaults, which include the hybrid only from 3.5 and only by that
  release's choice. An OpenSSL without ML-KEM rejects the list as a whole;
  the error queue is cleared and the context keeps the library defaults, which
  is exactly the old behaviour. Detected at run time rather than by
  `OPENSSL_VERSION_NUMBER`, so a binary built against new headers and run
  against an old library (or LibreSSL) still falls back correctly.
- **Builtins** (cap `IO.NetConnect.TLS` except the probe):
  `tls_ctx_set_groups(ctx, "a:b")` -> `Result(Int, String)`,
  `tls_negotiated_group(ssl)` -> `Option(String)` (`SSL_get_negotiated_group`
  + `SSL_group_to_name`, both OpenSSL 3.0), `tls_pq_available()` -> `Bool`
  (probes `X25519MLKEM768` once on a throwaway context, cached). Registered in
  typecheck (type + cap table), cap_symbols, cap_infer, eval (stubs: the
  interpreter has no TLS; `tls_pq_available` is false), llvm_builtins,
  defun, borrow (`tls_ctx_set_groups`: the String is borrowed), and the
  codegen preamble golden.
- **Stdlib** (`stdlib/tls.march`): `Tls.post_quantum_available()`,
  `Tls.set_groups(ctx, List(String))`, `Tls.negotiated_group(conn)`,
  `Tls.is_post_quantum(conn)`.
- **Test** `test/test_tls_groups.ml` (in `run_stdlib`, `Slow`): one compiled
  probe plays server and client (both linking the same OpenSSL; an
  `openssl s_server` peer would be whatever CLI is on PATH, LibreSSL on macOS
  runners). With ML-KEM available it asserts both sides agree on
  `X25519MLKEM768`; without, that the default handshake still succeeds
  classically. Always: `set_groups(["X25519"])` gives `x25519` (non-vacuity
  control) and an unknown group is `Err`. Proven red by changing the default
  list to `X25519:P-256` (the PQ assertion fails), green when restored.
  Locally (Homebrew OpenSSL 3.6) the PQ branch runs; Ubuntu 24.04's OpenSSL
  3.0 exercises the fallback branch.
