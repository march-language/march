# Design: lemmas for hot code reload, actors and choreography

Status: **plan only, nothing built.** Filed 2026-11-04 on `b86c86a63`. Todo:
`specs/todos/2026-11-04-lemmas-hcr-actors-choreography.md`.

Builds on `specs/2026-10-29-refinement-reflection-design.md` (phases 0 to 6 built; phase 7,
`--refine-infer` proposing lemma calls, in progress) and on the language chapters
`specs/lang/lemmas.md`, `refinement-types.md`, `actors.md`, `session-types.md`,
`choreography.md`, and the hot-reload guide `docs/hot-code-reload.md`.

The question: which laws about hot code reload (HCR), actor message passing and
choreographies can be stated as March lemmas (`@[lemma] fn name(...) : {Unit | P}`), which of
them today's reflection proves, what is missing for the rest, and in what order to build it.

## 0. Summary

**Who it is for, decided 2026-11-04 (verbatim): "App developers first".** An app developer
should get these guarantees **without writing a lemma**. They state what must stay true (an
`@invariant`, a refined handler parameter, a protocol) and the compiler proves it or shows a
counterexample. Lemmas are how *we* prove the compiler-owned laws once, in the stdlib. A user
writes one only when their own invariant needs induction over their own functions. §1 turns
this into rules; the phase order in §7 follows it.

**What proves today.** Every row was probed on `b86c86a63` (§2):

