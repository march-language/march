---
layout: docs
title: LSP & Editors
nav_order: 16
permalink: /docs/lsp/
---

# Language Server (LSP)

March ships `march-lsp`, a Language Server Protocol server that gives any
LSP-capable editor rich, **always-accurate** support. It is built directly on the
compiler's parse → desugar → typecheck pipeline: types, diagnostics, and
completions come from the real type checker (full Hindley–Milner inference), not
a re-implementation, so what the editor shows is exactly what the compiler sees.

There is also a **Debug Adapter Protocol** server (`march dap`) for breakpoint
debugging, and a **standalone query CLI** for scripts and LLMs. Both are covered
below.

---

## Install

`march-lsp` speaks LSP over **stdio**. It ships in the released March toolchain, so if
you installed a release build, `march-lsp` is already on your `PATH`; check with
`march-lsp --version` and skip straight to [Editor setup](#editor-setup).

Building from source? Compile it and put it on your `PATH`:

```sh
dune build lsp/bin/main.exe       # produces _build/default/lsp/bin/main.exe
dune install march-lsp            # installs it as `march-lsp` on PATH
```

Then point your editor at the `march-lsp` command. The server reports positions
in **UTF-16** (the LSP default; it advertises `positionEncoding: utf-16`) and
uses **`forge.toml`** as the project root marker, which is how it discovers the
other files in your project for cross-file features.

---

## Editor setup

### Neovim (built-in LSP, 0.11+)

```lua
vim.lsp.config.march = {
  cmd = { "march-lsp" },
  filetypes = { "march" },
  root_markers = { "forge.toml" },
}
vim.lsp.enable("march")
vim.filetype.add({ extension = { march = "march" } })
```

On Neovim 0.10, start it per-buffer:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "march",
  callback = function()
    vim.lsp.start({ name = "march", cmd = { "march-lsp" },
      root_dir = vim.fs.root(0, { "forge.toml" }) })
  end,
})
```

### Helix (`~/.config/helix/languages.toml`)

```toml
[[language]]
name = "march"
scope = "source.march"
file-types = ["march"]
roots = ["forge.toml"]
language-servers = ["march-lsp"]

[language-server.march-lsp]
command = "march-lsp"
```

### Zed (`~/.config/zed/settings.json`)

```json
{ "lsp": { "march-lsp": { "binary": { "path": "march-lsp" } } } }
```

The Zed extension in `zed-march/` also wires up the tree-sitter grammar
(highlighting, brackets) and the DAP debugger.

### Emacs (eglot)

```elisp
(add-to-list 'eglot-server-programs '(march-mode . ("march-lsp")))
```

### VS Code

Use a generic LSP client (a small `vscode-languageclient` wrapper, or an existing
"generic LSP" extension) with:

- `serverOptions`: `{ command: "march-lsp", transport: stdio }`
- `documentSelector`: `[{ language: "march" }]`

A matching DAP debug extension lives in `editors/vscode-march-debug/`.

---

## Features

### Diagnostics & navigation

| Feature | What it does |
|---|---|
| **Diagnostics** | Parse + type errors, warnings, hints with precise source spans (the same checks as `forge build`) |
| **Hover** | Inferred type at the cursor (with `linear`/`affine` qualifiers), the docstring if present, and actor state/messages on an actor name |
| **Go to definition** | Jump to a function, type, constructor, or module, **across files** |
| **Go to implementation / type definition** | Jump from an interface to its `impl`s, or from a value to its type |
| **Find references** | Every use of a name, **across the project** |
| **Document & workspace symbols** | File outline, and fuzzy project-wide symbol search (`Cmd/Ctrl+T`) |
| **Call hierarchy** | Incoming/outgoing calls for a function |
| **Rename** | Rename a symbol across all its use sites |

### Editing intelligence

| Feature | What it does |
|---|---|
| **Completions** | Context-aware: module members after `.`, constructors, interfaces, in-scope names, keywords; with snippet placeholders for function/constructor arguments |
| **Auto-import** | Completing an un-imported stdlib/dep member inserts the needed `import` |
| **Signature help** | Parameter hints at call sites |
| **Inlay hints** | Inferred types inline, plus FBIP annotations (`♻ reused` / `⧉ copied`) |
| **Semantic tokens** | Type-accurate highlighting, including ownership (`linear`/`affine`) |
| **Folding, selection range, linked editing** | Block folding, expand/shrink selection by AST node, live multi-cursor rename |

### Cross-file / project intelligence

The server discovers the rest of your project from `forge.toml`, so go-to-def,
find-references, workspace symbols, and **whole-project diagnostics** all work
across files, including resolving an `interface` declared in one file from an
`impl` in another.

---

## Typestate and capability intelligence

When your code uses the [typestate system]({{ site.baseurl }}/docs/capabilities/#typestate-tracking-resource-lifecycle) (`always_linear type` handles with `transitions` blocks), the LSP provides extra guidance directly in the editor.

### Typestate hover

Hovering any expression with a type that is a typestate handle shows:

- An **always-linear** badge if the handle was declared with `always_linear type` (the compiler requires it to be consumed, never dropped)
- The **current state** the handle is in at this point in the code
- Every **declared transition** from that state, showing which `via` function moves it to which next state

```
always-linear — must be consumed, not dropped

