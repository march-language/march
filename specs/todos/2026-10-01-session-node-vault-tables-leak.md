# `[P2]` Every session leaks its SessionNode Vault tables; a leader state rewritten in a Vault leaks everything it points to

Filed 2026-10-01 (dd step 12a, found while the control-plane nodes grew past 2 GB in a
minute). Two leaks, both in how Vaults hold values; neither is fixed, both are worked
around in `lib/desugar/control_wiring.march`.

## 1. A session's tables are never freed

`SessionNode.run_*` creates thirteen named Vaults per session
(`stdlib/session_node.march`, `session_node_handlers_<tag>` … `session_node_drain_<tag>`,
plus `session_node_slot_<sid>.<ep>` and `session_ap_answers_<sid>` / `session_ap_budget_<sid>`),
and nothing ever removes them from the runtime's Vault registry (`runtime/march_extras.c`,
`vault_registry`: `march_vault_new` registers, nothing unregisters). A process that
forms a session every 200 ms grew by 1.5 MB/s with a report payload of 900 bytes.

Measured (a `Ctl` session in-process, the real roles, 1000 then 3000 polls, one session
each): 8.6 MB → 16.6 MB with an empty report `detail`; 30 MB → 81 MB with a 9000-byte one.
So the per-session cost is the tables plus every message's encoding (point 2 of
[2026-10-01-session-message-encoding-leak.md](2026-10-01-session-message-encoding-leak.md)).

**Workaround in the control plane:** an agent's `Ctl` session is long-lived (the leader
ends it only when it stops leading, or after `MARCH_CONTROL_SESSION_POLLS`, default 1200
polls); a session a deploy drains (`Session.Drained`) is restarted through an actor that
has passed the deploy's marker (`CtlRespawner`), not from the draining task, which would
have formed a new draining session every 200 ms for ever; a failed attempt backs off up
to 5 s.

**Fix:** a session's tables should be dropped (or never registered by name) when the
session ends; `Vault.new` for a per-session table wants a `Vault.destroy`, or an
unregistered table handle.

## 2. A Vault entry overwritten with a record is not released

`Vault.set(t, k, v)` with a record `v` whose fields are heap values leaks `v` on every
overwrite. Measured compiled: 100,000 overwrites of a record holding a list of 50 strings
took 576 MB RSS; building the same record 100,000 times without storing it took 3.9 MB;
reading the entry and rewriting it with one Int field changed, 10 MB.

Likely cause: `vault_set` / `vault_set_ttl` / `vault_put_new` are in `Borrow.extern_owned_builtins`
(the caller hands over its reference) AND `march_vault_set` does `march_incrc(value)` for
the table, so every store gains one reference it never gives back; the overwrite's
`march_decrc(n->value)` releases one. Moving the three to `extern_borrow_table` did not
change the number on its own (the stdlib wrapper `Vault.set` passes its parameter through;
whether the borrow applies through it was not checked), so this is a finding, not a fix.

**Workaround in the control plane:** the leader's state is kept encoded as a String
(`ctl_encode_leader` / `ctl_decode_leader`), which has no children to leak, and the
release itself in its own entry written only when it changes.

**Acceptance:** the second measurement above stays flat (a few MB) for `Vault.set` of a
record in a loop, compiled and interpreted; a two-node scenario whose nodes form a session
every 200 ms for a minute stays under 100 MB.
