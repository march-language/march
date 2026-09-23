# Distributed deploys, step 4 remainder: `ClusterHandle` as `Cap(ClusterNode.Live)` (D35)

**DONE 2026-09-23.** Parent:
[../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
D35 and section 7.2 (level 3). The rest of step 4:
[2026-09-22-dd-step04-per-role-grants.md](2026-09-22-dd-step04-per-role-grants.md).
Logged as a todo on 2026-09-22 (this file, moved).

## What landed

- **`stdlib/cluster_node.march`** declares `type ClusterOps` and `proof cap Live with ClusterOps`, on the
  model of `Cap(Session.Live)`. `ClusterNode.attach(io : Cap(IO), ops) : Cap(ClusterNode.Live)`
  is `cap_impl(mint_cap(io), ops)`. `start(io, cfg)` builds the node exactly as before and
  returns `attach(io, ops_of(h))`, where `ops_of` closes the real dictionary over the
  node's backing record. The record is still the backing value (renamed from
  `ClusterHandle` to `CnHandle`, beside `CnState`/`CnLink`): the node actor, readers,
  writers and Vault mirrors are untouched, and every Vault read (`members`, `lookup`,
  `queue_for`, `names`, ...) is what it was plus one indirect call. Every public operation
  is `let d = ops(c)` then `d.<op>(...)`, where `ops(c)` is `cap_dict(c)` or a panic
  ("no cluster dictionary attached"), as in `Session`. The implementations moved into
  `h_*` private functions over `CnHandle`.
- **`ClusterNode.ops_stub(node_id)`**: a dictionary whose every operation panics naming
  itself, so a test overrides only what the code under test uses with record update.
- **Consumers.** `stdlib/session_node.march` (SessionNode and SessionAP): 18 places
  naming the type (17 parameters and the `Offer` record's `node` field), five raw
  `node_id` reads became `ClusterNode.node_id(...)`, and the session
  counter `Vault.incr(node.meta, "ap_sessions", 1)` became
  `ClusterNode.next_id(node, "ap_sessions")`; the module declares `needs ClusterNode.Live`.
  `Desugar_endpoints.run_module`: the five `<P>_Run` front families (`cluster_`, `offer_`,
  `initiate_`, `offer_hosted_`, `cluster_hosted_`) take `Cap(ClusterNode.Live)`, and the
  generated module's `needs` lists `ClusterNode.Live`. `forge/lib/topology.ml` never
  mentioned the type; unchanged.

## The dictionary's fields, and which were added beyond the todo's list

The todo listed `members`, `subscribe`, `register`, `lookup`, `queue_for`, `route`,
`creation`. Every public operation that reads the node is a field, because an operation
that bypassed the dictionary would not work on an attached cap at all (there is no record
behind it). Added, and why:

| Field | Why |
|---|---|
| `node_id` (a value, not a function) | SessionNode reads it for party ids, access-point names, answers and session ids; it was a raw record read. |
| `next_id(key)` | SessionAP numbered its sessions by bumping `node.meta` directly. A named counter keeps that out of the record. |
| `send_msg` | SessionAP sends Invite/Withdraw/Answer through it; a fake that captures sends needs it. |
| `unroute`, `route_type` | `route`'s inverse (SessionNode calls it 7 times) and its typed sibling. |
| `on_peer_closed`, `off_peer_closed` | `run_cluster_party` reacts to a peer's data connection ending. |
| `monitor_remote`, `demonitor_remote` | Public API over the record (links and control writers). |
| `register`'s siblings `unregister`, `names`, `watch`, `unwatch`, `stale_bindings` | The name registry: SessionAP's offer registry is `names` + `lookup`. |
| `stop`, `unsubscribe`, `all_members`, `addr_of`, `name_of`, `link_count`, `on_delivery_failed` | The rest of the public API over the record. |

`global_pid` (from `node_id` and `creation`) and `await_members` (from `members`) are
derived, not fields. `register` takes the pid as `Int` in the dictionary; the public
function keeps its polymorphic `pid` and converts.

## Deviations from the todo, and why

- **`Cap(ClusterNode.Live)` and `ClusterNode.attach`, not `Cap(Cluster.Live)` and
  `Cluster.attach`.** `mod Cluster` already exists (`stdlib/cluster.march`, peer address
  discovery from `MARCH_CLUSTER_NODES`), unrelated to the node. And Check 6 lets only the
  declaring module mint or `cap_impl` a proof cap, so the cap and `attach` must live in
  the module whose record backs it. The plan's D35 row and 7.2 now say so.
- **`start` takes `Cap(IO)` as a new first parameter**, as the step-2 entry predicted
  (`config_from_env` has no cap to thread). All 41 cluster fixtures already had
  `main(c : Cap(IO))` or `main(_c : Cap(IO))`; the underscore ones were renamed to `c`.
- **The dictionary type is `ClusterOps`, not `Ops`.** March has one global type namespace,
  and `Typecheck_env.resolve_cap_dict_type` tries a dictionary's BARE name first. With a
  second `type Ops` in the stdlib, `Session.attach`'s `cap_impl` resolved the wrong one and
  failed with `expected Ops but got Ops` (stdlib/session.march:66). The compiler hides
  stdlib-spanned diagnostics, so only the whole-stdlib ratchet (`entry_mod_qual_erasure`
  case 5 in the `compiler` suite) saw it; the first push of this PR had the collision.
  The resolver preferring the declaring module's qualified name would fix the class; it is
  filed separately rather than changed here.
- **The root-capability hint no longer fires on a proof-cap factory**
  (lib/typecheck/typecheck_caps.ml, Check 3). `test/dune`'s `cluster_node_check.out`
  requires `march --check stdlib/cluster_node.march` to print NOTHING, and the new
  `attach(io, ...)` and `start(io, ...)` drew "this function takes `Cap(IO)` (the root
  capability); consider narrowing". They cannot narrow: `mint_cap` is typed
  `Cap(IO) -> Cap(a)` and amplifying a narrowed cap is a type error. A function whose
  declared return type names a proof cap its own module declares is now exempt, like
  `main`; `Session.attach` and `Actor.introspect` lose the same unactionable hint. Pinned
  by `cap_ux_no_nag` "proof-cap factory not hinted about root cap" (a non-factory in the
  same module is still hinted), proved red with the exemption disabled. This golden is a
  dune rule, which `scripts/run-tests.sh` does not run: both CI test legs failed on it
  after the PR was opened.
