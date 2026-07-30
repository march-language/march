# March Docstrings Design

**Date:** 2026-03-18
**Status:** Approved

## Overview

Elixir-style docstrings for modules, functions, types, and all other declarations in March. Docs are first-class: stored in the AST, registered at runtime, queryable in the REPL, and available for static doc generation.

## Surface Syntax

`doc` is a new keyword. It appears as a declaration immediately before the item it documents. It accepts any string literal — single-line or triple-quoted (`"""`).

```march
doc """
A module for integer arithmetic.

All functions are pure and total.
"""
mod Math do
  doc "Adds two integers."
  pub fn add(a : Int, b : Int) : Int do
    a + b
  end

  doc """
  Divides `a` by `b`.

  Returns :error if `b` is zero.
  """
  pub fn div(a : Int, b : Int) : Result(Int, Atom) do
    match b with
    | 0 -> Err(:error)
    | _ -> Ok(a / b)
    end
  end
end
```

**Rules:**
- `doc` must be immediately followed by a declaration; anything else is a parse error.
- `doc doc fn ...` (double doc) is a parse error — caught by the grammar, not a validation pass.
- All declaration kinds are supported: `fn`, `mod`, `type`, `actor`, `interface`, `impl`, `protocol`, `extern`, `let`.

## Triple-Quoted Strings

`"""..."""` is a new lexer rule. The lexer scans until it sees a closing `"""`. Content is taken **verbatim**: newlines are preserved, no automatic indentation stripping, and **no escape sequence processing** (a `\n` in triple-quoted content is a literal backslash-n, not a newline). This matches Elixir heredoc semantics and makes triple-quoted strings predictable for documentation text.

Triple-quoted strings are valid anywhere a string literal is valid, not only in `doc`.

## AST

One new variant added to `decl` in `lib/ast/ast.ml`:

```ocaml
| DDoc of string * decl * span   (* doc "..." decl *)
```

The `string` is the doc content. The inner `decl` is the documented declaration. `span` covers the full `doc ... decl` range.

No changes to existing record types (`fn_def`, `module_`, etc.).

## Lexer (`lib/lexer/lexer.mll`)

1. Add `"doc"` → `DOC` to `keyword_table`.
2. Add `TRIPLESTRING` token (or reuse `STRING` — implementation choice; reusing `STRING` is simpler).
3. Add `read_triple_string` rule: entered on `"""`, exits on `"""`, tracks newlines with `Lexing.new_line`. No escape processing.

**Critical ordering:** The `"""` pattern in the `token` rule must appear **before** the `'"'` rule. The reason: `'"'` immediately calls `read_string`, which would consume the first `"` of `"""` and begin scanning a regular string. ocamllex's longest-match applies within a single rule alternative but cannot help here because `'"'` calls a sub-rule (`read_string`) that takes over the lexbuf. Placing `"""` first ensures it is matched as a distinct token before `'"'` fires.

## Parser (`lib/parser/parser.mly`)

Add `DOC` token declaration. Split `decl` into two rules:

```
inner_decl:
  | d = fn_decl        { d }
  | d = let_decl       { d }
  | ... (all existing decl alternatives)

decl:
  | d = inner_decl { d }
  | DOC; s = doc_string; d = inner_decl { DDoc (s, d, mk_span $loc) }

doc_string:
  | s = STRING      { s }
  | s = TRIPLESTRING { s }
