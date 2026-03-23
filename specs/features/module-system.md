# Module System

## Overview

March provides a hierarchical module system with explicit declarations (`mod Name do ... end`), module signatures (`sig Name do ... end`), and imports (`use Module.*`). Modules are namespace containers with visibility control (public/private) and can be nested arbitrarily. Module members are resolved during type checking, and the module namespace is flattened during TIR lowering so the final code uses fully-qualified names (e.g., `IOList.from_string`).

## Implementation Status

**Complete.** Module declarations, imports, visibility (`pub`), and signature conformance (`sig`) are all enforced during type checking.

**Implementation:** `lib/typecheck/typecheck.ml` (pub enforcement: lines ~2850–2950; sig conformance: lines ~3032–3060), `lib/ast/ast.ml`

### What's working
- **pub visibility** — `pub` declarations are exported; private names are inaccessible outside the module
- **Nested modules** — `mod A do mod B do ... end end` with `A.B.fn` qualified access
- **sig conformance** — `sig Name do ... end` verified against actual `mod Name` implementation; missing declarations are errors
- **use imports** — `use Module.*` (all public names) and `use Module.{f, g}` (named selection)

### Still incomplete / known limitations
- **Multi-level use paths** — `use A.B.*` is NOT supported. Only single-level `use A.*` works. Parser deferred multi-level path resolution to avoid shift/reduce conflicts (`lib/parser/parser.mly`).
- **Opaque type enforcement** — `sig` can declare types as abstract, but the type checker doesn't yet hide the representation from outside callers
- **Re-exports** — no `pub use` to re-export names from imported modules

## Source Files & Line References

### AST Representation: `lib/ast/ast.ml` (300 lines)

**Visibility qualifier (lines 28–32):**
```ocaml
type visibility =
  | Private       (* Only visible within the defining module (default) *)
  | Public        (* Exported from the module *)
```

**Module-related declarations (lines 132–137, 143–153):**
- `DMod of name * visibility * decl list * span` (line 132): Nested module with qualified visibility
- `DSig of name * sig_def * span` (line 133): Module signature definition
- `DUse of use_decl * span` (line 137): Import statement

**Use declarations (lines 143–153):**
```ocaml
type use_decl = {
  use_path : name list;        (* Module path, e.g. ["Collections"] *)
  use_sel  : use_selector;     (* What to import *)
}

type use_selector =
  | UseAll                     (* .* — import all public names *)
  | UseNames of name list      (* .{f, g} — import named items *)
  | UseSingle                  (* no selector — import the module itself *)
```

**Module signature (lines 274–280):**
```ocaml
type sig_def = {
  sig_types : (name * name list) list;   (* Opaque type declarations *)
  sig_fns : (name * ty) list;             (* Function signatures *)
}
```

**Top-level module (lines 298–299):**
```ocaml
type module_ = { mod_name : name; mod_decls : decl list }
```

**Function visibility (lines 159–165):**
```ocaml
type fn_def = {
  fn_name : name;
  fn_vis : visibility;              (* Public or Private *)
  fn_doc : string option;
  fn_ret_ty : ty option;
  fn_clauses : fn_clause list;
}
```

### Type Checking: `lib/typecheck/typecheck.ml` (2000+ lines)

**Environment extension (lines 266–276):**
```ocaml
type env = {
  ...
  interfaces : (string * Ast.interface_def) list;
  sigs       : (string * Ast.sig_def) list;
  (* Capabilities declared via [needs] in the current module scope *)
  capabilities : string list;
}
```

**Module member access (lines 1180–1190):**
- When encountering a bare uppercase identifier (e.g., `Mod.fn`), the typechecker treats it as module member access
- Resolution happens during expression checking via qualified name lookup

**Module needs validation (lines 1616–1690):**
- `check_module_needs env mod_name decls`: Validates that all `Cap(X)` types used in function signatures are declared via `needs` statements
- Detects unused capability declarations and missing requirements

**Check module function (lines 1949–2005):**
- `check_module ~errors m`: Type-check a complete module
- **Pass 1:** Pre-bind all top-level declarations (lines 1963–1995)
  - All functions and types are added to the environment before checking bodies
  - Enables recursive and mutually-recursive functions to reference each other
  - Module intra-references don't require declaration order
