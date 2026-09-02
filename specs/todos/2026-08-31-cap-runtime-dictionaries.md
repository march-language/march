# Capabilities: optional runtime dictionaries on `Cap(X)` (tail-resumptive only)

`[P3]` Design pinned 2026-08-31; reviewed end to end 2026-09-02.

**Everything except the session transport has landed** (#388, #389, #392,
#397). `SessionOps` — this design's payoff case — landed as `stdlib/session.march`
on 2026-09-02, after a same-day detour through a "language limitation" that
turned out to be a spelling error in this document's own tooling (recorded
below, kept because the detour is the instructive part).

This file is a design record AND a history. Sections marked **(history)** are
kept because the errors in them were instructive; they are not current claims.
The current truth is the Status table and the "What blocks `SessionOps`"
section, and nothing else in the file should be read as overriding them.

## Status

| slice | state |
|---|---|
| `proof cap X with T` declaration + validation | **landed** |
| `cap_impl` / `cap_dict` typing | **landed** |
| The gate (declaring-module; `--test` for IO caps) | **landed** |
| Interpreter runtime + dictionary dispatch | **landed** (#388) |
| Compiled (LLVM) runtime | **landed** (#388) — compiled/interpreted parity pinned |
| IO-capability dictionary SHAPES (derived) | **landed** (#389) — `march --emit-io-ops` |
| Compiler-inserted capability passing (`--test` builds) | **landed** (#389) — analysis + threading + dispatch wrappers, in TIR |
| `with_cap` binding site; `cap_ops_empty` base | **landed** (#389) |
| Mocking an IO capability, end to end | **landed** (#389); three CI fixtures under `test/cap_mock/` |
| Actor handlers reached (capture at spawn) | **landed** (#397) — one capability per actor |
| `--test` in the CAS cache key (pre-existing bug) | **fixed** (#389) |
| Session transport dictionary (`stdlib/session.march`) | **landed** (v1) — `test/session/stream_replay.march` replays `Stream` deterministically on both backends |

Tests: `test/test_cap_dict.ml` (28 cases, `cap_dict` in `run_compiler`) and
three compiled fixtures under `test/cap_mock/` (`cap_mock_io`,
`cap_mock_clock`, `cap_mock_actor`), each proved non-vacuous by disabling the
mechanism it exercises and watching it fail. The runtime cases are the
load-bearing ones: one dictionary proves dispatch reaches it, but only TWO
dictionaries on one capability distinguish a swap from a hard-coded
implementation, and the no-dictionary case pins the path every capability that
exists today takes. `cap_mock/` fixtures stay OUT of `test/native/`, whose
IR-verify sweep compiles without `--test`.

### What landed, concretely

- `lib/ast/ast.ml` — `DProofCap of name * name option * span`.
- `lib/parser/parser.mly` — `proof_cap_dict`. **Adds exactly one shift/reduce
  conflict (10 -> 11), verified by running menhir on both grammars.** The
  ambiguity is `repl_sequence`'s first set containing `WITH`, not this rule's
  shape; menhir resolves by shifting, which is the wanted reading. Documented at
  the rule.
- `lib/format/format.ml` — the `with` clause round-trips (dropping it would
  erase a capability's dictionary type on every `--fmt`).
- `lib/typecheck/` — `env.cap_dicts`, `resolve_cap_dict_type`, the `cap_impl`
  and `cap_dict` arms in `infer_expr`, and the `check_cap_dict_decls` /
  `check_cap_impl_sites` sweeps.
- `lib/eval/eval.ml` — a capability is either `VUnit` (the sentinel, i.e. null)
  or the dictionary record itself. No new value constructor.
- `lib/tir/cap_passing.ml` — the capability-passing pass (analysis, threading,
  dispatch rewrite, `with_cap`, spawn-site capture).
- `lib/typecheck/io_ops_gen.ml`, `cap_dict_resolve.ml` — derived IO dictionary
  shapes and their resolution.
- `runtime/march_runtime.c` — `march_cap_impl` / `march_cap_dict` /
  `march_mint_cap`, and `march_actor_meta.spawn_cap` with its accessors.

### The compiled representation costs nothing, and the RC hazard dissolved

Both facts were found by measuring, not by reasoning, and both are load-bearing
enough that a codegen refactor must not lose them (pinned by
`test/native/cap_dictionary.march`).

**`cap_dict` is the identity function.** `Option` is niche-encoded — `None = 0`,
`Some(x) = x` (`lib/tir/repr.ml`) — and a capability is already null-or-pointer,
so the `Option` that `cap_dict` returns is bit-identical to its argument. There
is no encoding step, no allocation, and no tag. `cap_impl` returns its second
argument; `cap_narrow` was already `return cap;`.

**The RC hazard this document called "the single highest-risk implementation
detail" does not exist in any reachable shape**, and the way that was established
matters more than the conclusion:

1. An inc/no-inc A/B on a 2M-iteration loop was IDENTICAL (130MB RSS both ways),
   so the obvious control proved nothing. Never trust that as a green.
2. `live_allocs()` (a builtin over the runtime's own live-object gauge) showed
   both variants leaking exactly 2 objects per cycle — but so did a CONTROL with
   no capabilities and no dictionaries anywhere, just a record holding a closure
   in a loop. That is pre-existing record behaviour (`needs_rc (TRecord) = false`
   — Perceus never RC-frees the aggregate), not this feature.
3. `--dump-tir` settled it: Perceus emits **no dec on `cap_impl`'s result** and
   **no dec on `cap_dict`'s result** in either reachable match arm. So an inc in
   either shim is an over-count.
4. `cap_narrow` is the one place a dec on the result IS emitted — and a
   dictionaried capability provably cannot reach it: `cap_narrow` may not produce
   a proof capability (`typecheck_unify.ml`'s forge arm) and an IO capability
   cannot carry a dictionary (`check_cap_impl_sites`). So the inc there would be
   an untestable guess baked into the runtime, and is deliberately absent.

**Item 4 was re-answered on 2026-09-02**, once IO capabilities could carry
dictionaries under `--test`. A dictionaried `Cap(IO.Console)` passed through
`cap_narrow` and used on both sides — the exact shape item 4 worried about —
runs compiled with no RC abort, the mock propagates through the narrow, and
`live_allocs()` shows no growth attributable to it. **Verified by execution;
the emitted RC ops for this specific shape were not audited**, so treat it as
"not observed to fail" rather than "proved balanced". If a dictionaried
capability ever aborts with an RC underflow, this is the first place to look.

### `mint_cap` needed its own symbol

It aliased `march_cap_narrow`, i.e. it returned its argument. A mint produces a
NEW capability rather than an attenuation, so it must not inherit the dictionary
of the `Cap(IO)` it was minted from — the interpreter already got this right by
returning the sentinel. The alias agreed with the interpreter only because a
`Cap(IO)` is always NULL today; the moment one can carry a dictionary the two
backends diverge silently, compiled inheriting it and interpreted not. Now
`march_mint_cap`, and witnessed by the `plain` line of the native golden.

### Two things the implementation changed about the design

**1. `cap_narrow` in the interpreter was returning `VUnit` and discarding its
argument.** Harmless while every capability was `VUnit`; it would have silently
dropped the dictionary across every narrow. Now the identity — which is what
`march_cap_narrow` has always been on the compiled side.

**2. (history) Mocking an IO capability was unreachable at this point**,
because `println : String -> ()` never consumes its capability, so a dictionary
attached to `Cap(IO.Console)` was never consulted. The sentence that followed
here — "closing it needs the cap-first migration of the 91 builtins" — turned
out to be the wrong conclusion: the compiler can insert the capability passing
itself in `--test` builds, and does (#389). See "Making IO mocking reachable".
`impl_io_cap_test_build` now pins the OPPOSITE of what it originally pinned:
that `--test` admits `cap_impl` on an IO capability.

## The gap

`Cap(X)` is an opaque unit sentinel with zero runtime content:

- `lib/eval/eval.ml:2650` — "at runtime caps are opaque unit sentinels";
  `root_cap` is `VUnit`, `cap_narrow` returns `VUnit` *discarding its argument*,
  and `mint_cap` is a no-op alias of it.
- `lib/tir/llvm_emit.ml:358` — `root_cap` emits `ptr null`.
- `lib/tir/llvm_builtins.ml:843-848` — `cap_narrow` calls `march_cap_narrow`,
  which is `return cap;` (`runtime/march_runtime.c:6541`); `mint_cap` reuses the
  same symbol as a "runtime-erased alias".
- `specs/lang/capabilities.md` §Runtime behaviour states the guarantee: all
  `Cap(X)` values are runtime-erased, compile to `null`, no allocation.

So a capability proves permission but cannot change what an operation *means*.

Give `Cap(X)` **optional** dictionary content — a record of the operations the
capability authorizes — so an implementation can be swapped at a binding site.

**Surviving motivation is exactly three things: mocking, tracing/interception,
transport swapping.** Do not re-motivate this with retry, timeout, rate-limiting
or fault injection: those are covered by supervision/`monitor`,
deadline-extended suspension, and session cancellation respectively.

## Method used to pin the shape

The failure mode here is designing the dictionary before knowing what a future
protocol projector would need to emit. So the shape was derived, not chosen: a
Maty-style event-driven endpoint was hand-written for an existing March
`protocol`, and the set of operations that code calls IS the dictionary.
Anything it does not call is not an entry. The artifact is reproduced in full
below.

## Deliverable 1: the hand-written endpoint artifact

Paper artifact — it does not compile, and several names in it do not exist.

```march
-- Source protocol: `Stream`, verbatim from
--   specs/lang/types/accept/t105_loop_stop_two_iterations_close.march
-- chosen because it is the richest protocol declared anywhere in the tree:
-- loop + choose + stop, i.e. recursion AND label dispatch AND termination.
--
--   protocol Stream do
--     loop do
--       Prod -> Cons : Int
--       choose by Cons:
--         more -> Cons -> Prod : Bool
--         done -> Cons -> Prod : Bool
--                 stop
--       end
--     end
--   end
--
-- Projections computed by lib/typecheck/typecheck_session.ml (project_steps);
-- binary protocol, so SSend/SRecv and no MPST merge:
--
--   Prod : Rec X. Send(Int, Offer { more: Recv(Bool, X), done: Recv(Bool, End) })
--   Cons : Rec X. Recv(Int, Choose{ more: Send(Bool, X), done: Send(Bool, End) })
--
-- Compare the CURRENT idiom for the same protocol (t105's `main`): both
-- endpoints hand-interleaved in one function, `Chan.recv` blocking on a queue
-- the caller must have populated first, and the loop manually unrolled twice
-- because a real back-edge would deadlock the synchronous queue runtime
-- (lib/eval/eval_session.ml `chan_recv` on an empty queue is an eval_error,
-- not a park). Nothing in that idiom can run distributed, and nothing in it
-- can be driven from an actor mailbox.

mod StreamEndpoints do

  -- ── generated by the projector: one constructor per protocol step ────────
  -- Labels ARE messages (Maty). `more`/`done` need no separate choose/offer
  -- operation: choosing is sending More(_)/Done(_), offering is the handler's
  -- `match`. The unlabelled step `Prod -> Cons : Int` gets a synthesised ctor.
  type StreamMsg =
      Item(Int)      -- Prod -> Cons : Int
    | More(Bool)     -- Cons -> Prod : Bool, branch `more`
    | Done(Bool)     -- Cons -> Prod : Bool, branch `done`

  type Role = Prod | Cons

  -- ── role Prod ────────────────────────────────────────────────────────────

  actor Producer do
    state { sess : Cap(Session), next : Int, sent : Int }
    init  { sess: ambient_session(), next: 1, sent: 0 }

    on Join(ap : AccessPoint) do
      let ep = Session.register(state.sess, ap, Prod)
      prod_send(state.sess, ep, state)
    end
  end

  -- Prod at  Rec X. Send(Int, Offer{ more: Recv(Bool, X), done: Recv(Bool, End) })
  pfn prod_send(sess : Cap(Session), ep, st) do
    let ep1 = Session.send(sess, ep, Cons, Item(st.next))
    -- Now at Offer{...}. Rather than block, install the handler for whichever
    -- label arrives and yield to the event loop. `suspend` is the LAST
    -- expression of this function: it is a tail call, it never returns here,
    -- and it captures no continuation — the actor state travels with it,
    -- which is exactly why Maty's Handler is parameterised by state.
    Session.suspend(sess, ep1, { st with next: st.next + 1, sent: st.sent + 1 },
      fn (from, msg, ep2, st2) ->
        match msg do
          More(_) -> prod_send(sess, ep2, st2)   -- loop back-edge (X)
          Done(_) -> Session.close(sess, ep2)    -- End
        end)
  end

  -- ── role Cons ────────────────────────────────────────────────────────────

  actor Consumer do
    state { sess : Cap(Session), budget : Int, total : Int }
    init  { sess: ambient_session(), budget: 2, total: 0 }

    on Join(ap : AccessPoint) do
      let ep = Session.register(state.sess, ap, Cons)
      cons_wait(state.sess, ep, state)
    end
  end

  -- Cons at  Rec X. Recv(Int, Choose{ more: Send(Bool, X), done: Send(Bool, End) })
  pfn cons_wait(sess : Cap(Session), ep, st) do
    Session.suspend(sess, ep, st,
      fn (from, msg, ep1, st1) ->
        match msg do
          Item(n) ->
            let st2 = { st1 with budget: st1.budget - 1, total: st1.total + n }
            if st2.budget > 0 do
              -- choose `more` == send More(_)
              let ep2 = Session.send(sess, ep1, Prod, More(true))
              cons_wait(sess, ep2, st2)          -- loop back-edge (X)
            else
              -- choose `done` == send Done(_), then `stop` == End
              let ep2 = Session.send(sess, ep1, Prod, Done(false))
              Session.close(sess, ep2)
            end
        end)
  end
end
```

### What it calls — this list is the dictionary

```
Session.register(sess, ap, Role)          -> Endpoint
Session.send(sess, ep, Role, Msg)         -> Endpoint
Session.suspend(sess, ep, State, Handler) -> Suspended
Session.close(sess, ep)                   -> ()
```

Four operations, and every one takes the capability as its first argument — every
one is dispatched *through* the capability, which is the point.

### What it does NOT call, and therefore is not an entry

- **`recv`** — event-driven endpoints never block; delivery is a callback.
  Consequence, and it is load-bearing: today's direct-style `Chan.recv` **cannot**
  be expressed over `suspend` without capturing a continuation, and continuation
  capture is out of scope. So `Chan.*` keeps its existing in-process queue
  implementation and is **not** governed by the dictionary. `recv` is a purely
  additive 5th field if a later item wants direct-style over a swapped transport.
  Admitting it now would smuggle a second, blocking control discipline into a
  tail-resumptive-only design.
- **`choose`** — collapses into `send` of a labelled message.
- **`offer`** — collapses into the handler's `match`.
- **`new`** — establishment is `register` against an access point.
  `Chan.new`/`MPST.new` build both endpoints eagerly in one process and cannot
  model a peer that joins later.

### Cross-check at >2 roles

Re-run against `Relay` (3 roles,
`specs/lang/types/accept/t42_mpst_protocol_new.march`): `Client -> Server`,
`Server -> Logger`, `Logger -> Client`. Server's projection is
`SMSend("Logger", …)` after `SMRecv("Client", …)` — the destination is a **role**,
not "the peer". So `send`'s `Role` argument is confirmed, not guessed.
Symmetrically, a role can in general be reachable from more than one sender at the
same message type, so the handler must be told who sent (`from`); without it the
projector would have to invent per-sender message constructors, re-coupling the
generated message type to the transport's delivery decisions.

Nothing else changed between the 2-role and 3-role rewrite.

## The pinned dictionary shape

**Protocol-agnostic / transport-level. This is the most consequential decision in
the design.** A per-protocol dictionary would force a code generator to emit a new
dictionary type per protocol, coupling the generator to the runtime
representation. No field below is named after a protocol, a role, or a label.

```march
type SessionOps = {
  register : AccessPoint -> Role -> Endpoint,
  send     : Endpoint -> Role -> Msg -> Endpoint,
  suspend  : Endpoint -> State -> Handler -> Suspended,
  close    : Endpoint -> ()
}

-- Handler = Role -> Msg -> Endpoint -> State -> Suspended
```

(Spelling corrected 2026-09-02: an earlier version wrote these as
`(A, B) -> C`, which in March is a function of one TUPLE argument — see
"`SessionOps` is NOT blocked" below.)

`AccessPoint`, `Role`, `Msg`, `Endpoint`, `State`, `Suspended` are **opaque at the
dictionary boundary** — uniform representation, `ptr`-shaped. The generated
endpoint code holds the typed view; the dictionary never does. Watch the
erased-i64 convention here (`ptr -> i64` is a *conditional* untag; never coerce
`i64 -> ptr`).

Two transports satisfy this interface, and the pair is the whole payoff:

1. **In-process deterministic** — `register` hands out a queue-pair endpoint,
   `suspend` pushes `(handler, state)` onto a single-threaded run queue that the
   test driver drains in a fixed order. A distributed protocol runs reproducibly.
2. **Actor/network** — `register` resolves a peer pid or socket, `send` is
   `march_send`, `suspend` returns the installed handler and new state to the
   actor's mailbox loop.

`SessionOps` is one instance of the pattern, not the pattern. `Cap(IO.Console)`'s
dictionary would be `{ write : (String) -> () }`; a tracing dictionary wraps
another dictionary's fields.

## Representation change to `Cap(X)`, and its RC cost

**Surface type unchanged.** `Cap(X)` stays `Cap(X)`; that is the entire value of
this over the status-quo workaround (below).

**Runtime:** `Cap(X)` becomes a **nullable pointer** to a heap-allocated
dictionary record. `null` means "no dictionary — ambient/default implementation",
which is *every capability that exists today*. So the current representation is
preserved exactly for all existing programs: `root_cap` still emits `ptr null`,
and `march_cap_narrow` is still `return cap;`.

**Interpreter:** no new value constructor. A capability is either `VUnit` (the
sentinel) or the dictionary record itself — which mirrors the compiled
null-or-pointer representation exactly. (The plan here originally said "`VUnit`
becomes `VCap of value option`"; that was not needed.) Eval's `cap_narrow` had
been returning `VUnit` and *discarding its argument*, which would have dropped
the dictionary across every narrow; it is now the identity.

### The RC cost is already being paid — measured, not assumed

`needs_rc (TCon _) = true` already (`lib/tir/rc_types.ml` truth table), and
`Cap(X)` lowers to `TCon ("Cap", …)`, so Perceus **already** emits RC ops on cap
binders. Verified 2026-08-31 with `--dump-tir` on

```march
fn use_cap(c : Cap(IO.Console), n : Int) : Int do
  let d = c
  let e = cap_narrow(d)
  helper(e, n)
end
```

which emits `let e_i12999 : Cap(IO.Console) = cap_narrow(c) in dec_rc e_i12999;`.
Today those decs hit `null` and `march_decrc`'s `IS_HEAP_PTR` guard makes them
free.

So: **no new RC ops, and no `needs_rc` change.** The only *cost* is that existing
no-op decs become real atomic decrements — and only on caps that actually carry a
dictionary.

### (history) "The real RC item is a correctness hazard" — resolved

This section originally called the `cap_narrow` return-without-inc "the single
highest-risk implementation detail" and said the shim "must `march_incrc`". It
was measured instead, and the conclusion reversed: Perceus emits no dec on
`cap_impl`'s or `cap_dict`'s result in any reachable arm, and a dictionaried
capability could not reach `cap_narrow` at the time. The full account — including
the two controls that proved nothing before `--dump-tir` settled it — is under
"The compiled representation costs nothing, and the RC hazard dissolved" near the
top, and item 4 there records the later re-check once IO caps could carry
dictionaries. An inc was deliberately NOT added.

The secondary note stands: a cap held in a record field or actor state and then
invoked is the closure-through-field shape, with the known hazards in
`specs/todos/2026-08-21-ecallptr-owned-arg-borrow-callee-leak.md`.

## Who may supply a dictionary, and when

Supplying a mock dictionary **is** forging a capability's behaviour — the same
threat model `check_mint_cap_sites` (`lib/typecheck/typecheck_caps.ml:1682`)
exists to defeat. The rule below starts from that gate as precedent.

New gated builtin: **`cap_impl(cap, dict) : Cap(X)`**. It attaches, it does not
mint and does not narrow.

1. **Result must be pinned.** The site's result type must be a concrete `Cap(P)`.
   A generalized/polymorphic supplier (`forall a. _ -> Cap(a)`, e.g. a `cap_impl`
   captured in a let-bound lambda) is rejected verbatim as in
   `check_mint_cap_sites` — such a value is a forge over every capability at once.
2. **`P` is a proof cap** → allowed only inside a **public `fn` of `P`'s declaring
   module**. `mint_cap`'s rule, unchanged. Justification: a dictionary is strictly
   *more* authority than a mint (it decides what the cap does, not merely that it
   exists), so it cannot be looser than the mint gate; and the declaring module
   already defines the meaning of its own operations, so it is not an escalation.
3. **`P` is an IO cap (`IO.*`)** → there is no declaring module. IO caps are
   compiler-owned and rooted at `main`'s grant, so rule 2 has nothing to bind to.
   Admit `cap_impl` on an IO cap **only under `--test`** (the test-runner build,
   `bin/main.exe --test`), and reject it in every other build mode.
4. **`cap_narrow` propagates a dictionary but can never attach one.** Propagation
   is already structural (`return cap;`). Attachment stays `cap_impl`'s sole job;
   the precedent is the existing "`cap_narrow` may never produce a proof cap"
   tagging in `typecheck_unify.ml:322` and `check_cap_narrow_sites`.

This maps each surviving motivation onto a gate: **transport swapping** and
**tracing** both go through a *declared* cap (`Session`, or the owning module's
own cap) and are covered by rule 2 in all builds; only **mocking IO** needs rule 3.

**State the weakness plainly:** rule 3 is a *build-mode* gate, not a type-level
one, and it is not as strong as rule 2. The originally stated failure mode —
"`forge publish` must refuse an artifact built with `--test`, or a library ships
its mock" — is narrower than it sounded: `forge publish` (`forge/lib/cmd_publish.ml`)
packages and submits **source**, not binaries, so the consumer's own `--test`
decides whether the elaboration runs and a published package cannot carry a
mocked build. The residual concern is any path that ships a `--test`-built
BINARY (hot-deploy is the candidate); none was audited, so that stays open as a
question rather than a defect.

## Interaction with `lib/caps/cap_rows.ml` — nothing to fix; the behaviour is right

**This section has now been wrong twice.** Both corrections are kept, because
the errors are more instructive than the conclusion: it was written from
reading the code's shape rather than running it, twice, and was wrong about the
mechanism, the blast radius, and the remedy.

### Correction 1: the blast radius (measured)

It first claimed dictionaries make precision worse "in a way that matters:
dictionary dispatch would become the ordinary way to use a capability, so a
refusal that today fires on unusual code would fire on ordinary code."

Measured with `MARCH_DUMP_CAP_ROWS=1`, a hook whose own comment says it exists
to make this refusal's blast radius measurable rather than assumed:

| | rows | `unknown` |
|---|---|---|
| baseline | 2733 | 127 |
| under `--test` | 2812 | 192 |

All 65 added rows are generated `__march_dispatch_*` wrappers, and **none
reaches user code**: the operation rewrite happens in TIR, so at the point
`cap_rows` runs nothing in the AST calls a wrapper and there is no reference
edge to propagate along. IO mocking costs nothing. Only HAND-WRITTEN dictionary
dispatch marks the function performing it `unknown`.

### Correction 2: the mechanism, and why there is no fix

It then said: "`cls_of_rhs` has no `EField` arm, so it falls to `COpaque`;
`app`'s `Some COpaque` branch sets `sd_unknown := true`", and proposed two
fixes on that basis.

Both halves are wrong. `d.emit(s)` has head `EField (EVar d, "emit")`, which is
neither `EVar` nor `ELam`, so it hits `app`'s catch-all:

```ocaml
| _ -> unknown := true; charge_unknown_callee shapes
```

`cls_of_rhs` is not consulted for a call head at all — only for `let`-bound
right-hand sides. And adding an `EField` arm would change nothing anyway: the
base is a match binder, and `EMatch` classifies binders `COpaque`
(`cap_rows.ml:138`), so the arm would derive `COpaque` and set `unknown`
regardless.

**More importantly, the proposed fixes were UNSOUND.** `unknown` means "this
function's reach cannot be determined statically, so refuse to certify a narrow
grant over it". For a function dispatching through a dictionary that is exactly
true: what it reaches is whatever dictionary someone else installed. Certifying
it console-only would be a lie.

The system is nonetheless sound overall, and it is worth knowing why — a
dictionary closure cannot smuggle capabilities past `needs`. Verified:

```march
mod Attrib do
  needs IO.Console
  type Ops = { emit : (String) -> Int }
  fn mk() : Ops do
    { emit: fn s -> do let _ = file_write("/tmp/x", s)  string_length(s) end }
  end
end
```

```
function bodies in `Attrib` call builtins that require `Cap(IO.FileWrite)`,
but `Attrib` declares no matching `needs`.
```

So a mock's capabilities are charged to the module that WRITES it, and the
dispatcher's `unknown` is a correct description of the dispatcher rather than
the only thing standing between a mock and unchecked authority.

**Conclusion: do not "fix" this.** The conservative refusal is the intended
semantics. If a future change makes hand-written dictionary dispatch common
enough that the refusal chafes, the question to ask is whether a narrow grant
over such a function is meaningful at all — not how to make `cap_rows` say yes.

## Is this an effect system? No — and the missing half is the larger half

The question a later reader will ask, so: this is the **dictionary-passing** half
of an effect system and none of the **delimited-control** half. Two separate
reasons, and the first one is structural rather than a matter of scope.

### March caps are a permission system, not a dispatch system

`println : String -> ()` (`lib/typecheck/typecheck_builtins.ml:485`). The
capability requirement lives in a SIDE TABLE — `builtin_cap_table` maps
`"println" -> "IO.Console"` (`:93`, 91 entries) — which
`check_module_needs` attributes to the enclosing module and checks against
`needs`. **The `Cap(X)` value is never an argument to the operation it
authorizes.**

So attaching a dictionary to a capability intercepts nothing by itself. You get
swappable behaviour only for operations *written* to take the cap first, which is
why every call in the endpoint artifact above threads `sess` explicitly.

This reframes the cost of the item. The dictionary is the small part; making it
general means migrating every builtin and stdlib IO signature to cap-first, which
is a language-wide API break. That migration — not the dictionary, and not the
gating rule — is the real gate on generality.

### What is and is not delivered

| | This design | A normal effect system |
|---|---|---|
| Swap an implementation | yes, for cap-first APIs | yes, everywhere |
| Tracing / interception | yes, for cap-first APIs | yes, everywhere |
| Test mocks | yes, for cap-first APIs; `--test`-gated for IO | yes |
| Intercept code you do not control | **no** — the callee must accept the cap | yes, `handle` is dynamically scoped |
| Abort / early exit from a handler | **no** (out of scope) | yes |
| Resume more than once; generators, backtracking | **no** | yes |
| Async/await, coroutines as effects | **no** | yes |
| Effect row on the arrow, effect polymorphism | partial — `cap_rows` answers "which effects" via a flow-insensitive call-graph fixpoint; there is no `e` row variable on arrows | yes |

Two rows deserve the emphasis:

- **Dictionary-passing is not handler installation.** The cap is threaded as an
  explicit value; an effect system installs a handler over a dynamic extent.
  `with tracing handle app()` works on an `app` that knows nothing about tracing;
  `app(traced_cap)` requires `app` to have been written to accept it. March has no
  `handle` construct and this item does not add one. For the three surviving
  motivations this mostly does not bite — you own the endpoints, the transport and
  the test — but it is the line past which the analogy fails.
- **No control effects.** Tail-resumptive-only buys a plain virtual call and
  nothing else. Abortive handlers need the Perceus-aware unwinding path March
  does not have (see the out-of-scope list).

### Verdict

Worth building for mocking, tracing and transport swapping, because those are
exactly the cases where the signatures are ours to write — and transport swapping
is the strongest, since `Session.*` would be new API with no migration to pay and
deterministic in-process replay of a distributed protocol as the payoff.

Not worth pitching as a general effect system. The honest sequencing to become one
is: (1) route operations through caps — done for `--test` builds by the
compiler-inserted passing below, still an API break for release builds; (2)
abortive handlers, which need the unwinding path first. (An earlier version
listed "(3) `cap_rows` precision, which this design makes worse" — measured,
it does not; see the `cap_rows` section.)

## Alternative considered and rejected

`specs/lang/capabilities.md` §"Testing with capability environment records"
already documents the workaround: pair an erased `Cap(X)` with a sibling function
field in a record, and swap the field in tests. It works today and needs no
compiler change.

Its cost is that every consumer signature must name the record type instead of
`Cap(X)`, so a library that takes `Cap(IO.Console)` can never be mocked by its
caller — only by code that was written against the record from the start. The
dictionary's entire value over it is that the swap is invisible to the signature.
A reader who does not need that property should prefer the record and close this
item.

## Making IO mocking reachable: compiler-inserted capability passing

Chosen over the alternatives (hand-migrating the builtins to cap-first
signatures; a dynamically-scoped `handle`; link-time substitution in the test
binary). The elaboration is gated on `--test`, so release codegen is unchanged
and the ABI churn exists only in test binaries.

### Why it is needed at all

`println : (String) -> ()`. The requirement lives in a side table
(`builtin_cap_table`, 91 entries over 15 capabilities); the capability VALUE is
never an argument. Worse than a wrong signature — there is often no capability
value in scope at all. This typechecks clean today:

```march
mod App do
  needs IO.Console
  pfn helper(n : Int) : () do
    println(int_to_string(n))     -- no cap value anywhere in this function
  end
  fn main(_c : Cap(IO.Console)) do helper(42) end
end
```

`needs` discharges the requirement module-wide through the call-graph closure.
So there is nothing at the call site to dispatch through.

### (a) Dictionary shapes — LANDED

`lib/typecheck/io_ops_gen.ml` derives each capability's dictionary from the
compiler's own tables. Three language properties forced the shape, each found by
measuring rather than by reasoning:

- **Fields are `Option`.** March records unify EXACTLY — no width subtyping
  (`Typecheck_unify`'s `TRecord`/`TRecord` arm reports both surplus AND absent
  fields) — so a mock must supply every field. An all-`None` base plus record
  update is what makes overriding one operation bearable.
- **Zero-arg operations take an explicit unit.** March auto-applies a zero-arg
  function the moment it is named: even a named `fn seven() : Int` passed as a
  value is rejected as `Int` against `() -> Int`. So `unix_time` is
  `(()) -> Float`, mocked as `fn _ -> 1234.0`. Without this `IO.Clock` — the
  canonical mocking target — would have no dictionary at all.
- **Polymorphic builtins are excluded**; a field holding one needs rank-2
  types. 19 of 91. `excluded_ops` reports them and `--emit-io-ops` prints them,
  because an operation a mock silently fails to cover is worse than one it
  visibly cannot.

Coverage, which decides how much of this is worth having:

| verdict | capabilities |
|---|---|
| fully mockable | Console, Clock, Random(2/3), FileRead, FileWrite, NetConnect, NetConnect.TLS, WebSocket, Signal, FileSystem, Network |
| partly | Process (12/13), NetListen (4/6), Spawn (1/5) |
| not at all | **Mut** — every `vault_*` is polymorphic |

The ones you would actually mock in a test (console, clock, randomness,
filesystem, network) are all in the first row.

**An earlier attempt generated `stdlib/io_ops.march` and was abandoned**: the
field types name types owned by many different stdlib modules (`FileError`,
`Csv.CsvRow`, `FileStat`) that no single module can import, and a module whose
values call IO builtins must declare `needs` for them — which propagate to
importers, so every program would have demanded all fifteen capabilities.
Building the record structurally from the builtins' own `ty` values sidesteps
both. `--emit-io-ops` remains as documentation, not as a file the compiler reads.

### (b) The elaboration pass — the original plan (history; it LANDED in #389)

Kept as written because the two notes after it record what the plan got wrong.
At the time the gate on `cap_impl` for IO capabilities was held CLOSED until
this landed, so a mock could not typecheck, attach, and silently never be
consulted.

1. New builtin `cap_ops_empty(c)`: the all-`None` dictionary for `c`'s
   capability, typed from `Io_ops_gen.dict_ty` the way the `cap_dict` arm
   already resolves its result. A mock is then
   `cap_impl(c, { cap_ops_empty(c) with println: Some(fn s -> capture(s)) })`.
2. Wire `dict_ty` into the `cap_dict` arm and `check_cap_impl_sites` for IO
   capabilities, and open the `--test` gate.
3. The pass itself, under `--test`: give every function in its capability
   closure (`fn_transitive_capability_closures_tbl`, which already computes
   exactly this) an implicit parameter per capability it needs; thread from the
   caller; root at `main`'s cap parameter, or at `root_cap` in a test body
   (nameable there and nowhere else — accept/t146, reject/t152). Rewrite each
   cap-requiring builtin call to

   ```
   match cap_dict($cap_IO_Console) do
     Some(d) -> match d.println do
                  Some(f) -> f(s)
                  None    -> println(s)   -- ambient
                end
     None -> println(s)
   end
   ```

   Elaborate bottom-up in one pass so the ambient arm is never re-elaborated.

### (b) implementation notes, from starting it

Two things were settled by attempting the pass; both changed the plan above.

**IT BELONGS IN TIR, NOT THE AST.** The AST has 58 expression constructors and
no generic map, so an AST rewriter must be total over all 58 by hand — and a
missed constructor is SILENT: a call site inside it keeps its old arity while
the callee gained a parameter. TIR has ~21, is in ANF (so every call is
`EApp (var, atoms)` or `ECallPtr` — no calls nested inside arbitrary
expressions), and `lib/tir/` already contains passes that change arity (mono,
defun). Writing the match without a `_` arm then makes exhaustiveness a
compile error rather than a runtime surprise.

The insertion point is immediately after `Lower.lower_module`, which
`bin/main.ml` already documents as "the one point in the pipeline where a TIR
fn's name is still exactly its source name — Mono hasn't mangled/duplicated
anything yet, Defun hasn't lifted any lambdas yet". That is exactly what
matching against the capability closure needs.

**THE MOCK NEEDS A BINDING SITE, which the plan above did not have.** Threading
alone is not enough: the implicit parameter has to be bound to the user's mock
*somewhere*, and a `let mock = cap_impl(...)` in a test body is just a local
the pass knows nothing about. The binding site is

```march
with_cap(mock, fn _ -> code_under_test())
```

Inside the lambda, the implicit parameter for `mock`'s capability is `mock`.
Written as an ordinary application rather than new syntax, so the pass needs no
parser change. Everywhere else an elaborated call passes `root_cap`, the plain
sentinel, which reads back as `None` and takes the ambient path — i.e. exactly
today's behaviour. (`root_cap` is banned in source outside a test body by
reject/t152, but the pass runs after typechecking and emits it directly, so the
ban is not in play. Do not re-typecheck the elaborated program without
accounting for that.)

**Restrictions for a first version**, each of which costs interception and never
correctness — an un-elaborated function keeps today's behaviour exactly:

- Actor handlers are skipped: the scheduler invokes them, not an elaborated
  caller, so there is nobody to thread from. **(Lifted in #397 — see "Actor
  handlers: capture at spawn" below.)**
- A function whose name is referenced anywhere except as a call head is not
  elaborated; changing its arity would break the reference, and eta-expanding
  every such site is more than a first version needs.

### (b) progress, and the SIGBUS that was open here (history; fixed in #389)

Everything in this list landed and is wired to `--test`:

- **Analysis** (`lib/tir/cap_passing.ml`): which functions must carry which
  capability, from the TIR call graph. ~160 of ~2750 across a whole program
  including stdlib, matching the pre-build estimate of ~7%.
- **Threading**: implicit parameters added and passed; a caller that cannot
  supply one passes `root_cap`, the ambient sentinel.
- **Dispatch wrappers**: generated as March SOURCE and injected before
  typechecking (`Io_ops_gen.dispatch_wrappers_source`, ~650 lines), so they are
  typechecked rather than hand-built as TIR. They typecheck clean, including
  the stdlib-owned types (`FileError`, `Csv.CsvRow`, `FileStat`) that killed the
  generated-stdlib-module approach.
- **`cap_ops_empty`**: the all-`None` base a mock overrides one field of.

An unanticipated benefit of rewriting in TIR: the wrappers are NOT reachable
from `main` at typecheck time, so injecting them does not widen any program's
capability closure and a narrow `main` grant still checks.

**The SIGBUS (rc=138) on `File.with_lines`, and the wrong first hypothesis.**
This section originally said the likely cause was "a threaded function reaching
a closure the pass did not classify as arity-frozen — the `unsafe` rule keys on
an `ADefRef`'s `did_name`". That hypothesis was TESTED — a check was added
reporting exactly that — and it reported nothing. Falsifying it is what found
the real cause: `with_lines` has a nested local `fn do_lines(a, f)` calling
`file_read_line`, and the scan charged that operation to the LOCAL's name. A
local is not in `tm_fns`, so `elaborate` never added parameters to it while
`thread` added an argument at its call sites. Defun lifts such locals to top
level LATER, which is why `--dump-tir` showed `fn do_lines` and made it look
top-level. Charging a local's IO to its enclosing function fixed it and closed a
missed-threading hole at the same time. The `ADefRef` check was kept: it asserts
an invariant threading depends on.

### The binding site: `with_cap` — LANDED

`with_cap(mock, fn _ -> body)` is an ordinary prelude function,
`fn with_cap(_c, f) do f(()) end`, so it needs no parser change. At runtime it
just calls `f`; the capability is consumed by the elaboration, which rewrites
calls inside the lambda to route through `mock` instead of the ambient
sentinel.

Lower emits the thunk as `let v = letrec [lam] in lam ... with_cap(mock, v)`,
so the lambda's `fn_def` is reachable from the `let` that binds it, and the
capability is read off the mock's own TYPE — which is what lets this be a
function call rather than syntax.

`thread`'s `avail : StrSet.t` became a `(cap * atom) list` so a capability can
be supplied by something other than the enclosing parameter.

`cap_ops_empty(c)` resolves to a generated `__march_ops_empty_<CAP>()`, also
emitted as March source, for the same reason the wrappers are: building the
record in TIR would mean re-deriving `None`'s constructor type and duplicating
lower's typecheck-ty -> TIR-ty translation.

**End-to-end, compiled, under plain `--test`** (test/cap_mock/cap_mock_io.march):

```
REAL:x            -- before
MOCK[REAL:x]      -- inside with_cap
REAL:x            -- after
```

Three calls to the same function, none of which names a capability. One
dictionary would not distinguish interception from a hard-coded
implementation; the calls either side pin that the swap is lexically scoped.

### ONE predicate gates all three

The dictionary types resolving for IO capabilities, the wrapper injection, and
the rewrite must agree. They did not: injection was `--test`-gated while the
rewrite was env-var-gated, so a build with the rewrite on and injection off
emitted calls to `__march_dispatch_print_line` and failed at link with an
undefined symbol — 76 codegen failures. `Flags.cap_mocking ()` is now the
single predicate for all three.

Also: neither `MARCH_CAP_PASSING` nor the mocking predicate was in `cas_flags`,
so a build with the pass on shared a CAS entry with one without — the
"pass off" run printed the mocked output. Same omission as `--test` itself,
found the same way.

### The end-to-end test is now wired in

`test/cap_mock/cap_mock_io.march` runs under `@test/runtest`, compiled with
`--test` and diffed against `.expected`. Proved non-vacuous by disabling the
dispatch rewrite and watching the diff fail, then restoring.

The fixture stays OUT of `test/native/`: that directory is swept by the LLVM IR
validity gate (`test_ir_verify.ml`), which compiles every `.march` in it
WITHOUT `--test` — and without `--test` there is no implementation of
`cap_ops_empty` to link, so the sweep would fail on it. Anything needing
`--test` to compile belongs elsewhere.

### Actor handlers: capture at spawn — LANDED (#397)

A handler is entered from the scheduler through `$actor.$d_dispatch`, so the
dispatch function's arity is frozen and it supplied the ambient sentinel. The
capability is now captured at the **spawn site** onto `march_actor_meta`
(`spawn_cap`) — NOT as a field on the actor record, whose layout is pinned by
the C runtime's hardcoded word indices (`a[2]=dispatch`, `a[3]=alive`) and is
what `migrate_state`, hot reload and `@compat` all reason about. The meta is
runtime-internal and none of them see it. `march_spawn`'s ABI is untouched: the
setter is a separate call after it, since `march_spawn` creates the meta.

Because capture is per-actor at spawn, a mock reaches an actor spawned inside
`with_cap` and not one spawned outside it, **regardless of when either runs** —
`test/cap_mock/cap_mock_actor.march` sends to the outside actor after the block
closes, so a global or dynamically-scoped slot would give the right answer for
the wrong reason.

**Limit: one capability per actor.** An actor whose handlers reach two would
need a record of them captured; `dispatch_cap` returns `None` for that case, so
such an actor keeps the previous behaviour rather than a partly-wrong one.

The bug worth remembering from building it: the first version scanned the
dispatch BODY for interceptable operations and found none, because handlers are
not inlined into the dispatch at the point this pass runs — that is the
optimizer, later. `--dump-tir` shows the POST-optimizer form, where the handler
is inlined, which made the wrong shape look right. `MARCH_DUMP_TXT=lower` shows
what the pass actually sees. Full account in
`specs/progress/2026-09-01-actor-capability-capture-at-spawn.md`.

### Incidental fix: `--test` was not in the CAS cache key

`--test` changes the emitted program (`lower_module ~test_mode` builds a
test-runner entry point), but `cas_flags` did not include it, so a `--test`
build and a plain build of the same source shared a cache entry and whichever
ran first won — `forge build` could hand you the test runner, or `forge test`
the plain binary. Pre-existing and unrelated to dictionaries; found by
compiling the same file both ways and getting the same artifact. Fixed.

**Risks to price before starting.** The pass changes the arity of most
functions in a test build, so it lands on defun, mono, Perceus, the CAS cache
key, hot-reload dispatch tables and FFI boundaries. (It said here that
`cap_rows` "gets worse in the usual way"; measured, it does not — the
`cap_rows` section has the numbers.) And `forge test` COMPILES by default
(`march --compile --test`; the interpreter is the `MARCH_TEST_INTERPRETER=1`
fallback) — which is why the compiled runtime had to land first.

## `SessionOps` is NOT blocked — and the section that said so was wrong (2026-09-02)

An earlier version of this section, written the same day, claimed a language
defect: "a user-declared record field cannot hold a 2+-argument function
type". That claim was **false**, and how it went wrong is the useful part.

### What is actually true

March's multi-argument function type is the **curried** spelling, documented
in `specs/lang/surface-syntax.md:292` ("`a -> b -> c` — curried") and used in
every interface method (`fn eq: a -> a -> Bool`). It works in a record field
for two and three arguments:

```march
type Ops = { f : Int -> Int -> Int, g : Int -> String -> Bool -> Int }
fn use_it(o : Ops) : Int do o.f(1, 2) + o.g(10, "x", true) end
-- { f: fn (a, b) -> a + b, g: fn (n, _s, _b) -> n }   -- prints 13
```

`(A, B) -> C` means something else, and correctly so: a function of ONE
argument that is a tuple. `ty: ty_nat_add ARROW ty` — the left of an arrow is
a single type, and `(A, B)` is a tuple type. `Tuple.apply(t, f : (a, b) -> c)`
calls `f(t)`, and `test_sort.march`'s `pair_fst_cmp` returns `fn b -> …` over a
pair. Both rely on that meaning. It must not change.

### Where the false claim came from

`Io_ops_gen.march_ty` rendered a curried arrow as `(A, B) -> C` — the tuple
spelling — so `--emit-io-ops` printed every multi-argument field in a form
that means the wrong thing, the pinned `SessionOps` shape below was written in
that form, and every probe copied it. The compiler-built dictionaries were
never affected because they are built from `ty` values, not from that string;
which is why a 2-argument `file_write` mock worked while the "same" shape typed
by hand did not. The renderer is fixed to emit the curried spelling; a test
pins that a rendered field type is valid surface syntax for a multi-parameter
lambda.

Two smaller things the same mistake exposed: `Tuple.apply`'s doc said "a
function that takes two separate args" while its body calls `f(t)` on the pair;
and the zero-argument spelling `(()) -> r` is the same AST as `() -> r`, which
is what the renderer now emits.

### The pinned shape, spelled correctly

```march
type SessionOps = {
  register : AccessPoint -> Role -> Endpoint,
  send     : Endpoint -> Role -> Msg -> Endpoint,
  suspend  : Endpoint -> State -> Handler -> Suspended,
  close    : Endpoint -> ()
}
-- Handler = Role -> Msg -> Endpoint -> State -> Suspended
```

Same four operations as derived above; only the arrows changed.

### What remains before building it

Only the representation of the two protocol-specific types, and neither is a
language change:

- **`Msg`**: erase to `Bytes` at the dictionary boundary. For a *transport*
  that is natural rather than a hack — a network transport must serialise
  anyway, and the projector that emits the endpoints knows the real type on
  both sides. This keeps `SessionOps` monomorphic AND protocol-agnostic, so the
  `with`-clause limitation (below) is not on the path.
- **`State`**: whether it belongs in the dictionary at all, or is closed over
  by the handler. A design question to settle in the first real endpoint, not
  before.

### Related, not blocking: the `with` clause is monomorphic

`Cap_dict_resolve.dict_ty_of_cap` builds `TCon (rec_name, [])`, so
`type SessionOps(m) = …` never unifies with the literal's `SessionOps('a)`.
Filed with a reject/accept pair in
`specs/todos/2026-09-02-cap-with-clause-is-monomorphic.md`; the diagnostic for
it now renders the arity instead of blaming a namespace collision. It would
only matter for a parameterised dictionary, which would be protocol-specific —
the thing the design rejects — so it is not on the `SessionOps` path.

### Landed: `stdlib/session.march` + `test/session/stream_replay.march`

The `Stream` protocol's two endpoints, written as a projector would emit them,
run against an in-process transport and produce the same eight-line trace
interpreted and compiled:

```
Prod sends Item(1)   Cons got Item(1)   Prod got More
Prod sends Item(2)   Cons got Item(2)   close 2   Prod got Done   close 1
```

What building the first real endpoint settled, each a change to the shape
above:

- **`State` is not in the dictionary.** The handler closes over it. So
  `suspend` is `Endpoint -> Handler -> Suspended` and `Handler` is
  `Role -> Msg -> Endpoint -> Suspended` — one argument fewer than the artifact
  assumed. Maty's `Handler(S, C)` carries state so that suspension needs no
  continuation capture; a March closure carries it for free.
- **`send` is spelled `emit`**: `send` is reserved for actor messaging.
- **A synchronous transport is wrong for send-then-suspend endpoints.** The
  first transport delivered inside `emit`; `prod_send` emits FIRST and suspends
  AFTER (that is the protocol), so Cons's reply arrived before Prod had
  installed a handler and was dropped. A FIFO run queue drained after every
  endpoint has had its turn — what an event loop gives you — is required, and
  its fixed drain order is the determinism. A delivery with no handler is a
  panic, never a silent drop: a silent drop is what hid this.
- **The transport must close over its tables.** `Vault.new(name)` twice is a
  fresh table interpreted and the same table compiled — a backend divergence
  filed in `specs/todos/2026-08-12-vault-toward-ets-semantics.md`.
- **Two parser facts the module hit**: `doc` is accepted only before a
  function (before a `type` or `proof cap` it is a parse error), and the stdlib
  loader reports a stdlib parse error as "Unknown module" — filed in
  `specs/todos/2026-09-02-stdlib-parse-error-reported-as-unknown-module.md`.

v1 scope: endpoints are functions, not actors (an actor host is additive and
brings the one-capability-per-actor limit with it); one in-process transport,
in the test; `Session.attach` is the only mint.

### Order of remaining work

1. An actor-hosted endpoint, once the one-capability-per-actor limit is lifted.
2. The monomorphic-`with` limitation only if a parameterised dictionary ever
   has a use.

## Explicitly OUT OF SCOPE — do not re-expand

Build **tail-resumptive handlers ONLY**: a handler that resumes exactly once in
tail position, compiling to a plain virtual call through the dictionary. No
continuation capture, no non-local exit, no unwinding, no scheduler or TCO
interaction.

- **Abortive handlers / non-local exit.** These need a Perceus-aware unwinding
  path (RC drops for skipped frames). March has no such path today: `panic` aborts
  the process, `let?` is an ordinary return. Separate, higher-risk, later work,
  and the gate on everything downstream. Do not fold it in.
- **General one-shot or multi-shot resumption.** Not needed.
- **A second-class / escape-restricting qualifier on `Cap`.** Deliberately
  rejected. A flow-sensitive effect system expresses capability scoping natively
  via pre/post conditions, and `Cap(X)` is unrestricted-by-default with an opt-in
  `linear` qualifier (`specs/lang/linear-types.md` §"Capabilities as Linear
  Types"). Second-class would be a third discipline for no gain.
- **`recv` in the dictionary**, and with it direct-style `Chan.*` over a swapped
  transport. See the derivation above; additive later.

## Background

Fowler & Hu, "Speak Now: Safe Actor Programming with Multiparty Session Types,"
OOPSLA 2026 — <https://doi.org/10.1145/3798267>
(PDF: <https://simonjf.com/writing/eventactors.pdf>). Introduces **Maty**:
multiparty session types for actor languages via a flow-sensitive effect system
(pre/post conditions on arrows, `Γ | C | S ⊳ M : A ⊳ T`) plus first-class message
handlers typed `Handler(S, C)`, parameterised by input session type *and* actor
state — which is why suspension needs no continuation capture. Extends to
Erlang-style supervision and cascading failure via affine sessions. Implemented as
generated typed APIs from Scribble global types, not a new compiler backend.

March already has multiparty projection (`lib/typecheck/typecheck_session.ml`),
actors, and OTP supervision. Whether to build the projector on top of this is a
**later** decision; this item needs Maty only as the shape the hand-written
endpoints imitate.

## Relevant files

- `lib/typecheck/typecheck_caps.ml` — `check_mint_cap_sites` (:1682),
  `check_cap_narrow_sites` (:1608), `check_json_cap_sites`, `check_module_needs`
- `lib/caps/cap_rows.ml` / `.mli` — capability row solver
- `lib/typecheck/typecheck_session.ml` — `project_steps` / `project_protocol`
- `lib/tir/llvm_builtins.ml` (:843-848), `lib/tir/llvm_emit.ml` (:358),
  `lib/eval/eval.ml` (:2650), `runtime/march_runtime.c` (:6541) — current
  runtime representation of caps
- `lib/tir/cap_passing.ml` — compiler-inserted capability passing
- `lib/typecheck/io_ops_gen.ml`, `lib/typecheck/cap_dict_resolve.ml` — derived
  IO dictionary shapes and resolution
- `test/cap_mock/` — the three end-to-end mocking fixtures
- `stdlib/session.march` — the session transport capability (`Session.attach` is the only mint)
- `test/session/stream_replay.march` — the `Stream` protocol replayed deterministically, both backends
- `specs/todos/2026-09-02-cap-with-clause-is-monomorphic.md` — blocker (2)
- `specs/progress/2026-09-01-actor-capability-capture-at-spawn.md`
- `lib/eval/eval_session.ml` — the existing in-process queue session runtime
- `lib/tir/rc_types.ml` — `needs_rc` / `borrow_eligible` contract
- `specs/lang/capabilities.md`, `specs/lang/linear-types.md`
