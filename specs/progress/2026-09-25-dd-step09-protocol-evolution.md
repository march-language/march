# Distributed deploys, build step 9: protocol evolution (items 1-6)

**LANDED 2026-09-25; the step stays open** in
[../todos/2026-09-22-dd-step09-protocol-evolution.md](../todos/2026-09-22-dd-step09-protocol-evolution.md):
the network acceptance test is written but pending on a hot-reload defect this work
found (below). Parent: [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
6.4, 6.1, 4.2, II.5; D5, D21, D25. Built on #648 (D27 drains, the epoch holds), step 3
(`Topology.place`), step 4 (grants outside the fingerprint). Items 1-2 were written before
#648 merged (the gate); 3-6 after, on a merge of origin/main. One commit per item.

## 1. The compatibility table

`lib/desugar/desugar_endpoints.ml`. A protocol version's *wire view* (`wstep`): every
message as sender, receiver, constructor (the `derive Json` tag) and deep payload key
(`ty_key_deep`), with loops, choices, stops and crash branches; `loop atomic` and `role R
needs` do not reach it, as they do not reach the fingerprint. `compare_versions` is rule
one: the step trees are equal except one `choose` has exactly one extra branch (not
`crash`), branches compared by label, every shared message's tag and key unchanged, roles
unchanged. The roles that accept the previous fingerprint are the choice's receivers: every
role other than the chooser that receives a message in any branch. A role the choice does
not reach stays "same fingerprint only" (conservative). A failure explains itself; a
renumbered unlabelled message is named (`Msg_A_C_1 is now Msg_A_C_2`, "Label them").

Generated: `<P>_Msg.compat() : List((String, String, List(String)))` (fingerprint, role,
accepts) and, for `SessionNode`, `compat_by_role()` keyed by role number.

Baselines: `--protocol-baseline <file>` (repeatable) and `--emit-protocols <dir>` in
`bin/main.ml`. A file is `{format: 1, current, previous}`: the version last built and, when
the last build changed the protocol, the one before, so a rebuild keeps the table (the
comparison is against `current` when this build differs from it, else `previous`). Emission
runs after a clean typecheck, skips stdlib protocols, writes atomically and only when the
bytes change. `--emit-protocols` suppresses the source-level CAS exit (else a warm cache
would never write), and the baselines' digest is in `build_cas_key`. forge
(`Cmd_build.protocol_flags`) passes both on every app build that declares an
`@[endpoints]` protocol, with `.forge/protocols/` as the directory.

## 2. D25: unlabelled steps warn at the step

`Desugar_endpoints.topology_protocols`, set by the driver from the `--topology` digest and
by the LSP (`Analysis`, from `Topology_doc.protocols_used`) before desugaring a `.march`
buffer; `Topology.protocols_used` is the one rule (roles in `[roles]`, protocols in a
pool's written `initiates`), now also used by forge's own per-protocol warning. Each
unlabelled step that is not a branch head warns at the step with its positional tag and a
suggested label.

## 3. Multi-fingerprint offers and formation

`stdlib/session_node.march`. Offer names `ap:<P>/<role>/<fp>/<node>`
(`name_fingerprint` reads one back; an old-form name has none and is treated as unknown), so
two versions of one role are offered side by side. `Offer` carries its `compat` rows.

Formation keeps a session to at most two fingerprints (`ApMix`). `candidates` admits an
offer at the initiator's own fingerprint (if an older one is already in the session, only
for a role whose row accepts it), an older one the initiator's table accepts for its own
role and every role already filled at its fingerprint (the Invite then *vouches* for it),
or an unknown one (possibly newer, which decides by its own table); it orders them own,
older, unknown, local first in each group, and reports how many it skipped.
`offer_verdict` calls `fp_verdict`: same fingerprint, an older one this role's row accepts,
or this offer's own fingerprint vouched for by the newer initiator. The step-11b certificate
check has a marked seam after it. Why pairwise checks suffice: with two versions, a pair is
safe iff the newer side's role accepts the older fingerprint, and whichever side is newer
holds that table (the initiator checks every pair when it is newer; each newer offer checks
the initiator's fingerprint, which is the older one every pair shares, when it is not).
Invite: `[sid, fp, reply, initiator role, vouch]`; 3 elements still decode.

Test, `test/two_node/protocol_mixed_local` (one node, loopback; version 2 built against
version 1's emitted baseline, version 1 played by the same code under its fingerprint):
both fingerprints of Buyer offered on one node; v2/v2 forms and picks `later`; v1 chooser
with v2 receiver forms; v2 chooser with only a v1 receiver is refused before any invite
("1 offer(s) ... were not invited"); v2 receiver initiating to a v1 chooser forms through
the vouch; an unknown v3 is refused by the offer ("protocol differs"). Red when the vouch
clause is removed.

## 4. Hosted access points across a change

`stdlib/topology.march`. `Topology.reoffer(node)` re-opens every open offer with the code
now running: a changed fingerprint opens under its new name (a hosted role with a fresh
actor from its `mk`), and the old offer is retired; an unchanged one is `AlreadyOffered`
and stays. `TopoOpened.stop` runs when a retired offer has drained, which kills its hosting
actor (the actor's epoch holds are then zero, D28/6.1). The placement loop, a task pinned
to the epoch it started in, sees `epoch_draining()` after a deploy and hands over through
the anchor actor (`Respawn`, handled past its marker, so on the new epoch), which runs
`reoffer` and a new loop.

Test, `test/two_node/hosted_protocol_change` (one node): an actor hosts three parked
old-version sessions (holds 1, 2, 3), the version switches, `reoffer` spawns a fresh actor
that serves a new session while the old one holds three, an old-version client is refused,
the three finish one at a time (holds 2, 1, 0) and the old actor is stopped by the tick.
Red (the old actor never exits) with the stop removed.

## 5. `@remote` schema hashes

`Typecheck_caps.schema_hash`: MD5 of a message type's structure (record fields in order,
variant constructors sorted, declared types expanded, back-references for recursion; not
the name), recorded per typed-send site in `March_ast.Json_dispatch.schemas` beside the tag.
`Node.send` / `Node.enqueue` lower to `send_tagged_schema` / `enqueue_tagged_schema`;
`NodeSend.encode_msg_schema` puts a non-empty schema as a 7th `ACTOR_MSG` element;
`Delivery.schema` (`""` from a 6-element frame). Receivers: `Node.accepts` now resolves to
`tag_is_schema` (tag equal, and the schema equal or absent); new witness forms
`Node.accepts_tag`, `Node.schema_matches`, `Node.schema_of`. `@[remote]`'s dispatch, on a
tag match with another schema: when the actor has `<actor>_migrate_msg` taking an old
variant, one arm per one-argument constructor of it, taken when the delivery's schema is
that argument's, decodes, wraps, converts and delivers (a `None` is refused); otherwise
`Err`, which the transport answers with DELIVERY_FAILED. The generated module moves after a
`migrate_msg` declared later than the actor.

Test, `test/native/remote_schema` (both backends): this schema, no schema, the old schema
migrated, migrate returning `None`, an unknown schema, and an actor with no migrate_msg.
`native_node_send_typed_loopback` now shows `schema=sent` on the wire. Red when
`tag_is_schema` ignores the schema.

## 6. Expand/contract (D21)

`forge/lib/protocol_split.ml`: `plan changes builds` is `Unchanged | Breaking | One (receivers'
builds first) | Split (expand, contract)`, split when a build holds both the chooser and a
receiver of the changed choice; `plan_project` reads `.forge/protocols` and the topology's
pools (`pool_roles`), or one build without a topology. Step 10b's `forge deploy --plan`
classifier is not on main; this is the function it calls.

The expand build: `--protocol-expand <P>:<label>` (repeatable, CAS-keyed). The chooser's
`<P>_Msg.role_fingerprint` is the previous fingerprint (every generated runner and access
point now passes `role_fingerprint(role)`), and its `choose_<label>` panics before sending.
Refused without a baseline, or unless the version is the baseline plus exactly that branch.

## Tests

- `test/test_endpoints.ml` +11: rule one (receivers accept, the chooser does not; removal is
  not compatible); renumbering after an inserted branch (incompatible, tag named, label
  suggested); a labelled protocol gaining a branch (compatible, rows for B and C); a grant
  change (same fingerprint, no rows); a changed shared payload; the baseline round trip and a
  rebuild keeping the previous version; `compat()`/`compat_by_role()` generated and
  typechecked; the expand build and its refusals; D25 (at the step's line, branch heads
  quiet, labelled quiet, qualified name). Perturbations: chooser counted as a receiver (2
  red), renumbering explanation off (1 red).
- `lsp/test/test_lsp_topology.ml` +1: the warning on the `.march` buffer, gone without a
  topology.
- `forge/test/test_forge.ml` +5: protocol flags only for a project with a protocol; the split
  for a monolith, for separate pools (receivers first), breaking and unchanged, and
  `plan_project` with no topology.

## Deviations

1. **The network acceptance test is pending.** `test/two_node_pending/protocol_evolve` is
   written: node-b (receiver) patched first, node-a (chooser) second, through
   `test/hcr_deploy.exe` (new: a local-socket `Cmd_deploy_hot.run`, key minting, the
   reload counters). It cannot pass: a hot patch `.so` defines the runtime itself
   (`nm`: `_march_sched_*` external, no undefined `march_` symbol), so code the patch runs
   has a private scheduler and vault registry. The first new-code session kills the process
   (SIGSEGV here; SIGBUS "no green thread running on this scheduler" on origin/main
   504c54c23 with no protocol change at all), and new code cannot see old code's named
   vaults. Filed: [../todos/2026-09-25-hcr-patch-so-private-runtime-copy.md](../todos/2026-09-25-hcr-patch-so-private-runtime-copy.md).
   It is outside `test/two_node/` because CI runs every scenario there.
2. **`Topology.reoffer` after a real deploy reopens with old code.** A role's `open` is a
   closure the old `main` built; closures and entry-module functions are outside the reload
   boundary (only names under the `--hot-reload` prefix and actor dispatch functions are
   reloadable), so the respawned loop calls the old `offer_<R>`, gets `AlreadyOffered`, and
   keeps the old offer. The mechanism is right under unit-epoch resolution (Model B,
   deferred in step 5); today an actor whose handler the deploy replaces can re-offer, as
   protocol_evolve's node-a does. Item 4's test drives `reoffer` with new code building the
   role, which is what it proves.
3. **The schema hash is not "ignored by an old receiver".** A node built before this
   decodes an `ACTOR_MSG` of exactly six elements and refuses seven (as #648's deviation 8
   for `Deliver`), so receivers must be upgraded before senders; frames without a schema
   (every non-typed send) are unchanged.
4. **Migration is matched by shape, not by constructor name.** The plan says "migrate_msg if
   the receiving actor has one for that hash": the dispatch tries each one-argument
   constructor of `migrate_msg`'s old variant whose argument's hash is the delivered one.
   A constructor-name match was tried first and made the generated `send(pid, Bump(x))`
   ambiguous against `V1.Bump` (inside the generated module the current-module preference
   does not apply, and actor constructors have no qualified spelling). The pre-existing
   hazard remains: an `@[remote]` handler constructor named like any constructor elsewhere
   (e.g. `Count` and `DataFrame.Count`) is ambiguous in the generated dispatch.
5. **Two same-named records confuse codec resolution.** In one program, `V1.Hit` and
   `Msgs.Hit` (or two same-shaped records) cannot both be named by `derive Json` dispatch, so
   the fixture names the old shape `V1.OldHit`; across builds (the real case) there is one.
6. **The step-11b seams.** The certificate check is a marked line in `offer_verdict`; the
   Invite's 4th element is the initiator's role as 11b defines it; coordinated with that
   session, which rebases onto whichever lands first.
7. **`@[endpoints]` in a library module does not resolve** (the generated modules are not
   found by bare name), so protocol code cannot be put under a `--hot-reload` prefix that
   way; protocol_evolve keeps it in the entry module and reloads through actor handlers.
8. Items 1 and 2 were committed before the merge (the gate); the merge needed one follow-up
   in the same merge commit (`ALoop` gained #648's `atomic` flag).

## Results

On the final tree (origin/main 0c9336abe merged), this Mac, load 5-12:

| suite | tests | result |
|---|---:|---|
| compiler | 1314 | pass |
| eval | 282 | pass |
| codegen | 632 | pass |
| stdlib | 890 | pass |
| stdlib_march | 74 | pass |
| test_jit | 32 | pass (in the full run and on its own) |
| LSP (lsp, utf16, jsonrpc, incremental, query_cli) | 378, 5, 37, 10, 7 | pass |
| refinecheck | 965 | 964 pass; `audit-baseline` failed on two new, expected lines (the new `native_remote_schema` fixture), regenerated and committed, then passes |

Also: `dune build @forge/test/runtest` (every forge suite, upgrade-from and topology-run
included) passes; the dune-rule fixtures `native_remote_schema` and `interp_remote_schema`
(new), `native_remote_actor_dispatch`, `interp_remote_actor_dispatch`,
`native_node_send_typed_loopback`, `native_topology_place`, `native_topology_hook_timeout`,
`topology_placement` match their goldens; `scripts/check-docs.sh`,
`check-runtime-sources.sh`, `check-actor-rc-stores.sh` pass.

Two-node (`scripts/two-node.sh`): `stream`, `stream_labelled`, `fan`,
`fingerprint_skew`, `topology_move`, every `cluster_ap*` (7), `hosted`, `hosted_restart`,
every `drain_*` (3), and the new `protocol_mixed_local` and `hosted_protocol_change` (three
runs of the latter before the golden was fixed) all pass. `protocol_evolve` is pending
(deviation 1).

Not run: `bench/` (no benchmarked path changed: formation and dispatch run per session or
per remote message, not per step). ASAN was not run.
