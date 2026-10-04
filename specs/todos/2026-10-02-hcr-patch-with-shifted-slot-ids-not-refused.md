`[P2]` A hot patch whose slot name table differs from the running binary's is accepted and mis-dispatches

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
