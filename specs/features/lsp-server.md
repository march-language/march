# LSP Server (`march-lsp`)

## Overview

`march-lsp` is a Language Server Protocol server for the March language. It provides IDE features — diagnostics, hover types, go-to-definition, completion, inlay hints, semantic tokens, code actions, signature help, references, rename, folding, code lens, and performance insights — to any LSP-compatible editor (VS Code, Neovim, Helix, Zed, Emacs, etc.). It can also be driven standalone via a stateless `march-lsp query` CLI (for scripts and LLMs).

Because it is built on the real compiler pipeline (parse → desugar → typecheck → TIR), types and diagnostics are accurate, not re-implemented heuristics.

## Implementation Status

Live and installed as `march-lsp` (built from `lsp/`). Transport: `linol`/`linol-lwt` over stdio.

See `specs/plans/2026-06-13-lsp-best-in-class.md` for the active plan to take the server to best-in-class / IDE-level quality (UTF-16 correctness, incremental analysis, sound symbol identity, context-aware completion, workspace model, standalone CLI).

## Features

| Feature | Status |
|---|---|
| Diagnostics (type/parse/lexer errors, warnings, hints) | ✅ |
| Hover (inferred type, doc string, perf insight, actor info) | ✅ |
| Go-to-definition (functions, types, constructors, modules) | ✅ |
| Completion (keywords, in-scope names, types, ctors, interfaces) | ✅ (flat — context-awareness planned) |
| Inlay hints (inferred types) | ✅ |
| Semantic tokens (full) | ✅ |
| Document symbols | ✅ |
| Code actions (match-exhaustiveness, De Morgan, make-linear, annotations, unused-import/binding, inspect, naming) | ✅ |
| Signature help | ✅ |
| Find references | ✅ |
| Rename | ✅ (name-based — sound symbol identity planned) |
| Folding ranges | ✅ |
| Code lens (perf annotations) | ✅ |
| Performance insights (TCO, closure capture, actor copy; TIR pipeline lenses) | ✅ |
| Standalone CLI query mode | ✅ (`march-lsp query …`, see `lsp/docs/editors.md`) |

## Architecture

Uses the **`linol`** OCaml library — a high-level LSP framework on top of the `lsp` package, with Lwt-based async I/O. Chosen over the raw `lsp` package or `ocaml-lsp-server` for its cleaner API.

### Key Files

```
lsp/
├── bin/main.ml          # entry point (stdio LSP; `query` CLI subcommand)
├── bin/query_cli.ml     # stateless CLI query mode entry
├── lib/server.ml        # linol Server subclass: handlers + capabilities
├── lib/analysis.ml      # compiler-pipeline-backed analysis engine
├── lib/query.ml         # transport-agnostic query facade (shared by server + CLI)
├── lib/position.ml      # span ↔ LSP range (via Utf16)
├── lib/utf16.ml         # UTF-8 ↔ UTF-16 column mapping + line index
├── lib/stdlib_cache.ml  # content-hashed stdlib parse/desugar memo
├── lib/forge_config.ml  # project root + import path discovery
├── docs/editors.md      # editor setup guides + CLI reference
└── test/                # alcotest suites (test_lsp, test_utf16, test_query_cli)
```

## Usage

```sh
# Build
dune build lsp/bin/main.exe

# Install the march-lsp binary into the opam switch
dune install march-lsp

# Start the server (stdio transport)
march-lsp

# Standalone one-shot queries (JSON on stdout)
march-lsp query hover       file.march --line 10 --col 4
march-lsp query diagnostics file.march
cat buffer.march | march-lsp query diagnostics buffer.march --stdin
```

Editor configuration snippets (Neovim, Helix, Zed, Emacs, VS Code) live in `lsp/docs/editors.md`.

## Related

- `specs/features/zed-extension.md` — Tree-sitter grammar (separate from LSP; already on main)
- `tree-sitter-march/` — Zed editor extension with full syntax highlighting
- `specs/plans/2026-06-13-lsp-best-in-class.md` — best-in-class roadmap (active)