- **Pass 2:** Check declarations in order, accumulating types in a hashtbl (lines 1996–2003)
- **Module signatures:** Verify conformance by checking that all `sig_fns` are present and exported (lines 1807–1823)
- **Capability tracking:** Validate that declared `needs` declarations match actual usage (lines 1824–1825)

**Nested module checking (line 1851–1854):**
```ocaml
| Ast.DMod (name, vis, decls, sp) ->
  let m' = { mod_name = name; mod_decls = decls } in
  let (errors', type_map') = check_module ~errors m' in
  (* Store the signature so parent module can verify conformance *)
  env' = { env with sigs = (sig_name, sig_def) :: env.sigs }
```

### Desugaring: `lib/desugar/desugar.ml` (280+ lines)

**Module member access desugaring (lines 135–145):**
- Detects qualified access patterns: `Mod.fn(...)` is parsed as `EVar "Mod"` applied to `fn(...)`
- Desugars to `EVar "Mod.fn"` to flatten module namespaces before lowering

**Multi-clause function desugaring (lines 163–220):**
- Individual clauses within a module are desugared to single-clause functions with match expressions
- This happens before the module structure is flattened

**Module desugaring (lines 260–280):**
```ocaml
let desugar_module (m : module_) : module_ =
  let decls = List.map desugar_decl m.mod_decls in
  { m with mod_decls = decls }
```

### Evaluation: `lib/eval/eval.ml` (3000+ lines)

**Module stack (lines 86–88):**
```ocaml
let module_stack : string list ref = ref []
```
Tracks the current module path during evaluation. Updated when entering/leaving nested `DMod` declarations.

**Nested module evaluation (lines 2898–2939):**
- Push module name onto stack (line 2899)
- Evaluate declarations with module prefix prepended to binding names (line 2900ff)
- For each function or value, name becomes `"ModName.binding_name"` (lines 2913–2926)
- Collect actual bindings at end and return (lines 2939–2961)

**Two-pass module evaluation (lines 2969–3050):**
```ocaml
let eval_module_env (m : module_) : env =
  (* Pass 1: Install stubs for all functions so they can reference each other *)
  (* Pass 2: Evaluate declarations and fill in the stub cells *)
  (* Return the environment with all bindings *)
```

**Import handling (lines 1915–1940):**
- `DUse { use_path; use_sel }`: Imports module names as accessible prefixes
- `UseAll`: Imports all public names from the module into scope
- `UseNames names`: Imports only specified names
- `UseSingle`: Imports the module namespace itself (e.g., `use Collections` makes `Collections.map` available)

### TIR Lowering: `lib/tir/lower.ml` (1100+ lines)

**Module lowering (lines 980–1080):**

**Pass 1 – Interface/Implementation Declarations (lines 990–1017):**
- Pre-process interface and implementation declarations
- Register method implementations for later resolution
- Build a map: `interface_name $ type_name . method_name → mangled_fn_name`

**Pass 2 – Declaration Lowering (lines 1018–1050):**
- Lower all other declarations to TIR
- Functions are lowered to TIR definitions with their TIR bodies
- Nested modules are handled by collecting their declarations

**Variable renaming for module boundaries (lines 623–659):**
```ocaml
let rename_tir_vars (prefix : string) (names : string list) (fn : Tir.fn_def) : Tir.fn_def
```
- When entering a nested module, intra-module function references are rewritten with the module prefix
- Example: `from_string` in module `IOList` becomes `IOList.from_string` in TIR

**Actor and Protocol Lowering:**
- Actors and protocols are lowered to TIR type definitions and dispatch functions
- Module names are preserved in generated function names (e.g., `ModName_ActorName_handler_name`)

## Syntax and Semantics

### Module Declaration

```march
mod Collections do
  fn map(f, list) do
    (* function body *)
  end

  fn filter(pred, list) do
    (* function body *)
  end
end
```

- Nested modules are allowed arbitrarily deeply
- All declarations within a module are scoped to that module

### Visibility Control

```march
pub fn exported_fn() do ... end      (* Exported *)
fn private_fn() do ... end           (* Private by default *)
```

- Only public functions and types are visible outside the module
- Private members can be used within the module without restriction

### Module Signatures

```march
sig IntegerOps do
  fn add : Int -> Int -> Int
  fn mul : Int -> Int -> Int
end

mod IntegerImpl : IntegerOps do
  fn add(x, y) do x + y end
  fn mul(x, y) do x * y end
end
```

