# FQN impl-coherence & dispatch identity — design + staged plan (A-full)

**Status:** implemented (2026-07-21). Tasks 0-6 landed on branch
`claude/fqn-dispatch-identity-stages`: collision-set + dev harness (a77f1142),
globally-unique runtime tags + forced Boxed repr for colliding types, lowering
module-qualified impl symbols (bd… Task 3), runtime tag-switch dispatch
(97f1c275), interpreter `iface_method_tbl` qualification (8d858b01), and the
flag-day that drops the builtin-only coherence gate so ALL interfaces get the
declaring-module relaxation (this commit). Witnesses: `accept/t89`
(typecheck) and `test/imports/speak_collision_native` (cross-backend runtime,
interpreted + compiled). **Known residual gap (deferred, tracked separately):**
when two colliding same-short-name types ALSO share a CONSTRUCTOR name, dispatch
misroutes in BOTH backends (the shared ctor collapses to one dispatch identity) —
this needs the `ci_module.Type.Ctor` extra qualification layer described below,
which was NOT built in this slice. Implementation companion to
`specs/plans/2026-07-17-fqn-type-ctor-identity.md` (the umbrella FQN overhaul)
and `specs/plans/2026-07-17-interface-impl-coherence.md` (the coherence check
itself). This doc resolves the specific slice the umbrella doc names as
"impl coherence: the coherence key becomes `(iface-FQN, type-FQN)`" (Stage 3) and
"module-qualify constructor identity in lowering/mangle" (Stage 4), scoped to
what interface impls actually need, using **constructor declaring-module
identity (`ci_module`)** as the carrier rather than a TIR-wide `TCon` rewrite.

Branch of record: `claude/fqn-impl-coherence-636503` (forked from the
`claude/compiled-bugs-a01119` tip, which is where the coherence check landed via
PR #38 / commit `2233109b`; the check is NOT on `main`).

## Problem (verified 2026-07-20)

The impl-coherence check (`register_impl_shape`, `types_overlap`,
`lib/typecheck/typecheck.ml`) keys type identity on the **bare short type name**.
Two genuinely-distinct same-short-name ADTs from different modules
(`AeLib.AeDir` vs `AeLib2.AeDir`) both lower to `TCon("AeDir")`, so the check
reports a false "Overlapping implementation" when each declares its own
`impl Eq(AeDir)`.

**Reproductions (worktree binary, `--check`):**
- Per-module `impl Eq(AeDir)` in two modules → `Overlapping implementation`
  (both lower to `TCon("AeDir")`). Same for a user interface `impl Speak(Thing)`
  across two modules, and even two nested modules in one file.
- The `test/imports/adt_eq_native` fixture stays green **only** via its blanket
  `impl Eq(a)` workaround (confirmed `--check` exit 0). Rewriting it with
  per-module `impl Eq(AeDir)` triggers the false overlap.
- Writing a **qualified** head `impl Eq(AeLib.AeDir)` does NOT fix it: it
  registers `TCon("AeLib.AeDir")`, which no longer matches the bare `TCon("AeDir")`
  at the dispatch site → `"AeDir does not implement Eq"`. So the fix must be
  internal, not a source-level qualification.

**Why the check exists (not just over-conservatism).** Both backends key impl
dispatch on the bare type name (interp `impl_tbl : (iface, type)` from
`type_name_of_value`/`ctor_type_tbl`; native `mono.resolve_impl_by_type` +
the generated impl symbol at `lower.ml:1081-1082`). A **spike** (coherence
temporarily disabled) compiled two distinct same-short-name types with distinct
`impl Speak(Thing)` bodies (`"from-A"` / `"from-B"`):

```
native output:  from-A
                from-A     ← second call silently ran the FIRST body
```

The two impls mangle to one symbol (`Speak$AeDir.speak`), last-write-wins. So
naively relaxing the typecheck without fixing dispatch converts an honest error
into a silent cross-backend miscompile. The coherence check is preventing that.

## Decision

Adopt **A-full**: give interface impls fully-qualified (declaring-module) type
identity across the coherence check AND both dispatch backends, so any two
same-short-name types can each implement any interface and dispatch to the
correct body. Identity rides on **`ci_module`** (already on every `ctor_info`,
including registry-loaded ones) and, at codegen, on the **impl's declaring
module** (`mod_prefix`) plus the value's **runtime constructor identity** — NOT
on qualifying `TCon` type-references (the reverted cut-b path).

Two invariants make this safe where cut-b failed:

1. **Discharge stays bare; selection is qualified.** `env.impls` entries keep a
   **bare** `inst_ty` so `discharge_constraints` (`List.exists` over
   `impl_matches_ty`, `typecheck.ml:6113-6115`) still satisfies a bare
   dispatch-site constraint. The declaring-module qualifier is *separate
   coherence metadata* consulted only by the overlap test. Qualifying `inst_ty`
   itself reintroduces the cut-b `expected X but got Mod.X` split (empirically
   reconfirmed via the qualified-head repro).
2. **Identity is per-entry `ci_module`, not a per-compilation collision set.**
   Cut-b's third-subsystem blocker was that the module-registry loader
   (`load_module_into_env`, `typecheck.ml:938`) ran in its own env and could not
   see the user compilation's collision set. `ci_module` is set at ctor-creation
   time in ALL three subsystems — pass-2 body check (`= env.current_module`,
   `:7970/8035/8048`), pass-1 prebind (`= prefix`, `:9451/9478/9569/…`), and the
   registry loader (`= mod_name`, `:1001`) — so keying on it is consistent across
   all three without shared state.

### The one hard sub-problem and its resolution

Native **general-user-interface** dispatch for colliding types (`speak(x)` where
`x : AeDir` could be either module's) cannot be resolved statically: the TIR type
of a *reference* is bare `TCon("AeDir")` and, per the umbrella doc's own
correction, module identity of a type reference is erased by unification (it
survives only on **constructors**). Two options:

- **(rejected) Qualify TIR type references** — this is cut-b; broke unification +
  the registry loader; full `mangle_ty`/CAS/`.ll` re-baseline.
- **(chosen) Runtime ctor-tag dispatch** — give the two impl bodies distinct
  symbols via the impl's declaring module (`mod_prefix`, available at
  `lower.ml:1081`, applied collision-conditionally), then select at the call site
  by the value's **runtime constructor identity** (`ci_module`-qualified, and it
  survives) → declaring module → symbol. This mirrors `ensure_adt_eq_fn`
  (`llvm_eq.ml:51`), which already does exactly this for `==` by reading per-tag
  layouts from module-qualified `ctor_info` keys.

