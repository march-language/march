# Distributed deploys, build step 4: per-role grants as values, authority report, scripted and chaos peers

**DONE 2026-09-22, minus D35** (`ClusterHandle` as `Cap(Cluster.Live)`, which touches
`stdlib/cluster_node.march`; it stays open as
[2026-09-22-dd-step04-cluster-live-cap.md](../todos/2026-09-22-dd-step04-cluster-live-cap.md)).
Parent: [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
sections 2, 7.1, 7.2, II.2, D2, D34, D36. Four commits, in the plan's order.

## 1. `role R needs cap, ...` in protocols

`ProtoRoleNeeds of name * name list * span` (each path dot-joined, keeping the path's
span). `role` is a SOFT keyword on the `Token_filter` demotion mechanism, kept only
before an uppercase name: session code names variables `role` throughout, so a hard
keyword was never an option. The typechecker's `check_role_needs` (beside
`check_crash_branches`) requires the line to be top-level and before the first message
step, to name a role of the protocol once, and every path to be a known capability with
`needs`' own did-you-mean (Check 0's `suggest_cap`); it records the grant into the new
`env.role_grants : (proto * role) -> (paths, span)`.

The generator ignores the line, so `fingerprint_of` cannot see it: a grant is about the
role's code, not the wire. Pinned by `grants_not_in_fingerprint` (no grants, one grant,
another grant: three equal digests). Grammar corpus `p39`.

## 2. Grants as values (D34)

`run_module` takes `~grants`; a granted role's body type is
`(Cap(Session.Live), Cap(P1), ..., Entry) -> Yield`, paths in declaration order. Every
front narrows from its `io` with `cap_narrow` (accepted by `check_cap_narrow_sites`
because `IO` subsumes every node) and passes them; the hosted fronts thread them through
`start(s, caps...)` / `start(sid, s, caps...)`. A role with no line keeps the old shape
byte for byte (`ungranted_body_type_unchanged`). The role module declares the grant paths
in its own `needs`, since its peers (part 4) name `Cap(P)` in their signatures.

The `Entry` alias the todo also listed had already shipped on 2026-09-21
([2026-09-21-choreography-entry-state-alias.md](2026-09-21-choreography-entry-state-alias.md)),
with the linearity and collision checks pinned there.

## 3. `check_role_grants` and `--dump-role-authority`

Next to `check_main_grant`. Roots: every call of a runner front of a granted role,
found by walking `env.fn_row_bodies` (`run_R`, `cluster_R`, `offer_R`, `initiate_R`: the
body; `host_R`, `host_R_or`, `offer_hosted_R`, `cluster_hosted_R`: `start`, `deliver`,
`cancel`, and the actor behind `host` when it is `spawn(A)` or a variable bound to one in
the same function). Each callback gets a synthetic row key, own caps = the builtins its
body calls, refs = its free variables plus spawned actors, solved by `Cap_rows.solve`
over a COPY of the tables. Two things about the key are load-bearing: it carries the
calling function's module prefix, so the solver's owner-prefix-first resolution reads
bare references the way the calling code did; and it uses `@` and `/`
(`role@Stream_Run/run_Cons:29:75`), which no identifier can, so it cannot shadow a
function. `cap_reach_chain` gained optional table arguments for the same reason.

The message mirrors `main`'s:

```
Role `Stream.Cons` is granted `Cap(IO.Console)` (`role Cons needs IO.Console`), but the
body passed to `Stream_Run.run_Cons` reaches `IO.FileWrite` (reached from the body:
body → cons → save). A role's grant bounds everything its code reaches, as `main`'s
grant bounds the program.
help: add `IO.FileWrite` to `role Cons needs ...` in protocol `Stream`, or remove the use.
```

