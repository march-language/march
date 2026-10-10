# Capture sets on function types: design

Status: DESIGN, nothing built. Written 2026-10-10 against `8b6a4b7`.

Parent: `specs/2026-08-10-r1-stage-c-effect-rows-design.md`. That design chose
approach B (rows beside the type system) and recorded approach A (rows in `ty`)
as a future engine swap behind the `Cap_rows` boundary. This is that swap, in
its narrowest form.

Line numbers below are approximate and were read at the commit above.

## Goal, restated precisely

Give every function **value** a set that says what it reaches, carried in its
type, so the fact survives when the value is stored in data, returned, or passed
through a parameter.

Stage C already computes this fact per function **definition**: edges come from
`free_vars_expr`, so a function's row is what its free names reach. That is a
capture set. It is lost the moment a closure goes into a constructor, because
`TArrow of ty * ty` has nowhere to keep it.

The claim after this work: **a closure's reach is a property of its type, not of
whether an analysis can trace it back to the expression that built it.**

## What exists, and the hole they share

Three analyses trace a function value back to its creation site syntactically,
and each gives up when the value passes through data:

| Analysis | Where | Gives up as |
|---|---|---|
| per-function rows | `lib/caps/cap_rows.ml` | `unknown` |
| per-role grants | `resolve_root_value`, `typecheck.ml` ~7989 | `RVUnknown` |
| sendability of closures (planned, deferred) | send plan, phase 3 | `LOpaque`, a warning |

Stage C measured its version of the hole: 107 of 2453 stdlib functions carry a
transitive `unknown` (4.4%, August figure), clustered in `Seq`/`Flow`,
`Compress`, `Check` and `ChannelServer`. The residual gap it recorded is exactly
this: a function that builds a `Flow` and consumes it is refused, because
provenance does not survive an ADT payload.

Related facts this design relies on:

- `ty` has eleven constructors. `occurs`, `generalize` (`collect` and `copy`),
  `instantiate` (`inst`), `unify` and `pp_ty` are each exhaustive over it.
- `TArrow` is curried. Lowering uncurries into `Tir.TFn` (`lower_types.ml`).
- `Poly of int list * constraint_ list * ty` already carries constraints that
  are instantiated per use and pushed to `env.pending_constraints`.
- `env.cap_producer_ivars` is a side table keyed by variable id, propagated on
  var-var bind in `unify` and copied to fresh variables in `instantiate`. The
  mechanism proposed here is the same pattern.
- The stdlib env is cached by marshalling, which loses physical identity
  (`typecheck_env.ml` ~369). Any side table must be keyed by id, not by ref.
- Closures cannot capture a linear or affine value (`check_captures`,
  `typecheck.ml` ~1040).
- Hashes are computed over TIR (`lib/cas/hash.ml`), after types are lowered.

## Decisions already taken

Settled in discussion on 2026-10-10.

**D1. The set means "reaches", not "performs".** A closure that captures a
`Cap(X)` token and only forwards it has X in its set. This is the only case
where "holds" and "does" differ: to act on X a closure must reference something
that needs X, and that reference already contributes X. Carrying an unused cap
is acceptable. One atom kind serves grants, sendability and hot reload.

**D2. Sets do not cross actor boundaries.** Actor message types get no capture
parameter. A closure taken out of a mailbox has an unknown set at the receiver,
so a handler that invokes it cannot be certified under a narrow grant. The
creator stays charged where the closure is built, as today.

D2 is recorded as "strip to unknown". "Strip to empty" would let a handler
granted `Cap(IO.Console)` run a received closure that does network IO and still
certify. If that trust point is wanted, it needs its own decision.

## Approaches considered

### A1: capturing types on every type (Scala 3, CC<:box)

Any type may carry a set: `T^{c}`. Sets name term variables. Subcapturing is a
subtyping relation. Generics need boxing.

- Pro: the most general formulation, with a published soundness proof.
- Con: March has no subtyping in `unify`. Sets over term variables make types
  dependent. Every type-directed pass would have to relate wrapped and bare
  types. March does not need variable identity in sets, because linearity
  already handles identity and scoping.

### A2: effect rows as types (Koka)

The arrow carries a row type `<net, file | r>`, unified structurally.

