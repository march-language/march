`[P2]` # The capability ceiling charges a lambda lifted out of a stdlib function to the entry module (2026-11-11)

Found by Task 6 of ocap phase 2b (`test/test_cap_mode_parity.ml`, `host_scope` /
`host_scope_ok`, modes `march_check` and `repl`).

`March_tir.Cap_attrib.owner_of` takes a function's owner from its TIR name (everything
before the last `.`). A lambda is named structurally (`$lam0_Socket_write`,
`lib/tir/lower_state.ml`) with no `.` on purpose, so its owner falls back to the entry
module, and it is never seen through as stdlib. A capability a stdlib lambda reaches is
therefore charged to the entry module:

- under `--check` / `--compile` the entry is the user's module, which usually declares the
  capability, so the wrong owner goes unnoticed (and a nested module is never blamed);
- under `march check` the entry is the synthetic `LibCheck`, and in the REPL `Repl`, which
  declare nothing, so a program the other modes accept is rejected with
  ``Module `LibCheck` uses `IO.NetConnect` ``.

Reproductions (both rejected by `march check`, accepted by `march --check`):
- a `main` that calls `Socket.write` (its `with_raw` closure);
- `HttpTransport.simple_get` from a module with `needs IO.NetConnect("127.0.0.1:9")`: still
  rejected for `IO.NetConnect.TLS`, through the `fn h -> ...` closures `Tls` passes to
  `with_conn` / `with_ctx` (Task 5). `cap_mode_parity` stays red on this until fixed.

Task 6 kept `HttpTransport` closure-free (the bracket is written out per raw call, as Task 5
did in `Udp`), so it adds no new case. Fix: resolve a `$`-named function's owner from its
lowering host (`Provenance` records `host`), or name the host module in the structural name
in a way `Hot_reload.module_of_name` still ignores; then drop the per-call workaround.
