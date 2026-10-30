# `[P1]` `forge deploy hot`: the first deploy after a baseline cannot see an actor's state change

Filed 2026-10-18 while reproducing
`specs/progress/2026-09-21-hcr-spawn-site-state-layout.md`.

`forge deploy hot` learns which actors' state changed by diffing the patch's
`<so>.schemas.json` against the RUNNING version's schemas, which it reads from
`.march/<name>_hot.so.schemas.json.prev` (`Cmd_deploy_hot`, `prev_schemas_path`). That
file is written only AFTER a successful hot deploy (`save_schemas_baseline`), and a
plain `march --compile --hot-reload` of the baseline writes no `.schemas.json` at all
(`bin/main.ml` emits it only with `--compile-so`). So the first hot deploy onto a
freshly built baseline has no old schemas: `Schema_diff.diff_schemas` returns nothing,
no actor gets the migrate bit, and a patch that changes an actor's state layout
(with a correct `migrate_state`) activates as a plain swap. Every live actor of that
type then runs the new handlers on its old state record.

Seen: `test/two_node/hcr_spawn_site_layout` deployed without the baseline schemas
(its first version) read garbage fields and died with SIGSEGV in the first new
handler, on actors that had nothing to do with the spawn-site bug. The scenario now
builds version 1 as a `.so` to get the schemas, which a user has no tool for.

The `@compat` check (`compat_errors`) and the migrate-bit computation both see an
empty diff, so neither refuses. (The sig_hash exemption for a migrating dispatch,
`has_migrate_exemption`, gates nothing here: with the epoch model on, a changed
dispatch signature deploys with a warning.)

Options (owner decision):

1. Record the baseline: whatever builds the binary a host first runs (`forge build`
   with hot reload on, `forge deploy` of a full release, `forge host init`) also writes
   that version's schemas and manifest as the `.prev` baseline.
2. Refuse: when there is no baseline and the patch carries any `__migrate_<Actor>`
   (or changes any `<Actor>_dispatch`), stop with "cannot tell whether <Actor>'s state
   changed: no baseline schemas for the running version" instead of deploying.
3. Ask the server: have the reload server keep the running version's schemas (it gets
   the patch's on every deploy; the base binary would need to embed its own) and answer
   them over the socket, so the baseline is the server's, not the operator's checkout.

2 is the minimum to stop the crash; 1 or 3 makes first deploys work. Test: the
spawn-site scenario without its `base_so` step must deploy correctly (1, 3) or be
refused (2).

## Decision (owner, 2026-10-30)

Option 3, the reload server keeps the schemas, with these details (also recorded in
`specs/plans/2026-09-28-road-to-1.0.md`, "Open decisions" 12):

- Every `--hot-reload` build embeds its `.schemas.json` and manifest as constant data in the
  binary, in a deterministic encoding (it enters the CAS key and the determinism oracle).
- A new read-only reload-socket verb `SCHEMAS`, protected like `ABI_QUERY` (owner-only socket,
  peer-uid check, not signed), answers the newest ACTIVATED version per actor and names the
  release it describes. The server records each activated patch's `.schemas.json` in its state
  directory, pruned with the patch stack.
- `forge deploy hot` asks the server first. When its local `.prev` disagrees, the server wins
  and forge warns that the local baseline was stale.
- A server built before this has no `SCHEMAS`: forge falls back to `.prev`; with none, it
  refuses ("this server predates schema reporting: restart it on a current build or pass
  --old-schemas"), never deploying without the migrate bit.

Tests: `test/two_node/hcr_spawn_site_layout` without its `base_so` step deploys correctly; a
deploy after another operator's deploy uses the server's baseline; an old server with no
`.prev` is refused.
