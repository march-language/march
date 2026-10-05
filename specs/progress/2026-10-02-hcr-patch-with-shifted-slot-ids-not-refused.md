`[P2]` A hot patch whose slot name table differs from the running binary's is accepted and mis-dispatches

**RESOLVED 2026-10-02 by #765** (merged as c462e105a; [2026-10-02-hcr-patch-slot-ids-by-name.md](2026-10-02-hcr-patch-slot-ids-by-name.md)), better than this todo's acceptance asked: rather than refusing a patch whose ids differ, a patch no longer carries ids at all. Its call sites load each slot id from a per-name cell that `__march_init` fills from the running binary's table (`march_dispatch_name_to_id`) after dlopen, so a v2 that adds a top-level fn dispatches correctly. #763 (merged later, test-only) had removed the new top-level fn from the `protocol_expand_contract` scenario to dodge the crash; the fn is back (2026-10-04), so the scenario again proves the case end to end.

Found 2026-10-02 (see specs/progress/2026-10-02-two-node-protocol-expand-contract-slot-ids.md).

Slot ids are the sorted position of each slot's name (`Hot_reload.Name_table`).
A patch that adds (or removes) a slot function renumbers every later slot, so
its `march_dispatch_enter_unit(<id>)` calls name the wrong functions in the
running binary. `forge deploy` avoids this by planning a restart for any new
slot fn (manifest diff against the baseline). A direct `hcr_deploy deploy` /
`ACTIVATE` with no baseline manifest does not: the node accepted the patch
and the first call through a shifted id crashed it (`SIGSEGV`, bad `Cap`).

Since #751 every top-level fn of the entry module is a slot, so this is far
easier to hit than when only `Mod.*` fns were.

Fix options: the patch carries its name table (or a digest of it) in its
manifest and the node refuses an ACTIVATE whose ids disagree with the
running table for any name both contain; or ids are made stable (assigned by
manifest, appended, never renumbered).

Acceptance: `hcr_deploy deploy` of a v2 that adds a top-level fn, with no
baseline, is refused with a clear message instead of crashing the node.
