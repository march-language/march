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

## Stage-1 build-attempt findings (2026-07-17) — the carry is deeper than the stage list conveys

A bounded build attempt (read-through + recon subagent, no code change to the
carry) verified the exact surface and surfaced constraints the stage list
understates. Recording so the eventual carry does not re-discover them.

**Feasibility confirmed.** There IS a genuine pass-1 prebind
(`check_module_core:9173`, `pre_env` fold `:9328`, nested via
`prebind_mod_members:9183`) that registers EVERY type name+arity into
`env.types` — bare and qualified — across all modules BEFORE any body is
checked in pass 2. So a "multiply-declared bare name" collision set is soundly
computable after pass 1, which is the precondition for collision-conditional
canonical spelling.

**The bare name is keyed on FIVE surfaces that must move together (verified,
line-anchored):**
1. registration — `env.types`/`env.ctors`, bare add with SILENT overwrite and
   **zero** collision detection (`typecheck.ml:7746`, `:9352`; the only dup
   checks are within a single decl).
2. `mangle_ty` (`mono.ml:117-118`) — bare `TCon` name verbatim → LLVM symbol.
3. `lower_types` (`lower_types.ml:44`,`:76`) — name carried verbatim to TIR,
   never re-derived, so typecheck's bare name reaches `mangle_ty` unchanged.
4. exhaustiveness `ctors_for_type` (`typecheck.ml:3287`) — folds the WHOLE
   `env.ctors`, keeps every ctor whose `ci.ci_type` STRING-EQUALS the bare
   scrutinee name. This is the L4 ctor cross-talk: a user `Handle`(ctor `H`) and
   stdlib `Handle`(ctor `Handle`) both carry `ci_type="Handle"`, so both ctor
   sets merge → spurious `missing case: Handle(_)`.
5. eval dispatch — `impl_tbl` `(iface,type)` and `ctor_type_tbl` keyed on the
   bare type name (`eval.ml:8769`,`:8583`,`:948`); two same-named types collide
   on one slot (last-registered wins), the runtime analogue of the same bug.

**Four hard invariants a prior engineer ALREADY established under bare identity
— the carry must re-derive each (this is the real cost, not mangling churn):**
- **Ctor-tag stability across build modes.** `unqualified_module_deps` +
  `dependency_order_dmod_run` (`typecheck.ml:7040-7050`,`:7144-7151`) fix module
  CHECK ORDER specifically so a constructor's resolved type is identical to the
  single-entry (forge per-file) build — the comment states this is to NOT
  "perturb the constructor tags assigned during lowering." A qualified-identity
  change that shifts resolution can shift ctor tags → silent miscompile.
- **A qualified-ctor experiment was already TRIED and REVERTED.**
  `prebind_mod_members` (`:9233-9243`) documents that setting `ci_type` to the
  qualified `qname` made a cross-module `Mod.Telemetry.JobEnqueued` resolve to
  `TCon("...ConduitTelemetryEvent")` that would NOT unify with the bare
  `ConduitTelemetryEvent` every signature uses ("expected X but got Mod.X").
  Conclusion in-tree: "the type side already canonicalizes qualified->bare (see
  canon_name); the constructor side must agree by carrying the bare type." The
  FQN carry must overturn this deliberately and re-prove cross-module unification
  for BOTH type and ctor identity at once.
- **Cyclic-module order-independence.** Bare names are prebound (`:9214-9227`) so
  a referrer checked before its definer in a cyclic module graph still resolves —
  resolution must stay a function of declarations-in-scope, not order.
- **Opaque-ctor hiding.** `sub_opaque`/`sig`-driven suppression (`:9190-9196`)
  keeps a signature-opaque type's ctors unreferenceable cross-module; the new
  resolver must preserve this visibility gate.

**Ctor identity is COUPLED into the type carry for colliding names, not optional
(Stage 4).** `ctor_info` carries NO declaring-module field (`ci_type` bare only,
`:410-414`), so nothing — not exhaustiveness, not eval dispatch — can tell two
same-named types' ctors apart today. Of the 11 type collisions, several
(`Value`/`JsonValue` sharing `Str`/`Null`/`Bool`/`Array`) also collide on ctor
NAMES, and those ctors carry tags. So distinguishing the colliding TYPES forces
distinguishing their CTORS (a `ci_module`/qualified-`ci_type` change that touches
tag assignment) — Stage 4 folds into Stage 1 for the colliding set. Adding a
purely-additive `ci_module` (≈18 construction sites: prelude `:2187-2192`,
source paths `:7767`/`:9357`/`:9647`, registry `:981`) is the minimal metadata
that lets the DIAGNOSTIC-only exhaustiveness fix (byte-identical, no codegen)
land independently — it is the natural first committable slice of the carry.

