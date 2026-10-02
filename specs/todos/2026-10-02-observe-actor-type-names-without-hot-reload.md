`[P3]` **Observe `ACTORS` rows have no actor type name unless the program is built with `--hot-reload`.**

From observe R1 ([`progress/2026-10-02-observe-r1-snapshot-verbs.md`](../progress/2026-10-02-observe-r1-snapshot-verbs.md)).

The row's `type` comes from the hot-reload dispatch table
(`dispatch_name_id` -> `march_dispatch_id_to_name`, `Counter_dispatch` ->
`"Counter"`), which only `--hot-reload` builds have, so every other build
reports `"type": null`. Deployed nodes are hot-reload builds, so the operator
path works; local runs and tests do not.

`dladdr` on the record's dispatch pointer is not a fix: without
`-export_dynamic` it returns the nearest EXPORTED symbol, i.e. a wrong name.

Fix shape: codegen passes the actor's name at the existing
`march_actor_set_call_tags` call (`lib/tir/llvm_emit_alloc.ml`), interned with
the tag table. That is a new runtime entry point a hot patch calls, so it bumps
`Hcr_abi.runtime_abi` (3 -> 4) and needs the usual old-runtime/new-patch
refusal test.
