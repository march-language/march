# Type System Completion — Implementation Plan

## Current State

### Interface Constraints — ✅ Core constraint discharge COMPLETE (commit d8e4566, Track A)

**What exists** (`lib/typecheck/typecheck.ml`, lines 1854–1896):
- `DInterface` declarations are parsed and registered in the environment
- Interface methods are stored with their signatures
- `DImpl` blocks are validated: method names checked, signatures matched against interface definition
- Type parameter substitution works for simple cases
- The type checker records which interfaces exist and which types implement them
- ✅ **Constraint discharge now works**: `CInterface of string * ty` constraint variant added, emitted during instantiation, and discharged by verifying impl existence. 12 new tests added.

**What's still missing**:
- ~~**Constraint discharge**~~ ✅ DONE
- **Superclass constraints**: `interface Ord requires Eq` is parsed but the `requires` chain is not enforced — you can impl `Ord` for a type without impl'ing `Eq`.
- **Associated types**: Interface definitions can declare associated types but these are never unified with concrete types in impl blocks.
- **Default methods**: Not implemented — every impl must provide all methods.

### Session Type Validation

**What exists** (`lib/ast/ast.ml`):
- `DProtocol` AST node with `ProtoMsg(sender, receiver, ty)`, `ProtoLoop(body)`, `ProtoChoice(branches)`
- Parser accepts full session type syntax
- Protocols are registered in the type environment

**What's missing**:
- No protocol adherence checking — an actor claiming to follow a protocol is never verified
- No deadlock detection for binary session types
- No linearity enforcement on session channels (a channel can be used multiple times or not at all)
- No session type duality checking (client protocol vs. server protocol)
- Multi-party session types explicitly deferred to post-v1

### Type-Qualified Constructor Names — ✅ Codegen collision FIXED (commit 2c710f7, Track B)

**What exists** (`lib/typecheck/typecheck.ml`):
- Constructor names stored in a flat `(string, constructor_info) Hashtbl.t` in the type checker
- ✅ In TIR lowering and LLVM emission, constructors are now stored as `"TypeName.CtorName"` (commit 2c710f7), fixing the codegen collision bug

**What's still missing** (type checker side):
- Type-qualified lookup in the type checker: `Option.Some` vs `Result.Some`
- Context-dependent disambiguation when the expected type is known from bidirectional checking
- Error messages for ambiguous constructor references

---

## Target State

### Interface Constraints (from `specs/design.md`, `specs/stdlib_design.md`)

1. **Full constraint discharge**: At every call site where a constrained type variable is instantiated to a concrete type, verify the type has the required impl
2. **Superclass enforcement**: `impl Ord for T` requires `impl Eq for T` to exist
3. **Associated type resolution**: `interface Mappable { type Element }` + `impl Mappable for List(a) { type Element = a }` should allow `x.Element` to resolve to `a`
4. **Default method inheritance**: Interfaces can provide default implementations that impls inherit unless overridden

### Session Types (from `specs/design.md`)

1. **Binary session type checking**: Verify actor message handlers follow declared protocols
2. **Linear channel usage**: Each session channel used exactly once per protocol step
3. **Duality checking**: Client and server views of a protocol are duals
4. **Protocol completion**: Verify all protocol paths are handled (no partial implementations)

### Type-Qualified Constructors (from `specs/design.md`)

1. **Qualified syntax**: `Type.Constructor` for disambiguation
2. **Bidirectional disambiguation**: When checking against a known expected type, resolve constructors without qualification
3. **Clear errors**: When ambiguous, list all types defining that constructor

---

## Implementation Steps

### Part A: Interface Constraint Discharge — ✅ Steps A.1–A.3 COMPLETE (commit d8e4566)

#### Step A.1: Build impl registry (Low complexity) — ✅ DONE
- File: `lib/typecheck/typecheck.ml`
- Create a map: `(interface_name, concrete_type) → impl_location`
- Populated during `DImpl` checking (currently these are checked but not indexed for later lookup)
- Add `impl_registry : (string * ty, span) Hashtbl.t` to the type environment
- Estimated effort: 1 day

#### Step A.2: Constraint collection during inference (Medium complexity) — ✅ DONE
- File: `lib/typecheck/typecheck.ml`
- During type inference, when a constrained function is instantiated, collect `(type_variable, interface_name)` pairs as deferred constraints
- Store in a `constraints : (ty_var * string) list ref` threaded through inference
- Estimated effort: 2 days
- Risk: Must handle let-generalization correctly — constraints on generalized variables become part of the type scheme

