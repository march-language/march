# March LSP Code Actions — World-Class Plan

**Status:** Draft
**Date:** 2026-03-25
**Inspired by:** rust-analyzer, Elixir LS/Expert/RefactorEx, HLS (Haskell), OCaml LSP (Merlin), Gleam LSP, TypeScript LSP

---

## Executive Summary

The March LSP has a solid foundation. This plan defines the path from that foundation to a
world-class developer experience — on par with rust-analyzer and Gleam LSP, the current
gold standards for statically-typed functional language tooling. The plan is organized by
priority tier (P1 → P3) and implementation phase, with each feature annotated by its
reference LSP inspiration, estimated complexity, and dependencies.

The core thesis: **great LSP tooling makes the type system feel like a collaborator, not
a gatekeeper.** The type checker knows what the code should look like. The LSP should
surface that knowledge as actionable completions, fills, and transformations — reducing
the gap between "I know what I want" and "the code is correct."

---

## Current State (as of 2026-03-25)

### Existing LSP Capabilities

The March LSP already implements:

| Feature | Implementation | Notes |
|---------|---------------|-------|
| Diagnostics | `analysis.ml` + `server.ml` | Type errors, unused bindings, dead code, non-exhaustive match |
| Hover | `server.ml on_req_hover` | Type info + doc comments |
| Go-to-definition | `analysis.ml def_map` | Name → definition span |
| Find references | `analysis.ml refs_map` | All use-site spans for a name |
| Rename | `server.ml on_unknown_request` | Cross-file workspace edit |
| Completion | `analysis.ml completion_items` | Snippets, module-aware |
| Signature help | `analysis.ml call_sites` | Active parameter highlighting |
| Semantic tokens | `server.ml` + `analysis.ml` | Delta encoding, 9 token types |
| Inlay hints | `analysis.ml inlay_hints` | Type annotations, parameter names |
| Folding ranges | `on_unknown_request` | Functions, modules, match arms |
| Code actions (existing) | `analysis.ml code_actions_at` | See table below |

### Existing Code Actions

| Action | Trigger | Kind |
|--------|---------|------|
| Fill missing match arms | Cursor on non-exhaustive match diagnostic | QuickFix |
| Add type annotation | Cursor on unannotated binding | RefactorRewrite |
| Prefix unused binding with `_` | Cursor on `unused_binding` diagnostic | QuickFix |
| Remove unused binding | Cursor on `unused_binding` diagnostic | QuickFix |
| Make binding linear | Cursor on value with consumed linear type | RefactorRewrite |
| Register-driven quickfixes | Diagnostic code → registered handler | QuickFix |

### Analysis Infrastructure

The `Analysis.t` record (in `lsp/lib/analysis.ml`) provides:

```ocaml
type t = {
  src         : string;
  filename    : string;
  type_map    : (span, Tc.ty) Hashtbl.t;    (* span → inferred type *)
  def_map     : (string, span) Hashtbl.t;   (* name → definition span *)
  use_map     : (span, string) Hashtbl.t;   (* use-site span → name *)
  vars        : (string * Tc.scheme) list;  (* in-scope term variables *)
  types       : (string * int) list;        (* type ctors → arity *)
  ctors       : (string * string) list;     (* data ctors → parent type *)
  interfaces  : (string * interface_def) list;
  impls       : (string * Tc.ty) list;
  actors      : (string * actor_def) list;
  doc_map     : (string, string) Hashtbl.t;
  refs_map    : (string, span list) Hashtbl.t;
  call_sites  : call_site list;
  consumption : consumption list;
  match_sites : match_site list;
  diagnostics : Lsp.Types.Diagnostic.t list;
}
```

This infrastructure is the backbone for all new code actions. Features that need new
data (e.g., pipe chains, typed holes) will require additions to this record and
corresponding analysis passes.

---

## Reference LSP Research Summary

This section synthesizes the key innovations from six world-class language servers,
organized to inform March's priorities.

### rust-analyzer (170+ Assists)

The gold standard for code action breadth. Key innovations:
- **Fill match arms** (exhaustive pattern generation from type ctors)
- **Add missing trait impl members** (scaffold from interface)
- **Extract function/variable/module** (selection-based refactoring)
- **Inline variable** (reverse of extract)
- **Generate new/getter/setter** (struct boilerplate)
- **Add turbofish** (explicit type application)
- **Merge/sort/unmerge imports**
- **Convert if-to-match / match-to-if** (control flow transformations)
- **Add explicit type annotation** (infer and insert)
- **Unwrap Result** (remove error wrapper from return type)
- **Apply De Morgan's law** (boolean logic transformations)
- **Convert arithmetic to checked/saturating** (safety upgrades)

Design philosophy: every transformation is reversible; the user can always undo. Actions
are triggered by context (cursor position + AST node type), never globally.

### Elixir LS / Expert / RefactorEx (29 Refactorings)

Best-in-class for functional pipeline tooling. Key innovations:
- **Introduce pipe** — converts `f(g(x))` → `x |> g() |> f()`
- **Remove pipe** — converts `x |> f() |> g()` → `g(f(x))`
- **Expand/collapse anonymous function** — `&fun/1` ↔ `fn x -> fun(x) end`
- **Expand/inline/merge aliases** — module alias management
- **Extract/inline/rename constant** — constant management
- **Extract/inline function**
- **Convert case ↔ with** — control flow transformation
- **Organize aliases** (Lexical) — alphabetize and deduplicate
- **Auto-alias** (Lexical) — type module name, get alias inserted
- **Introduce IO.inspect** / **Remove IO.inspect** — debug workflow