- **`ClusterHandle` is gone, not aliased.** A `type ClusterHandle = Cap(Live)` alias would
  have kept fixtures compiling, but a capability hidden behind an alias is exactly what the
  `needs` check should see, so the migration names the cap.
- **Zero-argument dictionary operations take `()`** (`members: fn _ -> ...`, called
  `d.members(())`): a `fn () -> e` lambda does not check against a `() -> T` field, and
  `ops(c).members()` does not parse. `Session.InProcess.drain` has the same shape.
- **Six fixtures had a helper `join() : ClusterNode.ClusterHandle` that started and
  waited.** A user function may not return a proof cap it did not mint ("Only public
  functions of `ClusterNode` can construct `Cap(ClusterNode.Live)`"), so `main` now binds
  the started node itself and the helper became `joined(h) : ()`. Same behaviour; the
  clustering chapter documents the pattern. (`cluster_crash_branch`, `cluster_fan_late_crash`,
  three nodes each.) `cluster_fd_release`'s `cycle` gained the `Cap(IO)` parameter.
- **A module that only binds the node in `let`s needs no `needs ClusterNode.Live`**; one
  whose signatures name it does (Check 1). The migration added the line to exactly the
  fixtures whose signatures name it.

## Acceptance

- **`test/session/cluster_placement.march`**, both backends against one golden (dune
  rules beside `stream_peers`). A toy placement written only against
  `Cap(ClusterNode.Live)` (`members`, `subscribe`, `unsubscribe`) keeps each of three roles
  on the least-loaded Alive member. The test attaches a fake dictionary
  (`{ ClusterNode.ops_stub("n0") with members, subscribe, unsubscribe, creation }` over
  Vaults it drives), injects `NodeDead` for n2, `NodeUp` for n4, `NodeDead` for n3 and n1,
  and asserts the moves (`db: n2 -> n1`, `cache: n3 -> n4`, `api`/`db: n1 -> n4`; a join
  moves nothing; four moves in all; after `unsubscribe` another death moves nothing). It
  also checks `node_id`, `creation` and the derived `global_pid` through the dictionary.
  No sockets, no node actor. Proved non-vacuous: making the public `members` drop its
  first element changed the golden's placement lines; restoring it went green.
  SessionAP's offer registry was not driven directly: `candidates` is private and a full
  fake of invite/answer needs a real `NodeQueue` writer for `queue_for`; the step-3
  `Topology.place` is the natural next consumer of this seam.
- **The two-node cluster scenarios**: see "Tests" for each run's result.

## Verification of the stdlib modules

`march --check stdlib/cluster_node.march` and `stdlib/session_node.march` (with
`MARCH_STDLIB` at the source tree): no errors, only the root-capability hints every
`Cap(IO)`-taking stdlib function gets. Checked alone they prove nothing for cross-module
calls (#591), so the whole-stdlib ratchet in the `compiler` suite
(`check_stdlib_like_cli`) is the real check; see "Tests".

## Tests

- `scripts/run-tests.sh stdlib`: 886 tests, all passed (322 s).
- `scripts/run-tests.sh stdlib_march`: 71 tests, all passed.
- `scripts/run-tests.sh compiler`, first run: 1239 tests, 1 failure, the whole-stdlib
  ratchet (`entry_mod_qual_erasure` 5: `stdlib/session.march: expected 0 internal
  error(s), found 1`), the `Ops` collision described above. After the rename to
  `ClusterOps`, that case passes.
- `test/cluster_placement.out` and `cluster_placement_interp.out` built through their dune
  rules; both match the golden, before and after the rename. Perturbation check above.
- `march --check` on all 41 migrated `test/two_node/cluster_*` node files: no errors.
- Two-node cluster scenarios (`scripts/two-node.sh`, `MARCH_STDLIB` at the source tree):
  17 of 18 pass. `cluster_partition` exits 3, "skipped: needs root (Linux iptables) to
  drop packets", by design on macOS; it runs on CI's Linux leg.
- `scripts/check-docs.sh`: passed (Check F: the 16 generated chapters match).
- Full `scripts/run-tests.sh` after the fixes: 11 of 12 suites passed (compiler 1239,
  eval 282, codegen 626, stdlib_march 71, test_jit 24, lsp 361, utf16 5, jsonrpc 36,
  incremental 10, query_cli 7, refinecheck 959). `run_stdlib` reported 19 failures in a
  contiguous block of unrelated compiled regressions (adversarial-regressions 35 to 54),
  in a run that overlapped rebuilds of `bin/main.exe`; rerun alone it passed 886 of 886.
- `test/dune` goldens `cluster_node_check.out` (empty) and `session_node_check.out` built
  and matched locally after the hint fix.
- CI on the PR's third commit (`f7bf8945e`): the whole CI workflow succeeded, both the
  macOS and the Linux test legs included.
