# Using march-lsp in your editor

`march-lsp` speaks LSP over stdio. Build it with `dune build lsp/bin/main.exe`
and put the binary on your `PATH` (or `dune install march-lsp`), then point your
editor at the `march-lsp` command. Positions are reported in UTF-16 (the LSP
default; the server advertises `positionEncoding: utf-16`).

## Neovim (built-in LSP, 0.11+)

```lua
vim.lsp.config.march = {
  cmd = { "march-lsp" },
  filetypes = { "march" },
  root_markers = { "forge.toml" },
}
vim.lsp.enable("march")
vim.filetype.add({ extension = { march = "march" } })
```

On older Neovim (0.10), start it per-buffer:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "march",
  callback = function()
    vim.lsp.start({ name = "march", cmd = { "march-lsp" },
      root_dir = vim.fs.root(0, { "forge.toml" }) })
  end,
})
```

## Helix (`~/.config/helix/languages.toml`)

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

## Zed (`~/.config/zed/settings.json`)

```json
{ "lsp": { "march-lsp": { "binary": { "path": "march-lsp" } } } }
```

## Emacs (eglot)

```elisp
(add-to-list 'eglot-server-programs '(march-mode . ("march-lsp")))
```

## VS Code

There is no bespoke extension; use a generic LSP client (e.g. a small
`vscode-languageclient` wrapper or an existing "generic LSP" extension) with:

- `serverOptions`: `{ command: "march-lsp", transport: stdio }`
- `documentSelector`: `[{ language: "march" }]`

## Standalone / LLM / scripting (no editor)

The same analysis engine is reachable as one-shot queries that print a single
JSON object and exit — no LSP handshake, no persistent process:

```sh
march-lsp query hover       file.march --line 10 --col 4
march-lsp query definition  file.march --line 10 --col 4
march-lsp query references  file.march --line 10 --col 4
march-lsp query completions file.march --line 10 --col 4
march-lsp query diagnostics file.march

# Analyse an unsaved buffer piped on stdin (the path is only used for messages):
cat buffer.march | march-lsp query diagnostics buffer.march --stdin
```

`--line`/`--col` are 0-indexed UTF-16. Exit status is `0` on success and `2` on
a usage error (the JSON then has an `"error"` field). Example:

```sh
$ march-lsp query diagnostics bad.march
{"diagnostics":[{"message":"I expected `Bool` but found `Int`.","range":{"start":{"line":1,"character":18},"end":{"line":1,"character":22}}}]}
```
