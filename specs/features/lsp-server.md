<!-- doc-lint:ignore-file: file pointers in this doc are shown relative to the `lsp/` subtree root (see the project-layout diagram), not the repo root. -->

# LSP Server (`march-lsp`)

## Overview

`march-lsp` is a Language Server Protocol server for the March language. It provides IDE features (diagnostics, hover types, go-to-definition, go-to-implementation, go-to-type-definition, completion (dot-completion + scope-precise locals), inlay hints, semantic tokens, document highlight, code actions, signature help, find references (incl. cross-file), rename (scope-correct), folding, code lens, performance insights, **workspace symbols**, and **document formatting**) to any LSP-compatible editor (VS Code, Neovim, Helix, Zed, Emacs, etc.). It can also be driven standalone via a stateless `march-lsp query` CLI (for scripts and LLMs).

Because it is built on the real compiler pipeline (parse → desugar → typecheck → TIR), types and diagnostics are accurate, not re-implemented heuristics.

## Implementation Status

Live, built from `lsp/` (Zed and other editors point at `_build/default/lsp/bin/main.exe` or the installed `march-lsp`). Transport: `linol`/`linol-lwt` over stdio.

**Best-in-class plan `specs/plans/archive/2026-06-13-lsp-best-in-class.md`: Phases 0–5 are implemented and merged**, plus document formatting, navigation extras, logging, and completion-depth improvements:

