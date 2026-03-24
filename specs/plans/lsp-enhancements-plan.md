# March LSP Enhancements Plan: Good → World-Class

**Status:** Draft
**Date:** 2026-03-24
**Inspired by:** rust-analyzer, ocaml-lsp, elixir-ls

---

## Executive Summary

The March LSP already has a solid foundation: diagnostics, hover with docs and actor info, go-to-definition, snippet-free completion, inlay hints, semantic tokens (with delta encoding), document symbols, code actions (make-linear, pattern exhaustion quickfix), find references, rename, and signature help — all wired through the `linol` OCaml library with per-document caching.

This plan defines the path from that foundation to a world-class LSP in six phases, ordered by implementation ROI. Each feature is documented with the LSP protocol method, required `analysis.ml` changes, AST/parser changes, estimated complexity, and dependencies.

---

## Architecture Recap

Before each feature section, it helps to know exactly what infrastructure exists:

### `lsp/lib/analysis.ml` — `Analysis.t`

```
type t = {
  src         : string;               (* raw source text *)
  filename    : string;               (* file path *)
  type_map    : (span, Tc.ty) Hashtbl.t;    (* span → inferred type *)
  def_map     : (string, span) Hashtbl.t;   (* name → definition span *)
  use_map     : (span, string) Hashtbl.t;   (* use-site span → name *)
  vars        : (string * Tc.scheme) list;  (* in-scope term variables *)
  types       : (string * int) list;        (* type ctors → arity *)
  ctors       : (string * string) list;     (* data ctors → parent type *)
  interfaces  : (string * interface_def) list;
  impls       : (string * Tc.ty) list;
  actors      : (string * actor_def) list;
  doc_map     : (string, string) Hashtbl.t; (* fn name → doc string *)
  refs_map    : (string, span list) Hashtbl.t; (* name → all use-site spans *)
  call_sites  : call_site list;         (* for signature help *)
  consumption : consumption list;       (* for make-linear code action *)
  match_sites : match_site list;        (* for exhaustion quickfix *)
  diagnostics : Lsp.Types.Diagnostic.t list;
}
```

### `lsp/lib/server.ml` — Dispatch

The `march_server` class inherits from `Linol_lwt.Jsonrpc2.server`. Most capabilities are declared via `config_*` methods. A handful of features (semantic tokens, find references, rename, signature help) are dispatched through `on_unknown_request` because `linol` does not yet expose typed handlers for them. New features will follow whichever pattern fits.

### Known Linol Gaps

`linol` currently lacks typed handlers for:
- `textDocument/foldingRange`
- `textDocument/callHierarchy/incomingCalls` and `outgoingCalls`
- `textDocument/selectionRange`
- `textDocument/linkedEditingRange`

These will be wired through `on_unknown_request` with manual JSON construction, following the same pattern as the existing semantic tokens handler.

---

## Phase 1: High-Impact Quick Wins

*These features share no complex dependencies and can be implemented in parallel.*

---

### Feature 1 — Snippet Completions

**Priority:** Critical
**Complexity:** S
**Depends on:** nothing

#### What

When completing a function whose type is known, populate `insertText` with a snippet template that places the cursor at each parameter in turn. For example:

```
List.fold_left  →  List.fold_left(${1:init}, ${2:list}, ${3:fn (acc, x) -> $4})
```

Constructors with arguments also get snippets:
```
Some  →  Some(${1:value})
```

Zero-argument functions and keywords remain plain text completions.

#### LSP Protocol

`CompletionItem.insertTextFormat = InsertTextFormat.Snippet` (value `2`).
`CompletionItem.insertText` carries the snippet string with `${N:placeholder}` tabstops.

#### Analysis Changes

`completions_at` in `analysis.ml` needs to:
1. Detect whether a completion candidate is a function by checking its type in `vars`.
2. Walk the `TArrow` chain (via `unwrap_arrows`, already present) to collect param types.
3. Build the `insertText` snippet string.

For data constructors, the parent type lookup already gives the arity via `types`; generate `CtorName(${1:arg1}, ...)` accordingly.

**New helper:**
```ocaml
let snippet_for_fn name (ty : Tc.ty) : string option =
  let (params, _ret) = unwrap_arrows ty in
  match params with
  | [] -> None
  | _  ->
    let placeholders = List.mapi (fun i p ->
        Printf.sprintf "${%d:%s}" (i + 1) p
      ) params in
    Some (Printf.sprintf "%s(%s)" name (String.concat ", " placeholders))
```

#### Server Changes

In `completions_at`, set `~insertTextFormat:Lsp.Types.InsertTextFormat.Snippet` and `~insertText:(snippet_for_fn ...)` on applicable items. The `config_completion` capability already registers the completion provider; no additional capability registration needed.

#### AST/Parser Changes

None.

---

### Feature 2 — Folding Ranges

**Priority:** High
**Complexity:** S
**Depends on:** nothing

#### What

Let editors collapse large blocks. Fold regions for:
- `fn ... do ... end` bodies (fold from `do` to `end`)
- `match ... do ... end` (fold whole match)
- Individual match arms (fold arm body when multi-line)
- `mod ... do ... end`
- `actor ... do ... end`
- `type ... = ...` variant lists (fold after `=`)
- Doc strings `doc """..."""`

#### LSP Protocol