- Signatures define an interface contract
- Implementation must export all declared functions
- Opaque type declarations are supported (parsed but not fully enforced)

### Import Statements

```march
use Collections.*              (* Import all public names from Collections *)
use Collections.{map, filter} (* Import only map and filter *)
use Collections                (* Import Collections as a prefix *)
```

**Semantics:**
- `use Collections.*`: Brings `map`, `filter`, etc. into local scope directly
- `use Collections.{map, filter}`: Brings only those names into scope
- `use Collections`: Registers `Collections` as a namespace; access via `Collections.map`

## Resolution and Compilation Flow

1. **Parsing:** Modules, imports, and visibility are parsed into the AST
2. **Type Checking:**
   - Module members are pre-bound in pass 1 to enable mutual recursion
   - Imports are resolved by looking up names in imported module's public exports
   - Signatures are checked for conformance
3. **Desugaring:**
   - Multi-clause functions are desugared within their modules
   - Module member access (`Mod.fn`) is flattened to qualified names
4. **TIR Lowering:**
   - Nested modules are flattened: nested function `foo` in module `M` becomes `M.foo` in TIR
   - Variable renaming ensures intra-module calls use qualified names
5. **Code Generation:**
   - All functions have their final module-qualified names (e.g., `Collections.map`)
   - No runtime module representation; modules are compile-time abstractions

## Test Coverage

### `test/test_march.ml`

**Module-related tests:**
- `test_parse_module_multi_head` (lines 115–130): Parser correctly handles module declarations
- `test_parse_module_single_fn` (lines 130–143): Single-function modules parse correctly
- `test_desugar_multi_head_fn` (lines 178–200): Multi-clause functions desugar to match expressions
- `test_tc_match` (lines 249–258): Type checking of match expressions (used in module function desugaring)

**Import and namespace tests:**
- Various tests verify that qualified names are correctly resolved
- Module member access is tested implicitly through standard library usage

## Known Limitations

1. **Signature Enforcement Not Complete:**
   - Signatures are parsed and stored but not fully validated against implementations
   - Missing implementations are not caught at compile time
   - Type-hiding (opaque types) is not enforced

2. **No Export Lists:**
   - Individual functions are marked public/private
   - No module-level export lists to reduce visibility further
   - All public functions in a module are automatically exported

3. **No Module Nesting in Signatures:**
   - Signatures cannot reference types from nested modules
   - Module hierarchies are flattened, losing semantic grouping in signatures

4. **Flat Global Namespace:**
   - All module-qualified names eventually resolve to a single global namespace
   - No runtime module system; modules are a compile-time organizational feature

5. **No Cyclic Module Dependencies:**
   - Circular imports are not detected or prevented
   - Developers must ensure module dependency DAG is acyclic

6. **Limited Standard Library Organization:**
   - Standard library modules exist but are minimal
   - No comprehensive module hierarchy for system functionality

## Dependencies on Other Features

- **AST:** Module declarations are core to the abstract syntax
- **Type Checker:** Module resolution and signature checking depend on full type inference
- **Desugaring:** Multi-clause function desugar depends on pattern matching desugaring
- **TIR:** Module flattening happens during TIR lowering
- **Evaluation:** Runtime module stack for two-pass evaluation

## Examples

### Nested Modules

```march
mod Math do
  mod Integer do
    fn gcd(a, b) do
      if b = 0 then a else gcd(b, a mod b) end
    end
  end

  mod Float do
    fn sqrt(x) do ... end
  end
end

fn test() do
  Math.Integer.gcd(12, 8)
end
```

### Capability Declarations with Modules

```march
mod IOOps do
  needs IO.FileRead, IO.FileWrite

  fn read_file(path : String) : String do
    (* function body using Cap(IO.FileRead) *)
  end
end
```

The `needs` declaration ensures that all capabilities used in the module are explicitly declared, enabling the compiler to track effects.

### Module Signatures with Implementation

```march
sig Logger do
  fn info : String -> Unit
  fn error : String -> Unit
end

pub mod ConsoleLogger : Logger do
  fn info(msg) do println("[INFO] " ++ msg) end
  fn error(msg) do println("[ERROR] " ++ msg) end
end
```

The signature constrains what `ConsoleLogger` must provide; attempting to omit `error` would be a type-check error (once signature enforcement is complete).