```

**`group_fn_clauses`** is called in two places in the parser (`module_` production and `mod_decl`). Both share the same function body, so updating `group_fn_clauses` once covers both.

**Rule: `doc` is only valid on the first clause of a multi-head function.** Subsequent clauses must not have a `doc` annotation — this is enforced by the grammar because `inner_decl` (not `decl`) is used after the first clause in the grouping pass. When grouping, the pass unwraps `DDoc(s, DFn(...))` to get the name, collects following bare `DFn` clauses with the same name, merges all clauses into one `DFn`, then re-wraps the merged node in `DDoc(s, merged_DFn, span)`.

## Typecheck (`lib/typecheck/typecheck.ml`)

All declaration-walking code must add a `DDoc` arm — the OCaml compiler will warn on non-exhaustive matches:

```ocaml
| DDoc (_, inner, _) -> check_decl ctx inner
```

The doc string is not type-checked — it is an opaque string value.

## Desugar (`lib/desugar/desugar.ml`)

`desugar_decl` must add a `DDoc` arm — the OCaml compiler will error on a non-exhaustive match otherwise:

```ocaml
| DDoc (s, inner, sp) -> DDoc (s, desugar_decl ctx inner, sp)
```

The doc string itself is not desugared.

## Evaluator (`lib/eval/eval.ml`)

A module-level doc registry:

```ocaml
let doc_registry : (string, string) Hashtbl.t = Hashtbl.create 64
```

The eval module has a two-pass structure for top-level declarations (`install_stub` pass + `make_recursive_env` pass) and a separate `eval_decl` function used for nested module contents. **All three must handle `DDoc`:**

- **`install_stub` (pass 1):** Add `| DDoc (_, inner, _) -> install_stub inner` so documented functions still get stubs installed for mutual recursion.
- **`make_recursive_env` (pass 2):** Add an explicit `DDoc` arm **before** the catch-all `_ :: rest`. The catch-all does not recurse into the wrapper — without an explicit arm, `DDoc`-wrapped declarations are silently dropped:
  ```ocaml
  | DDoc (s, inner, _) :: rest ->
      register_doc s inner;
      make_recursive_env (inner :: rest) env
  ```
- **`eval_decl`:** Used for nested module contents — also needs `| DDoc (s, inner, sp) ->` that registers the doc then calls `eval_decl inner`.

**Name extraction and registry key:** `register_doc s decl` extracts the key as follows. Only named declarations register; others are silently skipped (doc is still displayed if the user knows the key, they just can't look it up by name):

| Inner decl | Key |
|---|---|
| `DFn ({ fn_name; _ }, _)` | `module_prefix ^ fn_name.txt` |
| `DMod (name, _, _, _)` | `module_prefix ^ name.txt` |
| `DType (name, _, _, _)` | `module_prefix ^ name.txt` |
| `DActor (name, _, _)` | `module_prefix ^ name.txt` |
| `DInterface ({ iface_name; _ }, _)` | `module_prefix ^ iface_name.txt` |
| `DProtocol (name, _, _)` | `module_prefix ^ name.txt` |
| `DLet ({ bind_pat = PatVar n; _ }, _)` | `module_prefix ^ n.txt` |

`DLet` with a non-`PatVar` pattern, `DImpl`, `DExtern`, `DSig`, `DUse` do not register (no single stable name).

**Module prefix — new infrastructure:** The evaluator does not currently track a module path. This must be added as a `string list ref` module stack (a global mutable ref is acceptable given the single-threaded tree-walking eval):

```ocaml
let module_stack : string list ref = ref []

let module_prefix () =
  match !module_stack with
  | [] -> ""
  | parts -> String.concat "." (List.rev parts) ^ "."
```

`eval_decl` for `DMod (name, _, decls, _)` must push `name.txt` onto `module_stack` before evaluating nested decls and pop it after. All existing `eval_decl` and `make_recursive_env` call **signatures are unchanged** — the stack is accessed via the global ref, not threaded as a parameter.

## REPL

`h` is handled as a special case in the REPL evaluator, not a dedicated grammar production. Both `h(add)` and `h(Math.add)` parse as ordinary `EApp` expressions:

- `h(add)` → `EApp(EVar { txt="h"; span=_ }, [EVar { txt="add"; span=_ }], _)`
- `h(Math.add)` → `EApp(EVar { txt="h"; span=_ }, [EField(ECon({ txt="Math"; span=_ }, [], _), { txt="add"; span=_ }, _)], _)`

The REPL eval loop intercepts `EApp(EVar { txt = "h"; _ }, [arg], _)` before the normal eval path and extracts a dotted key from `arg` by walking the AST:

```ocaml
let rec extract_doc_key = function
  | EVar { txt; _ } -> Some txt
  | ECon ({ txt; _ }, [], _) -> Some txt
  | EField (e, { txt = field; _ }, _) ->
      Option.map (fun prefix -> prefix ^ "." ^ field) (extract_doc_key e)
  | _ -> None
```

Resolution order:
1. Try `module_prefix () ^ key`.
2. Try bare `key`.
3. Print `"No documentation for <key>"` if not found.

`h` with any other argument shape (non-identifier, multiple args) prints a helpful error message rather than crashing.

## What's Not Changing

- No changes to existing record types.
- `show_decl` (from `[@@deriving show]`) will automatically handle `DDoc` once the variant is added — `string`, `decl`, and `span` all have `show` instances already.

## Static Doc Generation (deferred)

A future `march doc` subcommand will walk the AST collecting `DDoc` nodes and emit Markdown or HTML. The AST infrastructure built here is sufficient — the doc generation pass is out of scope for this implementation.

## Test Cases

The test suite (`test/test_march.ml`) should cover:

1. `doc` on a `fn` — parses, typechecks, doc registered in evaluator.
2. `doc` on a `mod` — module doc registered.
3. `doc` on `type`, `actor`, `interface` — all parse and register.
4. Triple-quoted string — multiline content preserved verbatim, no escape processing.
5. `h(add)` in REPL — returns the registered doc string for a bare name.
6. `h(Math.add)` in REPL — returns the registered doc string for a qualified name (EField path walked to dotted key).
7. `doc` on `DLet` with `PatVar` — registered correctly.
8. `doc doc fn ...` — parse error.
9. `doc "orphan"` at end of file — parse error.
10. Multi-head `fn` with `doc` on first clause — clauses merged, doc preserved on the merged `DFn`.
