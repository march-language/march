# March Zed Editor Extension

**Last Updated:** March 22, 2026
**Status:** Complete. Grammar compiled and working.

**Implementation:**
- `tree-sitter-march/grammar.js` (12,726 lines) — Tree-sitter grammar for March
- `tree-sitter-march/src/grammar.json` — Compiled grammar JSON
- `tree-sitter-march/src/parser.c` — Generated C parser
- `tree-sitter-march/march.dylib` — Compiled macOS dynamic library
- `tree-sitter-march/queries/` — Tree-sitter highlight/indent/fold queries
- `tree-sitter-march/package.json` — Node.js package metadata
- `tree-sitter-march/tree-sitter.json` — Tree-sitter config

---

## Overview

The March Zed extension provides syntax highlighting for `.march` files in the Zed editor via a Tree-sitter grammar. The grammar covers the full March surface syntax including:

- All expression forms (`fn`, `let`, `match`, `if`, `do...end`)
- Actor declarations (`actor`, `on`, `state`, `init`)
- Module system (`mod`, `sig`, `interface`, `impl`, `use`, `pub`)
- Type annotations (including linear/affine, session types)
- Protocol declarations
- String interpolation (`${}`)
- Atoms (`:ok`, `:error`)
- Comments (`--` and `{- -}`)
- Pipe operator (`|>`)
- Pattern matching with guards (`when`)

---

## 1. Grammar Structure (`tree-sitter-march/grammar.js`)

The grammar is written in Tree-sitter's JavaScript DSL. At 12,726 lines it is comprehensive — covering the full language including edge cases like:

- **Multi-clause functions** — consecutive `fn name` clauses with pattern matching
- **`do...end` blocks** — context-dependent parsing (function body, inline block, module body)
- **Operator precedence** — pipe (`|>`), boolean (`&&`, `||`), comparison, arithmetic
- **String interpolation** — nested `${ expr }` inside string literals
- **Type expressions** — including `linear T`, `affine T`, `Chan(S)`, `Vec(T, N)`

---

## 2. Queries (`tree-sitter-march/queries/`)

Tree-sitter queries drive editor features:

| Query file | Purpose |
|------------|---------|
| `highlights.scm` | Syntax highlighting — maps grammar nodes to highlight groups |
| `indents.scm` | Auto-indentation rules |
| `folds.scm` | Code folding points (`do...end`, `fn...end`, etc.) |

### Highlight groups used

- `keyword` — `fn`, `let`, `if`, `match`, `do`, `end`, `actor`, `mod`, etc.
- `function` — function definitions and calls
- `type` — type names (`Int`, `String`, user-defined)
- `constructor` — data constructors (`Some`, `Ok`, `Cons`)
- `atom` — atom literals (`:ok`, `:error`)
- `string` — string literals and interpolations
- `number` — integer and float literals
- `comment` — `--` and `{- -}`
- `operator` — `|>`, `->`, `++`, arithmetic ops
- `variable` — bound names
- `linear` / `affine` — linearity qualifiers (if supported by theme)

---

## 3. Building

The grammar requires [Node.js](https://nodejs.org/) and the `tree-sitter-cli` package:

```bash
cd tree-sitter-march
npm install
npx tree-sitter generate    # regenerates src/grammar.json + src/parser.c
npx tree-sitter build       # compiles march.dylib (macOS) / march.so (Linux)
npx tree-sitter test        # runs grammar corpus tests
```

The compiled `march.dylib` is checked into the repository so Zed can load it without a Node.js build step.

---

## 4. Installation in Zed

Zed extensions can be loaded locally. Add to `~/.config/zed/settings.json`:

```json
{
  "languages": {
    "March": {
      "grammar": "/path/to/march/tree-sitter-march"
    }
  }
}
```

Or install via Zed's extension system once published.

---

## 5. Known Limitations

- **LSP support** — no Language Server Protocol server yet. Syntax highlighting only; no hover types, go-to-definition, or diagnostics in editor.
- **macOS only prebuilt** — `march.dylib` is macOS. Linux users need to run `npx tree-sitter build` to get `march.so`.
- **Grammar sync** — grammar.js must be manually updated when new syntax is added to the language. No automated sync from the parser grammar.
