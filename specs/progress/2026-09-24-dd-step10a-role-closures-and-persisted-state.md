# Distributed deploys, build step 10a: per-role closures, persisted state, signed TOPOLOGY, COMPACT

**DONE 2026-09-24.** The compiler/runtime half of build step 10. Parent:
[../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
sections 5 ("Admission", "Every reconciler action is signed"), 6.5, II.2 ("Hot
deploys"). What remains (10b: the ssh backend, `forge host init`, `forge deploy
--plan`) is the todo
[2026-09-22-dd-step10-ssh-backend-and-plan.md](2026-09-22-dd-step10-ssh-backend-and-plan.md) (10b, done 2026-09-25).
Six commits, one per item.

## 1. `ROLE` manifest lines

`check_role_grants`' solve is factored out as `solve_role_roots` (same synthetic
row keys, same `Cap_rows.solve` over copies of the tables) and shared with the new
`Typecheck.role_capability_closures`: per role with a grant, the union over its roots
of the IO caps solved, `Cap_lattice.normalize`d and sorted, plus each cap's reach
chain (`cap_reach_chain`, callback position first). A granted role with no root has
an empty closure. `bin/main.ml` writes, after the function lines,

```
ROLE Stream.Cons caps=IO.Console,IO.FileWrite via=IO.Console:body>cons;IO.FileWrite:body>cons>save
```

`Cmd_deploy_hot.parse_manifest` reads them into `manifest.roles`
(`role_name`, `role_caps`, `role_chains`); legacy manifests have none.
Only the IO lattice is kept, as `check_role_grants` judges: proof caps such as
`Session.Live` are not authority a node policy grants.

## 2. The client-side per-role gate

`compute_role_widening ~prior ~current` / `role_gate`: a role whose closure has a cap
no cap of the same role's baseline closure subsumes stops the deploy unless
`--grant-cap` covers it (subsumption, `filter_granted_widening`). A role absent from
the baseline widens by its whole closure. A baseline with no `ROLE` lines at all
(written before this step) makes the gate permissive for that deploy, with a note, as
the per-function gate is with no baseline. The baseline file is the whole prior
manifest (`save_manifest_baseline`), so it keeps the roles.
`print_widening_diagnostic ?role` names the role and each cap's chain:

```
error: hot deploy would widen role Stream.Cons's capability closure
  running version caps:  IO.Console
  new version adds:      IO.FileWrite (reached: body → cons → save)
```

## 3. `ACTIVATE6`

**Named `ACTIVATE6`, not `ACTIVATE5`:** step 6 had already shipped `ACTIVATE5` (the
migrate bitmask). Reusing it would have made a step-6 server rebuild the signed line
without `role_caps` and answer a misleading `ERR bad_signature`. `ACTIVATE6` is
`ACTIVATE5`'s payload plus `role_caps:<Proto.Role>=<root>;...` inside the signed line
(between `cap_root` and `callers`, strictly sorted by role) and an unsigned
`roles:<Proto.Role>=<csv>;...` block before `callers:`. The server recomputes each
root with `compute_cap_root` and answers `ERR role_cap_tamper` on a mismatch, on a
signed role missing from `roles:`, and on an unsigned role `roles:` adds; then, after
the function's own `cap_policy`, applies `MARCH_DEPLOY_POLICY` to every closure
(`ERR role_cap_policy <role> <cap>`). Order: signature, `cap_tamper`,
`role_cap_tamper`, `cap_policy`, `role_cap_policy`. Audit lines gain `"roles"`
(ACTIVATE6 only). forge sends `ACTIVATE6` whenever the manifest has `ROLE` lines,
`ACTIVATE4`/`ACTIVATE5` otherwise; against a server that predates it the deploy fails
with an upgrade message (no silent downgrade past the role check). `RELOAD_LINE_MAX`
went from 4 KiB to 16 KiB for the closures; the server thread's stack is set to
4 MiB (the handler frame already held the 256-entry batch array).

## 4. Host-local persisted state (6.5)

`<cas_root>/hcr_state/<16 hex of blake3(socket path)>/state`, rewritten with
temp+rename after every deploy: `base` (blake3 over every slot's baseline impl hash),
`topology <digest> <sig>`, `manifest` (blake3 over every slot's running impl hash),
`seq`, and one `entry <seq> <epoch> <signer> <sig64> <signed message>` per activated
function (a batch's functions share its seq). Keyed by the socket because the CAS
root is shared by every March program of a user.

`march_reload_server_start` loads the key and replays the state before it creates
the server thread, i.e. before `main` continues: every entry's signature is verified
again from the stored line; an entry with a bad signature, a missing artifact, an
unknown function or a malformed line is skipped with a `"type":"restore"` audit line
(`err_restore_sig`, ...); each function's newest valid entry is republished through
`activate_items`, deploy by deploy in seq order, with no drain armed; the file is
rewritten with just those entries. A different base build on the socket sets the file
aside (`state.base-changed`), as does `MARCH_HCR_NO_REPLAY=1` (`state.no-replay`).
`VERSIONS_DETAIL` gains `RESTORED entries:<n> skipped:<m> mode:<none|replayed|off|base_changed> stack:<n> manifest:<hex> topology:<hex|->`.

## 5. Signed `TOPOLOGY`

`TOPOLOGY <blake3> <sig64> <size>`, then the body. The signature (over
`TOPOLOGY <blake3>`, deploy key) is checked before `READY`; the body must hash to the
digest (`ERR digest_mismatch`); it is written to `topology.toml` in the state
directory (temp+rename), its digest and signature go into the state file, the push is
audited (`"type":"topology"`), and `march_hcr_on_topology(path)` is called. At start
a persisted topology whose digest and signature still verify goes through the hook
again. Client: `Cmd_deploy_hot.push_topology` (tunnel) and `push_topology_conn`.

## 6. `COMPACT`

`COMPACT` answers `STACK entries:<n> functions:<m> deploys:<d> artifacts:<k>
cas_bytes:<b>` (distinct artifacts, their sizes in the CAS). `forge hot-reload
status` prints it per node ("3 persisted patches over 2 deploys (2 functions), 1
artifact, 1.2 MiB in the CAS"). No rebuild logic.

## Deviations

1. **`ACTIVATE6`**, not `ACTIVATE5` (above).
2. **`TOPOLOGY` carries a size** and a `READY` handshake (the body needs framing), and
   the signature is checked before the body is read.
3. **No `SIGHUP`.** Step 8 has not landed; raising SIGHUP in-process with no watcher
   installed would end the process (the default action). The server calls
   `march_hcr_on_topology(const char *path)`, a documented no-op in
   `runtime/march_reload.c` (declared in `march_reload.h`) for step 8 to fill.
4. **`MARCH_HCR_NO_REPLAY` only, no `--no-replay` flag.** The runtime keeps argv in
   `march_runtime.c` (the D27 session's file), and a flag the runtime consumes would
   still reach the program's own `Process.argv`.
5. **"Manifest hash" is computed by the server**: blake3 over "name impl_hash" of every
   slot's running version (the server never receives the manifest file). The
   reconciler can compute the same from its desired manifest.
6. **Replay keeps each function's newest entry only** and rewrites the file, so a
   restart also compacts superseded entries. It does **not** re-apply
   `MARCH_DEPLOY_POLICY` (the unsigned caps are not stored; each entry was admitted
   under the policy of its time): a policy tightened between restarts does not evict
   an already-applied patch. Follow-up if wanted: store the caps/roles blocks and
   re-run the gates at replay.
7. **The `Hot-deploy authorization` section is in `specs/lang/capability-enforcement.md`**
   (the brief said `capabilities.md`); edited there, `docs/` regenerated.
8. **The end-to-end lives in `run_stdlib`** (adversarial-regressions, `Slow`, beside
   the other compiled HCR manifest tests), not `test_jit`, which is the REPL-JIT suite.
9. **Seams in other sessions' files: none.**

## Tests

- `test/test_reload_activate4.c`, three modes (each a dune `runtest` rule):
  default 76 checks (ACTIVATE6: matching roots admitted, stripped closure, missing
  role, unsigned role, unsorted block, `role_caps` covered by the signature, ACTIVATE4
  unchanged beside it, a real activation; TOPOLOGY: wrong signature refused before
  the body, digest mismatch, accepted and audited, stream in sync; COMPACT), policy
  13 (a widened role closure outside policy is `ERR role_cap_policy`, audited), and
  the new `restore` mode, 44 (each server lifetime a forked child over one HOME: activate
  and push a topology, exit; restart shows the hot version, the RESTORED line, the
  topology and COMPACT; `MARCH_HCR_NO_REPLAY`; a corrupted signature skipped with an
  audit line, no crash; a different base build not replayed).
- `run_stdlib` adversarial-regressions: `ROLE` lines from two real builds (the full
  closure through a helper, and the narrower one); and the step-10 acceptance end to
  end: a compiled base binary with `--signing-pubkey`, running its reload server under
  a node policy, refuses a signed `ACTIVATE6` whose role closure widened through a
  helper (`ERR role_cap_policy Stream.Cons IO.FileWrite`), forge's gate stops the same
  patch without `--grant-cap`, a control inside the policy is admitted, a forge
  `TOPOLOGY` push is accepted, and after a SIGKILL and restart the admitted patch and
  the topology are restored.
- `forge/test`: ROLE parsing, role gate (legacy baseline, widened, granted by
  subsumption, unrelated grant, narrowing, new role, baseline round trip), ACTIVATE6
  shape and role blocks, TOPOLOGY line, COMPACT parsing.
- Perturbations, each RED on exactly its checks and GREEN restored: role widening
  computed as empty (3 forge cases); both server role phases skipped (6 C checks);
  the server role policy phase skipped (the compiled end-to-end answers
  `ERR unknown_name cons` instead of the refusal); replay disabled (5 restore
  checks); the topology signature check skipped (1 C check).

A trap met on the way: a targeted `dune build` leaves `_build/default/runtime` with a
partial copy of the runtime (19 of 26 `.c` files, no `march_http.c`), and the driver
then links a session program without the TCP stack (`_march_tcp_* undefined`). Staging
every runtime source (`dune build --root . runtime/*.c runtime/*.h`) fixes it; CI's
full build stages everything.

## Results

`scripts/run-tests.sh` (full) at the final tree, load 11-26 on the 14-core Mac,
exit 0:

| suite | tests | result |
|---|---:|---|
| compiler | 1265 | pass |
| eval | 282 | pass |
| codegen | 626 | pass |
| stdlib | 888 | pass |
| stdlib_march | 72 | pass |
| test_jit | 24 | pass |
| LSP (lsp, utf16, jsonrpc, incremental, query_cli) | 361, 5, 36, 10, 7 | pass |
| refinecheck | 959 | pass |

`forge/test/test_forge.exe`: 183 pass. `test_reload_activate4_runner`: default 76,
policy 13, restore 44 checks, all pass. `scripts/check-docs.sh`,
`scripts/check-runtime-sources.sh`, `scripts/check-actor-rc-stores.sh` pass.

The first full run failed every REPL-JIT case in `run_codegen`: the JIT runtime
`.so` links `march_reload.c` without `march_blake3.c` (`runtime/sources.list`: blake3
is `hcr`, not `jit`), and the new state code called `march_blake3_hex` from paths the
optimizer could not drop. Fixed by routing the new digests through `state_hex`, which
is `march_blake3_hex` only under `HAVE_SIGNING_KEY` (a build with no deploy key
activates nothing and has no state), and by not replaying under `HAVE_SIGNING_KEY` 0.
The suite above is the rerun after that fix.
