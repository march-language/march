# Qualified Module Access — Implementation Plan

**Status:** Proposed
**Author:** Chase (spec), Claude (writeup)
**Date:** 2025-03-30

## Problem

Currently, `import Foo` dumps all of Foo's public bindings into the calling module's scope. There is **no way** to write `Foo.bar()` in expressions or `Foo.MyType` in type annotations without first importing or aliasing the module. This causes real problems:

1. **Name collisions** in Bastion (the web framework) — multiple modules export `handle`, `init`, `get`, etc.
2. **Type annotations** can't reference types from other modules without importing them, forcing either wildcard imports (polluting the namespace) or verbose alias declarations.
3. **Code readability** suffers — readers can't tell which module a function came from.

## Design

Qualified access works **without importing**, like Elixir:

```march
-- No import needed:
let m = Map.new()
let v = Map.get(m, "key")

-- import additionally brings names into local scope (preserves current behavior):
import Map
let m = new()

-- Type annotations:
fn handle(req : Http.Request) : Http.Response do ... end

-- Constructors:
let x = Result.Ok(42)

-- Pattern matching:
match val do
| Result.Ok(x) -> x
| Result.Err(e) -> panic(e)
end
```

**Scope:** Single-level only. `A.B.func` works if `B` is a nested module inside `A`, but there is no new multi-level chaining syntax. The existing `EField` chaining already handles `A.B.c` at the AST level.

## Current State Analysis

### How it works today

The compiler already uses a **string-prefix convention** for qualified names internally. When a `DMod` is processed, its public members are registered as `"ModName.member"` in the environment. The existing `import`/`use` mechanism works by finding all entries with a matching prefix and rebinding them without the prefix.

**Key existing machinery:**

| Component | Mechanism | Location |
|-----------|-----------|----------|
| Parser | `EField(ECon("Mod",[]),name)` for `Mod.name` | parser.mly:824-838 |
| Parser | `qualified_upper` for `Mod.Ctor` in patterns | parser.mly:929-938 |
| Parser | `TyCon("Mod.Type", [])` for dotted types | parser.mly:634-637 |
| Typecheck | `env.vars` stores `"Mod.name" → scheme` | typecheck.ml:350 |
| Typecheck | `prebind_mod_members` forward-declares `"Mod.fn"` | typecheck.ml:4898-4908 |
| Typecheck | `DUse` rebinds `"Mod.name"` as `"name"` | typecheck.ml:4328-4395 |
| Eval | `module_registry` global hashtable | eval.ml:249 |
| Eval | `EField` handler tries `module_path_str` first | eval.ml:5168-5201 |
| TIR Lower | `_use_aliases` maps short→qualified names | lower.ml:123 |

The infrastructure for qualified access **already exists** in embryonic form. The gap is that it only works for modules **within the same file**. Stdlib modules and other compilation units are not accessible via qualified syntax because their bindings aren't in the environment at all unless explicitly imported.

### The real missing piece: a module registry

When you write `Map.get(m, k)` today without importing Map, the typechecker has no entry for `"Map.get"` in `env.vars` — it was never loaded. The eval pass has a `module_registry` hashtable that gets populated at runtime, but only for modules defined in the same file via `DMod`.

**What we need:** A mechanism to lazily load a module's export table into the environment when its name is first used as a qualifier, so that `Map.get` can resolve without an explicit import.

## Implementation Plan

### Phase 0: Module Export Registry (Foundation)

Create a shared module export registry that all passes can query. This is the critical prerequisite for everything else.

#### 0a. New module: `lib/modules/module_registry.ml`

```ocaml
(** Module export registry — maps module names to their exported bindings.
    Populated by loading stdlib .march files and by processing DMod declarations.
    Queried by typecheck, eval, and TIR lower when resolving qualified names. *)

type export_kind =
  | ExFn                       (** Function binding *)
  | ExType of int              (** Type constructor with arity *)
  | ExCtor of string * int     (** Data constructor: parent type name, arity *)
  | ExValue                    (** Top-level let binding *)

type export_entry = {
  ex_name : string;            (** Short name (e.g. "get") *)
  ex_kind : export_kind;
  ex_public : bool;
}

type module_exports = {
  me_name : string;            (** Module name (e.g. "Map") *)
  me_entries : export_entry list;
}

(** Global registry: module name → exports. Populated lazily. *)
val register : string -> module_exports -> unit
val lookup : string -> module_exports option
val is_known_module : string -> bool

(** Load a stdlib module by name, parse+typecheck it, and register its exports.
    Returns the exports table. Caches results. *)
val ensure_loaded : string -> module_exports option
```

