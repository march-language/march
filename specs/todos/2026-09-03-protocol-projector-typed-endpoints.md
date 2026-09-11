# `[P2]` Choreography: a projector that emits typed endpoints over `Session`

**Status:** specced 2026-09-03, reviewed and amended 2026-09-10, not started.
Follows `specs/progress/2026-08-31-cap-runtime-dictionaries.md`, whose
`Session` transport capability is the substrate this builds on, and which
explicitly deferred "whether to build the projector on top of this" as a later
decision. This file is that decision, worked out far enough to build.

The 2026-09-10 review measured the design against current `main` and found two
of its claims false as first written. Both are corrected below and marked
**(review)**; the two compiler holes it exposed are filed on their own:
`2026-09-10-linear-lambda-parameter-not-must-use.md` and
`2026-09-10-linear-actor-state-field-retained-after-consume.md`.

## The gap, stated precisely

March has two halves of a choreographic story and they do not touch.

| | protocol conformance checked | actually runnable |
|---|---|---|
| `Chan` / `MPST` | yes | no |
| `Session` capability | no | yes |

**The typed half.** `protocol P do … end` parses to `Ast.DProtocol`, and
`Typecheck_session.project_protocol` projects it onto every role, producing a
`session_ty` per role: `SSend`/`SRecv` for two roles, `SMSend`/`SMRecv` with
explicit role annotations for more, plus `SChoose`/`SOffer`/`SRec`/`SVar`/`SEnd`.
Binary projections are checked for duality, multiparty ones for pairwise
send/recv consistency. The typechecker then advances a `TChan of session_ty ref`
one operation at a time across `Chan.send`, `Chan.recv`, `Chan.offer`,
`Chan.close` and the `MPST.*` equivalents.

That half cannot run. Its channel runtime is synchronous, single-threaded and
non-blocking: a `recv` before its matching `send` typechecks and then dies on
both backends. Loops must be hand-unrolled. Nothing on that path reaches an
actor mailbox or a network.
`specs/todos/2026-07-06-p2-compiler-session-types-protocols-channels.md` records
this as a deliberate scope boundary, not a defect.

**The runnable half.** `stdlib/session.march` makes the transport a capability
dictionary: `register`, `emit`, `suspend`, `close`. Endpoints are event-driven
in Maty's style — emit, then install a handler and yield, never block — and the
transport is swappable, so `test/session/stream_replay.march` replays the
`Stream` protocol deterministically and identically interpreted and compiled.

That half is untyped with respect to protocols. Endpoints are `Int`, messages
are `Bytes`, and the session typechecker has never heard of `Session`: it
matches on the literal names `Chan.*` and `MPST.*` only (verified by grep,
2026-09-03 and again 2026-09-10). Nothing checks that the fixture's `prod_send`
follows `Rec X. Send(Int, Offer{…})`. It could emit `Done` first and typecheck.

**The join is a code generator, and none exists.** `project_steps` is called
only from inside the typechecker. There is no protocol-to-code generation
anywhere in the tree. The fixture's endpoints were hand-written to imitate what
a projector would emit — deliberately, as the design's method — but nothing
emits them.

## Status