| Area | Lemma | Today |
|---|---|---|
| Choreography | `dual_dual`: duality is an involution | **proves** |
| Choreography | `project_dual`: a binary protocol's two projections are duals | **proves**, but only written as an implication (gap G1) |
| Actors | `from_cat`, `enq_other`, `enq_self`: per-sender FIFO on the mailbox model | **proves** |
| Actors | `stale_reply_ignored`, `call_reply_cat`: `Actor.call` correlation | **proves**, once a constructor named like a stdlib one is renamed (gap G2) |
| Actors | `downs_cat`: DOWN counting composes | **proves** |
| HCR | a `migrate_msg` result must meet the new handler's parameter refinement | **obliged, not provable**: the obligation is raised but can't be discharged. Correct (the probe's migration really is unsafe), but it is a warning with no counterexample. And it can't be written at all when old and new messages share a constructor name (gap G4) |
| HCR | `migrate_state` must meet the new state's field refinements | **obliged, not provable**, even when the old field carries the same refinement (gap G5) |

**What needs new machinery** (detail in §6):

| Area | Lemmas it blocks | Machinery |
|---|---|---|
| HCR | migration simulation (H3); a handler invariant whose proof needs a lemma (H4) | handlers as reflected state-transition functions (M3), block facts at a handler's result (M1, todo `2026-11-03-return-contract-ignores-block-facts`) |
| HCR | messages surviving two type changes (H6) | composing `migrate_msg`s (M7). Today the runtime drops such a message (`hcr_route_slow`) |
| HCR | the old version's invariant as the migration's hypothesis | baseline invariants from `.schemas.json` (M2) |
| Choreography | the projections compose back to the global protocol (C4); deadlock freedom (C5) | first-order configuration semantics in a stdlib theory module (M5), no new solver features |
| Choreography | **linking any of it to the compiler** | translation validation of the two OCaml projectors against the March spec (M6) |
| Actors | **linking the model to the C runtime** | trace conformance against `MARCH_TRACE` events (M8): tested, not proved |
| Actors | message refcount ownership | **not a lemma.** It's a property of Perceus and the runtime, checked by `--rc-trace` and `scripts/check-actor-rc-stores.sh`. §4.6 states it as a law and says why |

**Four gaps the probes turned up** in the lemma machinery itself. All four hurt any user, not
only these areas. Each is filed as its own todo:

- **G1.** A lemma hypothesis that calls a reflected function is not assumed.
  `fn h(g : {G | okz(_)}) : {Unit | okz(g)} do () end` is `lemma_unproved` (skip
  `reflect-fuel`), and the hint ("may need more unfolding of `dual`") points the wrong way.
  The same fact written as an implication inside the theorem proves.
- **G2.** A user function or constructor whose name the stdlib also declares (`unwrap`;
  `Reply`, which `Channel.HandleResult` declares) makes the theorem
  `unreflectable-predicate` with no reason given. Only `--reflect-report` says "a name more
  than one declaration could denote". This is the function and constructor sibling of todo
  `2026-11-03-reflect-type-name-clash-with-stdlib`.
- **G3.** `@invariant` with an unsupported expression is dropped with a build warning, and the
  deploy then proceeds unchecked (`bin/main.ml`, the schema writer's `pred_to_string`
  fallback; `docs/hot-code-reload.md` admits it). A guarantee the user believes in but doesn't
  have is the worst outcome for the audience this plan serves.
- **G4.** A `migrate_msg` that keeps a message's name can't build its result:
  `Some(Bump(n))` is `ambiguous_constructor` against the old type's `V1.Bump`, and every
  qualified spelling of the actor's own message is `unknown_constructor`. This is todo
  `2026-10-15-actor-message-ctor-cannot-be-qualified`, and here it hits the most common
  migration there is. Even if it could be written, the refinement checker withdraws a
  contract whose constructor name is shared (fail-closed, `refinement-types.md` "Closed
  2026-09-13"), so the handler's precondition would silently not be obliged.

## 1. How proving this feels to an app developer

The design rule: **the user asks a question about their system, and the build answers it in
one line, with what the answer rests on.** The questions are:

- "Will this deploy break the actors that are running?" (HCR)
- "Can my messages arrive out of order, my replies get mixed up, or a DOWN go missing?" (actors)
- "Can my protocol get stuck, or two roles disagree on what comes next?" (choreography)

### 1.1 Three tiers

1. **Nothing to write.** These laws belong to the compiler and runtime, and are proved once in
   the stdlib:
   - every projection is dual to its peer;
   - the projections compose back to the global protocol;
   - the supported fragment can't deadlock;
   - mailbox ordering, call/reply correlation and DOWN delivery hold, on the runtime model;
   - message tags stay consistent across a deploy.

   The user only hears about one when it fails for *their* program. The message then names
   their protocol, actor or message, not our lemma.
2. **State it, and the checker proves it.** `@invariant` plus `migrate_state` is the model:
   you say what must hold, and a failure comes with a concrete input
   (`old = { count: 1 }`). A refined handler parameter (`on Bump(n : {Int | _ > 0})`) does
   the same for `migrate_msg`. This tier must work in the editor as you type, not first at
   `forge deploy hot`.
3. **Write a lemma.** You only get here when your invariant uses your own recursive function
   (`total(hist) == count`). The step from tier 2 to tier 3 is a cliff today. Phase 7's
   proposals (`--refine-infer`) and hints that name the real cause (G1, G2) are what soften
   it. A tier-2 failure that a lemma would fix should say so, and name the lemma skeleton.

### 1.2 Honest labels

Each guarantee is reported with what it rests on. A bare "proved" next to a statement about
the C runtime would be read as "the runtime is verified", and that would be false.

| Label | Means | Used for |
|---|---|---|
| `proved` | the checker proved it about the code that runs | `migrate_state`, `migrate_msg` and handler bodies: user March code |
| `proved (model) · tested (runtime)` | proved about a March model of the runtime; the runtime is checked against the model by trace conformance | mailbox order, `Actor.call`, monitors |
| `proved (spec) · validated (compiler)` | proved about the stdlib's March projector; the compiler's own projection of this protocol was checked equal to it | projection, composition, deadlock freedom |
| `assumed` | the trust boundary | messages from another node (`refinement-types.md`: remote messages are "stated as that boundary, not enforced across it"); the runtime's refcounting |

`forge hot-reload check` and `march --check --guarantees` (§7, phase B) print one line per
actor and protocol in this vocabulary.

### 1.3 Never silent

An unchecked guarantee is always a diagnostic at the declaration, never a build-log line that
scrolls by. G3 becomes an error, or under `@compat(lenient)` a warning at the `@invariant`
span. A protocol outside the fragment the deadlock lemma covers says so, at the protocol, once
(C5).

## 2. Probes (on `b86c86a63`, `march --check --refine-report-sites=all`)

The probe files are reproduced in short below. Each `Int` stands for a role, label, sender or
correlation id: the logic treats `String` contents as opaque, so the theory modules use `Int`
ids, and the bridge (M6) maps names to ids.

**P1, duality and binary projection: proves.**

```march
type Local = LEnd | LSend(Int, Local) | LRecv(Int, Local)
           | LChoose(Int, Local, Int, Local) | LOffer(Int, Local, Int, Local)
           | LRec(Local) | LVar(Int)
type Global = GEnd | GMsg(Int, Int, Int, Global)          -- from, to, payload, next
            | GChoice(Int, Int, Global, Int, Global)      -- chooser, two labelled arms
            | GLoop(Global) | GVar(Int)

@[lemma]
fn dual_dual(l : Local) : {Unit | dual(dual(l)) == l} do ... end      -- 7/7 paths

@[lemma]
fn project_dual(a : Int, b : {Int | _ != a}, g : Global)
  : {Unit | !binary(g, a, b) || project(g, b) == dual(project(g, a))} do
  match g do
    GEnd -> ()
    GMsg(_, _, _, k) -> project_dual(a, b, k)
    GChoice(_, _, x, _, y) ->
      project_dual(a, b, x)
      project_dual(a, b, y)
    GLoop(k) -> project_dual(a, b, k)
    GVar(_) -> ()
  end
end                                                                     -- 5/5 paths
```

The natural statement, `g : {Global | binary(_, a, b)}` as a hypothesis with
`project(g, b) == dual(project(g, a))` as the theorem, is 2 of 5 paths: the recursive calls'
hypotheses are `reflect-fuel` skips at every fuel. That is G1. The minimal witness is
`fn h4(g : {G | okz(_)}) : {Unit | okz(g)} do () end`, which is `lemma_unproved`.

**P2, the mailbox, `Actor.call` and DOWN model: proves**, 10 of 10 obligations, after one
rename. The rename was G2: first `unwrap` (stdlib `Option`/`Result`), then the constructor
`Reply` (stdlib `Channel.HandleResult`).

```march
type Env = Msg(Int, Int) | Down(Int) | RReply(Int, Int)   -- sender+payload, monitor ref, corr id+value

@[lemma] fn from_cat(s : Int, xs : List(Env), ys : List(Env))
  : {Unit | from(s, cat(xs, ys)) == cat(from(s, xs), from(s, ys))}
@[lemma] fn enq_other(s : Int, q : List(Env), f : {Int | _ != s}, p : Int)
  : {Unit | from(s, enq(q, Msg(f, p))) == from(s, q)}
@[lemma] fn enq_self(s : Int, q : List(Env), p : Int)
  : {Unit | from(s, enq(q, Msg(s, p))) == enq(from(s, q), Msg(s, p))}
@[lemma] fn stale_reply_ignored(id : Int, c : {Int | _ != id}, v : Int, q : List(Env))
  : {Unit | call_reply(id, Cons(RReply(c, v), q)) == call_reply(id, q)}
@[lemma] fn call_reply_cat(id : Int, xs : List(Env), ys : List(Env))
  : {Unit | call_reply(id, xs) != None || call_reply(id, cat(xs, ys)) == call_reply(id, ys)}
@[lemma] fn downs_cat(r : Int, xs : List(Env), ys : List(Env))
  : {Unit | downs(r, cat(xs, ys)) == downs(r, xs) + downs(r, ys)}
```

**P3, HCR: obliged, not provable.** The probe is an actor with
`state { count : {Int | _ >= 0}, hist : List(Int) }` and `on Bump(n : {Int | _ > 0})`.

- `tally_migrate_state(old : { count : Int }) = { count: old.count, hist: Nil }`: the new
  state's `count >= 0` is obliged at the literal and skipped `unreflectable-subject`. With
  `old : { count : {Int | _ >= 0} }` it is still skipped (G5: a refinement on a field of an
  anonymous-record parameter doesn't reach `old.count`).
- `tally_migrate_msg(m : V1.Msg)`, with an old `V1.Bump(Int)`:
  - Written `Some(Bump(n))`, it is `ambiguous_constructor`, and `Some(Tally.Bump(n))` is
    `unknown_constructor` (G4).
  - With the old constructor renamed `OldBump`, `Some(Bump(n))` raises the handler's
    `_ > 0` obligation and skips it `unconstrained-subject`. That verdict is right: the old
    message carried any `Int`.
  - While the name was shared, the handler's own body was `solver-undecided` on
    `count + n >= 0`: the shared name withdrew the `n > 0` assumption.

## 3. Hot code reload

### 3.1 Where the statements live

| What | Place |
|---|---|
| `migrate_state` / `migrate_msg` naming, shape and IO-free checks | `lib/typecheck/typecheck_caps.ml` (`is_migrate_fn_name`, `check_migrate_msg_shape`, `check_migrate_fn_io_free`) |
| the `__hcr` wrapper, `Option` turned into a sentinel | `lib/desugar/desugar_migrate.ml` |
| old message type pinned to the old actor's tags | `lib/tir/migrate_msg_pins.ml`, `Llvm_toplevel.variant_ctor_tags` |
| `@invariant` parse, schema JSON | `lib/parser/parser.mly` (`actor_invariant`), `bin/main.ml` (`actor_invariant_map`, `pred_to_string`) |
| actor state as an inductive invariant, handler parameter contracts | `lib/refinecheck/refine_check.ml` (handler visit, `check_state_literal`), `refine_encode.ml` (actor state as a record sort) |
| marker, `migrate_state` chain, `migrate_msg` at dequeue, epoch holds and deferral | `runtime/march_runtime.c` (`hcr_route`, `hcr_route_slow`, `hcr_defer`, `hcr_advance`), `runtime/march_reload.c` (`resolve_migrate_fn`, `resolve_migrate_msg_fn`) |

HCR is the area closest to today's machinery: **the migration functions are ordinary March
code**, so a lemma about them is about the code that runs. No model or bridge is needed.

### 3.2 Candidate lemmas

Below, `Inv` is a reflected `fn tally_inv(s : TallyState) : Bool` (what M2 lets `@invariant`
elaborate to), and `OldInv` is the same for the old shape.

**H1. A migration preserves the invariant.** Tier 2: the user writes nothing beyond
`@invariant`.

```march
@[lemma]
fn migrate_preserves_inv(old : V1.State)
  : {Unit | !old_inv(old) || tally_inv(tally_migrate_state(old))} do ... end
```

Today the docs say `forge deploy hot` proves this for the `@invariant` grammar's table
(comparisons, `len`, field access). In-compiler, the new state's field refinements are
obliged at the migration's result and don't prove (P3, G5). Missing:
- G5, field refinements of the old record reaching `old.f`;
- M2, an `@invariant` that may call reflected functions, plus the *old* invariant as
  hypothesis;
- M1, if the migration's proof needs a lemma call.

Once those land the compiler generates H1 per actor. The user never sees it unless it fails,
and then gets the counterexample.

**H2. A converted message satisfies the new handler's contract.** Tier 2.

```march
@[lemma]
fn migrate_msg_respects_handler(m : V1.Msg)
  : {Unit | match tally_migrate_msg(m) do
              Some(Bump(n)) -> n > 0
              _ -> true
            end} do ... end
```

Today the obligation is raised at the constructor inside `Some(...)` (P3) whenever old and new
constructor names differ. It's a warning with no counterexample. Missing:
- G4 (resolve the actor message by datatype, as the ctor registry, `#1056`, does for types);
- a counterexample in the HCR diagnostic (refutation already exists for lemmas,
  `specs/progress/2026-11-03-lemma-refutation-and-rewrites.md`; reuse it).

A `match` inside a predicate isn't in the predicate grammar. The compiler-generated form is
one obligation per `Some(C(args))` site, which is what the checker already does.

**H3. Migration is a simulation (the real correctness law).** Handling an old message on the
old code and then migrating gives the same state as migrating first and handling the converted
message on the new code. This is what makes the marker's position harmless.

```march
@[lemma]
fn migrate_commutes(s : V1.State, m : V1.Msg)
  : {Unit | match tally_migrate_msg(m) do
              Some(m2) -> Tally.step(tally_migrate_state(s), m2) == tally_migrate_state(V1.step(s, m))
              None -> true
            end} do ... end
```

Missing:
- M3, `<Actor>.step(state, msg) : State`, a reflected function synthesised from the handlers
  whose state result is pure;
- the old version's handlers, at least as a `step` symbol, from the baseline the deploy is
  checked against (M2's baseline).

This one is tier 3 by nature: many real migrations are *not* simulations on purpose (they
reset a field), so it should be opt-in, `@compat(simulation)`, or stated by the user as a
lemma.

**H4. A handler preserves the invariant, with a lemma.** Tier 2 if no lemma is needed (that
already works: the inductive state invariant closed 2026-09-13). Tier 3 when it is:

```march
on Push(x : Int) do
  List.len_append(state.hist, [x])
  { state with hist: List.append(state.hist, [x]), count: state.count + 1 }   -- needs the fact
end
```

Missing: M1. The handler's result is a tail obligation, the same position as a function's
return contract, and block facts don't reach it.

**H5. Round trip for rollback.** `docs/hot-code-reload.md` "Schema baselines and rollback"
needs a reverse `migrate_state`. The law the user wants is "rolling back loses nothing that
the old version had":

```march
@[lemma]
fn rollback_roundtrip(old : V1.State)
  : {Unit | tally_rollback_state(tally_migrate_state(old)) == old} do () end
```

For plain records this is one unfolding of two non-recursive functions, so it should prove
today once G5's record-parameter handling lands. It needs a stated convention for pairing the
two functions (`<actor>_rollback_state`, or `forge` pairing by schema hash).

**H6. Two message-type changes compose.** `hcr_route_slow` drops an old message when two
message-type changes lie between its epoch and the actor's ("one conversion cannot bridge").
With both deploys' `migrate_msg`s available, the runtime could chain them. The law that makes
the chain safe is H2 for each link. No new proof machinery is needed; this is M7, a runtime
and deploy change, listed here because H2 is what licenses it.

**H7. Tag consistency.** "Actor-message tags are a stable function of the qualified
constructor name" (`migrate_msg_pins.ml`). This is a property of two *compiler outputs*, not
of a March function, so it **isn't a lemma**. Check it at deploy time instead: compare the
baseline's `.schemas.json` handler list and tags with the new build's for every constructor
both name (`forge deploy hot` already refuses a mismatched old type). Add a
`determinism-oracle`-style test that the tag function ignores declaration order.

## 4. Actor message passing

### 4.1 Where the statements live

| What | Place |
|---|---|
| `send`, mailbox enqueue | `runtime/march_runtime.c` `march_send`; interpreter `lib/eval/eval_builtins.ml`; operational rules `specs/lang/core-march.md` §4.10.2-4.10.5 |
| `Actor.call` correlation and deadline | `march_runtime.c` `march_actor_call`, `march_actor_call_unwrap`; `stdlib/actor.march` `call`, `reply`; interpreter `actor_call` |
| monitors, `Down` bypassing the mailbox limit | `march_runtime.c` `march_monitor`, `march_demonitor`, the death path; `specs/lang/actors.md` "Monitoring Actor Death" |
| HCR deferral and replay under an epoch hold | `march_runtime.c` `hcr_defer` |
| stash and become | `specs/lang/actors.md` "Stash and Become" |
| refcount word 0 | `march_incrc`/`march_decrc`; `scripts/check-actor-rc-stores.sh` |

### 4.2 The model and the bridge

The mailbox lives in C (compiled) and OCaml (interpreter). No March function implements it,
so a lemma can only be about a **March model**. The plan is a stdlib module,
`Actor.Theory` (`stdlib/actor_theory.march`), holding:
- the `Env` type and the first-order model functions of P2;
- `enq`/`deq`, `bounded_enq(limit, q, e)` (drop on full, except `Down`), and `defer`/`replay`;
- the lemmas below, proved and listed in `stdlib/lemmas.verified`.

The model is tied to the runtime by **trace conformance** (M8): a test mode records each
actor's enqueue and dequeue events (todo `2026-10-11-observe-trace-actor-events` is the hook),
replays them through the model, and checks the dequeue order the runtime produced is the one
the model computes. That makes these guarantees `proved (model) · tested (runtime)` (§1.2),
never more.

### 4.3 Ordering (A1), provable today

- `from_cat`, `enq_other`, `enq_self` (P2): one sender's messages keep their order, and
  another sender can't reorder them.
- **A1b. Deferral keeps order** (the epoch-hold path: newer-format messages "are set aside and
  replayed, in order"):
  `fn replay_order(s : Int, held : List(Env), q : List(Env)) : {Unit | from(s, cat(held, q)) == cat(from(s, held), from(s, q))}`.
  This is `from_cat` itself, once `replay` is modelled as putting `held` in front of `q`. The
  work is in confirming that *is* what `hcr_defer` does.
- **A1c. A call inside a handler keeps the queue** (`actors.md`: messages arriving during an
  `Actor.call` "stay in its mailbox, in arrival order"). The waiting loop's `call_reply`
  consumes only the matching `RReply`. A lemma `call_keeps_others(id, q)`:
  `{Unit | from(s, without_reply(id, q)) == from(s, q)}`. Provable today by the same induction.
- **A1d. Stash.** `become` replays the stash in front. The same shape as A1b.

### 4.4 `Actor.call` (A2), provable today

`stale_reply_ignored` and `call_reply_cat` (P2) are the correlation law: a late reply from an
earlier call can't answer this one. The timeout half is a model of the deadline:
`fn outcome(deadline : Int, t_reply : Int) : Result(Unit, Unit)`, with the law
`{Unit | outcome(d, t) == Ok(()) || t > d}` (one unfolding). The interpreter's documented
difference (it can't preempt, so the caller is released late) is a statement about elapsed
time, which the model doesn't have. It stays prose.

### 4.5 Monitors (A3), provable today on the model

- `downs_cat` (P2).
- **At most once:** `{Unit | downs(r, deliver_death(q, r, target)) <= 1 + downs(r, q)}`, plus
  the runtime half: `march_demonitor` and the death path each remove the monitor node, so the
  model's `deliver_death` is idempotent per ref. Proved on the model, tested by M8.
- **Never lost to a full mailbox:**
  `{Unit | downs(r, bounded_enq(limit, q, Down(r))) == downs(r, q) + 1}` for every `limit`,
  where `bounded_enq` drops an ordinary message on a full queue. One case split.

### 4.6 Message ownership (A4): a law, not a lemma

The law: **sending a message transfers the sender's one reference to the receiver's mailbox;
the send itself performs no increment and no decrement on the message, and a linear payload is
unreachable from the sender afterwards.** It is about Perceus's inserted
`march_incrc`/`march_decrc`, the runtime's mailbox and drop glue: none of that is a March
function, and none of it is in the logic. Two checks already enforce it:
- the linear type rules (`specs/lang/linear-types.md`) for the linear half;
- `--rc-trace` and `scripts/gc-trace-report.py` (every object live at exit, with its inc/dec
  history), plus `scripts/check-actor-rc-stores.sh`, for the refcount half.

The plan adds one regression fixture per send path (`send`, `Actor.cast`, `Actor.call`'s
envelope, `Node.send`, `migrate_msg`'s consumed message, the `None` drop) that asserts zero
live objects at exit under the RC trace. Writing a March model of ownership would prove
something about the model while the real risk is in codegen, so it isn't planned.

## 5. Choreography and session types

### 5.1 Where the statements live

There are **two projectors**, and both are OCaml:

| What | Place |
|---|---|
| projection for `Chan(Role, Proto)`, binary duality check, multiparty send/recv consistency | `lib/typecheck/typecheck_session.ml` (`project_steps`, `dual_session_ty`, `project_protocol`) |
| projection for `@[endpoints]` and choreographies, with merge, crash branches and `atomic` loops | `lib/desugar/desugar_endpoints.ml` (`project`, `merge`) |
| channel runtime (interpreter) | `lib/eval/eval_session.ml` |
| session runner, access points, cluster node | `stdlib/session.march`, `session_ap.march`, `session_node.march` |
| wire tags, fingerprint compatibility | `specs/lang/choreography.md` "Changing a protocol" |

Notes from reading them:
- `project_protocol`'s multiparty check is an *existence* check: each global message has some
  `SMSend`/`SMRecv` somewhere in the right projection. It isn't order-sensitive and isn't a
  pairwise duality. C3 below is the law that should replace it.
- The two projectors implement the same rules twice ("Same rules as `project_steps`"), and
  nothing checks that they agree. M6 makes the stdlib spec the referee for both.

### 5.2 The theory module and the bridge

A stdlib module `Session.Theory` (`stdlib/session_theory.march`) holds `Global`, `Local`,
`project`, `dual`, `merge`, a configuration semantics, and the lemmas. Roles, labels and
payload types are `Int` ids. Choice is n-ary over a branch list, a datatype that refers to
`Local` through `List`: reflection reflects a mutual SCC as a whole (reflection design §2.1),
and a mutually recursive lemma pair is the induction. Probe this first (phase C0). If it is
missing, the fallback is the binary-choice encoding of P1, which already proves.

**M6, translation validation.** For each protocol the program declares, the compiler emits
the protocol as a `Session.Theory.Global` value and each of its own projections (from both
projectors) as a `Local` value. It then checks `project(g, r) == emitted_r` by **evaluating
the stdlib's `project` in the interpreter**. These are ground terms, so evaluation decides
them, and SMT fuel (at most 8) would be far too small for real protocols. A mismatch is a
compiler bug, reported as an internal error naming the protocol and role. Once each
projection is validated, every proved lemma of `Session.Theory` holds for that protocol by
instantiation. That is what `proved (spec) · validated (compiler)` means. It is the same shape
as the lemma miscompile check in `forge test` (`specs/lang/lemmas.md` "Catching a
miscompile").

### 5.3 Candidate lemmas

**C1. Duality is an involution.** `dual_dual` (P1). **Proves today.**

**C2. A binary protocol's projections are dual.** `project_dual` (P1). **Proves today** in
implication form. After G1 is fixed it can be written with the hypothesis
`g : {Global | binary(_, a, b)}`.

**C3. Pairwise duality, multiparty.** For roles `p != q`, the part of `p`'s projection that
talks to `q` is dual to the part of `q`'s that talks to `p`:

```march
@[lemma]
fn project_pairwise(g : Global, p : Int, q : {Int | _ != p})
  : {Unit | !well_formed(g) || restrict(project(g, p), q) == dual(restrict(project(g, q), p))} do ... end
```

`restrict(l, q)` keeps the actions with peer `q`. Projecting a choice onto a bystander uses
`merge`, so the induction needs a `restrict_merge` lemma, and `well_formed` must include the
merge rule's side condition (a bystander whose arms differ must learn the label from its
first receive). Missing: no solver feature, but real proof work. Expect `assert` steps at
`merge`. This is the law that should replace the existence check in `project_protocol`.

**C4. The projections compose back to the global protocol.** No quantifiers are available
(lemmas.md "No quantifiers"), so composition is stated *constructively*: a schedule function
picks the global protocol's next action, and running the configuration of all projections on
that schedule produces the global protocol's trace.

```march
@[lemma]
fn compose(g : Global, roles : List(Int))
  : {Unit | !(well_formed(g) && loop_free(g) && covers(roles, g))
            || run(config(g, roles), schedule(g)) == Done(trace(g))} do ... end
```

`config(g, roles)` pairs each role with `project(g, role)`; `run` is the synchronous
semantics, first-order and terminating on `loop_free`. The proof is induction on `g` with one
step lemma per head constructor (subject reduction):
`step(config(g, roles), head(g)) == config(advance(g), roles)`. A bystander's projection is
unchanged by a step it isn't in, and that is the key auxiliary lemma (`project_skip`). Loops
are covered by unrolling once: the configuration after one iteration is the starting one
again, an equality of finite terms, not a coinduction. Missing: M5, the configuration
semantics, plus the size of the proof. No new solver features.

**C5. Deadlock freedom for the supported fragment.**

```march
@[lemma]
fn progress(g : Global, roles : List(Int))
  : {Unit | !(well_formed(g) && covers(roles, g)) || is_end(g) || enabled(config(g, roles), head(g))} do ... end
```

Together with C4's step lemma, every configuration reachable *on the schedule* is again of the
form `config(g', roles)`, so it either finished or can step. **The fragment is**:
- synchronous delivery (the runner's per-connection FIFO plus "holds it until C has asked for
  B", `choreography.md` "Message order", which is what makes asynchrony observationally
  synchronous here; M8-style trace conformance checks that claim);
- no crash branches;
- every bystander informed.

Crash branches (`ProtoCrashOr`, `LRecvCrash`) are the next extension. A protocol outside the
fragment is told so once, at the protocol (§1.3). Not covered, and said so: the F6 gap in
`session-types.md` (driving both ends of a `Chan` in one thread in the wrong order). That is
a scheduling property of the user's program, not of the protocol.

**C6. Tag stability for compatible changes.** `choreography.md` says a `choose` that gains a
branch is compatible only if no unlabelled message renumbers. Law: for the old and new
`Global`, `tags(old) ⊆ tags(new)` with equal payloads, where the only new tags are inside the
new branch. This is a first-order function on two ground terms, so M6's evaluator checks it
at deploy time, and the stdlib proves `tags_extend`, once, for the "add a labelled branch"
edit.

## 6. New machinery

| # | What | Unblocks | Size |
|---|---|---|---|
| G1 | assume a lemma parameter's refinement when it calls a reflected function (as the implication form already does) | C2 natural form, every hypothesis-style lemma | small; encoder |
| G2 | a predicate's `unreflectable-predicate` names the R6 reason (the clashing declaration) at the theorem; then resolve the user's own declaration (current-module rule) | any lemma about a function or constructor named like a stdlib one | small (message), medium (fix) |
| G3 | `@invariant` outside the grammar is an error at the attribute, never a silent drop | H1 trust | small |
| G4 | actor message constructors resolved by datatype; a qualified spelling; contracts not withdrawn for a constructor shared by an old type and the actor | H2 in the common case | medium; todo `2026-10-15-actor-message-ctor-cannot-be-qualified`, ctor registry `#1056` |
| G5 | a field refinement on an anonymous-record parameter reaches `old.f` | H1, H5 | small to medium |
| M1 | block facts reach a function's return contract and a handler's result obligation | H4, H1 with lemmas | medium; todo `2026-11-03-return-contract-ignores-block-facts` |
| M2 | `@invariant` elaborates to a reflected `<actor>_inv(state) : Bool`, which may call reflected functions; the baseline's invariant (from `.schemas.json`) is the migration's hypothesis | H1, H3 | medium |
| M3 | `<Actor>.step(state, msg) : State`, a reflected function from the handlers whose state result does not depend on an effect's value (`send`/`println` in statement position erased in the logic copy; `receive`, `Actor.call` results, `self()` block). Needs its own soundness table and RED controls, as phase 5's had | H3, handler invariants stated as lemmas | large |
| M5 | `Session.Theory`: `Global`, `Local`, `project`, `merge`, `restrict`, `config`, `run`, `schedule`; mutual-SCC lemmas probed first | C1-C6 | medium (code), large (proofs) |
| M6 | translation validation: emit each protocol and both projectors' outputs as `Session.Theory` values; check by interpreter evaluation | the link from C1-C6 to the compiler | medium |
| M7 | chain two deploys' `migrate_msg`s instead of dropping (`hcr_route_slow`) | H6 | medium; runtime |
| M8 | trace conformance: actor enqueue/dequeue/monitor events replayed through `Actor.Theory` | the link from A1-A3 to the runtime | medium; depends on todo `2026-10-11-observe-trace-actor-events` |

## 7. Phases, app developers first

Each phase follows the reflection design's conventions (§10 there): a fixture that goes RED
without the rule, ledger triples asserted (never exit codes), a progress file, a
`CHANGELOG.md` bullet, and `specs/lang/` updated, then `scripts/gen-lang-docs.py`.

**Phase A: never silent, and the honest failures (tier 2 works).** G3, G5, G4, and HCR
counterexamples for H1 and H2 (reuse lemma refutation). Then H1 and H2 run on every build of
an actor with `migrate_*` (not only at `forge deploy hot`), so the editor shows them. Done
when P3's two skips become a proof (correct migration) or a counterexample (the probe's
unsafe `Bump`), and an unsupported `@invariant` is an error.

**Phase B: the guarantee report.** `march --check --guarantees` and `forge hot-reload check`
print one line per actor and protocol in §1.2's vocabulary. This phase is cheap and makes
every later phase visible to the user.

**Phase C: choreography laws for free.** C0, probe mutual-SCC lemmas over an n-ary branch
list. Then M5 with C1 and C2 (already proved in P1's encoding), M6 for both projectors, then
C3, then C4 and C5 for the fragment. The user writes nothing; a protocol gets
`deadlock-free (fragment)` or one note saying why not. C3 replaces `project_protocol`'s
existence check once validated.

**Phase D: actor model and conformance.** `Actor.Theory` with A1-A3 (P2's lemmas, proved
today), M8 trace conformance in the native test suite, and A4's RC-trace fixtures. The report
gains `proved (model) · tested (runtime)` lines.

**Phase E: lemma ergonomics (tier 3).** G1, G2 and M1. These help every lemma author, and are
also what H4 needs. G1 and G2 are small and could go earlier if a phase above trips on them;
they are listed here because no app-developer guarantee depends on them once the compiler
writes the lemmas itself.

**Phase F: simulation and deploy depth.** M2's baseline invariants, M3 handler reflection,
H3 behind `@compat(simulation)`, H5 rollback round trip, M7 with H6, and C6's tag check at
deploy.

## 8. Open questions

1. **H3's opt-in.** Is the simulation law the default (and a migration that resets a field
   says so), or opt-in? The default is the stronger guarantee, but many correct migrations
   would fail it.
2. **Where the old version comes from.** H3 and M2 need the old handlers and invariant. Is
   the baseline `.schemas.json` enough (invariant text and handler shapes), or does the deploy
   checker need the old source (the old build's logic symbols, D17 hashes)?
3. **C5's synchronous claim.** The per-connection FIFO plus "hold until asked" argument should
   be a theorem of `Session.Theory` (asynchronous semantics simulated by synchronous on
   well-formed protocols), not an assumption. Is that worth phase C, or is M8 conformance
   enough at first?
4. **One projector or two.** Once M6 validates both OCaml projectors against the same spec,
   should `typecheck_session.ml` call `desugar_endpoints.ml`'s (or the reverse), so that there
   is one implementation to validate?
