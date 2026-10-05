# two-node protocol_expand_contract: SIGSEGV after the expand patch (fixed)

**Closed:** 2026-10-02

**Superseded 2026-10-04.** This was the test-only workaround (#763): v2 stopped adding a
top-level fn. The compiler fix, #765 (merged first, as c462e105a; see
[2026-10-02-hcr-patch-slot-ids-by-name.md](2026-10-02-hcr-patch-slot-ids-by-name.md)), makes
a patch resolve slot ids by name, so a v2 that adds a fn is correct. Merging #763 after it
removed the scenario's only end-to-end coverage of that case. v2's `may_choose_later` is
restored, exactly #765's version of `app_v2.march`, so the scenario again proves it.

## Symptom

`two-node[protocol_expand_contract]: the contract deploy to node-a failed`, both
nodes dying with `SIGSEGV addr=0x62` in `ClusterNode.names` right after their
expand deploy ("8 function(s) activated"). Red on every PR from 2026-10-02
(first seen once the 2-way shard let the job reach it; the unsharded job timed
out at 55 min before getting there). Reproduces on macOS too.

## Root cause

Bisected with the same scenario on one machine: green on main 521d77eca, red
from #751 (5281ea260, "entry-module top-level fns are slots"). The scenario's
v2 source added a top-level fn, `may_choose_later`. Slot ids are the sorted
position of the name (`Hot_reload.Name_table.build`), so a new entry-module fn
(a slot since #751) shifts the id of every slot after it: in the expand
patch `note` is id 11, in the running binary id 10 (`host_tick`, 7, sorts
earlier and was unaffected). The patch's `march_dispatch_enter_unit(11)` then
ran a different function than the one it meant, which handed `ClusterNode.names`
a value that is not a `Cap(ClusterNode.Live)`. Before #751 the entry module's
fns were not slots, so the name table was identical across the two versions
(and the deploy swapped nothing, which is why it passed).

The scenario deploys by hand with `hcr_deploy`, with no baseline manifest
(`node_<x>.hcr_manifest` does not exist for a `--compile`-only build), so
nothing flagged the new function. `forge deploy` has the baseline and plans a
restart for a new slot fn.

## Fix (test only)

- `app_v2.march` adds no top-level fn: the `role_fingerprint == fingerprint`
  test is written out in `shop_phase` and `shop`.
- The "v2 Buyer with a v1 Shop" line (key `pair:2/1`) became "v2 Buyer with an
  expand Shop" (`pair:2/2`). The old label counted the Shop's `shop_phase()`,
  which was 1 only because `shop` was not a slot: an old offer's closure kept
  running v1 code for ever. With `shop` hot-swappable the Shop on the v1
  fingerprint reports phase 2 after the expand. What the line proves (a v2
  Buyer forms sessions with a Shop still on the previous fingerprint, none
  refused) is unchanged.

Verified: `scripts/two-node.sh protocol_expand_contract` and `protocol_evolve`
pass (macOS arm64), twice.

Follow-up for the loader, which accepts such a patch silently: see
`specs/todos/2026-10-02-hcr-patch-with-shifted-slot-ids-not-refused.md`.