Typestate: resource `ConnTag`, state **`Closed`**

Transitions from `Closed`:
- `Closed` → `Open`  via `connect`
```

This pairs naturally with the existing type hover: the hover card first shows
the inferred type (`Handle(ConnTag, Closed)`), then the typestate block below the
separator.

### `via` completions

Inside a `transitions` block, after typing `via `, the completion menu filters to
functions in scope with a type that matches the transition shape:

```march
transitions Handle do
  ConnTag: Closed -> Open  via con<cursor>
                            --  ↑ only `connect`, `reconnect`, etc. offered
end
```

Only functions with the right type are shown: `Handle(R, S1) -> Handle(R, S2)` where `R` and the handle name match the enclosing `transitions` declaration. This prevents accidentally wiring a transition to an unrelated function.

---

## Code actions

The lightbulb / quick-fix menu offers a large set of refactors and fixes,
type-directed where possible:

- **Quick fixes**: add missing match arm(s) (`Add all N missing cases`),
  prefix/remove an unused binding, remove an unused import, fix a non-exhaustive
  match across the whole file.
- **Refactors**: introduce / remove pipe (`f(g(x))` ⇄ `x |> g() |> f()`),
  extract variable, extract function, inline variable / function, convert
  `if` → `match`, expand / collapse a function capture (`f` ⇄ `fn x -> f(x)`).
- **Type-directed**: destruct / case-split a variant value into an exhaustive
  `match`, fill a typed hole (`?`) ranked by the expected type, add a type or
  return-type annotation, organize imports.
- **Generators**: generate a doc comment, scaffold the missing methods of an
  `impl`, generate an actor client module, scaffold a session-type handler.
- **Auto-alias**: collapse a repeated module prefix into an `alias`.

> Project-wide refactors that rewrite *every* call site (rename, move, codemod,
> and **introduce parameter object**) live in the build tool as
> `forge refactor …`; see [Tooling]({{ site.baseurl }}/docs/tooling/). Cursor-driven actions above are
> the LSP's; project-wide rewrites are forge's.

---

## Performance insights

The LSP runs the full TIR optimization pipeline asynchronously and reports the
results as inlay hints and per-function **code lens**:

- `⚡ stack-allocated`: value promoted to the stack (no heap allocation)
- `♻ in-place`: FBIP, value reused in place without allocating
- `⚠ non-tail call`: a recursive call that isn't in tail position
- `📦 closure captures N values`: a closure capturing several variables
- allocation inside a recursive arm, actor message copies, indirect calls

A per-function lens summarizes them, e.g. `⚡ 2 stack-allocated · ♻ 1 in-place`.
Toggle the inlay annotations with the `march.inlayHints.performanceAnnotations`
client setting.

---

## Standalone query CLI

The same analysis engine is reachable as **one-shot queries** that print a single
JSON object and exit, with no LSP handshake and no persistent process. Handy for
scripts, CI, and LLM tooling:

```sh
march-lsp query hover       file.march --line 10 --col 4
march-lsp query type        file.march --line 10 --col 4   # inferred type only
march-lsp query definition  file.march --line 10 --col 4
march-lsp query references  file.march --line 10 --col 4
march-lsp query completions file.march --line 10 --col 4
march-lsp query diagnostics file.march
march-lsp query symbols     file.march                     # top-level symbols
march-lsp query format      file.march                     # formatted source (not JSON)

# Analyse an unsaved buffer piped on stdin (the path is only used for messages):
cat buffer.march | march-lsp query diagnostics buffer.march --stdin
```

`--line`/`--col` are **1-based** on the command line (human-friendly), counted in
UTF-16 code units, and converted to the 0-based LSP convention internally; ranges
in the JSON output are 0-based UTF-16 (LSP). Exit status is `0` on success and
`2` on a usage error (the JSON then has an `"error"` field).

```sh
$ march-lsp query type good.march --line 3 --col 6
{"type":"Int"}

$ march-lsp query diagnostics bad.march
{"diagnostics":[{"message":"I expected `Bool` but found `Int`.","range":{"start":{"line":1,"character":18},"end":{"line":1,"character":22}}}]}
```

`symbols` reports every symbol visible to the analysis (open file plus loaded
stdlib/workspace modules), matching the LSP `documentSymbol` request.

---

## Debugger (DAP)

March also ships a Debug Adapter Protocol server for breakpoint debugging,
launched as a subcommand of the compiler:

```sh
march dap        # speaks DAP over stdio
```

It supports line breakpoints, step in / over / out, a call stack, and local
variable inspection, by pausing the interpreter at each breakpoint. Editor
clients:

- **VS Code**: the extension in `editors/vscode-march-debug/`
- **Zed**: the `[debug_adapters.march]` entry in `zed-march/`

This is the protocol-based debugger; for a quick inline pause you can also drop a
`dbg()` call to open the REPL at that point (see [Tooling]({{ site.baseurl }}/docs/tooling/)).

---

## Why it's accurate

`march-lsp` and `march dap` use the compiler's own libraries: the same lexer,
parser, type checker, and IR passes that build your program. There is no separate
"editor model" to drift out of sync: a diagnostic in the editor is a diagnostic
in the build, and a hover type is the real inferred type.
