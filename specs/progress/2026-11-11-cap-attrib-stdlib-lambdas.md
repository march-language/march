# The capability ceiling charges a stdlib lambda to the function it was written in (2026-11-11)

Found by ocap phase 2b, Task 6 (`test/test_cap_mode_parity.ml`, `host_scope*` in modes
`march_check` and `repl`); fixed in its review round (ruling R11).

**Bug.** `March_tir.Cap_attrib.owner_of` takes a function's owner from its TIR name
(everything before the last `.`). By the pre-opt TIR it reads, Defun has lifted every lambda to
a top-level apply function named structurally (`$lam0_Socket_write$apply$3`,
`lib/tir/lower_state.ml`), with no `.` on purpose, so the owner fell back to the entry module and
the function was never seen through as stdlib. A capability a stdlib lambda reaches was charged
to the entry module:

- under `--check` / `--compile` the entry is the user's module, which usually declares the
  capability, so the wrong owner went unnoticed, and a nested module calling the stdlib function
  without the `needs` was never blamed;
- under `march check` the entry is the synthetic `LibCheck`, and in the REPL `Repl`, which
  declare nothing, so correct programs were rejected (``Module `LibCheck` uses
  `IO.NetConnect` ``): a `main` calling `Socket.write`, or `HttpTransport.simple_get`, which
  reached `IO.NetConnect.TLS` through `Tls`'s `with_conn` / `with_ctx` closures.

**Fix.** `Cap_attrib.attribute` charges a function with a recorded lowering host
(`Provenance`'s `host`, which Defun records for every lifted lambda and clones inherit) AS that
host, when the host is still defined in the module: its capabilities and its calls count as
the host's own. The ordinary rules then apply: `Socket.write` is stdlib, so the capability goes
through it to its callers. A function with no record (TIR that did not come through this
process's Defun) or whose host is gone is charged as itself, as before.
`Hot_reload.module_of_name` and the structural names are unchanged.

**Effect.** A module that calls a stdlib function whose capability sits in a lambda now needs
the capability itself: before, `mod Writer do fn send(s) do Socket.write(s, "x") end end`
under an entry module that declared `IO.NetConnect` was accepted; now it is
``Module `Writer` uses `IO.NetConnect` ``, the same verdict as for a direct `tcp_send_all`.

**Tests.** `test/test_cap_mode_parity.ml` fixtures `stdlib_lambda` (the `Writer` reject),
`stdlib_lambda_ok` and `socket_write_main` (`Socket.write` from `main`), in every mode;
`host_scope_ok` covers `HttpTransport.simple_get` under `march check`.