## Subsystem map (grep-verified 2026-07-20)

### Typecheck (coherence)
- `env.impls : (ty * Ast.span) list StrMap.t` keyed by **interface name**
  (`typecheck.ml:503`); entry = `(inst_ty_bare, span)` (`:6005`).
- `register_impl_shape` (`:5924`): `inst_ty = lenient_ty idef.impl_ty` (bare,
  `:5966`); overlap test `types_overlap t inst_ty` skipping `dummy_span`
  built-ins (`:5986-5998`).
- Pass-1 folds accumulate impls **cross-module into one list** (`:9556/9610/9618`
  in `check_module_core`, `:9847` in `check_module_with_env`) but do **not**
  rebind `current_module` to the impl's module — so the declaring module isn't
  currently visible at coherence time. **This is the missing wiring.**
- `ci_module` on `ctor_info` (`:415`); `ctors_for_type` already has the
  current-module shadow pattern to reuse (`:3333-3366`, esp. `:3356-3364`).
- `discharge_constraints` CInterface arm (`:6108-6116`) — must stay bare.
- Caveat: `add_ctor` dedups excluding `ci_module` (`:861-864`), so the **bare**
  ctor key keeps only one module's `ci_module`; both survive only under the
  **qualified** ctor keys. Resolution must not rely on the bare-key `ci_module`.

### Interpreter (`lib/eval/eval.ml`)
- `impl_tbl : (string*string, value)` (`:262`); writes at `:8897`/`:9218` with
  `type_name` from the **bare** `idef.impl_ty` (`:8856`/`:9181`).
- `ctor_type_tbl : (ctor, type)` bare (`:300`); populated `:8671/8937/9244`
  (variant), builtins `:7956/9056`; read by `type_name_of_value` (`:948`).