Method: `textDocument/foldingRange`
Provider registration: `foldingRangeProvider = Some (`Bool true)` in `config_modify_capabilities`.
Handler: `on_unknown_request` for `"textDocument/foldingRange"`.

Response is a list of:
```json
{ "startLine": N, "endLine": M, "kind": "region" | "comment" | "imports" }
```

#### Analysis Changes

Add to `Analysis.t`:
```ocaml
fold_ranges : (int * int * string) list;
(* (startLine_0idx, endLine_0idx, kind) *)
```

Add `collect_fold_ranges` pass over the raw (pre-desugar) AST decls. Key cases:
- `DFn`: fold from the line of `do` to `end` (line before `fn_name.span.end_line`)
- `DMod`: fold the entire body
- `DMatch`: fold each branch body if multi-line
- `DDescribe`: fold all enclosed tests

The raw AST already carries spans on every node. Convert span start/end lines to 0-indexed for LSP output.

**Implementation note:** Operate on the raw parsed AST (before desugaring), since desugar merges multi-clause functions into match expressions, losing the original `do...end` structure.

#### Server Changes

Register provider capability. In `on_unknown_request`, dispatch `"textDocument/foldingRange"` to:
```ocaml
let ranges = match get_analysis uri with
  | None -> []
  | Some a -> a.fold_ranges
