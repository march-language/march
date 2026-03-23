# march-lsp

Language Server Protocol server for the [March](../README.md) programming language.

Provides rich editor support built on the March compiler's parse, desugar, and typecheck pipeline. Because march-lsp uses the real compiler internals (not a re-implementation), types and diagnostics are always accurate.

## Features

| Feature | Status |
|---------|--------|
| **Diagnostics** | ✅ Parse + typecheck errors, warnings, hints with source spans |
| **Hover types** | ✅ Show inferred type at cursor (full HM inference) |
| **Go to definition** | ✅ Jump to definition of functions, types, constructors, modules |
| **Completion** | ✅ Keywords, in-scope variables, type constructors, interfaces |
| **Inlay hints** | ✅ Show inferred types inline for let-bindings |
| **Document symbols** | ✅ Outline of functions, types, interfaces, modules |
| **Semantic tokens** | ✅ Rich syntax highlighting beyond keyword patterns |
| **Code actions** | 🚧 Linear type suggestions, sort algorithm hints (stub) |
| **Actor info** | ✅ Hover over actor names to see state + message types |
| **Interface impls** | ✅ Find all implementations of an interface |

### March-specific highlights

- **Actor visualization** — hover on an actor definition to see its state fields and all handled message types in a formatted popup
- **Interface navigation** — the completion list includes all registered interfaces and their method signatures
- **Linear type annotations** — the type display includes `linear` and `affine` qualifiers when present
- **Pipe chain types** — hover anywhere in a `|>` chain to see the type flowing through that point

## Building

march-lsp lives in the same dune workspace as the March compiler, so it picks up the compiler libraries directly.

```sh
# From the repository root:
dune build lsp/bin/main.exe

# Or build + install the march-lsp binary to the opam switch:
dune install march-lsp
```

The resulting binary is `march-lsp` (or `_build/default/lsp/bin/main.exe` before install).

### Dependencies

march-lsp requires these opam packages (in addition to march itself):

```
linol        >= 0.10
linol-lwt    >= 0.10
lwt          >= 5.0
```

Install them into the `march` switch:

```sh
opam install linol-lwt --switch march
```

## Editor configuration

### VS Code

Install the [March VS Code extension](../vscode-march) (if available), or configure the LSP manually via the [vscode-languageclient](https://code.visualstudio.com/api/language-extensions/language-server-extension-guide) approach.

Add to `.vscode/settings.json`:

```json
{
  "languageserver": {
    "march": {
      "command": "march-lsp",
      "args": [],
      "filetypes": ["march"]
    }
  }
}
```

Or using the generic LSP client extension:

```json
{
  "languageServerExample.maxNumberOfProblems": 100
}
```

### Neovim (with nvim-lspconfig)

```lua
-- In your nvim config (Lua):
local lspconfig = require('lspconfig')
local configs = require('lspconfig.configs')

-- Register march-lsp if not already known
if not configs.march then
  configs.march = {
    default_config = {
      cmd = { 'march-lsp' },
      filetypes = { 'march' },
      root_dir = lspconfig.util.root_pattern('dune-project', '.git'),
      settings = {},
    },
  }
end

lspconfig.march.setup({
  on_attach = function(client, bufnr)
    -- Enable inlay hints (Neovim 0.10+)
    vim.lsp.inlay_hint.enable(bufnr, true)
  end,
})
```

Add file type detection to `~/.config/nvim/ftdetect/march.vim`:
```vim
autocmd BufRead,BufNewFile *.march setfiletype march
```

### Helix

Add to `~/.config/helix/languages.toml`:

```toml
[[language]]
name = "march"
scope = "source.march"
file-types = ["march"]
comment-token = "#"
language-servers = ["march-lsp"]

[language-server.march-lsp]
command = "march-lsp"
```

### Zed

Add to your Zed settings or use the [zed-march](../zed-march) extension. For manual LSP configuration:

```json
{
  "lsp": {
    "march-lsp": {
      "binary": {
        "path": "march-lsp"
      }
    }
  }
}
```

### Emacs (eglot)

```elisp
;; In your init.el:
(require 'eglot)

;; Register march-lsp
(add-to-list 'eglot-server-programs
             '(march-mode . ("march-lsp")))

;; Auto-start on .march files
(add-hook 'march-mode-hook #'eglot-ensure)
```

## Architecture

```
lsp/
  lib/
    position.ml   — Span ↔ LSP position conversion utilities
    analysis.ml   — Document analysis pipeline (parse→typecheck→collect)
    server.ml     — LSP server class (subclasses linol)
  bin/
    main.ml       — Entry point (stdio JSON-RPC loop)
```

### Data flow

```
Editor opens file.march
        ↓
on_notif_doc_did_open
        ↓
Analysis.analyse ~filename ~src
  ├── Parse (march_parser)
  ├── Desugar (march_desugar)
  ├── Load stdlib
  ├── Typecheck (march_typecheck → type_map, env)
  ├── Build def_map (name → definition span)
  └── Build use_map (use span → name)
        ↓
Publish diagnostics to editor
        ↓
[editor requests hover/definition/completion/inlay_hint]
        ↓
Query analysis result from cache
        ↓
Return LSP response
```

### Type map

The type checker produces a `(span → ty) Hashtbl.t` mapping every expression span to its inferred type. For hover, march-lsp finds all spans containing the cursor and returns the type at the smallest (most specific) span.

### Linear type tracking

The analysis pipeline builds a consumption map for linear and affine bindings. Future code actions will use this to:
- Highlight where a linear value is consumed
- Warn if a linear value escapes or is used twice
- Suggest `linear` annotation when a value is used exactly once

### Actor analysis

For `actor` declarations, march-lsp extracts the state fields and message handlers. Hovering over an actor name shows this information as a formatted markdown popup.

## Development

```sh
# Build and watch for changes
dune build lsp/ --watch

# Run the test suite (exercises the compiler, not the LSP directly)
dune runtest

# Test the LSP manually with a simple client
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}' | march-lsp
```

## Contributing

The LSP server intentionally delegates all language intelligence to the existing march compiler libraries. Adding new features typically means:

1. Exposing new information from the typecheck pass (e.g., a new map or index)
2. Adding a query function in `analysis.ml`
3. Hooking it up in `server.ml`

See `specs/design.md` and `specs/progress.md` in the root for the language roadmap.
