# `Vault.new(name)` twice: same table on both backends

Landed 2026-09-10. Closes the "Backend divergence found 2026-09-02" section of
`specs/todos/2026-08-12-vault-toward-ets-semantics.md` (which stays open for
write partitioning only).

`Vault.new` on a name that is already registered returned a **fresh** table in
the interpreter and the **same** table compiled (`march_vault_new` looks the
name up first). The interpreter's fresh table silently orphaned the first
one's data, which is how it surfaced: `test/session/stream_replay.march`'s
first `drain` re-created its tables by name and drained an empty queue.

The interpreter's `vault_new` now returns the registered table's handle when
the name resolves to a live table, matching ETS and the compiled runtime; a
name whose table was cleaned up (owning actor died) mints a fresh one, as
before. The per-actor cleanup thunk is only registered by the call that
actually created the table.

`test/native/vault_new_same_name.march` pins it on both backends.