- Pro: no side table. Rows are ordinary types.
- Con: row unification with open tails is a real change to `unify`. Closures
  with different closed rows fail to unify, so every arrow must be open, and
  the unifier then does row rewriting on every arrow-arrow unification.

### A3: a variable in the slot, lower bounds beside it (RECOMMENDED)

The arrow's third field is always a `TVar`. A side table maps variable id to a
lower bound: a set of atoms plus a set of other capture variables. Unification
only ever equates two capture variables. Inclusion appears only as a lower bound
on a fresh variable.

This is Talpin and Jouvelot's type and effect discipline. It gives subeffecting
without subtyping in the unifier.

- Pro: `occurs`, `collect`, `copy` and `inst` each gain one recursive call. No
  new variable kind. No arm of `unify` can fail because of a set. Errors arise
  only at discharge points, which already exist.
- Con: equality on variables is coarser than inclusion (see "Precision"). The
  side table needs its own level discipline (see "The level invariant"), which
  is the one place this can be unsound.

**Decision: A3.** It delivers the fact with the smallest change to the most
load-bearing code in the compiler, and it reuses a pattern
(`cap_producer_ivars`) that already works in the two functions that matter.

## The calculus (A3, precise)

### Representation

```
TArrow of ty * ty * ty        (* third field: always a TVar, the capture var *)

type atom =
  | ACap of string            (* a cap lattice path *)
  | AFn of string             (* qualified top-level name; expanded by Cap_rows *)
  | AOpaque of span           (* unknown reach; the span is the witness *)

type bound = { atoms : atom set; lower : int set }   (* ids of capture vars *)

env.capture_bounds : (int, bound) Hashtbl.t          (* keyed by var id *)
```

`solved(r) = atoms(r) ∪ ⋃ solved(r')` for `r'` in `lower(r)`, least fixpoint.
If a slot resolves to `TError` (error recovery does `r := Link TError`), its
solution is `{AOpaque}`.

### Curried chains

A multi-parameter function is a chain of arrows. All arrows in one chain share
**one** capture variable. Its bound includes the capture variables of every
parameter type, so a partial application holds what was supplied to it.

`List.map` comes out as `(a ->{f} b) ->{m} List(a) ->{m} List(b)` with
`m ⊇ {AFn "List.map"} ∪ {f}`. This is stage C's `deps`, expressed in the type.

### Rules

| Site | Effect on the table |
|---|---|
| lambda, local `fn` | fresh `r` at the current level. `r ⊇` atoms of the body (below) and the capture vars of everything it captures |
| reference to top-level `g` as a value | instantiate `g`'s scheme. Its capture var already carries `AFn g` |
| application of a head whose type is an arrow with var `h` | the enclosing function or lambda gets `⊇ {h}` |
| arrow-arrow `unify` | unify the two capture vars |
| var-var bind of capture vars | merge the two bounds into the survivor |
| `instantiate` | copy each quantified capture var's bound to its fresh var, renaming ids |

Atoms of a lambda body:

- `AFn n` for each top-level name free in the body. This is the existing
  `free_vars_expr` edge.
- `ACap p` for each builtin cap the body uses directly, and for each captured
  local whose type is a concrete `Cap(p)` (D1).
- a lower edge to every capture var that occurs in the type of a captured
  local: arrow slots, and the capture parameter of data types (next section).

### Captures at an unresolved type

A captured local may have type `a`, an unbound variable, when the lambda is
checked. Whether `a` later contains a capture var is not yet known.

Record an obligation `CCapture (r, ty)`: "`r` includes every capture var in
`ty`". Flush obligations in `generalize` before `collect`, and at module end.
An obligation whose type is still an unbound variable at generalization becomes
a constraint in the scheme, `Poly (ids, CCapture (r, a) :: cs, ty)`, and is
discharged at each instantiation, where `a` is known. This reuses the existing
`constraint_` path.

For grants this case is harmless by parametricity: a value at type `a` cannot
be invoked. It matters for consumers that read the set as "holds".

### The level invariant

`occurs` lowers levels structurally. A capture var mentioned only in a bound is
not structure, so it would keep a stale level, be generalized, and leave an
outer variable pointing at a template.

