# DONE 2026-10-08: Perceus released a record before a field read from it

Found by the TIR verifier's RC-balance check (check 3,
`specs/progress/2026-10-07-verify-rc-types-and-pass-bisect.md`). These were
compiled-only miscompiles; the interpreter was right.

| Shape | Where | Interpreted | Compiled before |
|---|---|---|---|
| String `match` on a field, binder arm | `test/native/native_node_send_loopback.march` `dispatch_a`/`dispatch_b` | `unknown tag-12345` | `unknown ` |
| Nested projection, then the record consumed by a call | `Topology.offer_lines`, `drain_lines` | `fp fp-1000003` | `fp 2` |
| Record update from a `List.find` result | `Topology`'s desired-role merge | `1016893` | SIGTRAP, exit 133 |

## Cause

`let t = d.f` is a borrowed projection. It holds no reference of its own; the
record `d` holds it. That is sound only while `d` outlives every read of `t`.
Two rules released `d` without looking at `t`.

1. **The cross-branch release** (`insert_rc_expr`, `ECase`). A variable live in
   one arm and dead in another is released at the head of the arm where it is
   dead. `d` was dead in the arm, but a projection of it was still live there:
   - in the string match, the binder arm `other -> "unknown " ++ other` read
     `d.tag` after `__drop(d)`;
   - in the record update, `if r.cap == 0 do 0 else w.w_cap end` released `w`
     at the head of its `True` arm, before the update read `w.w_place`.

   The downstream passes then saw a release already on the path and placed no
   drop of their own.
2. **The dup-on-consume rule** from
   `specs/progress/2026-09-28-borrowed-field-outlives-owner.md`. When the rest of
   the scope consumes `d`, it makes the projection take its own reference. It
   matched only a direct `d.f`. A nested chain `o.ap.fingerprint` lowers to
   `let t = (let a = o.ap in a.fingerprint)`, so `active(o)` consumed `o`, and
   then the concatenation read `t`.

## Fix (`lib/tir/perceus_core.ml`)

- **`env.field_owner`** maps each borrowed projection to the variable it points
  into. A direct field gives its source, a nested chain its root
  (`projection_root`), and an alias the alias's owner.
- **Cross-branch release.** An owner is not released at an arm's head while
  any borrowed projection of it, followed transitively through `owner_chain`, is
  live in that arm. Its release then comes from the passes that already place
  drops behind a projection's last read: the owned-aggregate parameter drop
  (`Perceus.insert_owned_aggregate_param_drops`) and the scope-end aggregate
  drop (`drop_agg_at_tails`). Either may give up, which is a leak, never an
  early release.
- **Dup-on-consume** now also applies to a nested projection chain, by its root.

Check 3 now runs under plain `--verify-tir` / `MARCH_VERIFY_TIR=1`, so
`test_oracle` runs it on every compile. `--verify-tir-rc` is kept as a spelling
of the same switch.

## Red, then green

- **Golden fixture** `test/native/field_use_after_parent_release.march` runs all
  three shapes in loops. With main's compiler it printed wrong output and exited
  133; now it matches the interpreter.
- **Verifier test** `test_codegen` `tir_verify` "rc: perceus
  parent-released-before-field-use fixed": the same three programs through the
  real pipeline. It asserted the use-after-release findings before the fix, and
  now asserts there are none.
- **Leak check.** Under `--rc-trace`, the string-match and record-update repros
  end with nothing live. The nested repro ends with the same two static closures
  that main's compiler leaves.
- **Sweep.** Check 3 finds nothing across the 439-program sweep (`test/native`,
  `bench`, `test/snapshots/src`) or the 90 programs of `examples/` and
  `specs/lang/golden/`.

## What else moved

Every program's IR hash changes, because the stdlib's `Topology` lambdas change and
fresh-name counters shift. Function-by-function, with fresh names and labels renumbered,
36 function instances change across the 440 programs of `test/native`, `bench` and
`test/snapshots/src`, in 14 distinct functions:
- **The repros and the stdlib functions above:** `classify`, `pick`, the new fixture's
  `main` lambda (which inlines `line`), `dispatch_a`/`dispatch_b`, and `Topology`'s
  `offer_lines`/`drain_lines`/`apply_desired` lambdas.
- **The same bug, unreported:**
  - `Handshake.verify_peer_cert`'s `_` arm released `peer`, then read `c.pubkey`, where `c`
    is matched out of `peer.cert`.
  - `Swim.refute` and four `ClusterNode` functions (`dial`, `core_replace_cert`, the
    `MoveTicker` handler) get their record's drop moved behind a projection's last read.
  - `take` in `test/native/idle_worker_leak_probe.march` changes the same way.

No benchmark function changes, so no benchmark was rerun. In leak-reporting mode
(`MARCH_VERIFY_TIR_LEAKS=1`), every changed program reports one leak fewer than with main's
compiler and no use-after-release. The leak findings left (about 260 per program) are the
accepted drop-glue fallbacks (`specs/todos/2026-10-08-verifier-a4-followups.md`).