- Type-dispatched builtins: `is_type_dispatched_iface` = Show/Eq/Ord/Hash
  (`:292-294`); they dispatch by value type via `type_name_of_value`.
- Interp has no `ci_module` but has `module_stack` (`:361`, impl's/DType's
  enclosing module) at the write/populate sites.
- Lockstep tables when qualifying `ctor_type_tbl` values: `record_type_tbl`
  (`:8677/…`), `ffi_type_decl_tbl` (`:8686/…`, feeds actor routing `:6913`).
- Outlier: Drop/`own` keys on the raw ctor **tag** (`:3494`), not
  `type_name_of_value` — handle separately.

### Native (`lib/tir/…`)
- **Collision pin:** `lower.ml:1069-1082` — `type_name` from bare `impl_ty`
  (`:1069`), `mangled = "Iface$Type.method"` (`:1081`, e.g. `Speak$AeDir.speak`
  for BOTH types), `fn_name = mangled` last-write-wins (`:1105`), dispatch entries
  bare (`:1109-1110/1116-1117`).
- `mangle_ty` (`mono.ml:139-153`) emits the `TCon` name verbatim; the name-string
  source is `lower_types.ml:44/76` (bare). This source ALSO feeds the CAS impl
  key (`cas/serialize.ml:126-130` `write_ty`) — so it is the true "flag-day
  pivot". Keep it BARE for single-declaration types (collision-conditional).
- `resolve_impl_by_type` (`mono.ml:21-33`) progressively strips `.`-prefixes;
  call-site `type_name` from `first_arg_ty` (`:318/375/521/632`), bare.
- Model: `ensure_adt_eq_fn` (`llvm_eq.ml:51`, `mangle_ty_for_eq` splits on `.`
  `:27-39`) keys on module-qualified `ctor_info` paths (`:235-264`).
- `mod_prefix` is threaded through `collect_iface_impls` (`lower.ml:1044/1123`)
  and currently used only to rename impl-body internals — it is the
  declaring-module source for the impl symbol.

## Staged plan

Each stage is independently green and separately committable. **Stage 1 lands
first** (release-relevant, byte-identical goldens); 2–3 complete A-full.

### Stage 1 — Coherence: distinguish distinct declaring modules (typecheck-only)
- Thread the impl's declaring module into `register_impl_shape` (rebind
  `current_module` at the four pass-1 fold sites, or pass the module explicitly).