Design philosophy: pipeline refactoring is a first-class citizen. The bidirectional
pipe/call conversion is essential for idiomatic functional code.

### HLS — Haskell Language Server (Wingman)

Best-in-class for type-directed code generation. Key innovations:
- **Add type signature** — infer and insert function type annotations
- **Case split** — pattern match on local variable, enumerate all constructors
- **Fill typed hole** — synthesize complete expression for `_`-hole from type context
- **Add missing typeclass methods** — scaffold required methods
- **Apply HLint suggestions** — code quality transforms as code actions
- **Make imports explicit** — expand wildcard imports
- **Wingman tactics**: case split, refine (one obvious step), split function args

Design philosophy: typed holes (`_`) are first-class. The compiler knows what goes
there; the LSP surfaces it. This is the most powerful form of code-as-collaboration.

### OCaml LSP / Merlin (Destruct & Construct)

Best-in-class for bidirectional type-driven generation. Key innovations:
- **Destruct** — given a value, generate exhaustive pattern match on its type
  - On expression: replace with exhaustive match enumerating all constructors
  - On wildcard `_` in match arm: refine the pattern
  - On non-exhaustive match: add the missing cases
- **Construct** — given a typed hole `_`, suggest values that fill it
  - Works for variants, tuples, records, function applications
- **Type-directed completion** — filter completions by expected type
- **Infer interface** — generate `.mli` file from `.ml` implementation

Design philosophy: **Destruct and Construct are dual operations** — one goes from
type to code (fill in the pieces), the other goes from code to type (break into pieces).
Together they form an interactive, type-driven REPL inside the editor.

### Gleam LSP (30+ Actions)

Best-in-class for completeness and UX polish. Key innovations:
- **Convert to/from pipe** — bidirectional `|>` conversion
- **Convert to/from `use`** — Gleam-specific syntax form conversion
- **Add missing patterns** — complete inexhaustive case
- **Fill labels** — add expected labels to incomplete function calls
- **Generate decoder** — create dynamic decoder from type definition
- **Generate to-JSON function** — create serialization from type
- **Discard unused result** — assign to `_`
- **Collapse nested case** — merge nested case expressions
- **Inexhaustive let to case** — convert risky let-pattern to exhaustive case
- **Extract variable/constant/function**
- **Inline variable**
- **Expand function capture** — `&fun` → `fn x -> fun(x)`
- **Case correction** — fix naming convention violations
- **Remove redundant tuples** in case expressions

Design philosophy: every syntactic form has a complement. The LSP knows both forms
and can freely convert between them. 30+ actions means every frustrating manual edit
has an automated equivalent.

### TypeScript LSP (~30 Actions)

Best-in-class for import management and interface compliance. Key innovations:
- **Auto-import** — infer and add import for unresolved name
- **Organize imports** — sort + remove unused (configurable on-save)
- **Add missing imports** — batch fix all unresolved names
- **Extract to function/variable/constant**
- **Move to new file** — top-level declaration → separate file
- **Generate getters/setters** — property encapsulation
- **Infer return types** — add explicit return type annotation
- **Convert parameters to destructured object** — refactor many-arg functions
- **Implement interface** — scaffold all required members
- **Fix all** (`source.fixAll`) — apply all safe auto-fixes at once

Design philosophy: import hygiene and interface compliance are zero-effort. The LSP
handles all bookkeeping, freeing developers to focus on logic.

---

## Proposed Features by Priority

Features are organized P1 (highest impact, implement first) through P3 (nice-to-have).
Each entry includes: description, reference LSP, estimated complexity, and dependencies.

---

### P1 — Highest Impact (Phase 1–2)

These features have the highest ratio of developer value to implementation effort. They
build directly on existing infrastructure and address the most common daily friction
points.

---

#### P1.1 — Fill Missing Match Arms (Enhanced)

**What it does:** The existing action fills missing arms with `_ -> todo!()` stubs. The
enhanced version generates *typed stubs* — each arm binds the constructor's fields with
appropriate names derived from the field types. For example, a `Result(Int, String)` match
generates:

```march
match result do
  Ok(value) -> todo!()
  Err(message) -> todo!()
end
```

Rather than:

```march
match result do
  _ -> todo!()
end
```

**Inspired by:** rust-analyzer `add_missing_match_arms`, OCaml Merlin `Destruct`
**Complexity:** Medium — requires field name inference from constructor signatures
**Dependencies:** `ctors` + `types` maps already exist; need to look up field types from
the type checker's constructor table
**Analysis changes:** Extend `match_site` to record the full constructor signatures for the
subject type

---

#### P1.2 — Introduce Pipe / Remove Pipe

**What it does:** Two complementary actions.

*Introduce pipe* — cursor on any expression of the form `f(g(h(x, args), more), rest)`:
converts to `x |> h(args) |> g(more) |> f(rest)`. Only valid when the first argument
threads through all calls.

*Remove pipe* — cursor on a `|>` chain: converts back to nested function application.

Example:
```march
# Before: introduce pipe
String.trim(String.downcase(input))

# After: introduce pipe
input |> String.downcase() |> String.trim()

# Remove pipe is the reverse
```

