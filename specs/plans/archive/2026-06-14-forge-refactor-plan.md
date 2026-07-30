# `forge refactor` — Project-wide refactoring CLI

**Status:** v1 complete (2026-06-14) — all four commands wired and tested

## Goal

Scriptable, whole-project refactorings the editor's cursor model can't do well.
Four subcommands sharing one parser-based engine (`lib/refactor/`), wired to
cmdliner in `forge/lib/cmd_refactor.ml` and registered in `forge/bin/main.ml`.

- `forge refactor rename Old New [--kind K] [--pattern] [--dry-run]`
- `forge refactor move Decl dest.march [--dry-run]`
- `forge refactor replace '<pat>' '<tmpl>' [--dry-run]`
- `forge refactor fix [--dry-run]`
- `forge refactor bundle <Fn> [--record NAME] [--dry-run]` — introduce a parameter object: bundle the function's parameters into a generated record, rewriting the signature, body, and every call site project-wide. v1: single-clause, annotated params; recursive calls rewritten as call sites may need touch-up. Note: arg source is recovered by splitting the call's paren contents on top-level commas, since string-literal spans in the parser only cover the opening quote.

## Engine (`lib/refactor/refactor.ml`, library `march_refactor`)

1. **Discover** every `.march` file under the project root (recursive walk).
2. **Parse** each (March_parser, raw AST — preserves surface names/spans),
   keeping the source text for span→byte-offset edits.
3. **Edit model:** `edit = { start; stop; repl }` (byte offsets); apply per file
   by splicing in descending offset order.
4. **Verify:** re-parse each edited file; never write source that no longer parses.

Core is a `name` visitor: `iter_names : (kind -> Ast.name -> unit) -> module_ -> unit`
visiting every name-bearing node (decl names, EVar/ECon/EField, patterns, types),
tagged by kind (Fn/Type/Ctor/Module/Field/Var/...). Rename filters by `--kind`.

## Commands

- **rename** — collect spans of `name` nodes whose text equals `Old` (or matches
  `--pattern` regex), filtered by `--kind`; rewrite to `New`. Project-wide,
  AST-precise (skips strings/comments). Known v1 limitation: name-based, not
  scope-resolved — a local shadowing the target is also renamed (use `--kind`).
- **fix** — run `march_lint`; turn safe naming findings (snake_case fns,
  PascalCase types/ctors) into project-wide renames via the rename engine.
- **move** — relocate a top-level declaration's source span to `dest` (create with
  a `mod` wrapper if new), remove from the source file.
- **replace** — parse pattern/template as March exprs with `$x` metavariables;
  structurally match call/operator-shaped expressions; substitute and rewrite.

## Testing (`test/refactor/`)

Temp multi-file project; assert resulting file contents for: cross-file rename,
regex bulk rename, `--kind` filtering, move into a new file, a call-shape codemod,
and a `fix` naming sweep. Plus `--dry-run` writes nothing.