**Why a separate module:** Both typecheck.ml and eval.ml need this, and they shouldn't depend on each other. The registry is a shared service.

#### 0b. Populate the registry from stdlib

The `stdlib/` directory contains 57 `.march` files. Each corresponds to a module (e.g., `stdlib/map.march` → module `Map`). Today these are loaded by the eval pass via a file-finding mechanism.

Add a function `ensure_loaded` that:
1. Finds the `.march` file for the given module name (case-insensitive filename search in `stdlib/`)
2. Parses and typechecks it (caching the result)
3. Extracts the public exports (functions, types, constructors)
4. Registers them in the global table

**Key concern:** Circular dependencies. If module A's body references `B.foo` and module B references `A.bar`, loading A triggers loading B which triggers loading A. Solution: use a "loading" sentinel. If a module is already in the "loading" state, return a placeholder. The two-pass approach in typecheck (forward-declare in pass 1, check in pass 2) already handles forward references within a file; the same principle extends to cross-file references.

#### 0c. Integrate with `bin/main.ml`

The compiler entry point (`bin/main.ml`) currently processes a single module. Before typechecking, it should:
1. Pre-scan for all module names referenced in qualified positions (optional optimization)
2. Or: hook `ensure_loaded` into the typecheck and eval passes so they trigger loading on demand

The on-demand approach is simpler and what Elixir does.

#### Files to create/modify:
- **Create:** `lib/modules/module_registry.ml`, `lib/modules/module_registry.mli`, `lib/modules/dune`
- **Modify:** `bin/main.ml` (initialize registry, pass stdlib path)
- **Modify:** `lib/dune` files to add `march_modules` dependency

---

### Phase 1: AST Changes

The AST already handles qualified names reasonably well, but needs one addition for clarity and to support unambiguous resolution in the desugar pass.

#### 1a. Add `EQualified` to expr (optional — see discussion)

**Option A: No AST change.** Continue using `EField(ECon("Map",[]), {txt="get"})` to represent `Map.get`. This is what the parser produces today. Pros: no AST change. Cons: the desugar/typecheck passes must pattern-match `EField(ECon(...), ...)` specially everywhere.

**Option B: Add a dedicated node.**

```ocaml
(* In ast.ml, add to the expr type: *)
| EQualified of name * name * span   (** Module.member: module name, member name *)
```

**Recommendation: Option A (no AST change).** The existing `EField(ECon(...),...)` representation is already used and handled in eval.ml:5170-5185. Adding a new node would require updating every pass that pattern-matches on `expr`. The desugar pass can instead normalize `EField(ECon(mod_name,[]),member)` patterns into the internal `"ModName.member"` string form that the rest of the pipeline already expects.

#### 1b. Add `TyQualified` to ty (recommended)

The parser already joins dotted type names into `TyCon({txt="Mod.Type"}, args)` (parser.mly:626-628, 634-637). This works because `surface_ty` in typecheck.ml looks up `name.txt` directly in `env.types`, and qualified type names like `"Http.Request"` can already be there (added by `DMod` processing).

**No AST change needed for types.** The string `"Mod.Type"` convention already works.

#### 1c. Pattern qualified constructors

Already supported: `qualified_upper` in parser.mly:934-938 produces `PatCon({txt="Result.Ok"}, pats)`. The eval pass strips the prefix at eval.ml:5122-5123. The typecheck pass looks up `"Result.Ok"` in `env.ctors` where it's already registered (typecheck.ml:1140-1145 for builtins).

**No change needed for patterns.**

#### Summary: No AST changes required

The existing representation handles all cases. The work is in making the downstream passes resolve these names against the module registry.

---

### Phase 2: Lexer/Parser Changes

The lexer and parser already handle the syntax correctly. Let's verify each case:

#### Expression position: `Map.get(m, k)`

Parser path: `UPPER_IDENT("Map")` → `ECon("Map", [])` → `.` shift → `DOT lower_name` → `EField(ECon("Map",[]), "get")` → `(` shift → `EApp(EField(...), [m, k])`.

This **already works** syntactically. No parser change needed.

#### Expression position: `Map.new()`

