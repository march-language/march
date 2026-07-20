# FQN impl-coherence & dispatch identity — design + staged plan (A-full)

**Status:** design / approved-for-implementation. Implementation companion to
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
  declaring modules do NOT overlap**; keep `inst_ty` bare in `env.impls`.
- Effect: two `impl Eq(AeDir)` (distinct modules) accepted; genuine same-module
  duplicate (t79) still rejected; parametric overlap (t80) unchanged. **Native
  type-dispatched builtins are already correct** (generated ctor-keyed structural
  fns), so `adt_eq_native` can drop its blanket `impl Eq(a)` in this stage.
- Witnesses: accept `t86`-style two-module distinct-same-name impls; keep
  reject/t79, reject/t80, accept/t83, accept/t85.
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
- Effect: the spike case prints `from-A` / `from-B`.
- Gate: full codegen suite; snapshot review of any intentionally-changed IR;
  CAS-cache correctness check on a value-revealing program; oracle green.

### Stage 4 — Docs, witnesses, cross-backend validation
- Update `specs/todos.md` (move item to Done) + `specs/progress.md` (capability).
- Cross-backend witness: two distinct same-name-type impls run correct bodies
  **interp and native**; genuine duplicate still rejected.
- Note the residual: `TCon` type-references remain bare (no type-reference
  qualification); that full carry stays the deferred umbrella-doc flag-day.

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