**Revised sizing.** Collision-conditional mangling keeps every single-declaration
type byte-identical (the 11 collisions are stdlib-internal and absent from the
golden corpus), so the golden gate stays strong. But the carry is atomic across
the 5 surfaces AND must re-establish the 4 invariants above — genuinely a
multi-session flag-day, not a single sweep. Recommended cut order: (a) additive
`ci_module` + exhaustiveness disambiguation (diagnostic-only, byte-identical,
closes L4's ctor half); (b) collision-set + collision-conditional canonical
spelling in `canon_name` gated on byte-identical goldens; (c) thread FQN through
`mangle_ty`/eval dispatch for the colliding set with a CAS bump; (d) the rule-3
ambiguous-error + migration sweep.

## Cut (a) — LANDED (2026-07-17, commit 10b53ec0)

`ci_module` added to `ctor_info` and threaded through all ~19 construction sites
(both checking paths, both `prebind_mod_members` variants, both entry folds, the
registry-load path, prelude, REPL); `ctors_for_type` disambiguates the
exhaustiveness universe by current-module shadow. **L4 fully closed** (both
halves: `accept/t81` linearity + `accept/t82` ctor). Byte-identical backend
(codegen 421 goldens unchanged); full suite green. `ci_module` is NOT in
`add_ctor`'s dedup key, so it survives pass-1/pass-2 re-registration.

## Cut (b) — ATTEMPTED, REVERTED (2026-07-17); mechanism proven, third-subsystem blocker found

Implemented the full collision-conditional identity in typecheck and ran the
suite; **reverted** because it needs a third subsystem the plan hadn't named.
What was built (and worked): a per-compilation `multiply_declared_types :
StringSet.t ref` on `env` (bare type names declared by ≥2 modules, computed from
`ci_module` grouped over `env.ctors` + an entry-decl scan, seeded ONCE before
Pass 1); a shared `canonical_type_name env ~decl_module ~bare` that spells a
colliding name module-qualified and a singly-declared name BARE; wired into BOTH
`surface_ty`'s `canon_name` (type annotations, with local-shadows→qualified→
leave-bare resolution) AND `instantiate_ctor` (`:2922`, ctor result types) so a
declaration and its references agree; `ctors_for_type` taught to bare-ify the
(now possibly FQN) scrutinee name and filter by the module prefix.

**Result: the mechanism is sound for the common path.** L4 stayed fixed; `run_eval`
(233), `run_compiler` (514), `run_snapshots` (29), and `run_stdlib` (809) all
green; `run_codegen` **418/421** — only THREE fixtures failed, all with the
predicted `expected X but got Mod.X` unification split.

**The blocker (precisely): canonicalization happens in THREE subsystems that do
not share the collision set.** (1) Pass-1 `prebind_fn_scheme`, (2) Pass-2 body
checking, (3) — the one the plan missed — the **module-registry loader**
(`load_module_into_env` / `ensure_loaded`), which converts a stdlib/lib module's
exported signatures to types when that module is pulled in on demand, using its
OWN env, NOT the user compilation's `multiply_declared_types` ref. So a
registry-loaded `Msgpack` fn signature keeps a BARE `Value`, while the user
program's `instantiate_ctor` produces `Msgpack.Value` → `expected Value but got
Msgpack.Value`. Seeding the collision set before Pass 1 fixes paths (1)+(2) but
cannot reach (3): the registry loader ran in a different env. Failing fixtures:
`node_call_loopback`, `rpc_auto_enroll` (registry-loaded `Msgpack.Value`),
`zero_arg_closure_default` (its own `type Conn` flat-shared with a
during-compilation-loaded lib `Conn`).

**Fix direction for the next attempt (pick one, then re-run cut b):**
- **(pref) Late canonicalization pass.** Leave all three subsystems producing
  BARE `TCon`s as today; add ONE post-typecheck rewrite that, given the final
  collision set, renames every colliding `TCon(bare)` to its module-qualified
  FQN uniformly (types + ctor result types + registry-loaded signatures at
  once). One place, one collision set, no per-subsystem threading — sidesteps
  the reverted-experiment's unification split by construction because it runs
  after all three subsystems agree on bare.
- **(alt) Thread the shared collision-set ref through the registry loader** so
  `load_module_into_env` canonicalizes with the same set. Smaller surface but
  the registry loader is called from many sites and caches modules across
  compilations — the set is per-compilation, so cache invalidation gets subtle.

The reverted patch (collision set + `canonical_type_name` + `canon_name` +
`instantiate_ctor` + `ctors_for_type`) is a clean starting point for the
late-pass approach — most of it (the collision set, the shared speller) is
reusable; only the wiring moves from inline-at-`canon_name` to a post-pass.

### Correction (2026-07-17, on closer analysis): a late pass can't disambiguate type REFERENCES

The "rewrite every colliding `TCon` to FQN after typecheck" framing above has a
hole. Once typecheck **unifies** two colliding types to one bare `TCon("Value")`,
the module identity is GONE — a `TCon("Value")` in the IR carries no record of
which module's `Value` it was, so a post-typecheck pass has no more information
than typecheck did and cannot split them. Module identity survives ONLY at
**constructor** sites (via `ci_module`, cut (a)). So a working "late pass" must
key on CONSTRUCTORS, not type-references — i.e. it is really "module-qualify
constructor identity in lowering/mangle" (Stage 4), not a TIR-wide `TCon`
rewrite.

**And there is no active codegen bug forcing it.** At the cut-(a) checkpoint,
`run_codegen` is 421/421 GREEN — the 3 failures in the cut-(b) attempt were
INTRODUCED by the FQN change, not pre-existing. The 11 collisions are contained
today by ctor-keyed lowering (a `match`/construction keys on the NAMED ctors,
which carry `ci_module`, not the bare type) plus the disambiguation heuristics.
So Stage 4 would REPLACE fragile heuristics with principled identity (real
robustness value, and it consolidates the "pile of heuristics") but fixes no
live miscompile.

**Net triage after cut (a):** L4 (the actual user-facing bug) is fully closed;
codegen is sound; the two remaining FQN goals are (1) type SOUNDNESS — rejecting
cross-type confusion, which needs consistent FQN across ALL THREE
canonicalization subsystems DURING typecheck (the registry-loader problem; a
late/lowering pass does NOT deliver it), and (2) heuristic consolidation
(Stage 4, `ci_module`-keyed ctor identity in lowering; codegen-affecting, CAS
bump, no active bug). Neither is forced by a live bug, so the full carry is a
deliberate multi-session architectural investment to schedule on its own, not a
fix that must land now.

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