#### Step A.3: Constraint solving at call sites (High complexity) — ✅ DONE
- File: `lib/typecheck/typecheck.ml`
- After unification resolves type variables to concrete types, walk the deferred constraints
- For each `(concrete_type, interface_name)`, look up in impl registry
- If not found, emit a type error: "Type `Int` does not implement `Show`"
- Estimated effort: 3 days
- Risk: Polymorphic recursion and higher-rank types can create unsolvable constraints; need good error messages

#### Step A.4: Superclass constraint enforcement (Low complexity)
- File: `lib/typecheck/typecheck.ml`
- When registering a `DImpl`, look up the interface's `requires` list
- For each superclass, verify an impl exists for the same type
- Estimated effort: 1 day

#### Step A.5: Associated type resolution (Medium complexity)
- File: `lib/typecheck/typecheck.ml`
- During `DImpl` checking, record associated type bindings: `(impl_type, assoc_name) → concrete_type`
- During type inference, when encountering `T.AssocType`, look up the binding
- Estimated effort: 3 days
- Risk: Interacts with constraint solving — associated types may depend on constraints that haven't been resolved yet

#### Step A.6: Default method inheritance (Low complexity)
- File: `lib/typecheck/typecheck.ml` + `lib/desugar/desugar.ml`
- In `DInterface`, methods can have a body (the default)
- During `DImpl` checking, if a method is missing, copy the default from the interface definition
- Apply type substitution to the default body
- Estimated effort: 2 days

### Part B: Session Type Validation

#### Step B.1: Protocol representation in type environment (Low complexity)
- File: `lib/typecheck/typecheck.ml`
- Currently protocols are parsed but stored minimally. Enrich the protocol representation:
  - Sequence of protocol steps (message, choice, loop, end)
  - Role assignments (sender, receiver)
  - Type variables bound in protocol scope
- Estimated effort: 1 day

#### Step B.2: Actor protocol annotation checking (Medium complexity)
- File: `lib/typecheck/typecheck.ml`
- When an actor declares `protocol: MyProtocol`, extract the protocol definition
- Build a protocol state machine from the `ProtoMsg`/`ProtoChoice`/`ProtoLoop` AST
- Estimated effort: 2 days

#### Step B.3: Handler-to-protocol matching (High complexity)
- File: `lib/typecheck/typecheck.ml` or new `lib/typecheck/session.ml`
- For each message handler in the actor, verify it corresponds to a valid protocol step
- Track protocol state: after handling message M1, the protocol should be in state S2
- Verify all protocol paths are covered (no missing handlers for choice branches)
- Estimated effort: 5 days
- Risk: Protocol loops create cycles; need a termination argument or bounded unfolding

#### Step B.4: Linear channel enforcement (Medium complexity)
- File: `lib/typecheck/typecheck.ml`
- Session channels must be used exactly once per protocol step
- Integrate with existing linearity tracking (mutable use flags)
- Mark channel types as `Lin` in the type system
- Estimated effort: 3 days
- Dependency: Linearity tracking already exists for values; extend to channels

#### Step B.5: Duality checking (Medium complexity)
- File: new `lib/typecheck/session.ml`
- Given a protocol P, compute its dual P̄ (swap sender/receiver roles)
- When two actors communicate, verify one follows P and the other follows P̄
- Estimated effort: 2 days

### Part C: Type-Qualified Constructor Names

#### Step C.1: Change constructor registry to qualified keys (Medium complexity)
- File: `lib/typecheck/typecheck.ml`
- Replace `(string, constructor_info) Hashtbl.t` with `(string * string, constructor_info) Hashtbl.t` keyed by `(type_name, constructor_name)`
- Maintain a secondary index: `constructor_name → list(type_name)` for unqualified lookup
- Estimated effort: 2 days
- Risk: This touches a lot of code — every constructor lookup needs updating

#### Step C.2: Bidirectional constructor disambiguation (Medium complexity)
- File: `lib/typecheck/typecheck.ml`
- When checking a constructor in a context where the expected type is known (e.g., `match x with Some(v) -> ...` where `x: Option(a)`), use the expected type to select the right constructor
- When no expected type, use the secondary index; if ambiguous, emit an error
- Estimated effort: 3 days
- Risk: Must handle nested patterns and partially-known types

#### Step C.3: Qualified constructor syntax (Low complexity)
- Files: `lib/lexer/lexer.mll`, `lib/parser/parser.mly`, `lib/typecheck/typecheck.ml`
- Parse `Type.Constructor` as a qualified constructor reference
- In the type checker, look up using the qualified key directly
- Estimated effort: 1 day
- Note: The parser may already handle dotted names for module access; constructor qualification follows the same pattern

