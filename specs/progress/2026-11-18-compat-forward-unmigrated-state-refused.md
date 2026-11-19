`[P2]` `@compat(forward)` / `@compat(any)`: an added field with no migration leaves the old-shaped state in place (reproduced 2026-11-18: SIGSEGV; fixed by refusing the deploy)

Found by reading, while building derived migrations (M11). Not reproduced.

`docs/hot-code-reload.md` said that under `@compat(forward)` "existing actors use default
values from `init`" for added fields. Nothing implemented that: with no
`<actor>_migrate_state` in the patch, `march_reload.c` sets `migrate_fn = NULL`
(`resolve_migrate_fn` finds no `__migrate_<Actor>`), and the live actor keeps its old state
record while the new handlers read the new layout. If so, a read of an added field is past
the end of the old record.

M11 covers the constant-`init` case under every policy (the derived function exists, so the
state is migrated). What remains is an added field whose `init` value is not a constant, and
any change under `@compat(any)`.

To do: reproduce (v1 `state { a : Int }`, v2 `@compat(forward)` adding `b : String` read by a
handler, `init(x : String) { a: 0, b: x }` so nothing is derived; deploy and send the
handler's message, under ASAN). If confirmed: refuse the deploy unless a migration exists,
or remove the two policies. The doc now says the state keeps its old shape and recommends a
migration.

## Resolution (2026-11-18)

**Reproduced.** `test/two_node/hcr_compat_forward_unmigrated` as first written: v1
`state { count : {Int | _ >= 0} }`; v2 `@compat(forward)` adding `label : String` (its `init`
value an `init` parameter, so nothing is derived) and `history`.  The deploy printed
"Deploy complete", the runtime logged `symbol not found: __migrate_Counter (proceeding without
migration)`, and the node died on the next `Report`: `fatal SIGSEGV si_code=2 addr=0x8` (the
read of `label` one word past the end of the old one-field record).  No ASAN needed.

**Fixed by refusing, in two places** (the todo's first option; the policies are kept, as
spellings that no longer waive anything):

- **forge** (`forge/lib/schema_diff.ml`, `check_compat`): a state-field change with no
  migration is an error under every policy.  `@compat(any)` was as unsound as `forward`: a
  removed or retyped field makes the new handlers read the wrong word.  The refusal under
  `forward`/`any` says the policy does not waive a migration, and why, plus the existing
  `not_derived_note`.  `forge deploy plan` (`deploy_plan.ml`) shares `check_compat`, so it now
  plans such a pool `blocked`, not `hot`.  The abort hint no longer suggests adding `@compat`.
- **runtime** (`runtime/march_reload.c`, the activation loop): a deploy whose migrate bit says
  the state changed, for an image with no `__migrate_<Actor>`, is `ERR migrate_missing`, with
  audit result `err_migrate_missing`.  Only an older forge or a hand-written request reaches it.

**Tests.**
- `test/two_node/hcr_compat_forward_unmigrated`: the same deploy is refused with both reasons,
  and the running v1 answers its own `Report` (`v1 count: 6`).
- `test/test_reload_activate4.c` (`test_schema_baseline`): `ACTIVATE5 Counter_dispatch` with
  migrate bit 1 against the stub (no `__migrate_Counter`) is refused, audited, and leaves the
  baseline schema unchanged.
- `forge/test/test_deploy_plan.ml` (mechanism 8): `forward` and `any` both plan `blocked`
  (it used to pin `any` as `hot`).

**RED.** Each check failed with the fix taken out:
- `check_compat` restored to `forward`/`any` → `Ok`: the plan test failed, and the scenario failed
  on the refusal text. The runtime check alone still stopped that deploy (`COMMIT_BATCH failed:
  ERR commit_partial_failure`, node alive), so each layer holds on its own.
- The runtime check disabled: the C test's three new checks failed.

**Residual.** The runtime trusts the signed migrate bit; it does not itself compare the
running and patch schemas (it holds both in `g_schemas`/the patch's `__march_hcr_schemas`).
A client that signs bit 0 for a state change still gets through.  Comparing them in
`schemas_extract` would close that; not done here (forge is the only signer, and it computes
the bit from the same schema diff).