in
`List (List.map (fun (sl, el, kind) ->
    `Assoc [("startLine", `Int sl); ("endLine", `Int el); ("kind", `String kind)]
  ) ranges)
```

#### AST/Parser Changes

None. The raw AST already tracks `do...end` structure via spans.

---

### Feature 3 — Add Type Annotation (Code Action)

**Priority:** High
**Complexity:** S
**Depends on:** nothing

#### What

When the cursor is on a `let` binding or function parameter with no explicit type annotation, offer a code action "Add type annotation" that inserts `: TypeName` from the inferred type in `type_map`.

```march
-- Before:
let x = compute(y)
-- After (action applied):
let x : Int = compute(y)
```

For function parameters:
```march
-- Before:
fn greet(name) do
-- After:
fn greet(name : String) do
```

#### LSP Protocol

Existing `code_action` infrastructure. New `CodeActionKind.RefactorRewrite` action.

#### Analysis Changes

In `code_actions_at`, add a third branch: when cursor falls on a `let` binding pattern (`PatVar`) that has no annotation (`bind_ty = None`), look up the pattern span in `type_map` to get the inferred type. Generate a `TextEdit` inserting `: TypeStr` after the variable name.

**New type in `analysis.ml`:**
```ocaml
(** Annotation insertion site: where to insert, what to insert *)
type annotation_site = {
  ann_insert_pos : Ast.span;  (* insert after this span *)
  ann_text       : string;    (* ": TypeName" *)
}
```

Add `annotation_sites : annotation_site list` to `Analysis.t`, populated during the consumption/block traversal pass.

For function parameters: traverse `DFn` clauses, find `FPNamed` params where `param_ty = None`, look up the param name span in `type_map`, generate annotation site.

#### Server Changes

No new server wiring — just extends `code_actions_at`.

#### AST/Parser Changes

None.

---

### Feature 4 — Remove Unused Binding (Code Action)

**Priority:** Medium
**Complexity:** S
**Depends on:** nothing

#### What

When the typechecker emits an "unused variable" warning for a `let` binding, offer a code action with two alternatives:
1. "Remove unused binding `x`" — delete the entire `let x = expr` statement.
2. "Rename to `_x`" — prefix with underscore to silence the warning.

#### LSP Protocol

`CodeActionKind.QuickFix`. Triggered when `params.context.diagnostics` contains an unused-variable diagnostic. The `CodeActionParams` struct includes the active diagnostics in the selection range, so the code action handler knows exactly which warning to fix.

**Note:** The current `code_actions_at` ignores `params.context.diagnostics`. To implement this properly, pass diagnostics context into the handler.

#### Analysis Changes

1. Give March diagnostics machine-readable codes (or at minimum, stable message prefixes). Currently all diagnostics are free-form strings. Add a `diag_code` string to `Errors.diagnostic`:
   ```ocaml
   type diagnostic = {
     ...
     code : string option;  (* e.g. "unused_binding", "non_exhaustive_match" *)
   }
   ```
2. Tag unused-variable warnings in `typecheck.ml` with `code = Some "unused_binding"`.
3. Propagate the code through `diag_to_lsp` → `Diagnostic.code`.
4. In `code_actions_at`, when a diagnostic with `code = "unused_binding"` overlaps the cursor, generate the two fix actions.

**Removal edit:** Find the `let x = ...` span in the source, extend to include the trailing newline, generate a deletion `TextEdit`.

**Rename edit:** Find the variable name token, insert `_` prefix via `TextEdit`.

#### Server Changes

`on_req_code_action` in `server.ml` needs to pass `params.context.diagnostics` down to `code_actions_for`. Currently it passes only the range. Thread diagnostics through.

#### AST/Parser Changes

None (purely a typecheck + analysis change).

---

## Phase 2: Exhaustive Match & Diagnostics-Driven Quick Fixes

---

### Feature 5 — Enhanced Exhaustive Match Generation

**Priority:** High
**Complexity:** M
**Depends on:** Feature 4 (diagnostic codes infrastructure)

#### What

The current "Add missing case" quickfix adds exactly one missing arm (the single case extracted from the warning message). Enhance this in two ways:

1. **Add all missing arms at once** — When multiple variants are missing, generate a single code action "Add all missing cases" that inserts all of them in one edit. Currently `match_sites` stores only a single `ms_missing_case` string per non-exhaustive match. Extend to store a list.

2. **Fix all incomplete matches in file** — When a new variant is added to a type, all existing `match` expressions on that type become incomplete. Offer a file-scope code action: "Add missing `NewVariant` arm to all matches in file".

#### LSP Protocol

Same `code_action` infrastructure. The bulk-fix action will have `kind = CodeActionKind.RefactorRewrite` to distinguish it from individual quickfixes.

#### Analysis Changes

Modify `match_site`:
```ocaml
type match_site = {
  ms_span          : Ast.span;
  ms_matched_type  : string option;     (* which type is being matched *)
  ms_missing_cases : string list;       (* ALL missing patterns, not just one *)
}
```

The typecheck pass currently emits one warning per missing case. Change the warning emission in `typecheck.ml` to batch all missing cases for a single match expression into one diagnostic with a structured payload, or emit multiple diagnostics that analysis.ml aggregates by span.

For the file-scope action: after aggregating `match_sites`, scan for cases where `ms_matched_type` is the same type. If a type `T` appears missing from multiple match expressions, offer one action to fix all of them. This requires knowing which type each match is dispatching on — available from `type_map` (look up the scrutinee's span).

**New field on `Analysis.t`:**
```ocaml
type_matches : (string * match_site list) list;
(* type name → all match sites on that type *)
```

#### Server Changes

`code_actions_for` receives the diagnostics list from `params.context.diagnostics`. When the selection contains a non-exhaustive match diagnostic, emit three actions:
- "Add missing case: X" (one arm, current behavior)
- "Add all N missing cases" (new)
- "Fix all incomplete `T` matches in file" (file-scope, if multiple sites)

#### AST/Parser Changes

None.

---

### Feature 6 — Diagnostics-Driven Quick Fixes Framework

**Priority:** High
**Complexity:** M
**Depends on:** Feature 4 (diagnostic codes)

#### What

A general framework where every compiler warning/error has a corresponding code action. The mapping:

| Diagnostic code | Quick fix |
|---|---|
| `unused_binding` | Remove binding or rename to `_x` (Feature 4) |
| `non_exhaustive_match` | Add missing arms (Features 5) |
| `unused_import` | Remove `use` declaration |
| `redundant_annotation` | Remove explicit type annotation |
| `missing_doc` | Scaffold `doc "..."` comment (Feature 20) |
| `linear_unused` | Insert `drop(x)` or use in return position |
| `linear_used_twice` | Annotate second use with `clone` |
| `type_mismatch` | Insert explicit coercion if safe, or offer typed hole |

#### LSP Protocol

`textDocument/codeAction` with `context.diagnostics` populated by the client.

#### Analysis Changes

1. **Diagnostic code registry** — A module-level mapping from `string` (diagnostic code) to a fix generator function:
   ```ocaml
   type fix_gen = t -> Lsp.Types.Diagnostic.t -> Lsp.Types.CodeAction.t list

   let fix_registry : (string, fix_gen) Hashtbl.t = Hashtbl.create 16
   ```

2. **Register fixes** — Each subsystem that emits a diagnostic with a code registers a fix generator at startup:
   ```ocaml
   let () = Hashtbl.add fix_registry "unused_binding" fix_unused_binding
   let () = Hashtbl.add fix_registry "non_exhaustive_match" fix_exhaustive_match
   ```

3. **code_actions_at extension** — Iterate `params.context.diagnostics`, look up each diagnostic code in `fix_registry`, call the generator, accumulate actions.

#### Server Changes

Pass full `CodeActionParams` (not just range) down to `code_actions_for`.

#### AST/Parser Changes

None directly. Requires `Errors.diagnostic` to gain a `code` field (Feature 4 prerequisite).

---

### Feature 7 — Dead Code Detection

**Priority:** Medium
**Complexity:** M
**Depends on:** nothing (standalone analysis pass)

#### What

Dim unreachable branches and unused top-level functions. Two sub-features:

**7a. Unreachable branch detection** — In a match expression, if a branch can never be reached given prior arms (e.g. wildcard arm followed by more arms), highlight it with a `DiagnosticSeverity.Hint` diagnostic.

**7b. Unused function detection** — Top-level `fn` definitions that are never called from `main()` or any exported symbol get dimmed using `SemanticTokenModifier` (a new `unused` modifier).

#### LSP Protocol

- Diagnostics for 7a (already supported).
- New semantic token modifier for 7b: add `"unused"` to the token modifiers legend in `config_modify_capabilities`. Tokens with `mod_unused` set are rendered at reduced opacity by editors that honor the modifier.

#### Analysis Changes

**For 7a:** Post-typecheck pass over desugared `EMatch` expressions. Walk arms in order; track which patterns are "covered" by prior arms. Flag any arm whose pattern is a subset of already-covered patterns.

**For 7b:** Build a call graph:
```ocaml
type call_graph = {
  cg_callers : (string, string list) Hashtbl.t;  (* who calls each fn *)
  cg_callees : (string, string list) Hashtbl.t;  (* what each fn calls *)
}
```

Populate by traversing `DFn` bodies and recording `EApp` targets. Mark `main` (and all publicly-exported functions, i.e. `fn_vis = Public`) as roots. Walk transitively reachable set. Mark everything else as unused.

Add `unused_fns : string list` to `Analysis.t`.

In `semantic_tokens_data` in `server.ml`, check `Analysis.unused_fns` and apply `mod_unused` modifier to matching function definition tokens.

#### Server Changes

Update `config_modify_capabilities` to add `"unused"` to `tokenModifiers` legend.

#### AST/Parser Changes

None.

---

## Phase 3: Refactoring

*These features require computing free variables and generating well-formed March source text. Careful implementation needed.*

---

### Feature 8 — Extract Function

**Priority:** Medium
**Complexity:** L
**Depends on:** nothing (but benefits from Feature 3's type annotation logic)

#### What

Select an expression in the editor, invoke "Extract function". The LSP:
1. Computes the set of free variables in the selection (variables used inside but bound outside).
2. Determines the inferred return type from `type_map`.
3. Generates a new function definition above the current function.
4. Replaces the selection with a call to the new function.

Example:
```march
-- Before (selection: `x * x + y * y`):
fn hyp(x : Float, y : Float) : Float do
  sqrt(x * x + y * y)
end

-- After "Extract function" → named `sum_of_squares`:
fn sum_of_squares(x : Float, y : Float) : Float do
  x * x + y * y
end

fn hyp(x : Float, y : Float) : Float do
  sqrt(sum_of_squares(x, y))
end
```

#### LSP Protocol

`CodeActionKind.RefactorExtract`. Triggered when the selection range spans a complete expression node. The client sends a `textDocument/codeAction` with a non-empty range.

#### Analysis Changes

**Free variable computation:**
```ocaml
(** Compute free variables in [expr]: variables used but not locally bound. *)
val free_vars : Ast.expr -> (string * Tc.ty option) list
```

Walk the expression, collecting `EVar` names; subtract names bound by `ELet`, `ELam`, `EMatch` patterns, `ELetFn` within the selection.

**Source generation:**
March source printer (a pretty-printer for `Ast.expr` back to March syntax). This is required for all of Phase 3.

```ocaml
(** Pretty-print a March expression back to source. *)
module Pp : sig
  val expr : Ast.expr -> string
  val ty   : Ast.ty   -> string
end
```

This is the most significant dependency of Phase 3. Implement once, reuse across Features 8–11.

**Selection → AST node matching:** Given a range from the client, find the smallest `expr` in the `type_map` whose span covers the range exactly (or is closest). The `type_map` already stores spans for all sub-expressions.

**New field on `Analysis.t`:**
```ocaml
expr_at_range : Ast.span -> Ast.expr option;
```
Implemented by traversing the expression AST and finding the node with the matching span.

#### Server Changes

When `on_req_code_action` receives a non-empty range, compute candidate "extract" actions. Present "Extract function" only if the range maps to a complete sub-expression (not a partial token).

#### AST/Parser Changes

None. Requires a new **March pretty-printer** (`lsp/lib/pp.ml`) — the most significant new file in Phase 3.

---

### Feature 9 — Extract Variable

**Priority:** Medium
**Complexity:** M
**Depends on:** Feature 8 (pretty-printer, selection → AST node)

#### What

Select an expression, invoke "Extract variable". Generates a `let` binding before the enclosing expression and replaces the selection with the binding name.

```march
-- Before (selection: `a + b * c`):
let result = a + b * c + a + b * c

-- After:
let tmp = a + b * c
let result = tmp + tmp
```

Note: the action replaces only the selected occurrence, not all occurrences (which would be a separate "Extract common subexpression" action).

#### LSP Protocol

`CodeActionKind.RefactorExtract`, title "Extract variable".

#### Analysis Changes

Find the enclosing statement/block position from the selection span. Generate `let <name> = <selection_text>` inserted before the line, and replace the selection range with `<name>`.

The name defaults to a type-based heuristic: `Int` → `n`, `String` → `s`, `List(_)` → `xs`, otherwise `tmp`.

#### Server Changes

Extends `on_req_code_action`.

#### AST/Parser Changes

None (uses pretty-printer from Feature 8).

---

### Feature 10 — Inline Function/Variable

**Priority:** Low
**Complexity:** L
**Depends on:** Feature 8 (pretty-printer), Feature 9 (selection matching)

#### What

Two sub-actions:

**10a. Inline variable** — Cursor on a `let x = expr` binding. Action "Inline `x`": remove the binding, replace all uses of `x` in the scope with the inlined expression text. Only valid when the binding is pure (no side effects — tracked via the purity analysis in `lib/tir/purity.ml` or a simpler local check).

**10b. Inline function** — Cursor on a call `f(arg1, arg2)` where `f` is a small, locally-defined function. Action "Inline `f`": substitute the function body, replacing parameter names with argument expressions. Only valid for single-clause functions with no recursion.

#### LSP Protocol

`CodeActionKind.RefactorInline`.

#### Analysis Changes

**For 10a:** Use `refs_map` to find all use sites. Check that `bind_expr` has no `EApp` to effectful builtins (conservative: only safe if `bind_expr` is a literal, variable, or arithmetic). Generate multi-edit: delete `let` line, replace all use spans with the pretty-printed expression.

**For 10b:** Look up the function body from `def_map` → find the `DFn` in the raw AST. Perform textual substitution (param name → arg expression). Wrap in parens if the body contains operators to avoid precedence issues.

#### Server Changes

Extends `on_req_code_action`.

#### AST/Parser Changes

None.

---

### Feature 11 — Convert Between Equivalent Forms

**Priority:** Low
**Complexity:** M
**Depends on:** Feature 8 (pretty-printer)

#### What

Structural transformations between syntactically distinct but semantically equivalent forms:

| From | To | Action title |
|---|---|---|
| `if c then e1 else e2` | `match c do \| true -> e1 \| false -> e2 end` | "Convert to match" |
| `match c do \| true -> e1 \| false -> e2 end` | `if c then e1 else e2` | "Convert to if/else" |
| `fn name(x) -> body` (local lambda) | `let name = fn x -> body` | "Convert to lambda" |
| `Cons(x, Cons(y, Nil))` | `[x, y]` | "Convert to list literal" |
| `[x, y]` (desugared) | `Cons(x, Cons(y, Nil))` | "Convert to Cons cells" |

#### LSP Protocol

`CodeActionKind.RefactorRewrite`.

#### Analysis Changes

Pattern-match on the smallest enclosing AST node for each transformation. Each conversion:
1. Detects the source form.
2. Constructs the equivalent target form as an `Ast.expr`.
3. Pretty-prints it using the `Pp` module.
4. Returns a `TextEdit` replacing the source range.

#### Server Changes

Extends `on_req_code_action`. These actions appear only when the cursor is inside a matching construct.

#### AST/Parser Changes

None.

---

## Phase 4: Alias Language Feature + LSP Support

---

### Feature 12 — Alias Language Feature (Compiler)

**Priority:** High
**Complexity:** M
**Depends on:** nothing

#### What

Elixir-style module aliases. The `DAlias` AST node and `alias_decl` type already exist:

```ocaml
type alias_decl = {
  alias_path : name list;   (* e.g. [Collections; HashMap] *)
  alias_name : name;        (* short name, defaults to last segment *)
}
```

Implement the full pipeline:

**Surface syntax** (parser already supports `DAlias`):
```march
alias Collections.HashMap          -- short name = "HashMap"
alias Collections.HashMap, as: Map -- short name = "Map"
```

**Desugar pass** — `March_desugar.Desugar.desugar_module`: rewrite all qualified references `Collections.HashMap.empty` → `Map.empty` (or `HashMap.empty`) in expressions and types within the same module scope. The alias is lexically scoped to the enclosing `mod ... do ... end` block.

**Typecheck pass** — Validate that the alias path refers to an existing module in the type environment. Emit an error if the module is not found.

**Runtime** — No effect (desugar handles it entirely).

#### Implementation Steps

1. **Desugar:** In `collect_decl` (or a new pre-pass), accumulate `DAlias` declarations into a `(string * string list) list` (short name → full path). Then walk expressions replacing `EVar` and `ECon` names that begin with a known alias prefix.

2. **Typecheck:** In `check_module`, when processing `DAlias`, verify `alias_path` resolves to a module in `env.modules`. Emit `Error` diagnostic if not.

3. **Test:** Add `test_alias_basic`, `test_alias_with_as`, `test_alias_unknown_path` to `test/test_march.ml`.

#### LSP Support

The LSP `def_map` / `use_map` traversal in `analysis.ml` ignores `DAlias` today (line 248: `| Ast.DAlias _ -> ()`). Once aliases are wired in the desugar pass, update `collect_decl` to:
- Register the alias short name in `def_map` pointing to the module's definition span.
- Record the alias `use_map` entry so go-to-definition follows the alias to the original module.

#### AST/Parser Changes

No new AST nodes. Parser already emits `DAlias`. Desugar and typecheck changes only.

---

### Feature 13 — Auto-Alias Code Action

**Priority:** Medium
**Complexity:** S
**Depends on:** Feature 12 (alias semantics must be implemented first)

#### What

Two triggers:

**13a. Repeated module prefix** — When a module name appears ≥ 3 times as a qualifier in the same file (e.g. `Collections.HashMap.empty`, `Collections.HashMap.insert`, `Collections.HashMap.get`), offer a code action "Add `alias Collections.HashMap`" that inserts the alias declaration at the top of the current module and rewrites all qualified references to use the short name.

**13b. Unknown module** — When the typechecker emits "unbound module `Foo`" and `Foo` is a known module in the stdlib or project index, offer "Add `alias Full.Path.Foo`".

#### LSP Protocol

`CodeActionKind.QuickFix` for 13b. `CodeActionKind.RefactorRewrite` for 13a.

#### Analysis Changes

**For 13a:** Add pass over `use_map` to count qualified name prefixes. A "qualified name" is an `EVar` or `ECon` whose text contains `.`. Extract the module prefix component, count occurrences per prefix, surface the top-N candidates.

**New field on `Analysis.t`:**
```ocaml
repeated_prefixes : (string * int) list;
(* module prefix → occurrence count, sorted descending *)
```

**For 13b:** Integrate with the diagnostics framework (Feature 6). When a diagnostic with code `"unbound_module"` is present, look up the module name in a stdlib module index (see Feature 14) and offer alias actions.

#### Server Changes

Extends `on_req_code_action`.

#### AST/Parser Changes

None.

---

## Phase 5: Project-Level Intelligence

*These features require reading multiple files and understanding the forge project structure. They represent the largest architectural leap in this plan.*

---

### Feature 14 — Workspace Symbol Search

**Priority:** High
**Complexity:** M
**Depends on:** forge project structure

#### What

Fuzzy-search any symbol (function, type, constructor, interface) across the entire project, not just the open file. Triggered by `Ctrl+T` / `Cmd+T` in most editors.

#### LSP Protocol

Method: `workspace/symbol`
Response: list of `SymbolInformation` with `name`, `kind`, `location`.

Registration: `workspaceSymbolProvider = Some (`Bool true)` in `config_modify_capabilities`.

#### Analysis Changes

**Project index** — A new module `lsp/lib/project_index.ml`:

```ocaml
type symbol_entry = {
  se_name     : string;
  se_kind     : Lsp.Types.SymbolKind.t;
  se_location : Lsp.Types.Location.t;
  se_detail   : string;  (* type signature *)
}

type t = {
  pi_symbols : symbol_entry list;
  pi_files   : string list;
}

val build : project_root:string -> t
val search : t -> query:string -> symbol_entry list
```

`build` walks the forge project:
1. Find `forge.toml` (walk up from LSP working directory).
2. Parse `forge.toml` to discover source files and dependencies.
3. For each `.march` file, run `analyse` and extract all `def_map` entries.
4. Cache the index on disk at `.march/search-index.json` (invalidated by mtime).

`search` does fuzzy matching: prefix match first, then substring, then trigram similarity. Returns top 20 results.

**Index persistence** — The index is rebuilt lazily on first `workspace/symbol` request and invalidated when any `.march` file changes (tracked via `on_notif_doc_did_change`).

#### Server Changes

New field `project_index : Project_index.t option ref` on the server state. Rebuild on file change events. Handle `workspace/symbol` via `on_unknown_request`.

#### AST/Parser Changes

None.

---

### Feature 15 — Cross-File Go-To-Definition

**Priority:** High
**Complexity:** M
**Depends on:** Feature 14 (project index)

#### What

When go-to-definition is triggered on a name that has no definition in the current file's `def_map`, fall back to the project index. Follow `use Module.{name}` and `use Module.*` declarations to find the defining file.

#### LSP Protocol

Extends existing `textDocument/definition` handler. No new capability needed.

#### Analysis Changes

`definition_at` currently returns `None` for names defined in other files (their `def_span.file` points to a stdlib path, which already works for stdlib, but not for user project files that weren't loaded).

With the project index, after failing local lookup:
1. Look up `name` in `Project_index.pi_symbols`.
2. If found, construct a `Location` pointing to the definition file.

Also, track `use` declarations in `analysis.ml`. Currently `DUse` is ignored (line 248). Add:
```ocaml
use_decls : use_decl list;
(* all 'use' declarations in the file — for cross-file resolution *)
```

Resolve qualified names (`Module.func`) by consulting the project index for the module path.

#### Server Changes

`on_req_definition` extended to fall back to project index.

#### AST/Parser Changes

None.

---

### Feature 16 — Cross-File Find References

**Priority:** Medium
**Complexity:** M
**Depends on:** Feature 14 (project index), Feature 15 (cross-file definition lookup)

#### What

Find all usages of a symbol across the entire project, not just the current file.

#### LSP Protocol

Extends `textDocument/references` handler. No new capability needed.

#### Analysis Changes

The project index needs a reverse index: `symbol_name → all locations in project`.

```ocaml
(* In Project_index.t: *)
pi_references : (string, Lsp.Types.Location.t list) Hashtbl.t;
```

Built by scanning all files' `use_map` entries during index construction.

`references_at` in `analysis.ml` extended to merge:
1. Local `refs_map` results (current behavior).
2. Project index `pi_references` results (cross-file).

#### Server Changes

`on_unknown_request` for `"textDocument/references"` passes results from both sources.

#### AST/Parser Changes

None.

---

### Feature 17 — Project-Level Diagnostics

**Priority:** Medium
**Complexity:** L
**Depends on:** Feature 14 (project index)

#### What

Run a whole-project typecheck and report cross-file type errors. Example: `mod A` exports `fn foo : Int → String` and `mod B` calls `foo` with a `Float` argument. The current per-file analysis typechecks each file independently and doesn't catch cross-module type mismatches (unless the stdlib is loaded).

#### LSP Protocol

`workspace/diagnostic` (LSP 3.17+) or push-based `textDocument/publishDiagnostics` for all open files.

#### Analysis Changes

**Whole-project analysis pass** (expensive, runs in background):
1. Parse + typecheck all `.march` files in dependency order.
2. Share the type environment across files (module type signatures).
3. Report cross-file errors to affected files via `publishDiagnostics`.

This requires:
- A multi-file typechecker entry point in `lib/typecheck/typecheck.ml` (or a new `lib/typecheck/project.ml`).
- The module system type environment to be serializable (for caching).

**Incremental strategy:** On file save, re-typecheck the saved file and all direct dependents (files that `use` the saved module). Use the CAS system (`lib/cas/`) for content-addressed caching of module type signatures.

#### Server Changes

New `on_notif_workspace_did_change_configuration` handler triggers project-level typecheck. Background Lwt thread; results pushed via `notify_back#send_diagnostic`.

#### AST/Parser Changes

None. Requires typecheck infrastructure changes.

---

## Phase 6: Advanced Features

---

### Feature 18 — Call Hierarchy

**Priority:** Medium
**Complexity:** M
**Depends on:** Feature 7b (call graph already needed for dead code detection)

#### What

Incoming calls: who calls this function. Outgoing calls: what does this function call. Displayed as a tree in editors supporting `callHierarchy` (VS Code, Helix 24+).

#### LSP Protocol

Three methods, all via `on_unknown_request`:
- `textDocument/prepareCallHierarchy` — returns `CallHierarchyItem` for the symbol at cursor.
- `callHierarchy/incomingCalls` — returns callers.
- `callHierarchy/outgoingCalls` — returns callees.

#### Analysis Changes

Reuse the call graph from Feature 7b. Add to `Analysis.t`:
```ocaml
call_graph : call_graph;
```

For incoming calls: `cg_callers[name]` — list of call sites with span info.
For outgoing calls: `cg_callees[name]` — list of callees with call-site spans.

The `call_sites` list already collects `{ cs_fn_name; cs_span; cs_args }`. Extend it to track the *containing function* name (the enclosing `DFn`), enabling the callers index.

**Extended call_site:**
```ocaml
type call_site = {
  cs_fn_name       : string option;  (* callee *)
  cs_caller        : string option;  (* enclosing function name *)
  cs_span          : Ast.span;
  cs_args          : Ast.expr list;
}
```

#### Server Changes

Three new dispatch branches in `on_unknown_request`.

#### AST/Parser Changes

None.

---

### Feature 19 — Semantic Selection (Expand/Shrink)

**Priority:** Medium
**Complexity:** S
**Depends on:** nothing (just needs the span tree)

#### What

Press `Alt+Shift+→` (or editor binding) to expand selection to the next larger AST node. Press `Alt+Shift+←` to shrink back. Sequence: token → expression → let binding → function body → function → module.

This is one of the most-loved features in rust-analyzer and transforms how developers select code for refactoring.

#### LSP Protocol

Method: `textDocument/selectionRange`
Response: a linked list of `SelectionRange` objects (each with a `parent` pointing to the next larger selection).

Registration: `selectionRangeProvider = Some (`Bool true)` in `config_modify_capabilities`.

#### Analysis Changes

The `type_map` already stores `(span, ty)` for all sub-expressions. Build a span tree:

```ocaml
(** Sorted list of all spans in the document, from smallest to largest *)
val span_ancestors : t -> line:int -> character:int -> Ast.span list
```

Walk `type_map`, collect all spans containing the cursor, sort by `span_size` ascending. Each span becomes one level in the `SelectionRange` chain.

This is purely derived from existing data — no new analysis pass needed.

#### Server Changes

New branch in `on_unknown_request` for `"textDocument/selectionRange"`. Construct the JSON chain from `span_ancestors`.

#### AST/Parser Changes

None.

---

### Feature 20 — Generate Doc Comment

**Priority:** Low
**Complexity:** S
**Depends on:** nothing

#### What

Code action on a function with no `fn_doc`: "Generate doc comment". Inserts a scaffolded doc string:

```march
-- Before:
fn process(input : String, limit : Int) : List(String) do
  ...
end

-- After:
doc "TODO: describe process.

Arguments:
- input: String
- limit: Int

Returns: List(String)"
fn process(input : String, limit : Int) : List(String) do
  ...
end
```

#### LSP Protocol

`CodeActionKind.RefactorRewrite`. Triggered when cursor is on a `DFn` with `fn_doc = None`.

#### Analysis Changes

Add `undocumented_fns : (string * Ast.fn_def * Ast.span) list` to `Analysis.t`. Populated by scanning `user_decls` for `DFn` where `fn.fn_doc = None`.

**Scaffold generation:**
```ocaml
let scaffold_doc (fn : Ast.fn_def) : string =
  let params = (* collect FPNamed params from first clause *) in
  let ret_ty = (* fn.fn_ret_ty *) in
  ...
```

#### Server Changes

Extends `on_req_code_action`.

#### AST/Parser Changes

None.

---

### Feature 21 — Linked Editing

**Priority:** Low
**Complexity:** S
**Depends on:** Feature 19 (AST node awareness) or nothing (can use refs_map directly)

#### What

When you rename a variable by typing in the editor (not via rename refactor), all other occurrences update simultaneously as you type. This is linked editing — live multi-cursor rename.

#### LSP Protocol

Method: `textDocument/linkedEditingRange`
Response: `LinkedEditingRanges` with `ranges` (all ranges to edit simultaneously) and optional `wordPattern`.

Registration: `linkedEditingRangeProvider = Some (`Bool true)` in `config_modify_capabilities`.

#### Analysis Changes

`references_at` already computes all occurrence spans for a name. Reuse directly.

```ocaml
val linked_editing_ranges : t -> line:int -> character:int
    -> Lsp.Types.Range.t list
```

This is just `references_at ~include_declaration:true` mapped to `Range.t`. One-liner.

#### Server Changes

New branch in `on_unknown_request` for `"textDocument/linkedEditingRange"`.

#### AST/Parser Changes

None.

---

### Feature 22 — Import Suggestions

**Priority:** Medium
**Complexity:** M
**Depends on:** Feature 14 (project index for project-level symbols), nothing for stdlib

#### What

When a function call `foo(...)` references an unknown name `foo`, and `foo` exists in an importable module, offer a code action "Add `use Module.{foo}`".

Similarly: when `Module.foo(...)` uses a module that isn't in scope, offer "Add `use Module`".

#### LSP Protocol

`CodeActionKind.QuickFix`. Triggered on diagnostics with code `"unbound_variable"` or `"unbound_module"`.

#### Analysis Changes

**Stdlib import index** — Pre-built at LSP startup from `load_stdlib()`:
```ocaml
(** name → list of modules that export it *)
val stdlib_exports : (string, string list) Hashtbl.t
```

Built by scanning stdlib `def_map` entries and recording which module each name comes from.

**Import suggestion generator:**
```ocaml
val suggest_imports : t -> name:string -> string list
(* returns list of "use Module.{name}" strings *)
```

Consults `stdlib_exports` first, then project index (Feature 14) for user modules.

**Edit generation:** Find the last `use` declaration in the file (or top of module body), insert new `use` after it.

#### Server Changes

Extends `on_req_code_action` via the diagnostics-driven framework (Feature 6). Diagnostic `"unbound_variable"` triggers `suggest_imports` lookup.

#### AST/Parser Changes

None.

---

## Implementation Notes: Shared Infrastructure

Several features share infrastructure that should be built once and reused:

### March Pretty-Printer (for Phase 3)

`lsp/lib/pp.ml` — prints `Ast.expr`, `Ast.ty`, and `Ast.pattern` back to valid March source. Required for Features 8, 9, 10, 11.

**Approach:** Structural recursion on `Ast.expr` with a configurable indent width. Preserve operator precedence by wrapping sub-expressions in parens at ambiguous sites. Output should roundtrip through the parser (property-testable).

### Diagnostic Codes (for Phase 2)

Add `code : string option` to `March_errors.Errors.diagnostic`. Update all `Errors.error` / `Errors.warning` call sites in `typecheck.ml`, `parser.ml`, and `eval.ml` to pass codes for machine-actionable diagnostics. Propagate through `diag_to_lsp`.

### Forge Project Discovery (for Phase 5)

`lsp/lib/project.ml` — discovers `forge.toml` by walking up from the file being edited. Parses source file globs and dependency declarations. Minimal; reuse logic from `forge/lib/project.ml` if possible (check if it's a library target, not just a binary).

---

## Priority Matrix

| # | Feature | Phase | Priority | Complexity | LOC est. |
|---|---------|-------|----------|-----------|---------|
| 1 | Snippet completions | 1 | Critical | S | ~50 |
| 2 | Folding ranges | 1 | High | S | ~120 |
| 3 | Add type annotation | 1 | High | S | ~80 |
| 4 | Remove unused binding | 1 | Medium | S | ~100 |
| 12 | Alias language feature | 4 | High | M | ~200 |
| 5 | Enhanced match generation | 2 | High | M | ~150 |
| 6 | Diagnostics-driven quickfixes | 2 | High | M | ~200 |
| 7 | Dead code detection | 2 | Medium | M | ~250 |
| 19 | Semantic selection | 6 | Medium | S | ~60 |
| 21 | Linked editing | 6 | Low | S | ~30 |
| 20 | Generate doc comment | 6 | Low | S | ~70 |
| 8 | Extract function | 3 | Medium | L | ~300 |
| 9 | Extract variable | 3 | Medium | M | ~100 |
| 13 | Auto-alias action | 4 | Medium | S | ~100 |
| 18 | Call hierarchy | 6 | Medium | M | ~150 |
| 22 | Import suggestions | 6 | Medium | M | ~200 |
| 10 | Inline function/variable | 3 | Low | L | ~250 |
| 11 | Convert between forms | 3 | Low | M | ~200 |
| 14 | Workspace symbol search | 5 | High | M | ~300 |
| 15 | Cross-file go-to-definition | 5 | High | M | ~150 |
| 16 | Cross-file find references | 5 | Medium | M | ~100 |
| 17 | Project-level diagnostics | 5 | Medium | L | ~400 |

**Recommended order for a single implementation session:**
1 → 2 → 12 → 3 → 4 → 5 → 6 → 19 → 21 → 8 (pp.ml first) → 9 → 14 → 15

---

## Feature Status Tracking

| # | Feature | Status |
|---|---------|--------|
| 1 | Snippet completions | ⬜ Not started |
| 2 | Folding ranges | ⬜ Not started |
| 3 | Add type annotation | ⬜ Not started |
| 4 | Remove unused binding | ⬜ Not started |
| 5 | Enhanced match generation | ⬜ Not started |
| 6 | Diagnostics-driven quickfixes | ⬜ Not started |
| 7 | Dead code detection | ⬜ Not started |
| 8 | Extract function | ⬜ Not started |
| 9 | Extract variable | ⬜ Not started |
| 10 | Inline function/variable | ⬜ Not started |
| 11 | Convert between forms | ⬜ Not started |
| 12 | Alias language feature | ⬜ Not started |
| 13 | Auto-alias code action | ⬜ Not started |
| 14 | Workspace symbol search | ⬜ Not started |
| 15 | Cross-file go-to-definition | ⬜ Not started |
| 16 | Cross-file find references | ⬜ Not started |
| 17 | Project-level diagnostics | ⬜ Not started |
| 18 | Call hierarchy | ⬜ Not started |
| 19 | Semantic selection | ⬜ Not started |
| 20 | Generate doc comment | ⬜ Not started |
| 21 | Linked editing | ⬜ Not started |
| 22 | Import suggestions | ⬜ Not started |

---

## Appendix: LSP Capability Registration Reference

All capability registrations land in `config_modify_capabilities` in `server.ml` unless noted:

```ocaml
method config_modify_capabilities caps =
  { caps with
    (* existing *)
    ServerCapabilities.semanticTokensProvider = ...;
    ServerCapabilities.referencesProvider = Some (`Bool true);
    ServerCapabilities.renameProvider = Some (`Bool true);
    ServerCapabilities.signatureHelpProvider = Some sig_help;
    (* Phase 1 additions *)
    ServerCapabilities.foldingRangeProvider = Some (`Bool true);           (* Feature 2 *)
    (* Phase 6 additions *)
    ServerCapabilities.selectionRangeProvider = Some (`Bool true);         (* Feature 19 *)
    ServerCapabilities.linkedEditingRangeProvider = Some (`Bool true);     (* Feature 21 *)
    ServerCapabilities.callHierarchyProvider = Some (`Bool true);          (* Feature 18 *)
    (* Phase 5 additions *)
    ServerCapabilities.workspaceSymbolProvider = Some (`Bool true);        (* Feature 14 *)
  }
```

`config_code_action_provider` already covers all code action features.

Folding ranges, selection ranges, linked editing, and call hierarchy are dispatched via `on_unknown_request` following the same pattern as semantic tokens.
