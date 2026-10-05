# `[P2]` Every session leaks its SessionNode Vault tables; a leader state rewritten in a Vault leaks everything it points to

**DONE 2026-10-04.** Both leaks fixed, and the control plane's workarounds for
them removed.

## 2. A displaced value is released at its type

`march_decrc` frees one cell and never its children; only the compiler knows a
value's layout. So the C side no longer releases what a Vault write displaces
(an overwrite, a drop, an expired claim, a replaced bounded list, a heap value
`incr` replaces): it BURIES it in a per-shard graveyard (`vault_bury`,
runtime/march_extras.c), and a new builtin, `vault_reap(table, key)`, hands the
graveyard of that key's shard back as a `List(v)`. Every writing wrapper in
stdlib/vault.march (`set`, `set_ttl`, `drop`/`delete`, `update`, `put_new`,
`push_capped`, `clear`, `ns_set`/`ns_drop`, now built on the handle API) ends
with a reap, and Perceus drops that list at the table's element type, so a
record's fields and a list's spine go with it. A leaf cell (String, boxed
Float, SIMD box) has no children and is released in C at once: a compiled
`List(Float)` holds raw doubles, so a box could not ride back in one. An empty
graveyard costs one relaxed load. `vault_reap`'s key goes through the same
tagged-key emit arm as the writers (an Int key would otherwise hash to another
shard), and each Vault arm in lib/tir/llvm_emit.ml now releases the Float box
it makes for a borrowed value or key (`emit_vault_arg`).

Main fixed two neighbours while this was open (a1038ee58): the family moved to
the borrow table and into `Defun.builtin_names` (before that every Vault call
was an indirect call, whose convention consumes every argument, which is why
borrowing them "did not change the number" in the filing below), and the
Unit-returning builtins stopped returning a heap cell.

## 1. A session's tables are closed

`Vault.close(t)` (new builtin `vault_close`) unregisters a table, empties it
(every value back as a `List(v)`, dropped typed, as above) and FREES it at once:
the handle is pointed at a closed sentinel and the table freed after the
operations already inside it drain. Every public Vault entry point brackets its
use of the table with an in-flight count on the HANDLE (`vault_enter` /
`vault_leave`, seq_cst on both sides), so a task that outlives its owner finds
an empty table that keeps nothing, never freed memory. The count is STRIPED
like the shard read locks (one counter per `VAULT_RD_STRIPES` stripe, each on
its own cache line, the handle grown to 1088 bytes): a first cut with one
shared counter put an RMW on one cache line into every read, and four threads
reading distinct keys went from ~2x a solo run to ~6x
(`test/test_vault_distinct_keys_scale.c`, red in the macOS conformance job);
striped, it is back at main's ~2x. An unclosed table is
freed with its last handle (the handle is a resource cell now). `Vault.live_tables()`
(builtin `vault_live_tables`) counts tables held; the interpreter implements
all three (its GC owns the values, so its reap is always empty).

`SessionNode.close_party` closes a party's 13 tables; every runner exit passes
it after reading its outcome: the standalone runner's join failure and its end
(`serve_party`, through `finish_links`), the cluster runner's three error arms
and its end (with the route's slot, `close_cluster_party`), and the
initiator's two answer tables once its route is gone. Cancellation, a crash
branch, a peer's death, a drain, the hard drain deadline and a host's death all
end through those exits. Public `finish` closes too. A heartbeat stops on the
party's "open" key, which the close removes (it used to stop only on
`link_done`). `Session.in_process()` gained `close(())` for its 12 tables.

Why the table is freed at the close and not with its last handle: a session's
handles outlive it. Its tables hold closures (the installed continuation, the
cancel/crash/drain handlers) that capture the session capability, whose `Ops`
capture the `Party`; dropping a closure that was never called frees its cell
and not its captures (filed as
[2026-10-04-dropped-closure-leaks-its-captures.md](../todos/2026-10-04-dropped-closure-leaks-its-captures.md)),
so each session's 13 handles (48 bytes each) still leak until that is fixed.
The ~24 KB tables do not.

## Tests

- `test/native/vault_churn_leak_probe.march` (compiled `--opt 2`): live-object
  deltas over 2,000 iterations of every writing operation (record, ADT, tuple,
  Float, Int-keyed, built keys, `set_ttl`, `delete`, `update`, `push_capped`,
  `put_new`, `ns_set`, `clear`) and 2,000 tables made, filled and closed, plus
  read-backs after each churn and a write after `close`. On main (9ee1f648b)
  every displaced-value leg is red (record: 204,000 over; Float 2,000; ADT
  4,000; tuple 8,000; `push_capped` 12,000; `clear` 408,000); with `close`
  replaced by `clear` the table leg prints 1,990 tables left and every name
  still registered.
- `test/two_node/session_churn`: two nodes run 66 cluster sessions (every
  third cancelled by role B leaving) and 23 standalone-runner sessions back to
  back; each node checks `Vault.live_tables()` after the warm-up and at the
  end. With `close_party` stubbed out: 780 tables over (13 a session) on each
  node for the cluster run and 260 for the standalone one; with closing but
  freeing only with the last handle (an intermediate version), the same, which
  is how the closure leak above was found.
- Peak RSS of that scenario's node-a: 125 MB, main 156 MB. Not flat: a cluster
  session still leaves ~40,000 live objects behind on main and here (the
  message encodings of
  [2026-10-01-session-message-encoding-leak.md](../todos/2026-10-01-session-message-encoding-leak.md)
  and the closure captures above), so the "a session every 200 ms for a minute
  under 100 MB" acceptance below waits on those two.

## Control plane

lib/desugar/control_wiring.march keeps the leader's state as a record again
(`ctl_encode_leader` / `ctl_decode_leader` and the separate release entry are
gone). The `Ctl` session budget stays at 1200 polls, its reason now the
closure-capture leak (a session still leaves ~1 MB behind; at the original 40
polls a node would form 30 times as many sessions); back to 40 once that todo
lands. `CtlRespawner` stays: restarting a drained session from a task on the
draining epoch would churn sessions for ever, which is a correctness matter,
not a leak.

Measured: all six control_* two-node scenarios pass. Node RSS sampled every
5 s through control_partition: branch peaks 47 / 26 / 35 MB, main (9ee1f648b)
53 / 29 / 37 MB, both rising ~2 MB per 5 s on the leader for the reasons above.

ASAN (Linux container, `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`): the probe,
session_churn twice, and cluster_sessions, cluster_ap,
cluster_ap_offer_retire, cluster_crash_branch, cluster_ap_hosted_cancel,
hosted, crash_hosted, drain_stream, drain_initiated, stream, fan and gone: no
report.

---


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