Example of the failure: inside a let-bound `f`, a lambda `fn x -> h(x)` is
stored into an outer cell. The lambda's var `r` has `r ⊇ {h}`. Unifying with
the outer cell lowers `r` but not `h`. `h` is then quantified, and a later
`f(net_fn)` does not reach the cell's set. The cell holds a network closure and
its type says it holds nothing.

**Invariant: for every edge `r ⊇ r'`, `level(r') ≤ level(r)`.**

Maintained at three points:

1. adding an edge: lower `r'` to `level(r)` if it is higher;
2. `occurs` lowering a capture var: lower every var in its bound, recursively;
3. merging on var-var bind: the survivor takes the lower level, then (2).

Consequence: the bound of any variable that is not quantified mentions only
variables that are not quantified.

`generalize` must also collect through bounds. A capture var reachable only
through the bound of a quantified var, and above the generalization level, is
quantified with it. Otherwise it is shared across instantiations while its own
bound mentions per-instance variables.

This section is the soundness argument for the whole design. It should be
reviewed, and ideally stated as a lemma in the Lean plan, before code lands.

## Data types

`type Flow(a) = Flow(() -> Step(a))` has no place for a set. An arrow slot
alone does not close the `Seq`/`Flow` gap.

A type is **capturing** if a constructor argument or field type mentions an
arrow or another capturing type. Computed as a fixpoint over each declaration
SCC. A type parameter that is later instantiated with an arrow does not count:
that arrow is visible in the argument.

A capturing type gets one hidden trailing parameter: `TCon ("Flow", [a; r])`.

- Inside the declaration, every arrow and every nested capturing type uses the
  declaration's own `r`. One set per value, all closures inside collapsed.
- A user-written `Flow(Int)` elaborates with a fresh `r`. So does a
  user-written arrow type.
- `pp_ty`, hover, `forge search`, impl head matching, the impl overlap check
  and interface arity all ignore it.
- `convert_ty` drops it, along with the arrow slot, so nothing reaches TIR.

Records are structural, so their arrows carry their own slots and need nothing.

**Actor message types are exempt (D2).** A type whose constructors are
`ci_is_actor_msg` gets no hidden parameter. Its constructor instantiation gives
each arrow argument a fresh var. In **construction** position that var has no
bound, so the sender's set is dropped. In **pattern** position it gets
`AOpaque`, so the receiver sees unknown. Marking both positions would poison
the sender's own variable through unification.

## Discharge and the existing consumers

No new check. The set feeds the checks that exist.

**`Cap_rows`.** Today an application whose head cannot be classified sets
`sd_unknown`. With a slot, the head has a capture var `h`, and the seed records
`h` instead. The solve becomes a joint fixpoint: `AFn g` expands to
`row(g).caps` (and to `AOpaque` if `row(g).unknown`), and `row(f).caps` absorbs
`solved(h)` for each invoked `h` in `f`. Both sides are monotone over a finite
lattice. `unknown` survives only where a solution contains `AOpaque`.

`check_fn_grants` and `check_main_grant` are untouched. They read rows.

**Per-role grants.** Where `resolve_root_value` returns `RVUnknown`, fall back
to the solved set of the role body's type before refusing.

**Sendability.** The send plan's phase 3 closure check can read the set where
it would have reached `LOpaque`. That plan is deferred and stays deferred.

**Diagnostics.** Each atom records a witness span, first writer wins, as
`cap_rows` provenance does today. Messages keep the stage B shape and name the
capture site: "holds `IO.Network` via `fetch`, captured here".

## Answers to questions raised in discussion

**Syntax: none.** Sets are inferred and never printed.

**Hashing: sets do not enter hashes.** They are erased before TIR, and hashes
are over TIR. The capability delta for hot deploys keeps its existing channel,
`env.cap_closures`. Adding sets to a hash would be a separate, deliberate
decision with a cache-hit cost.

**Interpreter and compile parity: structural.** Everything is typecheck-side
and reached from `check_module_core`.

**Session types.** `generalize` and `instantiate` skip `TChan` because
`session_ty` has no polymorphic variables. An arrow in a payload would break
that. Recommendation: a closure in a session payload gets `AOpaque` at the
receiver, the same rule as D2. Choreography payloads need a JSON codec, so they
cannot carry closures at all.

