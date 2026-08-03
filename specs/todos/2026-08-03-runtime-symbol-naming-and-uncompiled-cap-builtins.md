# Runtime symbol naming inconsistency + cap-table builtins with no compiled lowering

Found 2026-08-03 while building the cap→symbol table for `forge cap audit`
(`lib/caps/cap_symbols.ml`; full accounting enforced by `test/test_cap_symbols.ml`).

- [ ] **`dns_resolve`'s C function is unprefixed** (`runtime/march_runtime.c:3679` —
  `dns_resolve`, not `march_dns_resolve`; it reaches codegen via `mangle_extern`'s
  identity fallthrough). Two consequences: (a) naming inconsistency with every other
  runtime entry; (b) a **false-marker edge**: a user function named `dns_resolve` in
  the entry module (top-level module prefix is stripped in TIR) resolves through the
  same fallthrough and would record a spurious `IO.Network` capability marker.
  Over-approximation, so safe polarity for the audit — but the clean fix is renaming
  the C function to `march_dns_resolve` with an explicit mangle-table row, then
  updating `Cap_symbols.table` and the special-lowerings map in the drift test.

- [ ] **Three cap-table builtins have no compiled lowering at all**: `task_spawn_link`,
  `unix_time_ms`, `uuid_v7` (see `Cap_symbols.uncompiled_builtins`; `get_work_pool`
  is there too but is legitimately a global access, not a call). They typecheck and
  run interpreted — what happens compiled? Either they fail at link/emit (a
  compiled-vs-interpreted gap worth a proper diagnostic: "not available compiled"),
  or they silently lower through some path the cap-symbols accounting doesn't know
  about (worse — audit blind spot). Determine which, then either implement the
  lowering or make the typechecker reject them under `--compile` with a clear
  message. Update `uncompiled_builtins` when resolved — the drift test fails if an
  entry becomes stale in either direction.