Same path. **Already works.**

#### Type position: `Http.Request`

Parser path (ty_atom, line 634): `UPPER_IDENT("Http")` → `DOT` → `dotted_upper_tail` → produces `TyCon({txt="Http.Request"}, [])`.

**Already works.** No parser change needed.

#### Type position with params: `Result.Ok(Int, String)`

Wait — this is a **constructor** in a type context, not a type itself. Type annotations use `Result(Int, String)`, not `Result.Ok(Int, String)`. The qualified form for types is `Module.TypeName`, not `Module.Constructor`.

Parser path for `Option.Some` type: Currently produces `TyCon("Option.Some", [])`, which the typechecker would look up in `env.types` and fail (it's a constructor, not a type). This is correct behavior — constructors are not types.

#### Constructor position: `Result.Ok(42)`

Parser path (expr_app): `UPPER_IDENT("Result")` → `ECon("Result",[])` → `.` → `EField(ECon("Result",[]),"Ok")` → `(` → this is now `EApp(EField(...), [42])`, NOT `ECon("Result.Ok", [42])`.

**Problem:** The parser produces `EApp(EField(ECon("Result",[]),"Ok"), [42])` instead of `ECon("Result.Ok", [42])`. The eval pass handles this via the `VCon` fallthrough at eval.ml:5196-5200, but the typechecker doesn't know this is a constructor application.

**Fix needed (Phase 2a):** In the **desugar pass**, recognize `EApp(EField(ECon(mod,[]),ctor), args)` where `ctor` starts with uppercase and rewrite it to `ECon({txt="mod.ctor"}, args)`. This puts it into the form that typecheck and eval already handle.

Similarly, `EField(ECon(mod,[]),ctor)` where `ctor` starts uppercase (zero-arg constructor) should become `ECon({txt="mod.ctor"}, [])`.

#### 2a. Desugar pass: normalize qualified constructors

Add to `desugar.ml`, in the expression rewriting:

```ocaml
(* In desugar_expr or equivalent: *)

(* Module.Constructor(args) → ECon("Module.Constructor", args) *)
| EApp (EField (ECon (mod_name, [], _), ctor, _), args, sp)
  when String.length ctor.txt > 0
    && ctor.txt.[0] >= 'A' && ctor.txt.[0] <= 'Z' ->
  let qualified = { txt = mod_name.txt ^ "." ^ ctor.txt; span = ctor.span } in
  ECon (qualified, List.map desugar_expr args, sp)

(* Module.Constructor (zero-arg) → ECon("Module.Constructor", []) *)
| EField (ECon (mod_name, [], _), ctor, sp)
  when String.length ctor.txt > 0
    && ctor.txt.[0] >= 'A' && ctor.txt.[0] <= 'Z' ->
  ECon ({ txt = mod_name.txt ^ "." ^ ctor.txt; span = ctor.span }, [], sp)
```

This should be added to the existing `desugar_expr` function (or a new recursive expr walker if one doesn't exist). Currently, desugar.ml focuses on function clause desugaring and pipe desugaring. It does have an `EBlock` walker for pipe rewriting.

**Location:** desugar.ml needs a general `desugar_expr` recursive walker. Currently it only transforms specific things (pipes, sigils). Add one that handles the qualified constructor normalization.

#### 2b. Desugar pass: normalize qualified function calls

`EApp(EField(ECon("Map",[]),{txt="get"}), args)` should become `EApp(EVar({txt="Map.get"}), args)` so the typechecker and eval pass can look it up directly in `env.vars`.

```ocaml
(* Module.func(args) → EApp(EVar("Module.func"), args) *)
| EApp (EField (ECon (mod_name, [], _), member, _), args, sp)
  when String.length member.txt > 0
    && member.txt.[0] >= 'a' && member.txt.[0] <= 'z' ->
  let qualified = { txt = mod_name.txt ^ "." ^ member.txt; span = member.span } in
  EApp (EVar qualified, List.map desugar_expr args, sp)
```

Wait — should we do this in desugar, or handle it in typecheck/eval? Let's think carefully.

**Argument for desugar:** Simplifies all downstream passes. They just see `EVar("Map.get")` which they already know how to look up.

**Argument against:** The `EField` form is needed for runtime record access (`record.field`). We'd need to be sure we only rewrite when the LHS is a module name, which we can't always know statically at desugar time (before typechecking).

**Resolution:** In the desugar pass, we CAN detect `EField(ECon(name, [], _), member, _)` — the `ECon` with zero args is the tell. An uppercase bare identifier that isn't applied to arguments is always a module or constructor name, never a record value. So this rewriting is safe.

But do NOT rewrite `EField(EVar("x"), "field", _)` — that's record access and must stay as `EField`.

Also do NOT rewrite `EField(EField(...), ...)` chains — those are chained record access or nested module access, which already work via the recursive `module_path_str` in eval.ml.

**Decision: Do the rewriting in desugar for the simple `ECon(uppercase,[])` case only.** This catches `Map.get(...)`, `Result.Ok(...)`, etc. Chained access like `A.B.func()` continues to work via `EField` chaining as it does today.

---

### Phase 3: Module Registry Integration with Typecheck

This is the core of the feature: making the typechecker resolve qualified names against the module registry.

#### 3a. Hook `ensure_loaded` into `check_decl`/`infer_expr`

When the typechecker encounters a variable lookup for `"Mod.name"` and doesn't find it in `env.vars`:

1. Extract the module name prefix (everything before the last `.`)
2. Call `Module_registry.ensure_loaded mod_name`
3. If the module loads successfully, inject its exported bindings into the environment as `"Mod.name" → scheme`
4. Retry the lookup

**Where to add this:** In `lookup_var` (typecheck.ml:385) or in the callers.

Better: add a wrapper `resolve_qualified_var`:

```ocaml
(* In typecheck.ml, around line 385: *)

(** Resolve a possibly-qualified variable name. If the name contains a dot
    and isn't found in env.vars, attempt to load the module from the registry. *)
let resolve_qualified_var name env =
  match lookup_var name env with
  | Some _ as result -> result
  | None ->
    (* Try qualified resolution: "Mod.name" → load Mod *)
    (match String.index_opt name '.' with
     | None -> None
     | Some i ->
       let mod_name = String.sub name 0 i in
       match March_modules.Module_registry.ensure_loaded mod_name with
       | None -> None   (* Module not found *)
       | Some exports ->
         (* Inject all exports into env — but env is immutable!
            We need a different approach. *)
         ...)
```

**Problem:** The typechecker's `env` is an immutable record threaded through `check_decl`. We can't "inject" bindings mid-expression-checking and have them persist.

**Solution 1: Pre-populate env at module entry.** At the start of `check_module` (typecheck.ml:4892), scan the module's declarations for any qualified references and pre-load all referenced modules into the initial environment.

**Solution 2: Lazy resolution with side-effecting env.** The env is threaded functionally, but we could use a mutable `module_cache` field. When a qualified name is encountered and the module isn't yet loaded, load it and store the results in the mutable cache. Subsequent lookups check the cache.

**Solution 3: Two-level lookup.** The existing `env.vars` is the fast path. On miss, consult a global `module_exports` table (populated at program load or lazily). This avoids modifying `env` at all.

**Recommendation: Solution 3.** Add a global (mutable) function `resolve_from_registry : string -> scheme option` that the typechecker calls when local lookup fails. The global table is populated by parsing/typechecking stdlib modules (cached).

```ocaml
(* New field in typecheck.ml env — or a global ref *)
let module_scheme_cache : (string, scheme) Hashtbl.t = Hashtbl.create 256

(** Look up a qualified name, loading the module if needed.
    Returns a scheme for the name, or None. *)
let resolve_qualified name =
  match Hashtbl.find_opt module_scheme_cache name with
  | Some _ as s -> s
  | None ->
    match String.index_opt name '.' with
    | None -> None
    | Some i ->
      let mod_name = String.sub name 0 i in
      (* Load module, populate cache *)
      ...
```

#### 3b. Qualified type lookup in `surface_ty`

`surface_ty` (typecheck.ml:1403) converts `Ast.TyCon(name, args)` to internal types. When `name.txt` is `"Mod.Type"`:

1. `lookup_type "Mod.Type" env` might fail because the module's types haven't been loaded
2. Apply the same resolution: load the module via registry, then retry

**Location:** typecheck.ml:1434-1439, where `lookup_type` is called. Add a fallback:

```ocaml
let arity = match lookup_type name.txt env with
  | Some a -> a
  | None ->
    (* Try loading the module if this is a qualified name *)
    match load_module_types_if_qualified name.txt env with
    | Some a -> a
    | None ->
      Err.error env.errors ~span:name.span
        (Printf.sprintf "I don't know a type called `%s`." name.txt);
      0
in
```

#### 3c. Qualified constructor lookup

Constructor lookup is in `lookup_ctor` (typecheck.ml:387). For `"Result.Ok"`, it's already in `builtin_ctors`. For user-defined types from other modules, the same registry-based loading applies.

**Location:** Wherever `lookup_ctor` is called in `infer_expr`/`check_expr`, add a fallback to the module registry.

#### 3d. Pre-bind qualified names in pass 1

The existing `prebind_mod_members` (typecheck.ml:4898) handles forward references for `DMod` within the same file. Extend it to also pre-bind names from modules referenced in qualified expressions.

Alternatively (and simpler): just use the on-demand loading from Solution 3. The prebind approach is only needed because pass 1 and pass 2 interact; with a global registry, the bindings are always available.

#### Files to modify:
- `lib/typecheck/typecheck.ml`:
  - Add `resolve_qualified` fallback to `infer_expr` for `EVar` and `ECon`
  - Add qualified type lookup in `surface_ty`
  - Add qualified constructor lookup
  - Integrate with module registry

---

### Phase 4: Eval Changes (Interpreter Path)

The eval pass already has robust qualified name handling via `module_registry` (eval.ml:249) and the `EField` handler (eval.ml:5168-5201). The main gap is **stdlib module loading.**

#### 4a. Trigger stdlib loading on qualified access

In eval.ml, when `EField` qualified lookup fails (eval.ml:5178-5185), and the prefix looks like a module name:

```ocaml
(* In eval.ml EField handler, after module_registry lookup fails: *)
| None ->
  (* Try loading the module from stdlib *)
  let loaded = March_modules.Module_registry.ensure_loaded_eval prefix in
  match loaded with
  | Some v -> v
  | None -> (* fall through to record field access *)
```

`ensure_loaded_eval` would parse, desugar, typecheck, and eval the stdlib module, populating `module_registry`.

#### 4b. Unified module loading

Currently, stdlib modules are loaded by `bin/main.ml` or the REPL driver. The eval pass itself doesn't trigger loading. Add a hook:

```ocaml
(* In eval.ml, near module_registry definition: *)

(** Callback set by the driver (main.ml / repl) to load a module on demand. *)
let module_loader : (string -> unit) ref = ref (fun _ -> ())

(** Ensure a module is loaded. Idempotent. *)
let ensure_module_loaded (name : string) : unit =
  if not (Hashtbl.mem module_registry (name ^ ".__loaded__")) then begin
    !module_loader name;
    Hashtbl.replace module_registry (name ^ ".__loaded__") VUnit
  end
```

The driver sets `module_loader` at startup to a function that finds the `.march` file, parses, desugars, typechecks, and evals it.

#### Files to modify:
- `lib/eval/eval.ml`:
  - Add `module_loader` callback ref
  - Modify `EField` handler to trigger loading
  - Modify `lookup` to try qualified resolution
- `bin/main.ml`:
  - Set `Eval.module_loader` at startup

---

### Phase 5: TIR Lower Changes (Compiled Path)

The TIR lower pass already handles qualified names via string prefixes. The gap is the same: stdlib modules aren't lowered unless they appear in the file.

#### 5a. Include referenced modules in the TIR output

When `lower_module` encounters a reference to `Map.get`, the function `Map.get` needs to be in `tm_fns`. Currently, only `DMod` inner functions get added.

**Approach:** During lowering, when `resolve_use_alias` returns the name unchanged (no alias) and the name contains a dot, check the module registry. If the module hasn't been lowered, lower it and add its functions to `tm_fns`.

```ocaml
(* In lower.ml, in lower_to_atom_k for EVar: *)
| Ast.EVar { txt = name; span; _ } ->
  let name = resolve_use_alias name in
  (* If qualified and module not yet lowered, trigger lowering *)
  if String.contains name '.' then
    ensure_module_lowered (String.sub name 0 (String.index name '.'));
  let ty = ty_of_span span in
  k (Tir.AVar { v_name = name; v_ty = ty; v_lin = Tir.Unr })
```

#### 5b. Track lowered modules

```ocaml
let _lowered_modules : (string, unit) Hashtbl.t ref = ref (Hashtbl.create 8)

let ensure_module_lowered name =
  if not (Hashtbl.mem !_lowered_modules name) then begin
    Hashtbl.replace !_lowered_modules name ();
    match Module_registry.get_parsed_module name with
    | None -> ()  (* module not found — typecheck already reported error *)
    | Some m ->
      (* Lower the module's functions and add to our fn list *)
      lower_mod_decls (name ^ ".") m.mod_decls
  end
```

#### Files to modify:
- `lib/tir/lower.ml`:
  - Add module tracking
  - Modify `EVar` handling to trigger module lowering
  - Add lowered module functions to output

---

### Phase 6: REPL/JIT Considerations

The REPL uses the same eval path as batch compilation but with a persistent environment across inputs. Qualified access should Just Work because:

1. The REPL already maintains `module_registry` across inputs
2. The `EField` handler already does qualified lookup
3. Adding `module_loader` (Phase 4b) means `Map.get(m, k)` typed at the REPL will trigger loading `Map` on first use

**One REPL-specific concern:** Tab completion. The REPL's completer should be extended to suggest `Module.` completions:

- When the user types `Map.`, list all public exports of `Map`
- When the user types `Ma`, suggest `Map` as a module name (in addition to local variables)

This is a polish item, not a blocker.

#### Files to modify:
- `bin/main.ml` or REPL driver: set `module_loader` callback

---

### Phase 7: Interaction with Existing `import`, `use`, `alias`

#### Existing `import Module` behavior (PRESERVED)

`import Map` currently:
1. Loads the module (if not already loaded)
2. Finds all `"Map.name"` entries in the environment
3. Rebinds each as just `"name"`

This behavior is **completely preserved**. The only change is that `"Map.name"` entries are now available **even without** the `import`. The `import` just adds the short aliases.

#### Existing `use` behavior (PRESERVED)

`use Map.*` does the same as `import Map`. `use Map.{get, put}` does selective import. All preserved.

#### Existing `alias` behavior (PRESERVED)

`alias Collections.HashMap as HM` creates `"HM.name"` entries pointing to `"Collections.HashMap.name"` entries. Preserved.

#### New interaction: `import` becomes optional

After this change, `import` is **convenience, not necessity**. Code like:

```march
-- Before: required
import Map
let m = new()

-- After: also valid (no import)
let m = Map.new()
```

Both forms coexist. No migration needed.

#### Shadowing rules

When `import Map` brings `get` into scope and the current module also defines `get`:

1. **Local definitions win.** A locally-defined `fn get(...)` shadows the imported `get`.
2. **The qualified form always works.** `Map.get(...)` always refers to Map's version.
3. **Later imports shadow earlier ones.** `import A` then `import B` — if both export `foo`, `foo` refers to B's version. (This is the current behavior.)

These rules are **unchanged** by this proposal.

---

### Phase 8: Edge Cases

#### 8a. Module name vs. constructor name ambiguity

Both modules and constructors are uppercase identifiers. `Foo.bar` — is `Foo` a module or a constructor?

**Resolution order:**
1. If `Foo` is bound in the local environment as a value → record field access
2. If `Foo` is a known module name → qualified module access
3. If `Foo` looks like a zero-arg constructor → `VCon("Foo", [])`, then try field access (current behavior for actor message types, etc.)

The desugar rewriting (Phase 2) only fires on `ECon(name, [], _)` which is the parser output for a bare `UPPER_IDENT`. Since local bindings use `EVar`, there's no ambiguity: `ECon` always means "constructor or module name".

In practice, the eval pass already handles this correctly — the `EField` handler in eval.ml:5168-5201 tries module lookup first, then record field access.

#### 8b. Re-exports

If module A re-exports module B's function:
```march
mod A do
  import B
  fn foo() do B.bar() end
end
```

`A.foo` is accessible. `A.bar` is NOT accessible (B.bar was imported into A's local scope but not exported). This is correct — only declarations inside A's `DMod` block are exported under the `A.` prefix.

If you want re-export, you'd write:
```march
mod A do
  fn bar() do B.bar() end  -- explicit wrapper
end
```

#### 8c. Circular module references

Module A uses `B.foo`, module B uses `A.bar`. With lazy loading:

1. Start loading A
2. A references `B.foo` → trigger load B
3. B references `A.bar` → A is in "loading" state
4. For typecheck: A's functions were forward-declared in pass 1, so `A.bar` has a placeholder type. B typechecks against it. When A finishes, unification resolves the placeholder.
5. For eval: A's forward-declared stubs are in `module_registry`. B's closure captures a reference that will be resolved at call time.

This is the same forward-reference approach already used within a single file. Cross-file extends it.

#### 8d. Private members

`pfn` (private function) and private types should NOT be accessible via qualified syntax from other modules. The module registry should only export public members.

**Check:** When populating the registry, filter by `fn_vis = Public` (already done in `prebind_mod_members` at typecheck.ml:4901).

#### 8e. Nested modules: `Outer.Inner.func`

Already works today via `EField` chaining:
- `Outer.Inner` → `EField(ECon("Outer",[]), "Inner")` → eval resolves to `VCon("Inner", [])` or a module path
- `.func` → `EField(..., "func")` → eval uses `module_path_str` to build `"Outer.Inner.func"`

No changes needed for the parser or AST. The eval pass's `module_path_str` (eval.ml:5170-5176) already handles arbitrary depth chaining.

**For typecheck:** The `prebind_mod_members` function already handles nested modules (typecheck.ml:4905-4906). Extend the qualified resolution to handle dotted module names.

#### 8f. Stdlib modules that aren't files

Some "modules" like `List`, `Option`, `Result` have their types built into the typechecker (typecheck.ml:1130-1146) but their functions come from stdlib files. The registry needs to merge both sources.

---

### Phase 9: Migration Path

**Existing code continues to work with zero changes.** The feature is purely additive:

- `import Foo` still works exactly as before
- All existing unqualified references still resolve
- The only new capability is that `Foo.bar` now works without importing

**Recommended migration for Bastion:**
1. Remove wildcard imports that cause collisions
2. Use qualified access for the conflicting names
3. Keep targeted imports (`import Mod.{specific_fn}`) for frequently-used functions

Example before:
```march
import Http
import Router
import Session    -- Session.get collides with Map.get

fn handle(req) do
  let session = get(req)   -- ambiguous!
end
```

Example after:
```march
import Http
import Router

fn handle(req) do
  let session = Session.get(req)   -- clear!
  let value = Map.get(session, "user")  -- clear!
end
```

---

### Phase 10: Test Plan

#### Unit tests (in test/test_march.ml)

1. **Basic qualified function call:** `Map.get(Map.new(), "k")` evaluates correctly
2. **Qualified type annotation:** `fn f(x : Option.Some) ...` — wait, that's a constructor. `fn f(x : Http.Request) ...` resolves the type
3. **Qualified constructor expression:** `Result.Ok(42)` produces `VCon("Ok", [42])`
4. **Qualified constructor pattern:** `match v do | Result.Ok(x) -> x end` works
5. **No import needed:** A module with no `import Map` can use `Map.get`
6. **Import still works:** `import Map` + bare `get(...)` still resolves
7. **Shadowing:** Local `fn get(x)` shadows imported `get`, but `Map.get` still works
8. **Private access rejected:** `Mod.private_fn()` produces an error
9. **Nested module access:** `Outer.Inner.func()` works
10. **Type position:** `let x : List(Map.Entry) = ...` (if Map.Entry type exists)
11. **REPL parity:** Each test runs in both eval mode and (where applicable) TIR mode
12. **Circular reference:** Module A calls B.foo, module B calls A.bar — both typecheck and eval correctly
13. **Unknown module error:** `Nonexistent.foo()` produces a clear error message

#### Integration tests

14. **Bastion qualified access:** A Bastion controller using `Http.Request`, `Router.get`, `Session.get` without collisions
15. **Stdlib coverage:** Verify that all 57 stdlib modules are accessible via qualified syntax

#### Error message tests

16. **Typo in module name:** `Mpa.get(...)` → "Unknown module `Mpa`. Did you mean `Map`?"
17. **Typo in member name:** `Map.gte(...)` → "Module `Map` does not export `gte`. Did you mean `get`?"
18. **Private access:** `Mod.pfn_name()` → "Function `pfn_name` is private to module `Mod`."

---

### Phase 11: Implementation Order

Each phase is independently useful and testable:

| Phase | What | Unblocks | Estimated Scope |
|-------|------|----------|-----------------|
| 0 | Module export registry | Everything | New module, ~200 LOC |
| 1 | (No AST changes needed) | — | 0 LOC |
| 2 | Desugar normalization | Phases 3-5 | desugar.ml, ~50 LOC |
| 3 | Typecheck qualified resolution | Type safety | typecheck.ml, ~100 LOC |
| 4 | Eval lazy module loading | Interpreter works | eval.ml + main.ml, ~80 LOC |
| 5 | TIR lower qualified support | Compiled path works | lower.ml, ~60 LOC |
| 6 | REPL polish | UX | REPL driver, ~30 LOC |

**Recommended implementation sequence:**

1. **Phase 0 + 2 + 4** — Get it working end-to-end in the interpreter. This is the most immediately useful. Bastion developers can use `Module.func()` in their code and run it.

2. **Phase 3** — Add type safety. Qualified names typecheck correctly, errors are good.

3. **Phase 5** — Compiled path works. REPL/compiler parity achieved.

4. **Phase 6** — Polish: tab completion, error message suggestions.

---

### Appendix A: Key Functions Reference

| Function | File:Line | Role in this feature |
|----------|-----------|---------------------|
| `expr_field` | parser.mly:824 | Parses `Mod.name` as `EField` |
| `qualified_upper` | parser.mly:934 | Parses `Mod.Ctor` in patterns |
| `ty_atom` (dotted) | parser.mly:634 | Parses `Mod.Type` as `TyCon` |
| `desugar_fn_def` | desugar.ml:~100 | Needs `desugar_expr` walker |
| `lookup_var` | typecheck.ml:385 | Add qualified fallback |
| `lookup_type` | typecheck.ml:386 | Add qualified fallback |
| `lookup_ctor` | typecheck.ml:387 | Add qualified fallback |
| `surface_ty` | typecheck.ml:1403 | Type resolution for `Mod.Type` |
| `prebind_mod_members` | typecheck.ml:4898 | Forward-declare qualified names |
| `check_module` | typecheck.ml:4892 | Entry point, add registry init |
| `module_registry` | eval.ml:249 | Global qualified name → value |
| `module_path_str` | eval.ml:5170 | Builds dotted path from EField chain |
| `EField` handler | eval.ml:5168 | Qualified lookup in eval |
| `ECon` handler | eval.ml:5118 | Strips qualifier for VCon tag |
| `resolve_use_alias` | lower.ml:126 | Resolve short→qualified in TIR |
| `_use_aliases` | lower.ml:123 | Maps for import resolution |
| `lower_mod_decls` | lower.ml:~1310 | Lowers nested module functions |
| `DUse` handler | lower.ml:1342 | Builds use aliases for TIR |

### Appendix B: What the Parser Already Produces

| March syntax | Parser output | Status |
|-------------|---------------|--------|
| `Map.get(m,k)` | `EApp(EField(ECon("Map",[]),"get"), [m,k])` | Works syntactically |
| `Map.new()` | `EApp(EField(ECon("Map",[]),"new"), [])` | Works syntactically |
| `Result.Ok(42)` | `EApp(EField(ECon("Result",[]),"Ok"), [42])` | Needs desugar → `ECon` |
| `Result.Ok` | `EField(ECon("Result",[]),"Ok")` | Needs desugar → `ECon` |
| `Http.Request` (type) | `TyCon("Http.Request", [])` | Works syntactically |
| `List(Map.Entry)` (type) | `TyCon("List",[TyCon("Map.Entry",[])])` | Works syntactically |
| `Result.Ok(x)` (pattern) | `PatCon("Result.Ok", [PatVar "x"])` | Works syntactically |
| `import Map` | `DUse({use_path=["Map"];use_sel=UseAll})` | Works fully |

### Appendix C: Existing Qualified Name Convention

The compiler already uses `"Module.name"` strings as keys throughout:

- **typecheck env.vars:** `"List.map" → Poly(∀a b. (a→b) → List(a) → List(b))`
- **typecheck env.ctors:** `"Option.Some" → {ci_type="Option"; ...}`
- **typecheck env.types:** `"IO.Network" → 0` (capability types)
- **eval env:** `"Map.get" → VClosure(...)` (after DMod eval)
- **eval module_registry:** `"Map.get" → VClosure(...)` (global)
- **TIR fn_name:** `"Map.get"` (fully qualified)
- **TIR _use_aliases:** `"get" → "Map.get"` (import shortcut)

This convention is already load-bearing. The proposal extends it to work across compilation units, not just within a single file's `DMod` declarations.