Rule 4 (role grant ⊆ `main`'s grant) is a check on the parsed sets, reported at the
grant line. As G2 recorded, amplifying a narrowed cap is already a type error, so the
walk is the second line of defence, not the only one; the comment says so.

`--dump-role-authority` (implies `--check`) prints per root the grant, the IO caps
reached, the functions the reachable code references as values and the actors it spawns
or hosts, each with its row. A report, not a check; it exists so D1's delegation is
visible.

Witnesses: six CLI cases in `test/test_endpoints.ml` (violation with chain, a named
function as the body, widened grant accepted, wider than `main`, hosted actor charged
through `host`, the report); corpus `accept/t291`, `reject/t292`.

## 4. Scripted and chaos peers (D36)

Per role module: `type Step` (one constructor per message the role sends
(`Send_<Ctor>(payload)`), per choice (`Choose_<label>(payload)`), per message it receives
(`Expect_<Ctor>(payload -> ())`) and per crash branch (`Expect_crash_<name>(Crashed_<R> ->
())`)), `step_name`, one private `script_<State>` and `chaos_<State>` per state, and the
public `script(s, caps..., st, steps)` and `chaos(s, caps..., st, seed, gens...)`, both
bodies of the role's type.

**Script.** Each state's walker matches the next step against what the state can take;
a receive hands the payload to the step's callback and continues in the callback; an
offer installs the expected branch's callback and a panicking one for every other
branch. A mismatch, a script that runs out, or one that goes on after the protocol ended
PANICS with the state, what was expected and what came (`Stream, role Cons: script: in
state S_recv_Msg_Prod_Cons_1 expected Expect_Msg_Prod_Cons_1, but the next step is
Choose_more`). The state is consumed on the panic path by matching it, since the panic
never returns but linearity is static. The wrong-step arm is emitted only when the
state's own arms leave a `Step` constructor uncovered, or the checker reports it
unreachable (the `cli_no_unreachable_catch_all` pin caught this).

**Chaos.** The walker threads a `Gen.GenRng` (`Random.seed(seed)`; `Random.Rng` and
`Gen.GenRng` are the same record) through sends and choices; a receive passes it into
the callback. Choices: `Gen.int(0, n-1)`. Crash points: the ctors this role sends under
`or crash`, and the heads of a `choose` by this role with a `crash` branch
(`crash_ctors_of`, read from the annotated steps because the crasher's own projection is
a plain send); there `Gen.int(0, 3) == 0` makes the peer `leave_<state>` instead. Over
the in-process transport a role that left is gone, so a peer waiting on it with a crash
branch takes it (Logging: 13 of 50 seeds, 13 crash branches); over `SessionNode` a leave
cancels the peers, and a real crash stays the two-node harness's `kill_node`.

**The rule for user payload types (the plan's open question).** The chaos peer takes one
`Gen.Generator(T)` parameter per distinct non-builtin type the role SENDS, in order of
first appearance, named `gen_<T>` (`gen_<T>_2` for a second instantiation of the same
head; keyed by the printed type, so `Box(Int)` and `Box(String)` are two). Explicit
rather than looked up by name: a generated module cannot call a function its enclosing
module defines after it (the interpreter binds nested modules eagerly and fails with
"stub called before initialisation", measured), and the generated modules come first. A
missing generator is an ordinary arity/type error at the `chaos` call, whose expected
parameter is named after the type. Built-in payloads (`Int`, `Bool`, `String`, `Float`,
`Bytes`, `List`, `Option`, `()`, 2- and 3-tuples) have generators in the walker. A
`derive Gen` would replace the parameters one day; it is not needed for this.

**Acceptance:** `test/session/stream_peers.march`, both backends against one golden:
scripted Cons against the real Prod and scripted Prod against the real Cons; scripted A
and B against the real Fan C; chaos Stream for 50 seeds each way and chaos against chaos
(300 of 300 sessions closed, no cancels, no stalls); chaos Fan, all three roles, 50 seeds
(150 of 150); chaos Logging with a may-crash C (37 normal, 13 crashed, 13 crash branches,
every session decided). No sockets. The mismatch panics are pinned by
`cli_script_mismatch_panics` and `cli_script_runs_out_panics` in `test/test_endpoints.ml`.

## Docs

`specs/lang/choreography.md`: "Writing a protocol" (the line), "Per-role grants" (the
type, the check, the report), "Scripted and chaos peers"; `specs/lang/capabilities.md`
cross-reference from the grant section; `docs/` regenerated. `CHANGELOG.md` `### Added`.