#### Step C.4: Error messages for ambiguous constructors
- File: `lib/errors/errors.ml`, `lib/typecheck/typecheck.ml`
- When an unqualified constructor is ambiguous, list all types that define it
- Suggest using qualified syntax
- Estimated effort: 0.5 days

---

## Dependencies

- **Part A** (interfaces) has no external blockers — can start immediately
- **Part B** (session types) depends on Part A step A.2 (constraint collection) for proper protocol type checking
- **Part C** (constructors) has no external blockers — can start immediately
- Parts A and C are independent and can be parallelized

Internal ordering:
- A.1 → A.2 → A.3 (core constraint path)
- A.4 independent of A.2/A.3
- A.5 depends on A.3
- A.6 independent
- B.1 → B.2 → B.3 → B.4
- B.5 depends on B.2
- C.1 → C.2 → C.3 → C.4

## Testing Strategy

### Interface Constraints
1. **Positive tests**: Functions with `where a: Eq` called with `Int` (which has `Eq`) — should pass
2. **Negative tests**: Functions with `where a: Show` called with a type lacking `Show` — compile error
3. **Superclass tests**: `impl Ord for T` without `impl Eq for T` — error
4. **Associated type tests**: `Mappable.Element` resolves correctly through impl
5. **Default method tests**: impl without overriding default method still works

### Session Types
1. **Correct protocol**: Actor with handlers matching all protocol steps — passes
2. **Missing handler**: Protocol expects message M but no handler — error
3. **Wrong order**: Handlers in wrong protocol order — error
4. **Linear channel**: Channel used twice — error; channel not used — warning
5. **Duality**: Two actors with dual protocols — passes; non-dual — error

### Constructors
1. **Qualified**: `Option.Some(5)` works when Option is in scope
2. **Unqualified with context**: `let x: Option(Int) = Some(5)` resolves correctly
3. **Ambiguous**: Two types with `Error` constructor, unqualified use without context — error with suggestion
4. **Regression**: All existing tests must pass with new qualified lookup

## Open Questions

1. **Orphan impls**: Should a module be allowed to impl an interface for a type when it defines neither the interface nor the type? Orphan impls cause coherence problems in Haskell/Rust.

2. **Overlapping impls**: What happens if two impls cover the same `(interface, type)` pair? Need a coherence check or prioritization rule.

3. **Constraint propagation through HOFs**: If `map` has type `(a -> b) -> List(a) -> List(b)`, and you pass a function requiring `a: Show`, does `map` inherit that constraint? This is the "dictionary passing" vs "monomorphization" question.

4. **Session type recursion bound**: For `ProtoLoop`, how many times do we unfold before checking? Unbounded unfolding diverges.

5. **Multi-party session types**: Deferred to post-v1, but the design for binary sessions should be forward-compatible with MPST. Key question: should binary session types use a different mechanism than what MPST will eventually use?

6. **Constructor disambiguation heuristics**: When multiple constructors match and the expected type is partially known (e.g., `Option(_)`), should we prefer the more specific match?

## Estimated Total Effort

| Part | Effort | Risk |
|------|--------|------|
| A: Interface constraints | 12 days | Medium |
| B: Session type validation | 13 days | High |
| C: Type-qualified constructors | 6.5 days | Medium |
| **Total** | **31.5 days** | |

### Linear + Affine Dual Design (Design Decision)

> **Design decision (March 20, 2026):** Both **linear** and **affine** types are supported as first-class options going forward:
> - **Linear** (`linear T`): Resources that *must* be consumed exactly once. Use cases: session channels, file handles.
> - **Affine** (`affine T`): Resources where dropping is fine but duplication isn't. Use cases: unique buffers, capability tokens.
>
> With linear types now working in patterns (Track A, `infer_pattern` propagates `TLin`) and closures (Track A, captures tracked), the remaining work is:
> - Linear/affine propagation through record fields (H6 in correctness audit)
> - Ensuring the dual design is reflected in stdlib resource types

## Suggested Priority

1. ~~**Part C** (constructors) — codegen collision fixed (Track B); type checker disambiguation remains~~
2. ~~**Part A** (interfaces) — core constraint discharge done (Track A)~~
3. **Part A remainder** — Superclass enforcement (A.4), associated types (A.5), default methods (A.6)
4. **Part C remainder** — Type checker disambiguation (C.1–C.4)
5. **Part B** (session types) — important for correctness but less urgent since protocols are primarily an actor feature
6. **Linear/affine record propagation** — needed to complete the linear type story