**Inspired by:** RefactorEx `introduce_pipe` / `remove_pipe`, Gleam LSP `convert_to_pipe`
**Complexity:** Medium — requires AST pattern matching on call chains; pipe chain parsing
**Dependencies:** Parser already handles `|>` (EApp with pipe desugaring); analysis needs
to detect nestable call chains
**Analysis changes:** Add `pipe_candidates : pipe_chain list` to `Analysis.t`

---

#### P1.3 — Extract Variable

**What it does:** Select an expression (or cursor on a sub-expression); the action
introduces a `let` binding above the current statement with the expression as the RHS,
replacing the original occurrence with the new name.

```march
# Before (cursor on `x * x + y * y`)
let dist = Float.sqrt(x * x + y * y)

# After: extract variable `sum_of_squares`
let sum_of_squares = x * x + y * y
let dist = Float.sqrt(sum_of_squares)
```

**Inspired by:** rust-analyzer `extract_variable`, Gleam LSP `extract_variable`, TypeScript `Extract to variable`
**Complexity:** Medium — requires selection range support (already exists via folding ranges
infrastructure); name suggestion from type
**Dependencies:** `type_map` for type-based name suggestion; LSP selection range protocol
**Analysis changes:** Add `extract_candidates : (span * Tc.ty) list` — sub-expressions
suitable for extraction

---

#### P1.4 — Inline Variable

**What it does:** Cursor on a `let x = expr` binding; replaces all uses of `x` with
`expr`, then removes the binding. Only offered when the binding is used exactly once (or
as a user-confirmed action when used multiple times).

```march
# Before (cursor on `let greeting`)
let greeting = "Hello, " ^ name
IO.println(greeting)

# After: inline variable
IO.println("Hello, " ^ name)
```

**Inspired by:** rust-analyzer `extract_variable` (inverse), RefactorEx `inline_variable`, Gleam LSP `inline_variable`
**Complexity:** Low-Medium — `consumption` list already tracks use counts; workspace edit
**Dependencies:** `consumption` (already exists), `refs_map`
**Analysis changes:** None; use existing consumption + refs_map

---

#### P1.5 — Auto-Import / Add Missing Import

**What it does:** When a name is used but not imported/aliased, and it exists in a known
module, offer to add the import at the top of the file. If multiple modules export the
same name, present a disambiguating picker.

```march
# Before: `HashMap` is unknown
let m = HashMap.new()

# After: action "Import HashMap from std/collections"
import std/collections (HashMap)
let m = HashMap.new()
```

**Inspired by:** TypeScript `addMissingImports`, rust-analyzer `auto_import`
**Complexity:** Medium-High — requires a module index (all exported names per module);
can start with stdlib only
**Dependencies:** Module index (new infrastructure), diagnostic code for unresolved names
**Analysis changes:** Add `unresolved_names : (string * span) list`; new `ModuleIndex.t`
singleton loaded from stdlib

---

#### P1.6 — Generate Interface Impl Scaffold

**What it does:** When a type declaration implements an interface but is missing required
methods, offer to scaffold the missing method stubs. Works for both `impl Interface for
Type` blocks and standalone `impl` declarations.

```march
# Before: Printable interface requires `to_string`
type Point = Point(Int, Int)
impl Printable for Point do
  # cursor here — missing `to_string`
end

# After: "Add missing impl members"
impl Printable for Point do
  fn to_string(p: Point) -> String = todo!()
end
```

**Inspired by:** rust-analyzer `add_impl_missing_members`, HLS `add_missing_class_methods`, TypeScript `implement interface`
**Complexity:** Medium — requires interface definition lookup; signature generation from
interface method signatures
**Dependencies:** `interfaces` map (already exists); `impls` map
**Analysis changes:** Add `missing_impl_sites : missing_impl list` recording impl blocks
with absent required methods

---

#### P1.7 — Add Type Annotation (Enhanced)

**What it does:** The existing action inserts a type annotation on the binding name. The
enhanced version also handles:
- Function return type annotations (`fn foo(x) -> Int = ...`)
- Function parameter annotations
- Batch "annotate all unannotated bindings in file"

```march
# Before
fn greet(name) = "Hello, " ^ name

# After: "Add return type annotation"
fn greet(name) -> String = "Hello, " ^ name

# After: "Add parameter type annotation"
fn greet(name: String) -> String = "Hello, " ^ name
```

**Inspired by:** rust-analyzer `add_explicit_type`, TypeScript `infer_function_return_types`, HLS `add_type_signature`
**Complexity:** Low (return type) / Medium (parameters) — type_map lookup; text insertion
**Dependencies:** `type_map`, `annotation_sites` (already exists)
**Analysis changes:** Extend `annotation_site` to include function param sites and return
type sites

---

#### P1.8 — Discard Unused Result / Prefix with `_`

