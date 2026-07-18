# Interface impl coherence — design + implementation spec

**Status:** design / decision-needed (resolves the open divergence filed in
`specs/lang/core-march.md` §4.4.3 and `specs/lang/core-march-types.md` §2.3
`(T-Impl)` step 1, todos.md L120). Companion to the linear/affine slice
(`specs/plans/2026-07-17-closure-scalar-abi-uniform-ptr.md` is unrelated; this
is a separate type-system deliverable).

## The problem (verified)

`register_impl_shape` (`lib/typecheck/typecheck.ml:5745`) computes an impl's
instance type and **unconditionally prepends** it to `env.impls` — a
`ty list StrMap.t` keyed by *interface name* — with no lookup-before-insert
(`:5788-5791`):

```ocaml
{ env with impls =
  (let key = idef.impl_iface.txt in
   let lst = Option.value ~default:[] (StrMap.find_opt key env.impls) in
   StrMap.add key (inst_ty :: lst) env.impls) }
```

So two `impl Speak(Dog)` blocks for the identical `(interface, type)` pair both
typecheck with **no diagnostic** (`--check` exit 0, confirmed live). The two
backends then resolve the ambiguity **differently**:

- **Interpreter** dispatches through `impl_tbl` (`lib/eval/eval.ml:262`), a
  `(iface, type) → value` **Hashtbl** — `Hashtbl.replace` means *last
  registration wins*.
- **Compiled** resolves the method during monomorphization against `env.impls`
  (the prepended list) — a different, order-sensitive selection.

Result: a program with overlapping impls runs a **different method body** on
each backend — deterministic per backend, but divergent between them. This is
the exact class the differential oracle is meant to catch, but it is
declaration-legal today so nothing flags it.

**Blast radius (measured 2026-07-17):** the stdlib has **zero** real duplicate
impls (a line-anchored `impl Iface(Type` scan over `stdlib/*.march` finds no
`(iface,type)` declared twice; the apparent `impl Eq(BigInt)` "duplicate" is a
doc-comment at `bigint.march:13` vs the real impl at `:544`). `builtin_impls`
(`typecheck.ml:1453`) pre-registers Int/Float/String/Bool for Eq/Ord/Show/Hash.

## The decision to make

§4.4.3 frames this as a language-design choice with two families:

**(A) Coherence — reject overlapping impls at declaration time** (Rust/Haskell
orphan-free coherence). At most ONE impl per `(interface, type-head)`; a second
overlapping impl is a compile error. Dispatch is then unambiguous *by
construction*, so both backends agree with no runtime policy at all.

**(B) A shared deterministic selection policy** — allow overlaps but make both
backends pick the same winner (e.g. most-specific-wins, or a defined
declaration order). Requires a specificity lattice or a total order both the
interpreter and the monomorphizer honor identically.

**Recommendation: (A), coherence.** It is the principled fix: it removes the
ambiguity rather than standardizing a surprising resolution of it, needs no
cross-backend selection machinery (the hardest part of B to get byte-identical),
and matches the mental model every mainstream typeclass/trait system uses. B
keeps a permanent "which impl runs?" cognitive cost and a second place
(interp *and* compiled) that must stay in lockstep forever. Coherence is also
strictly easier to relax later (a future `overlapping impls` opt-in) than to
retrofit onto B.

The rest of this spec designs **(A)**. Three open sub-decisions are called out
inline as **[DECIDE]** — they narrow the policy, not the direction.

## The coherence rule

**Definition (overlap).** Two impl heads `impl I(τ₁)` and `impl I(τ₂)` for the
same interface `I` *overlap* iff `τ₁` and `τ₂` **unify** — i.e. there is a
substitution of their free type variables making them equal. Examples:

| `τ₁` | `τ₂` | overlap? |
|---|---|---|
| `Dog` | `Dog` | yes (identical) |
| `Dog` | `Cat` | no |
| `List(a)` | `List(Int)` | **yes** (`a ↦ Int`) |
| `List(a)` | `Option(a)` | no (different head ctor) |
| `Pair(a, a)` | `Pair(Int, Bool)` | no (`a` can't be both) |
| `Pair(a, b)` | `Pair(Int, Bool)` | yes |

**Rule (T-ImplCoherent).** When registering `impl I(τ)`, if any already-registered
impl head for `I` overlaps `τ` (including `builtin_impls`), reject with a
coherence error. Otherwise register.

**Staging.** Ship the check in two stages so the high-value, zero-false-positive
case lands first:
- **Stage 1 — exact overlap:** `τ₁` and `τ₂` are structurally equal after the
  same normalization `register_impl_shape` already applies (record→`TRecord`
  expansion, tvar canonicalization). Catches the reported `impl Speak(Dog)` × 2
  and every accidental copy-paste duplicate. Cannot false-positive.
- **Stage 2 — unifiability:** full `unify`-based overlap (the `List(a)` vs
  `List(Int)` row). Requires a fresh-instance unify that does not mutate the
  stored heads. Higher value (catches parametric overlap) but needs the
  parametric-impl corpus swept first (Stage 2 gate).

## Sub-decisions

- **[DECIDE-1] Builtin override.** Does `impl Eq(Int)` (a user impl overlapping
  a `builtin_impls` entry) error, or silently override the builtin? Recommend:
  **error** — coherence includes builtins; a user who wants a different `Eq(Int)`
  should say so via a newtype. (Rejecting is also what prevents the exact
  `impl_tbl`-vs-mono split for primitive types.)
- **[DECIDE-2] derive/satisfy vs manual.** A `derive(Eq)` (or `satisfy`) that
  generates `impl Eq(T)` for a `T` the user ALSO wrote `impl Eq(T)` for is a real
  overlap (§4.4.4). Recommend: the **generator skips** when a manual impl already
  covers the pair (derive is "fill the gap"), so an explicit impl always wins and
  no coherence error fires for the generated one. Alternative: error and force the
  user to drop the `derive` — noisier.
- **[DECIDE-3] Orphan rule.** Coherence and orphan rules are separate: coherence
  = "≤1 impl per pair"; orphan = "the impl must live in the interface's OR the
  type's defining module." Without an orphan rule, two *unrelated* modules can
  each define a conflicting impl and which one is in scope depends on load order
  — coherence alone catches the collision at registration, but the diagnostic
  will point across modules. Recommend: **land coherence now; file the orphan
  rule as a follow-on** (it interacts with the flat type namespace — see below).

## Enforcement design

1. **Carry the impl span.** `env.impls` is `ty list StrMap.t` today — it has no
   span, so a coherence error cannot cite the *other* impl. Change the value to
   `(ty * Ast.span) list` (or add a parallel `impl_spans` side table keyed by
   `(iface, normalized-ty-key)`). The `impl_def` carries `impl_iface.span` /
   the block span; thread it into `register_impl_shape`.
2. **Check before insert** in `register_impl_shape` (`:5788`): fold the existing
   list looking for an overlapping head (Stage 1: structural `=` on the
   normalized `inst_ty`; Stage 2: `unify`-in-a-fresh-copy). On a hit, emit the
   error and DO NOT insert the duplicate (keep the first — deterministic).
3. **Builtins.** Seed the overlap search with `builtin_impls` for the interface
   (already materialized at `:2191`) per [DECIDE-1].
4. **Pass placement.** `register_impl_shape` is pass-1 (shape pre-registration),
   run once per impl before bodies are checked — the right place: the error fires
   exactly once per duplicate, before dispatch resolution.
5. **Normalization parity.** Reuse `register_impl_shape`'s own `lenient_ty`
   (record→`TRecord` expansion at `:5769-5777`, tvar canonicalization) for BOTH
   sides of the comparison, so a nominal-vs-structural spelling of the same record
   type is correctly seen as overlapping (mirrors the dispatch-visibility fix that
   motivated the expansion).
6. **Interp defense-in-depth.** Change `impl_tbl` registration
   (`eval.ml`, the `Hashtbl.replace` at the DImpl fold) to detect a
   pre-existing entry for the same `(iface,type)` — with coherence enforced at
   typecheck this can never legally fire, so make it an internal assert / warning
   rather than silently replacing. This closes the "last-write-wins" leak if an
   impl ever reaches eval without going through the coherence gate (e.g. a REPL
   fragment).

## Diagnostic (shape)

```
-- ERROR
Duplicate implementation: `impl Speak(Dog)` conflicts with an existing
implementation of `Speak` for `Dog`.
  first defined here:  foo.march:12
  conflicting here:    foo.march:31
A type may implement an interface at most once (coherence). If you meant a
different behavior, wrap the type in a newtype and implement the interface on
that.
```

For Stage 2 (parametric), name the overlap witness: "`impl Show(List(Int))`
overlaps `impl Show(List(a))` (with `a = Int`)".

## Cross-backend + divergence closure

Once declaration is coherent, `impl_tbl` (interp) and the monomorphizer
(compiled) each see exactly one impl per `(iface,type)` — they agree by
construction, closing the §4.4.3 divergence at its source. Update:
- `core-march.md` §4.4.3: retitle from "Known divergence" to "Resolved by
  coherence" with the rule and its witnesses.
- `core-march-types.md` §2.3 `(T-Impl)` step 1: replace the "open divergence,
  cross-references §4.4.3" note with `(T-ImplCoherent)`.
- `test/test_oracle.ml`: any `known_divergence` entry that was an impl-overlap
  program now MATCHES (or is rejected at `--check`) — graduate it.

## Interaction with the flat type/ctor namespace

Coherence keys on `(interface-name, normalized-type)`. Both resolve by **bare
name** (the no-per-module-type-namespace design point, core-march-types §2.5) —
the same flatness that blocks linear-types L4. This is fine for coherence
(bare-name keys are exactly what makes two `impl Speak(Dog)` collide) but means
the eventual **orphan rule** (DECIDE-3) will need module-qualified type identity
on `TCon` — the same namespace overhaul L4 waits on. File orphan-rule work
behind that.

## Implementation plan (Stage 1)

- **Task 1 — Blast-radius sweep + witnesses.** Sweep `stdlib/`, `examples/`,
  `test/native/`, `specs/lang/**` for any real `(iface,type)` declared twice
  (line-anchored `impl` scan + a `--check` run of every corpus file with a
  temporary warn-on-overlap build). Confirm zero (stdlib already clean). Add
  witnesses: `reject/tNN_impl_coherence_duplicate` (two `impl Speak(Dog)`, EXPECT
  "Duplicate implementation"), `accept/tNN_impl_distinct_types`
  (`impl Speak(Dog)` + `impl Speak(Cat)`), `accept/tNN_impl_distinct_ifaces`
  (`impl Speak(Dog)` + `impl Walk(Dog)`). Bump the types INDEX counts + Check C.
- **Task 2 — Carry the span.** Change `env.impls` to `(ty * span) list` (or a
  side table), thread `impl_def` span into `register_impl_shape`, update the two
  other readers of `env.impls` (`:5790` here + any dispatch/`impl_matches_ty`
  consumer) for the new shape. No behavior change; suite stays green.
- **Task 3 — Exact-overlap check + diagnostic.** Add the lookup-before-insert in
  `register_impl_shape` (structural `=` on normalized `inst_ty`, seeded with
  `builtin_impls` per DECIDE-1), emit the coherence diagnostic, keep the first
  impl. Turn the reject witness green; confirm the accept witnesses stay green;
  full suite green.
- **Task 4 — Interp defense + divergence-doc closure.** Make `impl_tbl`'s DImpl
  insert assert-on-duplicate; retitle §4.4.3, update §2.3 `(T-Impl)`, graduate
  the oracle `known_divergence` entry; mark todos.md L120 done.

## Implementation plan (Stage 2 — parametric overlap, gated)

- **Task 5 — Parametric-impl corpus gate.** Enumerate every parametric impl in
  stdlib/corpus (`impl I(F(a))` shapes) and check pairwise unifiability under the
  proposed rule; confirm no *legitimate* pair overlaps (e.g. no stdlib relies on
  `impl Show(List(a))` + a more-specific `impl Show(List(Int))` both existing).
  If any does, that pair is the real design tension — escalate.
- **Task 6 — Unifiability check.** Replace the structural `=` with a
  fresh-instance `unify` (copy both heads' tvars before unifying so stored heads
  are not mutated); Stage-2 witnesses (`reject` List(a)/List(Int),
  `accept` List(a)/Option(a)); full suite green.

## Risks

- **Span refactor reach (Task 2):** `env.impls`'s shape is read in ≥2 places;
  missing one silently drops coherence for that path. Mitigate: grep every
  `env.impls` / `.impls` read and update together (same discipline as the
  closure-ABI four-boundary landing).
- **Builtin false-positive (DECIDE-1):** if "override builtins" is chosen
  instead, the seed-from-`builtin_impls` step is dropped — but then a user
  `impl Show(Int)` silently shadows the builtin on one backend and not the other
  again. Recommend rejecting.
- **derive/satisfy double-count (DECIDE-2):** if the generator does not skip, a
  `derive(Eq) type T` plus a hand-written `impl Eq(T)` newly errors — a real
  behavior change for existing code. The corpus sweep (Task 1) must include
  `derive`/`satisfy` sites, not just literal `impl` blocks.
- **Stage 2 legitimate-overlap escape (Task 5):** parametric overlap is only
  safe to forbid if nothing legitimately relies on specificity. The gate is
  mandatory before Task 6.

## Stage 1 — LANDED (2026-07-17)

Tasks 1–3 shipped; Task 4 partially (docs). The user-vs-user duplicate check is
live: `register_impl_shape` does a lookup-before-insert on `canonical_impl_key`
(alpha-normalized head), `env.impls` now carries the decl span so
Pass-1/Pass-2 re-registration (same span) is not mistaken for a duplicate
(different span). Witnesses `reject/t79`, `accept/t83`, `accept/t84`. Suite green
(eval 233 / compiler 514 / snapshots 29 / stdlib 809 / types 163).

**DECIDE-1 (builtin override) DEFERRED — empirically forced.** Rejecting a user
impl that overlaps a built-in (`impl Eq(Int)`) was implemented, but the
blast-radius sweep (running the full suite) found **6 interface-machinery test
fixtures** (test_eval declarations 15/17, test_compiler typecheck 18/20/48/50)
that legitimately re-implement built-ins on primitives (`impl Eq(Int)` /
`impl Ord(Int)`) to exercise constraint discharge and default methods. Enabling
the builtin-overlap error breaks all six. So built-ins are seeded into
`env.impls` with `dummy_span` and SKIPPED by the coherence check; turning
DECIDE-1 on is its own change + a test-migration pass (move those fixtures to a
user newtype). The high-value user-vs-user case ships without it.

**Still open:** Task 4's doc retitle of `core-march.md` §4.4.3 / §2.3 `(T-Impl)`
(the divergence is now closed for the user-vs-user case), the oracle-graduation
of any impl-overlap `known_divergence`, DECIDE-1, DECIDE-3 (orphan rule, blocked
on the flat namespace), and Stage 2 (parametric unifiability overlap).
