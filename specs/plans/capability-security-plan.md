# Capability Security — Implementation Plan

## Current State

### What Exists

**AST support** (`lib/ast/ast.ml`):
- `DNeeds` declaration node for `needs Cap(X), Cap(Y)` syntax
- `DExtern` with optional capability type for FFI blocks
- `ESend` and `ESpawn` expressions referencing actor capabilities
- Capability types parsed as `TCon("Cap", [TCon("IO.Network", [])])` etc.

**Type checker** (`lib/typecheck/typecheck.ml`):
- Capability hierarchy hardcoded (lines 386–414):
  ```
  IO (root)
  ├─ IO.Console
  ├─ IO.FileSystem  →  IO.FileRead, IO.FileWrite
  ├─ IO.Network    →  IO.NetConnect, IO.NetListen
  ├─ IO.Process
  └─ IO.Clock
  ```
- `cap_ancestors` — returns parent chain for a capability
- `cap_subsumes` — checks if one cap is ancestor of another
- `cap_path_of_names` — resolves dotted names to cap paths
- `cap_paths_in_surface_ty` — extracts `Cap(X)` types from annotations
- `check_module_needs` (lines 1616–1705) — validates that all `Cap(X)` used in module function signatures are declared via `needs`; warns on unused or overly-broad caps

**Effects stub** (`lib/effects/effects.ml`):
```ocaml
let check_capabilities (_m : March_ast.Ast.module_) = ()
```
This is a complete no-op placeholder.

**Stdlib usage**: Several stdlib modules use `needs` declarations in their source (e.g., `file.march`, `http_transport.march`) but enforcement is only at the type-annotation level, not at the call-graph level.

### What's Missing

1. **No call-graph capability inference** — if module A calls module B which `needs IO.Network`, module A is not required to declare that capability
2. **No runtime capability threading** — capabilities are not passed as values or tokens; they're purely declarative
3. **No `Cap.narrow()` attenuation** — the spec describes narrowing `Cap(IO)` to `Cap(IO.FileRead)` but this is unimplemented
4. **No manifest system** — the spec describes a `march.toml` manifest declaring what capabilities a package requires, with user approval on install
5. **No capability delegation for HOFs** — if you pass a closure that uses `Cap(IO.Network)` to a pure function, there's no tracking
6. **No extern capability enforcement** — `DExtern` has a cap field but it's not checked against the module's `needs`

---

## Target State (from specs)

Per `2026-03-19-capability-security-design.md` and `2026-03-19-capability-security.md`:

1. **Compile-time enforcement**: Every function that transitively uses a capability must have it declared via `needs` in its enclosing module
2. **Capability attenuation**: `Cap.narrow(cap, IO.FileRead)` returns a restricted capability token
3. **Pure-by-default**: Modules without `needs` declarations are guaranteed pure — no IO, no actors, no FFI
4. **Manifest system**: `march.toml` at package root declares required capabilities; user approves on install
5. **Transitive propagation**: If module A imports module B which `needs IO.Network`, module A must also declare `needs IO.Network` (or a parent)
6. **Extern gating**: `extern` blocks require their capability to be in the module's `needs` set
7. **Actor spawn gating**: Spawning an actor that `needs` caps requires the spawner to have those caps

---

## Implementation Steps

### Phase 1: Transitive Capability Checking (Medium complexity, Low risk)

**Step 1.1: Build module dependency graph with capability requirements**
- File: `lib/typecheck/typecheck.ml`
- After all modules are typechecked, build a map: `module_name → Set(capability)`
- Extract from `DNeeds` declarations already parsed
- Estimated effort: 1 day

**Step 1.2: Propagate capabilities transitively through imports**
- File: `lib/typecheck/typecheck.ml` (new function `check_transitive_caps`)
- For each module, collect the union of capabilities from all `DUse`-imported modules
- Error if a module uses another module's capabilities without declaring them
- Estimated effort: 2 days
- Risk: Need to handle re-exports and selective imports carefully

**Step 1.3: Check extern blocks against module capabilities**
- File: `lib/typecheck/typecheck.ml`
- In the `DExtern` checking branch, verify the extern's capability type is subsumed by the module's `needs` set
- Uses existing `cap_subsumes` function
- Estimated effort: 0.5 days

### Phase 2: Call-Graph Capability Inference (High complexity, Medium risk)

**Step 2.1: Intra-module capability inference**
- File: new `lib/effects/effects.ml` (replace stub)
- Walk each function body and collect all capabilities used:
  - Direct: calls to builtins tagged with capabilities
  - Indirect: calls to functions in modules that `needs` caps
- Build per-function capability set
- Estimated effort: 3 days

**Step 2.2: Cross-module capability flow analysis**
- File: `lib/effects/effects.ml`
- After intra-module pass, propagate through the call graph
- Handle mutual recursion via fixed-point iteration
- Estimated effort: 2 days
- Risk: Higher-order functions complicate this — a closure captured in module A but called in module B

