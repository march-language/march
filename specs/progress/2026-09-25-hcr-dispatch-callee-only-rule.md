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
- The nested modules are taken from the PARSED entry module: desugaring adds
  the `@[endpoints]`/`@[remote]`-generated modules (`Order_Buyer`, `Order_Run`,
  ...) as nested modules too, and swapping those mid-session made
  `protocol_evolve`'s version-1 Buyers hit a non-exhaustive match on a
  `later` they had never heard of. A session finishes on the protocol code
  it formed under; a protocol change ships as a new offer.
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
  unfolded. What is folded is a CANONICAL hash: the helper's pretty-printed
  TIR with every counter suffix after a `$` and every inliner `_i<n>` suffix
  replaced by `#`. The first version folded the CAS hash, which serialises
  names, and lifted names come from global counters, so any edit renumbered
  them and every deploy hot-swapped the stdlib's own actors
  (`ClusterNodeActor_dispatch`, which answers SWIM, `Endpoint_dispatch`,
  `Writer_dispatch`). Checked by diffing two versions' manifests: the
  canonical fold flags exactly what the control compiler flags plus the
  app's changed lambdas.
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
- `test/two_node/protocol_evolve`, step 9's network acceptance scenario (#658),
  moved out of `two_node_pending`: a protocol gaining a choice branch deploys
  hot across both nodes with sessions in flight on both fingerprints. It also
  needed `SessionNode.initiate` to look again when the only offer answers
  "closing" (the re-offer window), and node-b to linger for the counters query.
- Same-box A/B benchmark, below.

## The boundary cost, re-measured (G1's benchmarks, compiled `--opt 2`)

Same box as G1 (the 14-core Apple-silicon Mac), 2026-09-25, five interleaved
rounds after one untimed execution of every binary; **every sample started at a
1-minute load average between 4.67 and 4.98** (the gate was 5; G1 had to settle
for 6.5–7.7). Three compilers-worth of binaries: `plain` (no `--hot-reload`),
`hr_old` (origin/main `ee0413cf4`, the caller-AND-callee rule) and `hr_new`
(this branch), each compiler compiling its own runtime and stdlib, from fresh
directories with a fresh `HOME`. Medians, wall seconds, `[min–max]`; the
percentage is against `plain`; CPU is median user / system.

| benchmark | variant | median wall | min-max | vs plain | user/sys |
|---|---|---:|---|---:|---|
| list_ops_nested | plain | 0.096 | 0.096-0.102 | +0.0% | 0.077/0.031 |
| list_ops_nested | hr_old | 0.097 | 0.096-0.105 | +1.5% | 0.078/0.031 |
| list_ops_nested | hr_new | 0.100 | 0.097-0.106 | +4.3% | 0.078/0.032 |
| actor_ping | plain | 2.864 | 2.657-3.011 | +0.0% | 0.647/1.391 |
| actor_ping | hr_old | 1.345 | 1.327-1.354 | -53.0% | 0.637/0.880 |
| actor_ping | hr_new | 1.361 | 1.344-1.379 | -52.5% | 0.643/0.892 |


Static `march_dispatch_enter_unit` call sites in the binaries (`otool -tv`):
`list_ops_nested` 8 (old rule) → 12 (new rule);
`actor_ping` 3 → 7. The new sites are the
entry module's and its closures' calls into `Ops.*` / `Game.*`, which the old rule
compiled direct.

**Delta.** `list_ops_nested`: `hr_new` reads +4.3 % against `plain` where `hr_old`
reads +1.5 % (G1 measured +1.1 %), i.e. the rule change costs 3 ms on a 100 ms
run whose round-to-round spread is 10 ms; in two of the five rounds the two
hot-reload variants tied. A handful of extra dynamic dispatch calls per run
(the entry's calls into `Ops`, once each) cannot cost 3 ms, so as in G1 this is
layout or noise, not a per-call cost; it stays far below the 10 % threshold
that would have forced Model B first. `actor_ping`: `hr_new` 1.361 s against
`hr_old` 1.345 s (+1.2 %, inside the spread of both); the per-message boundary
call was already dispatched under the old rule (`Game.relay` → `Game.step`), and
the extra sites (`main` → `Game.*`, called once) are not on the hot path. The
plain-versus-hot-reload gap on `actor_ping` (2.86 s vs 1.35 s) is G1's filed
anomaly, unchanged.