**What it does:** When an expression produces a value that is never used (and this triggers
a warning), offer:
1. Assign to `_`: `let _ = expr`
2. Use in next expression (if there's an obvious continuation)

This is a common frustration point in strict functional languages where side-effectful
functions return values the caller doesn't need.

```march
# Before: warning — result of `IO.println` discarded
IO.println("hello")

# After: "Discard result"
let _ = IO.println("hello")
```

**Inspired by:** Gleam LSP `discard_unused_result`
**Complexity:** Low — variant of existing unused-binding action
**Dependencies:** Existing unused-binding infrastructure

---

### P1.9 — Expand Function Capture / Collapse to Capture

**What it does:** Two complementary actions.

*Expand* — `&module_fn` or `fn(x) -> f(x)` style captures → full `fn (x) -> ...` lambda
*Collapse* — `fn (x) -> f(x)` → `&f` shorthand (when applicable)

```march
# Before
List.map(items, &String.trim)

# After: expand
List.map(items, fn (x) -> String.trim(x))

# Reverse: collapse anonymous function
List.map(items, fn (x) -> String.trim(x))
# → List.map(items, &String.trim)
```

**Inspired by:** RefactorEx `expand_anonymous_function` / `collapse_anonymous_function`, Gleam `expand_function_capture`
**Complexity:** Low-Medium
**Dependencies:** Parser support for `&` capture syntax (check if implemented)

---

### P2 — High Value (Phase 3–4)

These features deliver significant value but require more infrastructure or tackle
less-universal use cases.

---

#### P2.1 — Typed Hole Completion (Construct)

**What it does:** Place `_` as a placeholder in an expression position. The LSP detects
the expected type from the surrounding context and offers completions that satisfy that
type:
- Values of the right type in scope
- Constructors that return the right type
- Functions whose return type matches

```march
# Cursor on `_`
let x: Option(String) = _
# Completions offered: Some("..."), None, existing Option(String) bindings in scope
```

**Inspired by:** OCaml Merlin `Construct`, HLS Wingman `fill_typed_hole`
**Complexity:** High — requires bidirectional type inference for hole sites; Merlin calls
this "type-directed completion"
**Dependencies:** Typechecker must propagate expected types to hole sites; new
`hole_sites : (span * Tc.ty) list` in Analysis.t
**Analysis changes:** Thread expected types down during typechecking; expose hole_sites

---

#### P2.2 — Destruct (OCaml-style Pattern Generation)

**What it does:** Cursor on a variable; "Destruct" generates an exhaustive match on that
variable's type, replacing the expression with a full pattern match. This is the most
powerful pattern-matching aid in the OCaml ecosystem.

```march
# Before (cursor on `result`)
fn process(result: Result(Int, String)) -> String =
  result

# After: "Destruct result"
fn process(result: Result(Int, String)) -> String =
  match result do
    Ok(value) -> todo!()
    Err(message) -> todo!()
  end
```

Works on:
- Variables in expression position
- Wildcards `_` in existing match arms (refines the pattern)
- Function parameters (generates multi-clause function)

**Inspired by:** OCaml Merlin `Destruct` (primary inspiration)
**Complexity:** High — requires type lookup for variable + constructor enumeration +
multi-clause function generation
**Dependencies:** `type_map`, `ctors`, constructor field types

---

#### P2.3 — Extract Function

**What it does:** Select a block of statements or an expression; "Extract function"
creates a new top-level function (or local function via `let`) with the selected code
as the body, capturing free variables as parameters.

```march
# Before (selection: `x * x + y * y`)
fn distance(x: Float, y: Float) -> Float =
  Float.sqrt(x * x + y * y)

# After: "Extract function `sum_of_squares`"
fn sum_of_squares(x: Float, y: Float) -> Float =
  x * x + y * y

fn distance(x: Float, y: Float) -> Float =
  Float.sqrt(sum_of_squares(x, y))
```

**Inspired by:** rust-analyzer `extract_function`, RefactorEx `extract_function`, Gleam `extract_function`, TypeScript `Extract to function`
**Complexity:** High — free variable analysis, parameter ordering, name conflict avoidance
**Dependencies:** Selection ranges; free variable analysis (new pass)
**Analysis changes:** Add `free_vars_of : span -> (string * Tc.ty) list` utility

---

#### P2.4 — Generate Constructor (`new` function)

**What it does:** Cursor on a type declaration; generates a `new` (or custom-named)
constructor function with the type's fields as parameters, with validation stubs if the
type has constraints.

```march
# Before
type User = User {
  name: String,
  age: Int,
  email: String
}

# After: "Generate User.new"
fn User.new(name: String, age: Int, email: String) -> User =
  User { name, age, email }
```

**Inspired by:** rust-analyzer `generate_new`, TypeScript `Generate constructor`
**Complexity:** Medium — record field enumeration; naming conventions
**Dependencies:** Type declaration parsing; record field types

---

#### P2.5 — Generate Getter / Setter

**What it does:** Cursor on a record field; generates accessor functions for that field.

```march
# Before
type Point = Point { x: Float, y: Float }

# After: "Generate getter for x"
fn Point.get_x(p: Point) -> Float = p.x

# After: "Generate setter for x"
fn Point.set_x(p: Point, x: Float) -> Point =
  Point { ..p, x }
```

**Inspired by:** rust-analyzer `generate_getter` / `generate_setter`, TypeScript `Generate get and set accessors`
**Complexity:** Medium — field accessor pattern generation
**Dependencies:** Record type field analysis

---

#### P2.6 — Organize Imports / Sort Aliases

**What it does:** Sort all `import` statements alphabetically, group by stdlib vs. local,
remove duplicates. Optionally auto-run on save (configurable).

**Inspired by:** TypeScript `source.organizeImports`, Lexical `organize_aliases`
**Complexity:** Low-Medium — import AST walking; text replacement
**Dependencies:** Import declaration AST nodes

---

#### P2.7 — Convert `if/else` to `match` and Back

**What it does:** An `if/else if/else` chain over a variable becomes a `match`; a
two-arm `match` over a boolean becomes `if/else`.

```march
# Before
if shape == Circle then ...
else if shape == Square then ...
else ...

# After: "Convert to match"
match shape do
  Circle -> ...
  Square -> ...
  _ -> ...
end
```

**Inspired by:** rust-analyzer `convert_if_to_match` / `replace_match_with_if_let`
**Complexity:** Medium — pattern analysis for exhaustiveness

---

#### P2.8 — Case Correction (Naming Convention Fixes)

**What it does:** Detects naming convention violations (e.g., `camelCase` function names
instead of `snake_case`; `snake_case` type names instead of `PascalCase`) and offers to
rename to the conventional form, updating all references.

```march
# Before (warning: function should be snake_case)
fn myFunction(x: Int) -> Int = x + 1

# After: "Rename to my_function"
fn my_function(x: Int) -> Int = x + 1
```

**Inspired by:** Gleam LSP `case_correction`
**Complexity:** Low — regex-based name transformation + existing rename infrastructure
**Dependencies:** Existing rename code action

---

#### P2.9 — Add Missing Patterns to `let` / Inexhaustive `let` → `case`

**What it does:** When a `let` pattern is non-exhaustive (e.g., `let Ok(x) = result` may
fail if `result` is `Err`), offer to either:
1. Add a guard/assertion
2. Convert to an exhaustive `match`

```march
# Before (non-exhaustive)
let Ok(value) = fetch_data()

# After: "Convert to exhaustive match"
let value = match fetch_data() do
  Ok(v) -> v
  Err(e) -> panic!("fetch failed: " ^ e)
end
```

**Inspired by:** Gleam LSP `inexhaustive_let_to_case`
**Complexity:** Medium
**Dependencies:** Non-exhaustive let diagnostic

---

#### P2.10 — Remove Unused Import

**What it does:** Quick fix for unused import diagnostics — remove the specific import
declaration (or just the unused name from a partial import list).

**Inspired by:** TypeScript `source.removeUnusedImports`, rust-analyzer `remove_unused_imports`
**Complexity:** Low — diagnostic-driven text deletion
**Dependencies:** Unused import diagnostic (needs new diagnostic pass)

---

#### P2.11 — Generate `to_string` / `Printable` Impl

**What it does:** Cursor on a type; generates a `Printable` or `Show` interface
implementation that formats the type's constructors and fields.

```march
# Before
type Color = Red | Green | Blue

# After: "Implement Printable for Color"
impl Printable for Color do
  fn to_string(c: Color) -> String =
    match c do
      Red -> "Red"
      Green -> "Green"
      Blue -> "Blue"
    end
end
```

**Inspired by:** Gleam LSP `generate_to_json`, rust-analyzer trait impl scaffolding
**Complexity:** Medium
**Dependencies:** `interfaces` map; constructor enumeration

---

#### P2.12 — Collapse Nested Match

**What it does:** When a match arm immediately contains another match on the same
subject, collapse into a single match with compound patterns.

```march
# Before (nested match)
match opt do
  Some(inner) ->
    match inner do
      Ok(v) -> v
      Err(e) -> default
    end
  None -> default
end

# After: "Collapse nested match"
match opt do
  Some(Ok(v)) -> v
  Some(Err(_)) -> default
  None -> default
end
```

**Inspired by:** Gleam LSP `collapse_case`
**Complexity:** High — requires match arm merging with pattern composition

---

### P3 — Nice-to-Have (Phase 5+)

These features are polish and March-specific innovations that go beyond most LSPs.

---

#### P3.1 — March-Specific: Actor Boilerplate Generation

**What it does:** Cursor on an `actor` declaration; generates:
- Message type (`type ActorMsg = ...`)
- Handler function skeleton
- `spawn` call example
- Client wrapper functions (one per message variant)

```march
# Before
actor Counter do
  state: Int
  receive Increment -> ...
  receive GetCount -> ...
end

# After: "Generate Counter client module"
mod Counter.Client do
  fn increment(pid: Pid(Counter)) -> Unit =
    send(pid, Increment)

  fn get_count(pid: Pid(Counter)) -> Int =
    call(pid, GetCount)
end
```

**Inspired by:** No direct analog — March-specific innovation
**Complexity:** Medium-High
**Dependencies:** Actor analysis (already in `actors` map)

---

#### P3.2 — March-Specific: Session Type Scaffolding

**What it does:** Given a session type annotation, generate the protocol handler skeleton
that satisfies it — all the send/receive steps in order.

```march
# Session type: Send Int; Receive String; End
# Action: "Generate session handler"
fn handle(ch: Channel(!Int, ?String, End)) -> Unit = do
  send(ch, _)
  let response = receive(ch)
  close(ch)
end
```

**Inspired by:** No direct analog — exploits March's unique session types feature
**Complexity:** High
**Dependencies:** Session type parser/checker

---

#### P3.3 — March-Specific: Linear Type Consumption Audit

**What it does:** For functions that take linear values, display an inlay annotation
showing where each linear value is consumed. Offer a code action to highlight the full
consumption path.

**Inspired by:** No direct analog — exploits March's linear types
**Complexity:** Medium
**Dependencies:** `consumption` (already exists)

---

#### P3.4 — Introduce Debug Inspect / Remove Inspect

**What it does:** Wrap any expression with `Debug.inspect(expr, "label")` for temporary
debugging, then clean it up with a single action.

```march
# Before
let result = compute(x)

# After: "Wrap with Debug.inspect"
let result = Debug.inspect(compute(x), "result")

# Reverse: "Remove Debug.inspect"
let result = compute(x)
```

**Inspired by:** RefactorEx `introduce_io_inspect` / `remove_io_inspect`
**Complexity:** Low

---

#### P3.5 — Convert `with` to `case` / `case` to `with`

**What it does:** March's equivalent of Elixir's `with` expression (if it exists, or
when added). Convert between chained `let Ok(x) = ...` patterns and explicit `match`.

**Inspired by:** RefactorEx `convert_from_with` / `convert_to_with`
**Complexity:** Medium
**Dependencies:** `with` expression syntax (if added to March)

---

#### P3.6 — Move Declaration to New Module

**What it does:** Select a top-level function or type; "Move to new file" creates a new
`.march` file with that declaration (updating imports automatically).

**Inspired by:** TypeScript `Move to new file`, rust-analyzer `extract_module`
**Complexity:** High — cross-file workspace edits; import management

---

#### P3.7 — Generate Decoder from Type

**What it does:** Given a record type, generate a JSON decoder function using the stdlib
JSON/decode API.

```march
# type User = User { name: String, age: Int }
# Action: "Generate User JSON decoder"
fn decode_user(json: Json) -> Result(User, String) = do
  let name = Json.field("name", Json.string, json)?
  let age = Json.field("age", Json.int, json)?
  Ok(User { name, age })
end
```

**Inspired by:** Gleam LSP `generate_decoder`
**Complexity:** Medium-High — stdlib JSON API knowledge baked in

---

#### P3.8 — Batch Code Action: Fix All

**What it does:** Apply all safe auto-fixes in the file with one action:
- Remove all unused bindings
- Add all missing type annotations (on unannotated `let` bindings)
- Prefix all unused params with `_`
- Remove all unused imports

**Inspired by:** TypeScript `source.fixAll`
**Complexity:** Low — orchestration of existing actions

---

#### P3.9 — Merge / Split Match Arms

**What it does:**
- *Merge*: two adjacent match arms with identical bodies → `Arm1 | Arm2 -> body`
- *Split*: an arm with `|` patterns → separate arms

```march
# Before (two arms with same body)
match x do
  A -> 0
  B -> 0
  C -> 1
end

# After: "Merge A and B arms"
match x do
  A | B -> 0
  C -> 1
end
```

**Inspired by:** rust-analyzer `merge_match_arms` / `split_match_arm`
**Complexity:** Medium

---

#### P3.10 — Apply De Morgan's Law

**What it does:** On a boolean negation expression, offer to rewrite using De Morgan:
`!(a && b)` → `!a || !b` and vice versa.

**Inspired by:** rust-analyzer `apply_demorgan`
**Complexity:** Low

---

#### P3.11 — Add Missing Labels to Function Call

**What it does:** When calling a function with labeled parameters but some labels are
omitted, offer to expand the call to include all labels explicitly.

```march
# Before (labels omitted)
connect("localhost", 8080)

# After: "Add labels"
connect(host: "localhost", port: 8080)
```

**Inspired by:** Gleam LSP `add_labels`
**Complexity:** Low-Medium
**Dependencies:** Labeled parameter tracking in `call_sites`

---

## March-Specific Innovations

Beyond what other LSPs offer, March has unique features that enable novel code actions:

### Innovation 1: Linear Type Consumption Path Visualization

March tracks linear type consumption via the `consumption` analysis. We can expose this
as a code lens or code action that shows the full lifecycle of a linear value — where it
enters scope, where it is consumed, and whether it could be moved earlier/later. No other
LSP tracks resource ownership at this level of precision in the editor.

### Innovation 2: Actor Protocol Compliance Checking

March's actor system gives the LSP visibility into message protocol definitions. A code
action that validates all send sites against the actor's expected message types — and
generates missing handlers — is unique to March. This is a step beyond TypeScript's
"implement interface" because it covers distributed message passing.

### Innovation 3: Session Type Step Generation

Given a session type `!Int; ?String; End`, the LSP can generate the exact sequence of
send/receive/close calls required to satisfy the protocol. This makes session types feel
like scaffolding rather than constraints.

### Innovation 4: Pipeline Refactoring with Type Guidance

Unlike Elixir's pipe refactoring (which is purely syntactic), March's typed pipe
refactoring can verify that the pipe transformation preserves types at each step and
warn when it does not. The LSP knows the type of each intermediate value in the chain.

### Innovation 5: Typed Hole Completion with Ranked Suggestions

Building on OCaml Merlin's Construct feature, March can rank typed hole completions by:
1. Values in scope with exact type match (highest priority)
2. Functions returning the right type applied to in-scope args
3. Constructors producing the right type

This creates a "type-driven autocomplete" that feels like pair programming with the
type checker.

---

## Implementation Phases

### Phase 1 — Polish Existing + Quick Wins (2–3 weeks)

Focus: Low-effort, high-visibility improvements to existing actions + purely additive
features that need no new analysis infrastructure.

| Feature | Complexity | Key Changes |
|---------|------------|-------------|
| P1.1 Fill match arms (enhanced, typed stubs) | Medium | Extend match_site with ctor signatures |
| P1.7 Type annotation enhancements (return type + params) | Low-Medium | Extend annotation_sites |
| P1.8 Discard unused result | Low | Variant of existing action |
| P2.8 Case correction (naming conventions) | Low | Regex + existing rename |
| P2.10 Remove unused import | Low | New diagnostic + text delete |
| P3.4 Introduce/remove debug inspect | Low | Text wrap/unwrap |
| P3.8 Batch fix all | Low | Orchestrate existing actions |
| P3.10 Apply De Morgan | Low | Boolean pattern rewrite |

**Deliverable:** 8 new/improved actions; zero new analysis passes needed.

---

### Phase 2 — Core Refactoring (3–4 weeks)

Focus: The most requested daily-driver refactoring operations. These require new
analysis passes but not new infrastructure.

| Feature | Complexity | Key Changes |
|---------|------------|-------------|
| P1.2 Introduce / Remove pipe | Medium | pipe_candidates analysis pass |
| P1.3 Extract variable | Medium | extract_candidates pass; selection ranges |
| P1.4 Inline variable | Low-Medium | Use existing consumption + refs_map |
| P1.9 Expand / collapse function capture | Low-Medium | Parser check; capture site analysis |
| P2.7 Convert if/else ↔ match | Medium | Pattern analysis pass |
| P2.9 Inexhaustive let → match | Medium | Non-exhaustive let diagnostic |
| P3.9 Merge / split match arms | Medium | Match arm AST manipulation |
| P3.11 Add missing labels to call | Low-Medium | Extend call_sites |

**Deliverable:** 8 new actions; requires ~4 new analysis passes.

---

### Phase 3 — Type-Directed Generation (4–5 weeks)

Focus: Features that require deep type system integration. These are the highest-value
features for an ML-family language LSP.

| Feature | Complexity | Key Changes |
|---------|------------|-------------|
| P1.5 Auto-import | Medium-High | ModuleIndex singleton; unresolved_names |
| P1.6 Generate interface impl scaffold | Medium | missing_impl_sites pass |
| P2.1 Typed hole completion | High | Bidirectional type propagation; hole_sites |
| P2.2 Destruct | High | Constructor enumeration; multi-clause generation |
| P2.4 Generate constructor (`new`) | Medium | Record field analysis |
| P2.5 Generate getter/setter | Medium | Field accessor generation |
| P2.11 Generate Printable impl | Medium | Constructor format generation |

**Deliverable:** 7 new actions; requires type system bidirectionality + module index.

---

### Phase 4 — Advanced Refactoring (4–6 weeks)

Focus: Complex transformations that touch multiple files or require deep AST surgery.

| Feature | Complexity | Key Changes |
|---------|------------|-------------|
| P2.3 Extract function | High | Free variable analysis; selection ranges |
| P2.6 Organize imports | Low-Medium | Import sort + dedup |
| P2.12 Collapse nested match | High | Pattern composition algorithm |
| P3.6 Move declaration to new file | High | Cross-file workspace edits |
| P3.7 Generate decoder | Medium-High | Stdlib JSON API knowledge |

**Deliverable:** 5 new actions; most complex phase due to cross-file work.

---

### Phase 5 — March-Specific Innovations (6–8 weeks)

Focus: Features unique to March that no other LSP offers.

| Feature | Complexity | Key Changes |
|---------|------------|-------------|
| P3.1 Actor boilerplate generation | Medium-High | Actor analysis; message dispatch |
| P3.2 Session type scaffolding | High | Session type AST walking |
| P3.3 Linear type consumption audit | Medium | Consumption path visualization |
| P3.5 Convert `with` ↔ `case` | Medium | `with` expression support |

**Deliverable:** 4 new actions; requires March-specific language features.

---

## Summary Table: All Proposed Actions

| ID | Feature | Priority | Phase | Complexity | Inspired By |
|----|---------|----------|-------|------------|-------------|
| P1.1 | Fill match arms (typed stubs) | P1 | 1 | Medium | rust-analyzer, Merlin |
| P1.2 | Introduce / remove pipe | P1 | 2 | Medium | RefactorEx, Gleam |
| P1.3 | Extract variable | P1 | 2 | Medium | rust-analyzer, Gleam, TS |
| P1.4 | Inline variable | P1 | 2 | Low-Med | rust-analyzer, RefactorEx |
| P1.5 | Auto-import | P1 | 3 | Med-High | TypeScript, rust-analyzer |
| P1.6 | Generate impl scaffold | P1 | 3 | Medium | rust-analyzer, HLS, TS |
| P1.7 | Type annotation (enhanced) | P1 | 1 | Low-Med | rust-analyzer, HLS, TS |
| P1.8 | Discard unused result | P1 | 1 | Low | Gleam |
| P1.9 | Expand/collapse fn capture | P1 | 2 | Low-Med | RefactorEx, Gleam |
| P2.1 | Typed hole completion | P2 | 3 | High | Merlin, HLS Wingman |
| P2.2 | Destruct | P2 | 3 | High | OCaml Merlin |
| P2.3 | Extract function | P2 | 4 | High | rust-analyzer, Gleam, TS |
| P2.4 | Generate constructor | P2 | 3 | Medium | rust-analyzer, TS |
| P2.5 | Generate getter/setter | P2 | 3 | Medium | rust-analyzer, TS |
| P2.6 | Organize imports | P2 | 4 | Low-Med | TypeScript, Lexical |
| P2.7 | Convert if/else ↔ match | P2 | 2 | Medium | rust-analyzer |
| P2.8 | Case correction | P2 | 1 | Low | Gleam |
| P2.9 | Inexhaustive let → match | P2 | 2 | Medium | Gleam |
| P2.10 | Remove unused import | P2 | 1 | Low | TypeScript, rust-analyzer |
| P2.11 | Generate Printable impl | P2 | 3 | Medium | Gleam |
| P2.12 | Collapse nested match | P2 | 4 | High | Gleam |
| P3.1 | Actor boilerplate | P3 | 5 | Med-High | March-specific |
| P3.2 | Session type scaffolding | P3 | 5 | High | March-specific |
| P3.3 | Linear consumption audit | P3 | 5 | Medium | March-specific |
| P3.4 | Introduce/remove inspect | P3 | 1 | Low | RefactorEx |
| P3.5 | Convert with ↔ case | P3 | 5 | Medium | RefactorEx |
| P3.6 | Move to new file | P3 | 4 | High | TypeScript, rust-analyzer |
| P3.7 | Generate decoder | P3 | 4 | Med-High | Gleam |
| P3.8 | Batch fix all | P3 | 1 | Low | TypeScript |
| P3.9 | Merge/split match arms | P3 | 2 | Medium | rust-analyzer |
| P3.10 | Apply De Morgan | P3 | 1 | Low | rust-analyzer |
| P3.11 | Add missing labels | P3 | 2 | Low-Med | Gleam |

**Total: 31 new/enhanced code actions across 5 phases.**

---

## Infrastructure Requirements

### New Analysis Passes Required

| Pass | Used By | Estimated Lines |
|------|---------|----------------|
| `pipe_candidates` — detect nestable call chains | P1.2 | ~100 |
| `extract_candidates` — sub-expressions suitable for extraction | P1.3 | ~80 |
| `missing_impl_sites` — impl blocks with absent required methods | P1.6 | ~120 |
| `unresolved_names` — names used but not imported | P1.5 | ~60 |
| `module_index` — stdlib exported names | P1.5 | ~200 (separate module) |
| `hole_sites` — typed hole positions with expected types | P2.1 | ~150 (TC change) |
| `free_var_analysis` — free variables in a span | P2.3 | ~80 |
| `param_annotation_sites` — unannotated function params | P1.7 | ~80 |

### New `Analysis.t` Fields

```ocaml
pipe_candidates    : pipe_chain list;
extract_candidates : (span * Tc.ty) list;
missing_impls      : missing_impl list;
unresolved_names   : (string * span) list;
hole_sites         : (span * Tc.ty) list;
param_annot_sites  : param_annot_site list;
```

### Protocol Changes

All actions fit within the existing `textDocument/codeAction` protocol. No new LSP
protocol methods needed until Phase 4 (move-to-file requires `workspace/applyEdit` with
multiple documents, already in the LSP spec and supported by linol).

---

## Design Principles

Drawing from the best of all reference LSPs, the March LSP code action system should
follow these principles:

1. **Type system as collaborator** — every action that generates code should produce
   type-correct stubs, using `todo!()` or `_` only as a last resort.

2. **Reversibility** — every transformation that changes syntax (pipe intro, extract,
   inline) should have a corresponding reverse action.

3. **Cursor-context sensitivity** — actions appear only when relevant to the current
   cursor position and AST node. No global actions except "fix all."

4. **No surprises** — generated code should follow March's naming conventions and style
   automatically. Use the existing case-correction logic.

5. **Diagnostic-driven and cursor-driven** — some actions are triggered by diagnostics
   (quick fixes), others by cursor position (refactoring). Both are valuable; neither
   should dominate.

6. **March-first innovations** — the linear type consumption audit, actor boilerplate
   generation, and session type scaffolding are unique to March. These are the actions
   that will make developers choose March for its tooling, not just its type system.

---

## References

- [rust-analyzer Assists Documentation](https://rust-analyzer.github.io/book/assists.html)
- [RefactorEx — Elixir Refactoring Catalog](https://github.com/gp-pereira/refactorex)
- [Next LS Code Actions](https://www.elixir-tools.dev/docs/next-ls/code-actions/)
- [Lexical LSP](https://github.com/lexical-lsp/lexical)
- [HLS Features](https://haskell-language-server.readthedocs.io/en/latest/features.html)
- [Wingman for Haskell](https://haskellwingman.dev/)
- [Tarides: Merlin Destruct and Construct](https://tarides.com/blog/2022-12-21-advanced-merlin-features-destruct-and-construct/)
- [Gleam Language Server Code Actions](https://gleam.run/news/convenient-code-actions/)
- [TypeScript Refactoring in VS Code](https://code.visualstudio.com/docs/typescript/typescript-refactoring)
- [existing plan: specs/plans/lsp-enhancements-plan.md](lsp-enhancements-plan.md)
- [existing plan: specs/plans/2026-03-23-lsp-feature-improvements.md](2026-03-23-lsp-feature-improvements.md)