**Step 2.3: Capability warnings and errors**
- File: `lib/errors/errors.ml` + `lib/effects/effects.ml`
- Emit errors when a function uses a capability not in its module's `needs`
- Emit warnings when a `needs` declaration is broader than necessary (e.g., `needs IO` when only `IO.FileRead` is used — existing `check_module_needs` already does some of this)
- Estimated effort: 1 day

### Phase 3: Capability Attenuation (Medium complexity, Medium risk)

**Step 3.1: Add `Cap.narrow` as a builtin**
- Files: `lib/typecheck/typecheck.ml`, `lib/eval/eval.ml`, `lib/tir/llvm_emit.ml`
- Type: `Cap(A) -> Cap(B) -> Cap(B)` where `B` is a descendant of `A`
- In the interpreter, this is a no-op that returns the narrowed cap token
- In compiled code, also a no-op (caps are phantom types at runtime)
- Estimated effort: 1 day

**Step 3.2: Thread capability tokens through function calls**
- Files: `lib/desugar/desugar.ml` or `lib/typecheck/typecheck.ml`
- Design decision needed: are capabilities explicit parameters, or implicit via the module system?
- If explicit: desugar `needs IO.Network` into an extra parameter on each function
- If implicit (recommended for v1): keep current module-level declaration, enforce at compile time only
- Estimated effort: 1 day (implicit) or 5 days (explicit)

### Phase 4: Manifest System (Low complexity, Low risk)

**Step 4.1: Define `march.toml` schema**
- New file: `lib/manifest/manifest.ml`
- Parse TOML (use existing OCaml TOML library or simple custom parser)
- Fields: `[package]`, `name`, `version`, `[capabilities]` with list of required caps
- Estimated effort: 2 days

**Step 4.2: Validate package capabilities against manifest**
- File: `bin/main.ml` (at compilation entry point)
- Load `march.toml`, compare declared caps against what the package's modules actually `needs`
- Error if package uses undeclared capabilities
- Estimated effort: 1 day

**Step 4.3: User approval flow for capability grants**
- File: `bin/main.ml` or new `lib/manifest/approve.ml`
- When installing/running a package that requires capabilities, prompt user
- Store approvals in `~/.march/approved.toml` or similar
- Estimated effort: 2 days
- Dependency: Package manager (see `cas-integration-plan.md`)

### Phase 5: Actor Spawn Capability Gating (Low complexity, Low risk)

**Step 5.1: Validate spawn capabilities**
- File: `lib/typecheck/typecheck.ml`
- When typechecking `ESpawn(ActorName)`, look up the actor's `needs` declarations
- Verify the spawning module has all required capabilities
- Estimated effort: 1 day

---

## Dependencies

- Phase 1 has no blockers — can start immediately
- Phase 2 depends on Phase 1 (needs the module→caps map)
- Phase 3 depends on a design decision about explicit vs. implicit capability passing
- Phase 4 depends on the CAS/package system (see `cas-integration-plan.md`) for the install flow
- Phase 5 depends on Phase 1

## Testing Strategy

1. **Unit tests for capability subsumption** — extend existing cap_subsumes tests
2. **Module-level tests**: create test modules with missing/incorrect `needs` declarations, verify errors
3. **Transitive tests**: A imports B imports C; verify capability propagation
4. **Negative tests**: pure module accidentally calling IO function → compile error
5. **Integration tests**: full compile of example programs with capability checking enabled
6. **Regression**: ensure all 401 existing tests still pass (many stdlib modules will need `needs` declarations audited)

## Open Questions

1. **Explicit vs. implicit capability threading**: Should capabilities be passed as runtime values (like Scala 3 capabilities) or remain compile-time-only module annotations? Implicit is simpler but less flexible for capability delegation.

2. **Capability polymorphism**: Should functions be parametric over capabilities? E.g., `fn fetch(cap: Cap(A)) where A: IO.Network` — this interacts with the interface system.

3. **REPL capabilities**: The REPL needs all capabilities by default. Should there be a `--sandbox` flag that restricts REPL capabilities?

4. **Third-party FFI**: When linking against C libraries, how do we map C functions to March capabilities? Currently `DExtern` has an optional cap field, but there's no standard mapping.

5. **Capability revocation**: The spec mentions `Cap.narrow()` but not revocation. Should a parent capability holder be able to revoke a narrowed capability? This has significant runtime implications.

## Estimated Total Effort

| Phase | Effort | Risk |
|-------|--------|------|
| Phase 1: Transitive checking | 3.5 days | Low |
| Phase 2: Call-graph inference | 6 days | Medium |
| Phase 3: Attenuation | 2–6 days | Medium |
| Phase 4: Manifest system | 5 days | Low |
| Phase 5: Spawn gating | 1 day | Low |
| **Total** | **17.5–21.5 days** | |
