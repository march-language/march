# FIXED 2026-09-04 — aggregate parameters are OWNED, closing the last aggregate leak

All six leak fixtures are now flat. `live_objs` at exit, same program at
N=1,000 and N=100,000:

| fixture | before | after |
|---|---|---|
| record, scalar fields | 1,000 / 100,000 | **0 / 0** |
| record with a String field | 2,002 / 200,002 | **2 / 2** |
| record update `{ b with n: .. }` | 1,001 / 100,001 | **1 / 1** |
| tuple | 2,003 / 200,003 | **2 / 2** |
| variant holding a record | 2 / 2 | 2 / 2 |
| variant control | 2 / 2 | 2 / 2 |

## What it took

**1. `borrow_eligible` is false for `TTuple`/`TRecord`.** A borrowed aggregate
parameter leaves the CALLER holding the release, and in a self-tail-recursive
loop that release is unreachable: it sits after the tail call, `llvm_tco` folds
the call into a back-edge, and the dec is discarded — `has_self_tail_call` says
so outright. It cannot simply be emitted before the back-edge either; that
frees the cell the next iteration reads. Ownership fixes it uniformly: each
iteration releases the aggregate it was handed before jumping with a new one.

**2. `Perceus.insert_owned_aggregate_param_drops`.** A parameter has no binding
site to hang a drop on — a variant gets `add_scrutinee_free_for`, a let-bound
aggregate gets the scope-end drop — so an owned aggregate parameter was never
released. The drops are pushed to every TAIL position, NOT wrapped around the
body: wrapping puts an operation after the body, the self tail call stops being
a tail call, TCO stops firing, and the loop recurses (measured correct and
leak-free to ~5,000 iterations, then SIGBUS from stack exhaustion by 20,000).

**3. `used_only_as_field_source` follows a pure alias.** Tuple destructuring
lowers to `let linear $p = t in let n = $p.$fv0 in ..`, so refusing an alias
binding left a tuple parameter with no drop site at all.

## The two tests that had to change, and why it is not test-fitting

`perceus 3` (`to_string borrowed field no EDecRC`) and `perceus 13`
(`record param multi-call no RC underflow`) both asserted "no `EDecRC` anywhere
in the callee" as a PROXY for "no dec of the extracted field". The second one's
own comment says so: *"must not contain a dec_rc for the extracted string field
from cfg"*. With aggregates owned, the record's own release inside the callee is
correct and expected; a dec of the FIELD is still the bug.

Both now assert by the TYPE of what is released, and the first additionally
pins that the record is released exactly once. Verified against the actual TIR
before changing them:

```
fn acc(s : { content_dir : String }) : String =
  let $t = s.content_dir in
  inc_rc $t;      -- escaping field dup'd
  dec_rc s;       -- record released once
  $t              -- and NO dec of the field
```

This is the third instance of the same over-broad-proxy pattern on this branch;
`test_perceus_local_record_field_no_spurious_decrc` was narrowed the same way.

## Snapshot diff

Purely ownership TRANSFER — each dec moves from the caller (after the call) into
the callee (at its tail). `peek`, `move_right` and `describe` now release their
own parameter and `main` no longer does. One release each, relocated.

## Verification

`dune runtest` — the full CI-equivalent, not just `scripts/run-tests.sh` —
clean apart from `test/apps/actor_stress`, which is inherently nondeterministic:
its compiled binary produced **3 distinct output orderings across 5 runs**, and
it failed and passed at the base commit too, independent of this change.
Refinement audit 693/693. All correctness witnesses hold (shared-record,
escaping-field, record-update aliasing, multi-call, niche golden).

## Follow-up

`test/apps/actor_stress`'s golden compares interleaved output from concurrent
actors. It is flaky by construction and should either sort its output or pin a
deterministic schedule.