- Compute a **coherence identity** for the impl head = `(bare-type-name,
  declaring-module)`, derived from `current_module` for the canonical
  (impl-in-type's-module) case, using the `ctors_for_type` shadow pattern.
- Change the overlap test so two heads with the **same bare name but different
  declaring modules do NOT overlap** — **but SCOPE this relaxation to the
  type-dispatched builtin interfaces (`Eq`/`Ord`/`Show`/`Hash`)**, whose native
  dispatch routes through generated ctor-qualified structural functions
  (`ensure_adt_eq_fn`) and is therefore correct compiled. A GENERAL user
  interface dispatches on the bare type name in BOTH backends and mangles two
  same-short-name impls to ONE symbol, so relaxing it there would SILENTLY run
  the wrong body compiled (verified `from-A`/`from-A`) — those collisions MUST
  stay rejected until Stage 3. Keep `inst_ty` bare in `env.impls`.
- Effect: two `impl Eq(AeDir)` (distinct modules) accepted (`adt_eq_native` drops
  its blanket `impl Eq(a)`); two distinct-module `impl Speak(Thing)` (general
  interface) still rejected; genuine same-module duplicate (t79) still rejected;
  parametric overlap (t80) unchanged.
- Witnesses: accept `t88_impl_distinct_modules` (builtin `Eq`), reject
  `t82_impl_general_iface_collision` (general `Speak`); keep reject/t79,
  reject/t80, accept/t83, accept/t85.
- Gate: full suite + oracle green; goldens byte-identical (no mangling change).

### Stage 2 — Interpreter dispatch qualification
- Compute a declaring-module-qualified `type_name` at the `impl_tbl` write
  (`eval.ml:8856/9181`) from `module_stack`.
- Store qualified type names as `ctor_type_tbl`/`record_type_tbl` values
  (`:8671/8677/8937/8942/9244/9249`) so `type_name_of_value` returns the
  qualifier; keep `ffi_type_decl_tbl` consistent; handle Drop-by-tag (`:3494`).
- Effect: general interp interface dispatch selects the correct body for
  same-short-name types.
- Gate: full eval + stdlib suites; a new interp witness (two modules, distinct
  `impl Speak(Thing)` bodies, correct output).

### Stage 3 — Native collision-conditional symbols + runtime ctor-tag dispatch
- Build the collision set (short type names declared by ≥2 modules) from the
  lower-time type-def / qualified `ctor_info` keys.
- **Collision-conditionally** qualify the impl symbol + dispatch entries at
  `lower.ml:1069-1082/1109-1117` by the impl's declaring module (`mod_prefix`),
  so colliding types get distinct symbols (`Speak$AeLib.AeDir.speak`) while
  single-declaration types stay byte-identical (CAS keys + snapshots unchanged).
- Emit **runtime ctor-tag → declaring-module → impl-symbol** selection at
  general-interface call sites whose static type is a colliding short name
  (vtable-style tag dispatch, following `ensure_adt_eq_fn`).
- Effect: the spike case prints `from-A` / `from-B`; flip `reject/t82` (general
  same-short-name collision) to an accept + a compiled cross-backend witness.
- Also retire the Stage-1 builtin-name gate: Stage 1 scopes the coherence
  relaxation to `Eq`/`Ord`/`Show`/`Hash` by INTERFACE NAME (matching the
  interpreter's `is_type_dispatched_iface` convention). Once general-interface
  dispatch is ctor-correct, that name gate is unnecessary and its one exotic hole
  (a user interface shadowing one of those four names with an extra
  non-structural method could receive the relaxation while its extra method still
  dispatches on the bare type name) closes with it.
- Gate: full codegen suite; snapshot review of any intentionally-changed IR;
  CAS-cache correctness check on a value-revealing program; oracle green.

### Stage 4 — Docs, witnesses, cross-backend validation
- Update `specs/todos.md` (move item to Done) + `specs/progress.md` (capability).
- Cross-backend witness: two distinct same-name-type impls run correct bodies
  **interp and native**; genuine duplicate still rejected.
- Note the residual: `TCon` type-references remain bare (no type-reference
  qualification); that full carry stays the deferred umbrella-doc flag-day.

## Stages 2+3 combined — refined approach (2026-07-20, general-interface case)

Building the FULL general-user-interface same-short-name case (chosen: land
interp + native + typecheck-relax together). Two empirical findings reshape the
plan beyond the clean stage split above:

**Finding A — the interpreter's general-interface dispatch is ALREADY broken for
multiple impls, by NAME not type.** `eval.ml`'s `DImpl` arm binds each general
interface method under its BARE method name in `env` (`:8877`
`(mname.txt, clo) :: env`); a second `impl Speak(_)` shadows the first, so
`speak(x)` resolves to the last-bound method regardless of `x`. Verified:
`impl Speak(Dog)` + `impl Speak(Cat)` (DISTINCT short names) prints `meow`/`meow`
interpreted (should be `woof`/`meow`) while native is correct — a pre-existing,
uncovered interp-vs-native divergence (the `accept/t83` Dog/Cat witness is
`--check`-only, never run). Only the type-dispatched builtins (Eq/Ord/Show/Hash)
dispatch by value type today, via `impl_tbl[(iface, type_name_of_value)]`.
→ **Layer 1 (interp):** generalize that mechanism — bind every interface method
to a first-arg **type dispatcher** that looks up `impl_tbl[(iface,
type_name_of_value arg0)]`, instead of name-binding the concrete method.
`impl_tbl` is already populated for general interfaces (`:8897`). Methods that
can't dispatch on arg0 (e.g. `from_json : JsonValue -> a`) keep today's
name-binding (already special-cased). Same-short-name types then need
`impl_tbl` keys + `type_name_of_value` qualified by declaring module
(collision-conditional, from `module_stack`) so `NA.Thing` vs `NB.Thing` don't
collide — the original Stage-2 work.

**Finding B — regular ADT ctor tags are PER-TYPE 0-based, so a runtime tag
switch cannot identify the module.** `llvm_toplevel.ml:488` assigns
`ce_tag = tag_idx` (0,1,2… within each type), so `NA.Thing.TA` and `NB.Thing.TB`
BOTH get tag 0. The design's "runtime ctor-tag → declaring-module" step assumed
tags identify the module; they do not. Actor-msg ctors already get
globally-unique tags (`:437` `actor_msg_tag` base `0x0100_0000`) — the model.
→ **Layer 2 (native):** collision-conditionally give a colliding type's ctors
**globally-unique tags** (reuse the actor-msg scheme) AND key `ctor_info` by a
**module-qualified** ctor identity (`ci_module`, threaded into lowering — the
umbrella doc's Stage 4), so `EAlloc`/`match`/dispatch all resolve the same tag.
Qualify the generated impl symbol by declaring module (`lower.ml:1081`). Then a
call `speak(x)` whose static type is a colliding short name emits a switch on
`x`'s (now module-unique) tag → the right impl symbol. Single-declaration types
keep per-type tags + bare identity → CAS keys + goldens byte-identical.

**Layer 3 (typecheck):** once both backends dispatch correctly for colliding
general interfaces, drop the `iface_native_type_dispatched` gate in
`register_impl_shape` so the relaxation covers ALL interfaces, and flip
`reject/t82` → an accept + a compiled + interp cross-backend runtime witness
(`from-A`/`from-B`).

**Sequencing:** build Layer 1 (interp, most tractable, fixes the Dog/Cat
divergence), then Layer 2 (native, the flag-day), then Layer 3 (relax) — all on
`claude/fqn-impl-coherence-stage2-636503`, landed together. Gate at each layer;
final oracle + full-suite + snapshot review; CAS value-reveal check for Layer 2.

### Layer 2 — concrete implementation steps (native flag-day), verified harness

DEV HARNESS: `MARCH_DEV_RELAX_COHERENCE=1` env-var bypass in `register_impl_shape`
(TEMPORARY — remove when Layer 3 lands) lets a same-short-name general-interface
program compile. Baseline confirmed: `mod Top { mod NA{type Thing=TA;
impl Speak(Thing)->"from-A"} mod NB{type Thing=TB; impl Speak(Thing)->"from-B"} }`
compiles and MISCOMPILES natively `from-A`/`from-A` today (interp is correct after
Layer 1). Fixture at `scratchpad/spike/spike.march`.

Root cause (grep-verified): (1) two `impl Speak(Thing)` mangle to ONE symbol
`Speak$Thing.speak` (`lower.ml:1069-1082`, bare type_name), last-write-wins;
(2) the mono dispatch table maps `speak → [("Thing", sym)]` with both impls under
bare "Thing" (`resolve_impl_by_type` first-wins); (3) ADT ctor tags are PER-TYPE
0-based (`llvm_toplevel.ml:488`) so `NA.Thing.TA` and `NB.Thing.TB` both = tag 0
→ no runtime discriminator.

The four coordinated changes (collision-conditional — a short type name declared
by ≥2 modules; single-declaration types stay byte-identical):
1. **Collision set** at `build_ctor_info` (`llvm_toplevel.ml:424`): scan the
   `TDVariant` names (module-qualified at `lower.ml:1267/1269`, e.g. `NA.Thing`)
   → the set of short names (last `.` segment) appearing under ≥2 module prefixes.
2. **Global tags for colliding types**: in `build_ctor_info`, a colliding type's
   ctors get globally-unique tags (reuse the actor-msg counter scheme at `:437`,
   base `0x0100_0000`) instead of `ce_tag = tag_idx`. Keep the module-qualified
   `ctor_info` key (`ci_module`) so `NA.Thing.TA`/`NB.Thing.TB` are distinct
   entries and `EAlloc`/`match` (which resolve via the same key) get the new tag.
3. **Qualified impl symbol + dispatch entry** (`lower.ml:1069-1082/1109-1117`):
   qualify `type_name` by the impl's declaring module (`mod_prefix`) for colliding
   types → distinct symbols (`Speak$NA.Thing.speak`) + distinct dispatch entries.
4. **Runtime tag-switch at the call site** (`mono.ml` dispatch, `:318/375/521/632`
   + `resolve_impl_by_type`): when the call's static arg type is a colliding short
   name, emit `switch(tag(arg0))` over the colliding types' (now module-unique)
   tags → the matching qualified impl symbol, instead of a single static call.
   Model: `ensure_adt_eq_fn` (`llvm_eq.ml:51`) reads per-tag layouts from
   module-qualified ctor_info keys.

CAS/golden: the TCon-name/tag change flows through `mangle_ty` + `write_ty`
(`cas/serialize.ml:126`); collision-conditional keeps single-declaration output
byte-identical (verify with `git status test/snapshots/` + a CAS value-reveal).
If any mangled symbol changes, add the flag to `cas_flags` (bin/main.ml, 2 sites).

Layer 1b (interp same-name) rides alongside: qualify the `iface_method_tbl` key +
`type_name_of_value` (`eval.ml`) by declaring module for colliding short names
(collision set from the same ≥2-modules scan, computed at DType eval via
`module_stack`), else bare. Layer 3: replace the dev bypass with the real drop of
the `iface_native_type_dispatched` gate; flip `reject/t82` → accept + add a
compiled+interp `from-A`/`from-B` runtime witness.

### Layer 2 — the value-representation solution + dispatch codegen (execution-ready)

**The blocking sub-problem (found while implementing step 2).** A runtime tag
switch needs every colliding value to carry a readable, module-unique
discriminator. But two representation optimisations defeat a naive tag change:
- **Single-ctor / nullary types** (e.g. `Thing = TA`) may be lowered to an
  immediate or an unallocated constant with **no stored tag word** — nothing to
  switch on at runtime.
- **Niche-repr types** (Option-shaped: one nullary + one payload ctor, `None`
  encoded as a null pointer) special-case small tags; blindly bumping a niche
  type's ctor tag to `0x0100_0000` corrupts the niche encode/decode.

So the tag can't just be reassigned globally — the colliding type's whole
representation has to guarantee a readable discriminator.

**Solution — uniform tagged representation for colliding types (collision-
conditional).** For any type in the collision set, the value-representation
classifier (the `niche_repr_of_concrete` / boxed-vs-immediate decision in
`llvm_data.ml` / `llvm_case.ml`) must emit the **uniform heap-boxed, tag-word
representation** — never niche, never single-ctor-immediate. Then:
- every colliding value stores an `i32` tag (`emit_store_tag`, `llvm_data.ml:25`)
  that `emit_load_tag` (`:18`) can read at a dispatch site;
- the tag is the **global** tag from step 2, so it is module-unique;
- `EAlloc` and `match` for the colliding type already resolve via the
  module-qualified `ctor_info` key, so they store/read the same global tag —
  self-consistent.
Because it is gated on the collision set, single-declaration types keep niche/
immediate reprs → their emitted IR, CAS keys, and `.expected` snapshots are
byte-identical. Verify with `git status test/snapshots/` + a CAS value-reveal on
a niche-heavy single-declaration program (e.g. an `Option`-returning bench).

**Dispatch codegen — one generated dispatch function per `(iface, method,
colliding-short-name)`** (mirrors `ensure_adt_eq_fn`, `llvm_eq.ml:51`, not an
inline switch at every call site):
- Name: `__march_ifdispatch_<Iface>_<method>_<Short>`; generated lazily the first
  time a call to that method on a colliding-short-name static type is emitted.
- Body: `load tag from arg0; switch (tag) { <each colliding type T's ctor tags>
  -> tail-call <T's qualified impl symbol>(args); default -> unreachable }`. The
  `(type → its ctor tags → its qualified impl symbol)` rows come from the mono
  dispatch table once it is keyed by module-qualified type (step 3) + `ctor_info`.
- At the call site (`mono.ml` first-arg-type dispatch, `:318/375/521/632`): if the
  static arg type's short name is in the collision set, emit a call to the
  generated dispatch function instead of `resolve_impl_by_type`'s single static
  symbol. Non-colliding calls are unchanged (byte-identical).

**Collision set — computed once, threaded to three consumers.** Derive it from
the module-qualified `TDVariant`/`TDRecord` names in the TIR module
(`m.Tir.tm_types`; short = last `.` segment, module = prefix; short names under
≥2 distinct module prefixes). Consumers: (a) `build_ctor_info` (global tags +
repr force), (b) the repr classifier (force uniform tagged), (c) `mono` dispatch
(emit the dispatch function / route). Compute in one place (a `Llvm_ctx` field
populated at `build_ctor_info`, or a pre-pass) so all three agree.

**Ctor-name collisions within the set.** For the target case (`NA.Thing = TA`,
`NB.Thing = TB`) the ctor NAMES differ, so the `TypeName.CtorName` `ctor_info`
keys already distinguish them. When two colliding types ALSO share ctor names
(e.g. two `AeDir` both with `AeNorth`), the `ctor_info` key must become
**module-qualified** (`ci_module.Type.Ctor`) and `EAlloc`/`match` must embed the
same — this is the umbrella doc's Stage-4 ctor-identity carry. Do it
collision-conditionally too; it is only reachable for same-ctor-name colliders.

**Layer 3 finalisation + witnesses.** Drop the `iface_native_type_dispatched`
gate (remove the `MARCH_DEV_RELAX_COHERENCE` dev bypass) so the coherence
relaxation covers all interfaces; flip `reject/t82` → `accept/t82` (or a new
accept) and delete the `run_compiler` "general-iface err" case added in Stage 1;
add a runtime witness under `test/imports/` that RUNS both interpreted and
compiled and asserts `from-A`/`from-B` (the first cross-backend runtime witness
for same-name general dispatch). Update the `adt_eq_native`-style native golden
set if any colliding fixture's IR intentionally changes.

**Validation gate (all must pass):** full suite (`scripts/run-tests.sh`, not -q);
`dune build @runtest @oracle` (native rules + parity); `git status
test/snapshots/` empty (or reviewed + regenerated deliberately); a CAS
value-reveal on a single-declaration niche program (byte-identity proof); the
new `from-A`/`from-B` runtime witness green on BOTH backends. If any mangled
symbol / tag changes for a single-declaration type, the collision-conditional
gate has a leak — fix it, do not re-baseline goldens.

**Estimated shape:** 3–4 focused sub-tasks (collision-set + repr force; global
tags; dispatch-function codegen + mono routing; Layer 1b + Layer 3 + witnesses),
each independently buildable, with byte-identity checked at every step. This is
the compiler's highest miscompile-risk surface (value representation + tags);
keep every intermediate green and collision-conditional.

## Test & validation strategy
- Reuse the `specs/lang/types/{accept,reject}/` witness harness (t79/t80/t83/t85
  already exist; add t86-style two-module accept + an interp/native runtime
  witness under `test/imports/`).
- Rewrite `test/imports/adt_eq_native` to drop the blanket `impl Eq(a)` and use
  per-module `impl Eq(AeDir)` once Stage 1 lands (proves the fix end-to-end,
  compiled).
- Run `scripts/run-tests.sh` (full, not `-q`) at each stage boundary; run the
  oracle; review `git diff test/snapshots/` for Stage 3.
- If Stage 3 changes any mangled symbol, add the affecting flag to `cas_flags`
  (`project_cas_cache_key_flags`) and verify with a value-revealing program.

## Risks
- **Stage 3 mangling / CAS** — collision-conditional keeps single-declaration
  output byte-identical; the change is confined to programs that actually contain
  a same-short-name collision. Verify with the CAS value-reveal check.
- **`add_ctor` bare-key `ci_module` loss** (`:861-864`) — do not read the
  declaring module from the bare ctor key; use `current_module`/`mod_prefix` (the
  impl's own module) or the qualified ctor keys.
- **Pass-1 vs pass-2 module context** — coherence runs in pass 1 where
  `current_module` isn't the impl's module today; the Stage-1 threading is the
  fix and must not perturb pass-2 ctor tag assignment.
- **Interp lockstep tables** (Stage 2) — `record_type_tbl` + `ffi_type_decl_tbl`
  must qualify together or `from_json` / actor routing silently miss.
- **Residual, documented** — general-interface colliding dispatch relies on
  runtime ctor identity; a type with no constructors (impossible for ADTs used
  here) or a fully-erased generic position would fall back to the single-impl
  sentinel, same as today.