**Emitted witnesses.** `scheme_witnesses` and `inst_witnesses` will see capture
vars among the quantified ids. The emitter filters them, or `types-oracle`
churns.

**Builtins that store a closure and run it later** (`task_spawn`,
`http_server_listen`, timers, signal watch). Each signature must link the
argument's var to its own by hand. The send plan's boundary registry is the
list to audit.

## Precision

Two closures that flow to the same place share a set. A parameter passed
alongside a dirtier closure is dirtied for the rest of that function. Named and
let-bound functions are unaffected, because each use instantiates.

This only ever grows a set, so the failure mode is a spurious refusal at a
discharge point, never a missed one.

## Staging and gates

1. **Mechanical prep.** Route arrow construction through a helper. `TArrow`
   appears 746 times in `lib/typecheck`, 662 of them in
   `typecheck_builtins.ml`. No behaviour change. Gate: `ir-oracle` and
   `types-oracle` unchanged.
2. **Slot and table, inert.** The field, the rules, the level invariant.
   `MARCH_DUMP_CAPTURE_SETS=1` dumps solved sets. No consumer.
3. **Capturing data types, inert.** Hidden parameter and its erasure.
4. **Measure.** Four gates, all required before any consumer reads a set:
   - **Agreement.** For every top-level function, the cap projection of its
     solved set equals `fn_transitive_capability_closures_tbl`. Any difference
     is a bug in one of them.
   - **Erasure.** `ir-oracle` byte-identical, `determinism-oracle` green.
   - **Cost.** Typecheck time over the stdlib, against a budget set before
     measuring. Proposed: under 5% slower.
   - **Blast radius.** Count of functions whose solution contains `AOpaque`,
     broken down by source.
5. **Feed `Cap_rows`.** Gate: the `Seq`/`Flow` cluster leaves `unknown`. The
   remaining sources are mailbox receives, `TError` and erasure points. Full
   corpus sweep, as stage C did, through the real binary against the real
   stdlib-prepended shape.
6. **Per-role grants.**

## Testing plan (RED first)

- Unit tests on the bound table as a pure module: merge, instantiate with
  renaming, collect through bounds, solve.
- **A level-invariant regression test** built from the example above: a
  let-bound function that stores a closure over its parameter into an outer
  cell, called twice with different arguments. It must fail before the
  invariant is implemented.
- New `capture_sets` group in `test_compiler.ml`: a self-built `Flow` consumed
  under a narrow grant (accept), a `Flow` holding a network closure under a
  console grant (reject, chain named), partial application, a closure in a
  record field, a closure in a list, a captured unused cap token (D1), a
  closure received from a mailbox (D2, refused), and at least one test on the
  flattened-prelude shape.
- Corpus accept/reject pairs under `specs/lang/types/`.
- The agreement gate as a permanent test, not a one-off measurement.

## Out of scope, recorded

- **Once-callable closures over linear captures.** Independent of this work
  and user-visible on its own. The set would only trigger it. The rule belongs
  in `TLin`. Whether calling a `TLin` arrow consumes it today is unchecked.
- **A hot-reload marker** (an epoch or "holds code" atom). The representation
  admits it. No consumer is designed here.
- **A written annotation surface**, including a declared ceiling on a message
  field as an escape from D2.
- **Subcapturing in `unify`.** If the precision cost above proves real, lower
  edges at application sites are the next step, not subtyping.

## Open questions

1. **Closures in actor state.** State is ordinary data and gets a capture
   parameter. Which function discharges it: `init`, each handler, or nobody?
2. **Erasure points.** Values typed without structure (`Any`-like types,
   `cap_dict` dictionaries, FFI callbacks) lose the set. Refuse or assume top,
   per site. Not yet enumerated.
3. **Polymorphic captures for "holds" consumers.** The `CCapture` constraint
   is the least certain part of this design. It may be simpler for sendability
   and hot reload to combine the set with a structural walk of the
   instantiated type.
4. **Cached schemes.** The marshalled stdlib env must carry
   `capture_bounds`. Whether any other path persists schemes is unchecked.
5. **Where the Lean plan stands.** It targets cap attachment completeness.
   This moves part of "attachment" into typing.

## Corrections found during implementation

(Empty. Record them here, not in place, as the stage C design does.)
