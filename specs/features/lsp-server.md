# LSP Server (`march-lsp`)

## Overview

`march-lsp` is a Language Server Protocol server for the March language. It provides IDE features — diagnostics, hover types, go-to-definition, completion, inlay hints, semantic tokens, and actor info — to any LSP-compatible editor (VS Code, Neovim, Helix, Zed, etc.).

## Implementation Status

**Implemented on branch `claude/vibrant-bartik` — pending merge to main.**

The LSP server needs a test suite before it can be merged. Tests are being written separately.

## Features

| Feature | Status |
|---|---|
| Diagnostics (type errors, parse errors) | ✅ |
| Hover (show type at cursor) | ✅ |
| Go-to-definition | ✅ |
| Completion (keywords, in-scope names, stdlib) | ✅ |
| Inlay hints (inferred types on let bindings) | ✅ |
| Semantic tokens (syntax highlighting data) | ✅ |
| Actor info (mailbox/state on Pid hover) | ✅ |

## Architecture

Uses the **`linol`** OCaml library — a high-level LSP framework built on top of the `lsp` package, with Lwt-based async I/O. This was chosen over raw `lsp` package or `ocaml-lsp-server` for its cleaner API and less boilerplate.

### Key Files (on branch `claude/vibrant-bartik`)

```
lsp/
├── dune              # Build target: march_lsp binary
├── march_lsp.ml      # Main server: Linol.Server subclass, all handlers
└── test/
    ├── dune
    └── test_lsp.ml   # Integration tests (in progress)
```

## Usage

```sh
# Build
dune build lsp/march_lsp.exe

# Start server (reads from stdin, writes to stdout — standard LSP transport)
dune exec lsp/march_lsp.exe

# Configure in Neovim (example)
vim.lsp.start({
  name = "march",
  cmd = { "march-lsp" },
  filetypes = { "march" },
})
```

## Merge Blockers

1. **Test suite** — `lsp/test/test_lsp.ml` needs to cover core LSP round-trips: initialize → open file → get diagnostics → hover → completion
2. Once tests pass, PR from `claude/vibrant-bartik` → `main`

## Related

- `specs/features/zed-extension.md` — Tree-sitter grammar (separate from LSP; already on main)
- `tree-sitter-march/` — Zed editor extension with full syntax highlighting