- **Phase 0**: UTF-16 position correctness end-to-end (`utf16.ml` line index + boundary remap; advertises `positionEncoding`); removed dead `bin/march_lsp.ml`.
- **Phase 1**: stdlib parse/desugar memoized (`stdlib_cache.ml`); error-resilient analysis (`analyse_resilient`); version-guarded + crash-isolated background TIR fiber.
- **Phase 2**: transport-agnostic `Query` facade; stateless `march-lsp query` CLI; editor setup docs (`lsp/docs/editors.md`).
- **Phase 3** (`...-lsp-symbol-identity.md`): scope-aware local symbol resolver; **shadow-correct** go-to-definition / references / rename; `prepareRename`. Also: top-level def/refs/hover filter to the user file and prefer user defs over same-named stdlib (no stdlib-collision).
- **Phase 4** (`...-lsp-completion.md`): context-aware **dot-completion** for record fields.
- **Phase 5.1** (`...-lsp-workspace.md`): **workspace symbols** (`workspace.ml` parse-only indexer + `workspace/symbol`); `forge_config` wired for project-root discovery.
- **Phase 5.2**: **cross-file find-references** (use-site index merged with live current-file results, top-level symbols only).
- **Phase 5.3**: workspace index invalidation on `didSave`.
- **Phase 5.4** (`...-lsp-incremental-engine.md`): **incremental typecheck engine**: the stdlib is typechecked once into a cached base env (`typecheck_cache.ml`) and forge deps once into a deps env keyed by their content; only the edited file's own decls are re-checked per keystroke (via `Tc.check_module_with_env_full`), replacing the previous whole-program re-typecheck of `stdlib @ deps @ user` on every change. Also: `run_tir_pass` insights memoized by source hash; `didChangeWatchedFiles` invalidates the workspace + deps caches; `did_change` debounced (coalesces keystroke bursts); JSON-RPC integration tests over stdio.
- **Formatting**: `documentFormattingProvider` + CLI `format`, via `march_format` (idempotent guard in `utf16.ml`).
- **Navigation extras**: `textDocument/implementation` (interface → its impls, via `collect_impl_sites`), `textDocument/typeDefinition` (value → its named type's decl), `textDocument/documentHighlight` (occurrences under cursor).
- **Logging**: `window/logMessage` on document open (first editor-visible observability).
- **Completion depth**: scope-precise local bindings (`collect_scoped` records a scope span per binder) offered first via `sortText` ranking.

**Remaining (Phase 5):** a per-def in-file typecheck firewall (AST-level `sig_hash`/`impl_hash` for the user file's own defs; deferred; requires canonical serialization of the full surface AST, and the dominant cost is already removed by caching the stdlib+deps prefix; see the deferred "Increment G" in `specs/plans/archive/2026-06-13-lsp-incremental-engine.md`); module-qualified precision for cross-file references (currently name-based); richer completion (auto-import, qualified `Module.`, postfix). A separate **compiler-side** issue: user `type` declarations are shadowed by same-named stdlib types in the typecheck environment (the type-level analogue of the def_map collision the LSP already fixes), fixable only in the typechecker.

## Features

| Feature | Status |
|---|---|
| Diagnostics (type/parse/lexer errors, warnings, hints) | ✅ |
| Hover (inferred type, doc string, perf insight, actor info) | ✅ |
| Go-to-definition (functions, types, constructors, modules) | ✅ scope-correct |
| Go-to-implementation (interface → impls) | ✅ |
| Go-to-type-definition | ✅ |
| Completion | ✅ dot-completion (record fields) + scope-precise locals, `sortText`-ranked |
| Inlay hints (inferred types) | ✅ |
| Semantic tokens (full) | ✅ |
| Document highlight (occurrences under cursor) | ✅ |
| Document symbols | ✅ |
| Workspace symbols (project-wide) | ✅ |
| Code actions (match-exhaustiveness, De Morgan, make-linear, annotations, unused-import/binding, inspect, naming) | ✅ |
| Signature help | ✅ |
| Find references | ✅ incl. cross-file (name-based for top-level symbols) |
| Rename | ✅ scope-correct + `prepareRename` validation |
| Document formatting | ✅ full-document, via `march_format` |
| Folding ranges | ✅ |
| Code lens (perf annotations) | ✅ |
| Performance insights (TCO, closure capture, actor copy; TIR pipeline lenses) | ✅ |
| Position encoding | ✅ UTF-16 (advertised) |
| Logging (`window/logMessage`) | ✅ on document open |
| Standalone CLI query mode | ✅ `march-lsp query hover\|definition\|references\|completions\|diagnostics\|format …`, `--stdin` |

## Architecture

Uses the **`linol`** OCaml library, a high-level LSP framework on top of the `lsp` package, with Lwt-based async I/O. Chosen over the raw `lsp` package or `ocaml-lsp-server` for its cleaner API.

### Key Files

```
lsp/
├── bin/main.ml          # entry point (stdio LSP; `query` CLI subcommand)
├── lib/server.ml        # linol Server subclass: handlers + capabilities
├── lib/analysis.ml      # compiler-pipeline-backed analysis engine
├── lib/query.ml         # transport-agnostic query facade (shared by server + CLI)
├── lib/query_cli.ml     # stateless CLI query logic (hover/def/refs/diag/format)
├── lib/workspace.ml     # cross-file symbol + use-site index (workspace/symbol, x-file refs)
├── lib/position.ml      # span ↔ LSP range + outbound remap (via Utf16)
├── lib/utf16.ml         # UTF-8 ↔ UTF-16 column mapping, line index, trailing-newline normalize
├── lib/stdlib_cache.ml  # content-hashed stdlib parse/desugar memo
├── lib/typecheck_cache.ml # memoized typed stdlib + deps envs (incremental check)
├── lib/forge_config.ml  # project root + import path discovery
├── docs/editors.md      # editor setup guides + CLI reference
└── test/                # alcotest suites (test_lsp, test_utf16, test_query_cli, test_incremental, test_jsonrpc)
```

## Usage

```sh
# Build
dune build lsp/bin/main.exe

# Install the march-lsp binary into the opam switch
dune install march-lsp

# Start the server (stdio transport)
march-lsp

# Standalone one-shot queries (JSON on stdout; `format` emits raw source)
march-lsp query hover       file.march --line 10 --col 4
march-lsp query references  file.march --line 10 --col 4
march-lsp query diagnostics file.march
march-lsp query format      file.march
cat buffer.march | march-lsp query diagnostics buffer.march --stdin
```

Editor configuration snippets (Neovim, Helix, Zed, Emacs, VS Code) live in `lsp/docs/editors.md`.

## Related

- `specs/plans/archive/2026-06-13-lsp-best-in-class.md`: best-in-class roadmap (master plan)
- `specs/plans/archive/2026-06-13-lsp-symbol-identity.md`, `specs/plans/archive/2026-06-13-lsp-completion.md`, `specs/plans/archive/2026-06-13-lsp-workspace.md`: phase sub-plans
- `specs/features/zed-extension.md` / `tree-sitter-march/`: Tree-sitter grammar (separate from LSP)