| slice | state |
|---|---|
| Global protocol → per-role local types (`project_protocol`) | **exists**, reused as-is |
| Transport as a swappable capability (`Session`) | **landed** (#402) |
| Actor capability capture, any number of capabilities | **landed** (#404, #405, #407) |
| Generated message type + codec | not started |
| Generated per-role, per-state endpoint API | not started |
| Handler typing | **subsumed** — see "Item 2 mostly dissolves" |
| Actor-hosted endpoint | not started; **blocked** on two things, see item 3 |

## Method

The same method the parent design used, for the same reason: do not invent the
generated API, derive it from a hand-written artifact and let the artifact be
the specification of the generator's output.

**The artifact already exists.** `test/session/stream_replay.march` is a
working, tested endpoint pair for the richest protocol in the tree
(`Stream`: loop, choose and stop, i.e. recursion, label dispatch and
termination). The generator's job is defined as: given `protocol Stream`, emit
the typed API that the fixture's `prod_send` and `cons_wait` would call instead
of calling `Session.emit` and `Session.suspend` raw. Their bodies stay
hand-written; they carry user logic (`print_line`, the budget counter) that no
projector can invent.

## The design: session states become nominal linear types

The central choice, and the one that makes this cheap.

A projected `session_ty` is a tree of states. Give **each state its own
generated `always_linear type`**, and each transition a generated function from
one state type to the next. Then the ordinary typechecker enforces protocol
conformance with no new machinery:

- **Order** is enforced because you can only call the transition whose input
  type you are holding. Emitting `Done` at the loop head does not typecheck:
  that function does not take the state you have.
- **Linearity** is enforced because `always_linear` puts the qualifier on the
  *type*, so every binding of it is linear. Replaying a stale state, which
  would fork a session, is a compile error. Abandoning a session in
  straight-line code is a compile error.

**(review) Linearity does NOT reach a lambda's parameters**, and every
generated callback is a lambda. A linear state passed into a callback and never
used is accepted silently — no error, no warning, with or without a type
annotation on the parameter — while using it twice inside the callback IS
rejected, and a named function's parameter is fully checked. So the guarantee
as first written was false exactly where this API lives. The design closes the
hole by construction, below, rather than waiting on the checker; the checker
hole is filed separately.

No effect system, no `TChan` ref, no new constructor in `session_ty`, and
nothing in the existing `Chan`/`MPST` path is touched.

### (review) Callbacks return an unforgeable token

Every generated callback returns a `Yield`, a public type whose only
constructor takes a value of a **private** type:

```march
ptype Secret = Secret
type  Yield  = Yield(Secret)
```

Only the generated `suspend`-shaped wrappers and `close` produce a `Yield`,
and each consumes a state to do so. A callback that abandons its state has
nothing to return, so the abandon becomes a type error even though the
linearity checker never looks at the lambda's parameter. Verified live: a
callback that tries `Gen.Yield(Gen.Secret)` from outside fails with "I cannot
find `Secret`"; the honest callback that consumes its state is accepted.

`ptype` on `Yield` itself does **not** work: it hides the type *name*, so the
user cannot even write the callback's signature. The name must be public and
only the constructor's argument private.

This also replaces the raw `Int` that `Session.suspend`'s handler returns,
which was a wrinkle in the first draft: `close` paths had no honest `Int` to
hand back.

### Mapping

| projected form | generated |
|---|---|
| `SSend(T, S')` / `SMSend(role, T, S')` | `fn send_<label>(s, ep : St, v : T) : St'` |
| `SRecv(T, S')` / `SMRecv(role, T, S')` | `fn recv(s, ep : St, k : T -> St' -> Yield) : Yield` |
| `SOffer{l₁…lₙ}` | one `offer` taking **one callback per label**, each `Tᵢ -> Stᵢ -> Yield`, so branch coverage is total by construction |
| `SChoose{l₁…lₙ}` | n functions `choose_<lᵢ>`, each returning that branch's state |
| `SRec(X, S)` | the binder's state type; `SVar X` resolves back to it, so a loop back-edge is just returning that type |
| `SEnd` | `fn close(s, ep : St_end) : Yield` — linear, so it cannot be skipped |

A label and its payload are **one message**, not two. That is what the source
syntax already means (`more -> Cons -> Prod : Bool` is the choice *and* the
message) and what the landed fixture encodes. So `SOffer`'s callbacks take the
payload directly.

**(review) That fusion assumes a rule the language does not enforce.**
Declaration-time checks on a `choose` verify only that it has two or more
branches (`typecheck.ml`, `validate_step`'s `ProtoChoice` arm). Nothing
requires a branch to *begin* with a message from the chooser, so a branch that
starts elsewhere leaves the offering role with a label and no message to carry
it. The generator must enforce the standard projectability condition itself:
**every branch of a `choose` begins with a message from the chooser to the
offering role**, rejected with a diagnostic naming the protocol, the label and
the offending first step. Do not assume it.

### Worked shape, `Stream` role `Prod`

Projection: `Rec X. Send(Int, Offer{ more: Recv(Bool, X), done: Recv(Bool, End) })`.

Shape only — not verified syntax, exactly as the parent spec's artifact was:

```march
mod Stream_Prod do
  ptype Secret = Secret
  type  Yield  = Yield(Secret)

  always_linear type S_loop  = S_loop(Int)    -- at Rec X: must send an Int
  always_linear type S_offer = S_offer(Int)   -- awaiting more/done
  always_linear type S_end   = S_end(Int)     -- at End: must close

  fn send(s : Cap(Session.Live), ep : S_loop, v : Int) : S_offer

  -- one callback per label; the back-edge is `on_more` returning to S_loop
  fn offer(s : Cap(Session.Live), ep : S_offer,
           on_more : Bool -> S_loop -> Yield,
           on_done : Bool -> S_end  -> Yield) : Yield

  fn close(s : Cap(Session.Live), ep : S_end) : Yield
end
```

The user's `prod_send` then reads as it does today, minus the raw transport
calls and minus the possibility of getting the protocol wrong.

### State naming

Derive names structurally from the protocol (`S_loop`, `S_offer`, `S_end`), not
by numbering a traversal. Numbering means an unrelated edit near the top of a
protocol renumbers every state below it and breaks user code that named them.
Structural names change only when the structure they name changes. Collisions
inside one role need a deterministic disambiguator; settle its spelling when
the first protocol needs one, not before.

### The codec

The `Bytes` erasure at the dictionary boundary is deliberate and is what keeps
`SessionOps` protocol-agnostic. The generator is the thing that puts the types
back, so it must emit the codec too:

- one message type per protocol, one constructor per message or label, with a
  synthesised name for an unlabelled step;
- `encode : Msg -> Bytes` and `decode : Bytes -> Msg`.

**Recommendation: derive a `Json` codec**, which is what `Channel.serialize`
already does for actor messages, rather than inventing a binary format. It
composes to user payload types and keeps the first version honest about wire
compatibility, which is not a goal yet. Revisit only if a benchmark demands it.

**(review) This depends on `414baa5a`**, return-type-directed `from_json`,
which landed after this spec was first written. Before it, two or more
`derive Json` types in one module made the compiled backend refuse to build
at all, so "composes for free" was false on the day it was written. Two
consequences for the generator: the generated message type and any user
payload type that also derives `Json` now coexist; and the generated `decode`
**must annotate its result type**, because a `from_json` call whose result
type nothing pins is rejected.

### Where generation happens

Follow the precedent this same design line already set: **generate March
source, parse it, desugar it, append the declarations before typechecking.**
`Io_ops_gen.dispatch_wrappers_source` is injected exactly this way in
`bin/main.ml` (~L1747 on `main` as of 2026-09-10), and the reason given there
applies verbatim here — the generated code is then checked like any other
code, instead of being built directly as TIR where a mistake is a silent
miscompile.

**(review) Generation is opt-in, never unconditional.** The first draft said
"emit for every `DProtocol` in the module, unconditionally" and, three
sections later, that the existing `Chan`/`MPST` corpus must stay untouched.
Those cannot both hold: all eight protocol programs under
`specs/lang/types/accept/` would gain generated functions taking
`Cap(Session.Live)`, none of them uses `Session`, and seven declare capability
manifests that do not include it. So:

- **Recommended trigger: an attribute on the protocol declaration**, in the
  spirit of `@[vectorize]` and `@[no_alloc]` — explicit, per protocol, and the
  March idiom for opting a declaration into a compiler behaviour. Whether the
  parser accepts an attribute on `DProtocol` today is step 0 of the build; if
  it does not, that is a small parser change and still the right shape.
- The fallback, generating whenever the module declares `needs Session.Live`,
  is zero-syntax but implicit; use it only if the attribute proves costly.
- Either way the generated code takes `Cap(Session.Live)` parameters, so the
  module must declare `needs Session.Live` and the existing needs check must
  see the generated declarations. A protocol opted in without the grant gets
  the ordinary "declares no grant" diagnostic, which is the right answer.

Not `--test`-gated: a protocol's endpoints are production code.

## Item 2 mostly dissolves

The earlier framing had "handler typing" as a separate item, on the grounds
that Maty types handlers by input session type *and* actor state together, and
March has only the state half free from closures.

With states as nominal types, the generated wrapper's signature already says
which state a handler is installed at and which state it must produce. The
guarantee arrives as ordinary type checking of generated code, which is how
Maty itself is implemented — generated typed APIs over a transport, not a new
compiler backend, as its own paper states. So there is no flow-sensitive
effect system to build.

**The residual, which the nominal encoding genuinely does not give:**

- **Progress.** Linearity forces every state to be consumed exactly once, so a
  session cannot be silently abandoned in straight-line code. It does not
  force an event-driven endpoint to ever be *reached*: a handler that is never
  invoked because no message arrives leaves its state unconsumed at runtime,
  where the type system has already stopped looking. A liveness property, out
  of scope, worth stating so nobody claims it.
- **Cross-role agreement at runtime.** Duality and multiparty consistency are
  checked on the projection at declaration time. Two peers compiled from
  *different versions* of a protocol will still disagree. A protocol version
  or digest exchanged at `register` would catch it; not in the first version.
- **The transport is trusted.** A transport that delivers to the wrong endpoint
  breaks session fidelity and no generated type sees it.

## Item 3: the actor-hosted endpoint — (review) blocked, not small

The first draft called this "unblocked and small". Half of that is right. A
`Cap(Session.Live)` does reach an actor handler as a message payload, verified
on both backends:

```march
actor Ep do
  state { n : Int }
  init  { n: 0 }
  on Attach(c : Cap(Session.Live)) do
    let _ = Session.close(c, 7)
    { state with n: state.n + 1 }
  end
end
-- prints "closed 7", interpreted and --compile, no --test
```

There is deliberately no ambient transport, so a message is the right way in.
And with #404/#405/#407 landed, such an actor may also log and read the clock
and still be mockable.

**What the first draft got wrong is where the endpoint state lives.** It said
"in the actor's own state". Measured: a linear field in actor state that the
handler consumes and the `{ state with … }` update silently retains is
accepted with no error and no warning. That is the parameter-bound-record
gap of finding L3 in `specs/lang/linear-types.md`, except L3 promises a
warning and here there is nothing. An endpoint state held in actor state
therefore has **no** linearity guarantee, which is the one thing this design
exists to provide.

Two prerequisites, neither designed yet:

1. **A place to keep the state that the checker actually tracks.** Either the
   L3 gap is closed for actor state, or the endpoint state does not live in
   actor state at all — it rides in each message and is `let`-bound inside the
   handler, where tracking is real. The second is buildable today and is the
   recommended shape; it also matches Maty, where state travels with the
   handler.
2. **A transport whose `suspend` delivers into a mailbox.** Today's `suspend`
   installs a closure. An actor-hosted endpoint needs a `suspend` that records
   "deliver the next message on this endpoint to pid P as an actor message",
   the "Actor/network" transport the parent design listed as an option and
   nobody has designed. It is a second transport, not a change to the
   dictionary.

This is still the demonstration the whole line was for. It is now its own
follow-on, sequenced after the binary and multiparty generators land.

## Verified live (2026-09-03, re-run and extended 2026-09-10)

Every load-bearing claim above, with the probe that established it. Exit codes
measured directly, never through a pipe. Compiler built from `main` at
`137737f3`; no linearity-related commit landed between it and `0.4.0`.

| claim | probe | result |
|---|---|---|
| Nested modules can hold generated state types and transitions | `mod Gen` with two types and a transition fn | runs, prints |
| `always_linear type` catches **reuse** of a stale state | same value passed to two consuming calls | exit 1, "used more than once" |
| `always_linear type` catches **abandoning** a state | state bound and never consumed | exit 1, "was never used" |
| … also when the state was **returned from a function** | `let st = step(mk())`, abandoned; and used twice | exit 1 both |
| `linear` on a *parameter* does **not** give either guarantee to the caller | reuse probe with a plain type and `linear` param | exit 0, silently accepted |
| **(review)** a linear state passed into a **lambda** parameter, abandoned | `run(fn st -> …)` never touching `st`, annotated and not | **exit 0, no warning** |
| **(review)** … used twice inside the lambda | same, `fin(st)` twice | exit 1 |
| **(review)** … a **named** function's parameter, abandoned | `fn drop_it(st : S1)` | exit 1 |
| **(review)** a linear **actor-state** field consumed and retained | `sink(state.st)` then `{ state with n: … }` | **exit 0, no warning** |
| **(review)** the `Yield` token is unforgeable from outside | `Gen.Yield(Gen.Secret)` in the user module | exit 1, "I cannot find `Secret`" |
| **(review)** … and the honest callback is accepted | `run(fn st -> Gen.finish(st))` | exit 0 |
| **(review)** `ptype Yield` hides the type *name* | user signature naming `Gen.Yield` | "does not export `Yield`" |
| The session checker does not know `Session` | grep for `Session` in `typecheck_session.ml` | no match |
| A `Cap(Session.Live)` reaches an actor handler by message | the actor above | both backends |

The fifth row is the trap: the qualifier must be on the **type**, and
`specs/lang/linear-types.md` records the related finding L8 that a `linear`
return type alone does not propagate to a plain `let`. A generator that emits
`linear` parameters instead of `always_linear` types would produce an API that
looks safe and checks nothing. The sixth row is the second trap, found only by
probing the exact shape the API uses.

## Decisions to settle while building, not before

1. **Which payload types may cross the boundary.** Scalars, `String` and
   `Bytes` are free. User types need the derived codec to exist. Start by
   rejecting what will not encode, with a diagnostic naming the payload type
   and the protocol step, rather than emitting code that fails later.
2. **Where the generated module hangs.** `Stream_Prod` as a sibling module is
   the simplest; a nested `mod Stream do mod Prod do … end end` reads better
   and is confirmed to work. Pick one and pin it in a test, because it is in
   user-visible names and cannot be changed quietly afterwards. Whichever is
   chosen, `Secret` must be private to the *generated* module, not to the
   user's, or the token is forgeable.
3. **Access points.** `register(ap, role)` takes an `Int` today. A generated
   API should name the protocol's access point rather than pass a bare zero.
4. **Multiparty `from`.** `SMRecv` carries the sender role, so a generated
   handler can be given a typed sender instead of the raw `Int` the fixture
   ignores.

## Out of scope — do not re-expand

- **Fixing the `Chan`/`MPST` runtime.** It stays a same-thread conformance
  checker. This work routes around it; it does not replace or repair it.
- **`recv` in the dictionary**, and direct-style blocking over a swapped
  transport. The parent design excluded it and nothing here needs it.
- **A new effect system.** See "Item 2 mostly dissolves".
- **Wire compatibility across protocol versions.** Noted as a residual above.
- **Closing the two linearity holes.** Filed separately; this design does not
  depend on either fix, by construction.

## Order of work

0. **(review)** Confirm the opt-in attribute parses on a `protocol`
   declaration, or add it. Nothing else can be tested end to end without the
   trigger.
1. Message type and codec for one protocol, generated and injected. No
   endpoint API yet. Prove the generated declarations typecheck and round-trip,
   with a second `derive Json` type in the same module to exercise the
   `414baa5a` dependency.
2. State types, the `Yield` token, and transitions for a **binary** protocol,
   `Stream` first, since its expected output is the existing fixture. Include
   the choose-branch rule and its diagnostic.
3. Rewrite `test/session/stream_replay.march` to call the generated API, and
   require the trace to stay byte-identical. **(review)** Note what that proof
   rests on: the consumer today suspends *then* emits on the same raw
   endpoint, and the typed API forces emit first. The trace is unchanged only
   because this transport enqueues on `emit` and drains after the handler
   returns; a transport that delivered inside `emit` would not give the same
   trace. Say so next to the fixture.
4. A negative fixture per guarantee: wrong order, replayed state, abandoned
   session in straight-line code, **and abandoned state inside a callback**,
   which is the one the token exists for. Each must fail to compile, and each
   must be shown failing before it is trusted.
5. Multiparty, on `Relay` (3 roles), which the parent design already used as
   its cross-check.
6. The actor-hosted endpoint, once item 3's two prerequisites exist.

## Tests

- Golden: the rewritten `stream_replay`, trace unchanged, both backends.
- Reject corpus: four `specs/lang/types/reject/` cases from step 4. A generated
  API whose misuse still compiles is worthless, so these are the load-bearing
  tests, not the accept cases.
- Unit: projection to generated-source, pinned for `Stream` and `Relay`, so a
  change in emitted shape is a readable diff rather than a downstream failure.
- The existing `Chan`/`MPST` accept/reject corpus must be untouched. With
  generation opt-in this is now achievable; if it moves, this work has reached
  into the old path, which it must not.

## Relevant files

- `lib/typecheck/typecheck_session.ml` — `project_protocol`, `project_steps`,
  `dual_session_ty`; reused unchanged
- `lib/typecheck/typecheck.ml` — `validate_step`, the `ProtoChoice` arm where
  the choose-branch rule is missing
- `lib/typecheck/typecheck_types.ml:103` — `session_ty`
- `lib/ast/ast.ml:370` — `protocol_def`, `protocol_step` (was :341 on
  2026-09-03)
- `lib/typecheck/io_ops_gen.ml` + `bin/main.ml` (~L1747) — the
  generate-source-and-inject precedent
- `lib/ast/json_dispatch.ml` — return-type-directed `from_json` (`414baa5a`)
- `stdlib/session.march` — the transport capability
- `test/session/stream_replay.march` — the artifact this must reproduce
- `specs/lang/linear-types.md` — `always_linear`, findings L3 and L8
