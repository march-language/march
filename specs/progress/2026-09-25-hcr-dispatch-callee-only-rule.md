# Hot reload: a call dispatches whenever its callee is reloadable

Closed 2026-09-25, together with
`2026-09-25-hcr-patch-so-private-runtime-copy.md` (the patch `.so` that carried
its own runtime). Found by distributed-deploys step 9: after a deploy,
`Topology.reoffer` reopened roles with the OLD body.

## The defect

`Hot_reload.needs_dispatch` (lib/tir/hot_reload.ml) required BOTH the caller
and the callee to be reloadable. Every call from non-reloadable code into the
boundary was therefore compiled as a direct call to the baseline symbol and
never saw a patch: the generated topology `main` and the rest of the entry
module (never reloadable; lowering gives its top-level functions bare names),
the closures they build (a lifted lambda has a bare name too), actor handlers
(`Worker_Tick`, bare) calling module functions, and any stdlib code calling
back into the app. The role-body closure the topology entry builds,
`fn (topology_s, topology_st) -> UpgradeApp.Serve.serve_one(env, ...)`, is one
of these: the call sat in a bare-named lambda.

## The rule now

A call dispatches whenever the CALLEE is reloadable (an app module under the
prefix or an include, not excluded, and published in `hr_names`), whoever the
caller is. Calls to stdlib, excluded modules and the runtime stay direct;
intra-SCC calls stay direct as before (that decision is made above this
predicate). `caller_module` stays in the signature so a call site still names
both ends. Nothing about the runtime had to change: the table is
process-global and `march_dispatch_enter_unit` resolves against the running
proc's `code_epoch`, so a non-reloadable caller gets the code its task was
spawned under (#612/#648).

Two things had to change with it:

- **The entry file's nested modules join the boundary.** forge passes
  `--hot-reload <EntryModule>`, but lowering strips the entry module's name
  from every declaration in that file, so a nested `mod Serve` is named
  `Serve.serve_one`, never `UpgradeApp.Serve.serve_one`, and `is_reloadable`
  left it off the boundary: in a single-file topology app only actor
  handlers could be hot-deployed, and `forge deploy hot` answered
  "No hot-deployable changes detected" for a changed role body.
  `bin/main.ml` now collects the entry file's nested module paths after
  parsing and carries them as the config's `includes` when the prefix names
  the entry module (`hr_entry_nested`). The entry module's own top-level
  functions stay off the boundary (they share `main`'s bare spelling); see
  `specs/todos/2026-09-25-hcr-entry-module-top-level-fns-outside-boundary.md`.
- The forge upgrade fixtures keep their role body in a nested module
  (`UpgradeApp.Serve.serve_one`), which is the shape a real app has.
- **A boundary function's slot hash folds in the lambdas it builds.** The
  slot identity (`hr_impl_hashes` in bin/main.ml) is deliberately
  non-transitive (a leaf change must not flag the whole caller chain), but
  lowering lifts every lambda into a separate bare-named function
  (`$lam<n>$apply$<k>`, join points), so a change INSIDE a lambda -- where
  every session body lives -- left the boundary function's hash byte-identical
  (`Serve.serve_one` hashed the same in both fixture versions) and the deploy
  activated nothing for it. Bare-named (module `""`) callees are never slots,
  so their hashes are now folded into each boundary root transitively,
  stopping at other slots and at cycles; qualified callees (stdlib) stay
  unfolded.
- **The reload server no longer dlopens a patch with `RTLD_DEEPBIND`**, and a
  Linux patch is linked `-Wl,-Bsymbolic` instead (macOS's two-level
  namespace already binds intra-image references). DEEPBIND made the patch
  prefer its own symbols over the baseline's; with no runtime in the patch,
  hidden non-boundary functions and link-time-bound boundary functions,
  nothing is left for it to decide, and AddressSanitizer refuses a dlopen
  that carries it, which had kept every hot deploy out of the sanitize gate
  (CI runs every two-node scenario under ASan). The new scenario now runs
  under ASan on Linux, clean.

## What the epoch resolves to (tested)

A task inherits its spawner's code epoch (`spawn_code_epoch`, II.4.3); an
actor moves to the new epoch at its next marker even when its own handler was
not activated. So after a deploy, a task an old, unchanged handler spawns runs
at the NEW epoch and its dispatched call into the boundary gets the new code.
Both new tests exercise exactly that: an unchanged actor handler spawns a task
per message/session, only the nested module the task calls into changed, and
the new version is what runs (`v2 probe 9 sees created=1` in the repro;
`v2 Buyer with a v1 Shop: seen` in the scenario).

## Tests

- `test/test_hot_reload.ml`: the predicate (stdlib→app, ""→app and
  excluded-caller→app dispatch; stdlib→stdlib stays direct).
- `forge test --upgrade-from`, fixture `live`
  (forge/test/fixtures/upgrade/live): the new role body spawns a task that
  reads the Vault the old hook created and starts an Echo session of its own;
  the traffic asserts the answer only the new body produces (1111, the old
  body gives 1002). The hook of every version now keeps its caps in `Env`
  and creates `upgrade_state`.
- `test/two_node/hcr_new_code_session`: node-a hosts Shop from an actor and
  keeps the offer in a Vault, node-b's Driver actor starts a Buyer session
  per tick from a task; both nodes are patched (b then a) with the actor
  handlers unchanged and only `Host.*` / `Buy.*` changed. node-b prints the
  version pairings (1/1, 2/1, 2/2 seen; 1/2 not), no session lost, and
  node-a's version-2 host reports it sees the version-1 offer. Driven by
  `test/hcr_deploy.exe`, step 9's local deploy tool (copied verbatim from its
  branch so the two merge cleanly).
- Same-box A/B benchmark, below.

## The boundary cost, re-measured (G1's benchmarks, compiled `--opt 2`)

BENCH_TABLE
