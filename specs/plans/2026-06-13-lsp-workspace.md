# LSP Workspace Model — Implementation Plan (Phase 5, increment 1)

> REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** Begin the workspace story with cross-file **workspace symbols** (`workspace/symbol`, the editor "go to symbol in project" / Ctrl-T), wiring in `forge_config` (currently never called by the server).

**Scope note:** Phase 5's full incremental typecheck engine (per-def caching with the CAS sig/impl firewall) is a large, separate effort; the dominant per-keystroke latency win already shipped in Phase 1 (stdlib memo). This increment delivers the highest-value *cross-file* capability with a cheap parse-only index (no typecheck), self-contained and testable.

## Design

- `lsp/lib/workspace.ml` — a pure indexer:
  - `type ws_symbol = { wsy_name; wsy_kind : SymbolKind.t; wsy_file : string; wsy_span : Ast.span }`.
  - `symbols_of_source : filename:string -> src:string -> ws_symbol list` — parse+desugar one file (errors → `[]`), walk top-level decls (fn, type + variants/fields, actor, interface + methods, nested modules, top-level let binders) collecting name + span + kind.
  - `index_sources : (string * string) list -> ws_symbol list` — map over (filename, src) pairs.
  - `query_symbols : ws_symbol list -> string -> ws_symbol list` — case-insensitive subsequence match on name (empty query → all), capped.
- `lsp/lib/server.ml`:
  - advertise `workspaceSymbolProvider = true`.
  - On `workspace/symbol`: discover project `.march` files (via `Forge_config.find_forge_root` from an open doc's dir, then walk the tree skipping `_build`/`.git`/`.claude`), read+index them, filter by the query, return `SymbolInformation[]` (name, kind, location). Cache the index; rebuild lazily.

## Task 1: Pure indexer
- [ ] Test (in-memory, two sources): `index_sources [("a.march", "...fn alpha..."); ("b.march", "...fn beta...")]` then `query_symbols idx "alpha"` finds `alpha` in `a.march`; `query_symbols idx ""` returns all; a subsequence query (`"alph"`) matches.
- [ ] Implement `workspace.ml`.
- [ ] Green; commit.

## Task 2: Server wiring
- [ ] `workspaceSymbolProvider = true`; `workspace/symbol` handler with file discovery via `forge_config` + a tree walk; index cache.
- [ ] Build; manual smoke (open a project, query a symbol). Commit.

## Follow-ups
- Cross-file find-references / go-to-definition (use the same index).
- `didChangeWatchedFiles` to invalidate the index on disk changes.
- Incremental typecheck engine (CAS sig/impl firewall) — separate large plan.
