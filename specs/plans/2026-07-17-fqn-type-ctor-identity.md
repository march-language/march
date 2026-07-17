# Fully-qualified type & constructor identity — design + staged plan

**Status:** design / decision-needed. Architectural overhaul of name resolution
for **types and constructors**, to give every declaration a fully-qualified
canonical identity instead of the current flat bare-name namespace. This is the
shared upstream blocker for at least four filed items:

- linear-types **L4** (`always_linear` name-collision infects a same-named user type)
- interface **impl-coherence orphan rule** (`specs/plans/2026-07-17-interface-impl-coherence.md`, DECIDE-3)
- constructor-namespace **cross-talk** (exhaustiveness sees a foreign module's ctor)
- the **opaque-type asymmetry** (`core-march-types.md` §2.5: a private `ptype`'s bare name is nominally referenceable cross-module)

Fixing the namespace once unblocks all of them; patching each locally trades one
soundness hole for another (verified for L4 — see below).

## Ground truth: the current model (verified 2026-07-17)

March already resolves **values** toward qualified identity, but **types and
constructors** are resolved toward *bare* identity — the inconsistency is the
whole bug.

**Types.** `surface_ty`'s `canon_name` (`lib/typecheck/typecheck.ml:2672`)
**collapses a qualified reference to its BARE form**: it tries `lookup_type
bare` and, if the bare name resolves at the right arity, emits `TCon(bare,
args)` (this is the `9001e4c0` "qualified-path ↔ bare unification"). So:
- Every `TCon` in the typed IR carries a **bare** name.
- `env.types : int StrMap.t` (`:473`) is one flat map; a type is registered
  under BOTH its bare name (`:7725` `StrMap.add name.txt`) and its qualified
  name (`:8484` `StrMap.add full_path`), sharing the bare key across modules.
- Two modules that each declare `type Handle` produce the SAME `TCon("Handle")`
  — "literally one nominal type" (§2.5's no-per-module-type-namespace design
  point). Unification treats them as equal because equality is bare-name.

**Constructors.** `env.ctors : ctor_info list StrMap.t` (`:474`) keys by bare
ctor name to a LIST of `ctor_info` (each carrying `ci_type`, the parent type —
already qualified in one path, `:960` `ci_type = mod_name ^ "." ^ parent_type`).
A ctor name shared by two types has both infos in one list; disambiguation is by
`ci_type` at the use site, which is fragile when the parent type itself is
bare-collapsed.

**Values (the contrast — already half-done).** desugar's `qualify_module_refs`
(`lib/desugar/desugar.ml:2109`) rewrites `EVar "f"` → `EVar "Mod.f"` for
nested-module bodies; `check_fn` registers both bare and qualified fn names
(`:5643`); module VISIBILITY is a typecheck concept (`pub_set`, `pub`/`pfn`).
So values move toward qualified identity + visibility gating; types/ctors do not.

**The always_linear infection, precisely (verified).** `always_linear_types :
string list` (`:518`) holds BARE names; auto-promotion is `List.mem tname
always_linear_types` by bare name (`:5108`, `:5254`, `:5492`). A user `type
Handle = H(Int)` with an unused `h : Handle` param **errors "never used"** — the
stdlib `Handle`'s linearity leaks onto the same-named user type through the bare
name, with zero `linear` keywords in the user program. The bare-name entry is
*load-bearing*: legitimate stdlib-`Handle` code refers to it bare and relies on
that match, so removing the bare key regresses real linearity guarantees. No
linearity-local fix distinguishes the two `Handle`s because `TCon` has no
identity to check.

## The decision

**Adopt fully-qualified canonical identity for types and constructors, resolved
from surface bare/aliased references at compile time.** The FQN (declaring
module + name) is the identity used for equality, registry keys, and
property-attachment; bare names and aliases are surface ergonomics that a
resolution step maps to the FQN. This finishes the model values already use.

This does NOT make source verbose: you keep writing `Handle` and `use Foo as
Bar`; the resolver maps them to `Stdlib.Handle` / `Foo.Thing`.

**The one genuinely new behavioral rule** (everything else is mechanical): under
`MARCH_LIB_PATH` auto-discovery, what does a bare name resolve to when several
modules declare it and the current module imports none explicitly? Proposed:

1. **Local shadows import.** A module's own declaration of `T` is the meaning of
   bare `T` inside it, shadowing any imported/auto-discovered `T`.
2. **Single visible candidate resolves.** If exactly one non-local `T` is in
   scope (imported or prelude), bare `T` resolves to it.
3. **Ambiguous bare = error, not silent pick.** If two or more non-local `T`s
   are visible and none is local, bare `T` is a resolution error demanding
   qualification (`Mod.T`). (Today this silently resolves flat — the source of
   the cross-talk.)

Rules 1–3 are the behavior change; they are also exactly what closes L4 (rule 1
makes the user `Handle` distinct from stdlib's) and the ctor cross-talk (rule 1
gives exhaustiveness the local type's ctors).

## Constraints the overhaul must not break

These are what the flat design quietly buys today — the spike must preserve each:

- **Auto-discovery ergonomics.** `MARCH_LIB_PATH` slurps every `.march` file;
  today everything is flat-visible unqualified. The new rules must keep the
  common case (one declaration of a name) working with zero import ceremony —
  only genuine collisions change behavior.
- **Order-independent, per-file typecheck (forge).** `forge build` typechecks
  each lib file individually as its own entry (`project_forge_build_per_file_entry`);
  resolution must not depend on module load order.
- **Cross-module type sharing.** `9001e4c0` made `Mod.T` and bare `T` unify so a
  type flows across files without an import; the FQN model must still let a
  correctly-imported/qualified `T` unify with its declaration.
- **Codegen mangling + eval dispatch.** `TCon` names feed LLVM symbol mangling,
  `impl_tbl`'s `(iface,type)` key (`eval.ml:262`), and TIR lowering
  (`lower_types.ml`). Changing the canonical name changes mangled symbols and
  dispatch keys — a cross-backend, CAS-cache-invalidating change (bump discipline
  like the float-boxing flip).
- **Prelude/builtins stay unqualified-global.** `List`/`Option`/`Int`/… resolve
  to their prelude FQN with no import — a well-defined special scope, not a
  new exception.

## Stage 0 findings (spike run 2026-07-17)

**Collision census (measured by parsing `type`/ctor declarations).**
- **11 type-name collisions in stdlib** — the same bare type name declared in ≥2
  modules as *different* types: `State` (dist_supervisor / swim / swim_driver),
  `Value` (msgpack / dataframe), `Level` (compress / logger), `HEntry`
  (hash_map / hamt / map), `TransportError`, `ProcessResult`, `Tree`, `Upgrade`,
  `Conn`, `Header`, + 1. (An earlier line-anchored `bash` census reported 0 — it
  was wrong; the parse-based count is authoritative.)
- **9 ctor-name collisions across different parent types** (of 383 ctors):
  `Str`/`Null`/`Bool`/`Array` shared by `JsonValue`+`Value` (the exact
  Msgpack/Json case a prior compiled-only miscompile was fixed for),
  `HLeaf` (HEntry/Heap), `Row` (CsvRow/Row), `NotFound` (DnsError/FileError),
  `Text` (Mode/XmlNode), `Int` (Sig/Value).
- **0 collisions** between `examples/`+`test/native/` types and stdlib types.

**How the collisions coexist today (and why it's fragile).** `env.types` stores
only ARITY (`int StrMap.t`) so a bare-name type collision is harmless there *iff
arities match*; the real type identity is recovered downstream. Constructors are
disambiguated by an **accumulated pile of heuristics**, each born from a real
bug:
- `lookup_ctor` (`:785`) returns the HEAD of the per-name candidate list
  (most-recently-registered — order-dependent).
- `lookup_ctor_in_type` (`:796`) picks the candidate whose `ci_type` matches a
  KNOWN scrutinee/expected type — the actual disambiguator when type context
  exists.
- `add_ctor` (`:821`) runs a Pass-1 cross-module prebind (`d95fe942`) + a
  Pass-2 move-to-front so a module resolves its OWN ctors — its doc comment
  documents a sibling-ctor **shadowing regression** this fixed.
- the current-module-preference fix (`project_ambiguous_ctor_current_module`)
  patched a compiled-only miscompile where `Msgpack.Value.Array` (tag 5) vs
  `Json.JsonValue.Array` (tag 4) resolved to the wrong tag.

**Types have NONE of these heuristics** — `lookup_type` is a bare arity lookup
with no module preference — which is exactly why linear-L4 (and the exhaustiveness
cross-talk) bite on the type side while ctors mostly survive. So the flat
namespace has ALREADY caused ≥2 shipped bugs; this is not a hypothetical future
cost.

**Reframing:** the FQN overhaul is therefore not *new* machinery bolted on — it
**consolidates** `canon_name` + the four ctor heuristics + the current-module
preference into ONE principled resolver, and extends the identity types never
got. Net long-term complexity goes DOWN.

**Code inventory (every site that keys on a bare type/ctor name).**
| Site | File:line | Keys on | Change |
|---|---|---|---|
| `canon_name` (resolution) | `typecheck.ml:2672` | collapses qualified→BARE | invert to FQN |
| `lookup_type` | `typecheck.ml:784` | bare name → arity | resolve bare→FQN |
| `lookup_ctor` / `_in_type` | `typecheck.ml:785`/`796` | bare name, ci_type list | key by FQN parent |
| `add_ctor` prebind/move-to-front | `typecheck.ml:821` | bare name list | subsumed by FQN |
| `always_linear_types` | `typecheck.ml:518`,`5108`,`5254`,`5492` | bare name list | key by FQN |
| `env.impls` key | `typecheck.ml:490`,`5789` | bare iface name | (iface-FQN,type-FQN) |
| `impl_tbl` (interp) | `eval.ml:262`,`969`,`984` | `(iface,type)` bare Hashtbl | key by FQN |
| `type_name_of_value` | `eval.ml:943` | bare type name | resolve to FQN |
| `lower_types` TCon | `lower_types.ml:44`,`76` | carries bare name → TIR | carry FQN |
| `mangle_ty` | `mono.ml:118` | bare name → LLVM symbol | **CAS/golden pivot** |
| `resolve_impl_by_type` | `mono.ml:21` | bare type_name | FQN |

The canonical name flows `source → canon_name → TCon(bare) → TIR → mangle_ty →
symbol / impl_tbl key`. `mangle_ty` (`mono.ml:118`) is the point where a
canonical-name change becomes a mangled-symbol change — the CAS-invalidation +
`.ll`-golden re-baseline pivot the plan flags.

**Go/no-go: GO, staged.** The behavior-change blast radius is small and bounded:
rule 1 (local-shadows) is zero-risk on the 11 collisions (each module already
uses its OWN type); rule 3 (ambiguous-bare-error) can only fire if a THIRD
module references one of the 11 colliding names BARE while declaring neither —
Stage 1's resolver surfaces those exactly (expected: near-zero, since stdlib
cross-module refs already use qualified paths). The dominant cost is the
`mangle_ty` re-baseline (a flag-day, not a design risk).

## Staged plan

Big and hot-path (unification, mangling, cross-backend). Stage so each step is
independently green and the risky behavior change is isolated.

### Stage 0 — Spike & inventory (MANDATORY, no behavior change)
- Enumerate EVERY bare-name lookup of a type or ctor: `lookup_type`,
  `lookup_ctor`, `canon_name`, `name_is_variant`, `env.records`, `env.ctors`,
  `always_linear_types`, `env.impls` key, plus the eval + codegen + lower_types
  readers. Produce a table (file:line → what it keys on).
- Enumerate every reliance on flat cross-module sharing in `stdlib/` + `examples/`
  + `test/` (programs that reference a type declared in another file WITHOUT
  qualification or import) — this is the migration blast radius for rule 3.
- Decide the FQN spelling (reuse `module.member` as elsewhere; `current_module`
  is already threaded, `:522`).
- Deliverable: a written inventory + a go/no-go on the behavior rules, sized.

### Stage 1 — Carry FQN identity WITHOUT changing resolution
- Give `TCon` a resolved FQN as its canonical name: invert `canon_name`
  (`:2672`) to prefer the **qualified** identity when it is unambiguous, while
  keeping today's *resolution reach* (a bare ref still finds its declaration).
  Registries key by FQN with a bare→FQN resolution shim so no lookup site
  changes behavior yet.
- Unification: two `TCon`s equal iff same FQN. Prove no regression by keeping the
  bare→FQN shim total for the current single-declaration case.
- **The shim MUST be total — confirmed empirically (2026-07-17).** A naive
  shortcut that qualifies only *locally-declared* types (so `Main`'s `type Foo`
  becomes `TCon("Main.Foo")`) while leaving cross-module bare refs collapsing to
  `TCon("Foo")` BREAKS unification: the declaration and its cross-module
  references no longer share a name. Stage 1 is therefore atomic — resolution
  must produce the SAME canonical FQN at every site at once — not an incremental
  per-site rollout. (Learned while shipping the L4 linearity stopgap below.)
- Gate: full suite + oracle green, byte-identical golden/codegen output (the FQN
  must mangle to the SAME symbol as the bare name did for single-declaration
  types — verify with the preamble/golden diff, or accept a deliberate mangle
  change + CAS bump and re-baseline every `.ll` golden).

### Stage 2 — The resolution rules (the behavior change)
- Implement local-shadows-import + single-candidate + ambiguous-error (rules
  1–3) in the bare→FQN resolver. This is where a same-named user type becomes
  distinct.
- Migrate any Stage-0 blast-radius programs that relied on flat cross-module
  bare references (add the missing import/qualification).
- Witnesses: `reject` (ambiguous unqualified cross-module `T`), `accept`
  (local `T` shadows imported `T`), `accept` (qualified `Mod.T` resolves).

### Stage 3 — Flip the downstream consumers (the payoff)
- `always_linear_types`: key by FQN; auto-promotion checks the resolved TCon's
  FQN → **L4 (linearity half) already fixed as a stopgap (2026-07-17,
  `resolves_always_linear`, `accept/t81`)**; Stage 3 replaces that
  current-module-declaration heuristic with the clean FQN key and can drop the
  bare-name entry safely once identity is qualified.
- impl coherence: the orphan rule (interface-or-type-module) becomes expressible;
  the coherence key becomes `(iface-FQN, type-FQN)` → the coherence spec's
  DECIDE-3 unblocks.
- Exhaustiveness: check against the resolved type's own ctors → **cross-talk
  fixed**. Add a witness (user `type Handle = H(Int)` matches exhaustively).
- Opaque-type asymmetry: `ExType`/`ExRecord` can now be visibility-gated like
  `ExFn`/`ExValue` (§2.5's filed gap) — optional, same slice.

### Stage 4 — Constructor identity (optional follow-on)
- Give ctors a per-parent-type FQN identity so a bare ctor shared by two types
  resolves by the scrutinee's resolved type, not a `ci_type`-list scan.

## Risks

- **Hot-path unification change (Stage 1)** — every `TCon` comparison. A subtle
  FQN-vs-bare mismatch silently breaks type equality across the whole language.
  Mitigate: Stage 1 keeps resolution reach identical and is gated on a
  byte-identical (or deliberately-rebaselined) golden/codegen diff.
- **Mangling / CAS / cross-backend** — if the canonical name changes, mangled
  symbols and `impl_tbl` keys change; interp and compiled must move together and
  every `.ll` golden re-baselines. Treat Stage 1 as a flag-day with a CAS bump.
- **Migration surprise (Stage 2)** — rule 3 turns a previously-silent flat
  resolution into an error for genuinely-ambiguous cross-module bare names. The
  Stage-0 blast-radius sweep must find them all first; a surprise here breaks a
  user's `forge build`.
- **Auto-discovery scope creep** — the temptation to also add an explicit import
  system. Keep this overhaul to *identity + shadowing*; explicit imports are a
  separable follow-on (the current auto-discovery + these rules already fix the
  filed bugs).
- **Per-file typecheck order-independence (forge)** — the resolver must be a
  function of (declarations in scope), not load order; test with the forge
  per-file harness.

## Alternatives considered

- **(A) Full FQN identity (this spec).** Root fix; unblocks all four items;
  overhaul-sized.
- **(B) Targeted side-table of qualified identities** for JUST `always_linear`
  and impl coherence, leaving `TCon` bare. Smaller, but: it can't fix the ctor
  cross-talk or the opaque-type asymmetry (those are `TCon`-identity problems),
  and it adds a parallel identity notion that will drift from the bare `TCon`
  the rest of the compiler uses — a second source of truth. Rejected as a
  strategic dead-end, though viable as a stopgap if the overhaul is deferred.
- **(C) Ban same-name types across modules** (a collision diagnostic at
  declaration). Cheap and prevents the infection, but breaks the legitimate
  case (a module SHOULD be able to name its own `Handle`) and doesn't help
  qualified disambiguation. Rejected.

## Open questions for sign-off

1. **Scope of the behavior change:** ship rules 1–3 (local-shadows +
   ambiguous-error), or the minimal rule 1 (local-shadows) only, deferring the
   ambiguous-error until an import system exists?
2. **Mangling:** accept a deliberate canonical-name change (re-baseline every
   `.ll` golden + CAS bump), or engineer Stage 1 to mangle single-declaration
   types identically to today (no golden churn, more resolver complexity)?
3. **Explicit imports:** stay on auto-discovery + resolution rules (this spec),
   or fold in an explicit `import`/visibility model at the same time (larger, but
   avoids a second pass over the same code)?
4. **Sequencing vs. the stopgap:** land the impl-coherence Stage 1 (exact
   overlap) and a linear-L4 stopgap (alternative B) NOW for immediate value, then
   do this overhaul; or hold both for the overhaul so they're done once, cleanly?
