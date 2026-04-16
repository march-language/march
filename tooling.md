---
layout: page
title: Tooling
nav_order: 15
---

# Tooling

March ships with a build tool, an LSP server, and a tree-sitter grammar for editor syntax highlighting.

---

## Installing forge

After cloning and building the repo, install `forge` to your PATH with:

```sh
dune build && dune install forge
```

Then all forge commands are available directly:

```sh
forge run my_program.march
forge test
forge search "map"
```

---

## forge — Build Tool

`forge` is the official project manager for March.

### Creating a Project

```sh
forge new my_app
cd my_app
```

Scaffolded layout:
```
my_app/
├── forge.toml          # project manifest
├── src/
│   └── my_app.march    # entry point (mod MyApp do ... end)
└── test/
    └── my_app_test.march
```

`forge.toml`:
```toml
[package]
name = "my_app"
version = "0.1.0"

[dependencies]
# add deps here
```

### Building and Running

```sh
# Build the project
forge build

# Build and run
forge run

# Run with arguments
forge run -- --port 8080
```

### Testing

```sh
# Run all tests
forge test

# Run tests matching a filter
forge test --filter "list operations"
```

### Formatting

```sh
forge format
forge format --check   # check without modifying
```

### Cleaning Build Artifacts

```sh
forge clean
```

### Interactive Mode (REPL)

```sh
forge interactive
# alias:
forge i
```

---

## forge search — Hoogle-style Search

`forge search` lets you find functions by name, type signature, or documentation keyword.

### Search by Name

```sh
forge search "map"
# Finds: List.map, Map.map_values, Option.map, Result.map, ...

forge search "fold"
# Finds: List.fold_left, List.fold_right, Map.fold, Enum.fold, ...
```

### Search by Type Signature

```sh
forge search --type "List(a) -> (a -> b) -> List(b)"
# Finds: List.map, Enum.map

forge search --type "Option(a) -> a -> a"
# Finds: Option.unwrap_or

forge search --type "String -> Int"
# Finds: String.length, String.to_int (partial)
```

### Search by Documentation Keyword

```sh
forge search --doc "sort"
# Finds functions with "sort" in their docstrings

forge search --doc "hash"
```

### Output Options

```sh
forge search "map" --limit 5
forge search "map" --json   # JSON output
```

### Rebuilding the Search Index

```sh
forge search --rebuild
```

The search index is cached at `.march/search-index.json` and rebuilt when source changes.

---

## Dependency Management

### Adding Dependencies

Edit `forge.toml`:

```toml
[dependencies]
bastion = "~> 0.4"
depot   = ">= 1.0.0, < 2.0.0"
```

Then:
```sh
forge deps
```

### Updating Dependencies

```sh
forge deps update
forge deps update bastion   # update specific package
```

### Lock File

`forge.lock` pins exact versions for reproducible builds. Commit it to version control.

### Semver Constraints

| Syntax | Meaning |
|--------|---------|
| `~> 1.2` | `>= 1.2.0, < 2.0.0` |
| `~> 1.2.3` | `>= 1.2.3, < 1.3.0` |
| `>= 1.0.0` | At least 1.0.0 |
| `= 1.2.3` | Exactly 1.2.3 |

---

## LSP Server

The March LSP server provides IDE features for any editor that supports the Language Server Protocol.

Binary location after build:
```
_build/default/lsp/bin/march_lsp.exe
```

### Features

| Feature | Description |
|---------|-------------|
| **Diagnostics** | Type errors, unused variables, exhaustiveness warnings reported inline |
| **Hover** | Type of the expression under the cursor; docstring if available |
| **Go to Definition** | Jump to where a function, type, or module is defined |
| **Find References** | All uses of a name across the project |
| **Completions** | Context-aware: module members after `.`, keywords, in-scope names |
| **Code Actions** | Quick fixes, add missing match arms, insert typed holes |
| **Rename** | Rename a symbol across the project |
| **Performance Insights** | Inlay hints for tail-call optimization, closure captures, FBIP reuse |
| **Code Lens** | Per-function annotations: `⚡ 2 stack-allocated · ♻ 1 in-place` |

### Performance Insights

The LSP runs the full TIR pipeline asynchronously and reports optimization results as inlay hints and code lens items:

- `⚡ stack-allocated` — value promoted to stack (no heap allocation)
- `♻ in-place` — FBIP: value reused in-place without allocation
- `⚠ non-tail call` — recursive call that's not in tail position
- `📦 closure captures N values` — closure with many captured variables

### Configuring the LSP

In your editor's LSP configuration, point to the binary:

```json
{
  "command": "/path/to/march/_build/default/lsp/bin/march_lsp.exe",
  "filetypes": ["march"]
}
```

---

## Zed Editor

March ships a tree-sitter grammar for Zed with syntax highlighting and bracket matching.

### Installing the Extension

The grammar is at `tree-sitter-march/` in the repository. In Zed:

1. Open the command palette: `Cmd+Shift+P`
2. Search for "Install Dev Extension"
3. Point to `tree-sitter-march/`

Alternatively, the compiled `march.dylib` can be installed directly into Zed's extension directory.

### What's Highlighted

- Keywords: `fn`, `pfn`, `let`, `match`, `do`, `end`, `mod`, `actor`, `on`, `type`, etc.
- String literals and interpolation (`${}`)
- Comments (`--` and `{- -}`)
- Operators and punctuation
- Type annotations
- Constructors (capitalized identifiers)
- Atoms (`:name`)

---

## Time-Travel Debugger

Place a `dbg()` breakpoint anywhere in your code:

```elixir
fn process(items : List(Int)) : Int do
  let filtered = List.filter(items, fn x -> x > 0)
  dbg()    -- breakpoint: REPL opens here
  let result = List.fold_left(0, filtered, fn acc x -> acc + x)
  result
end
```

When execution reaches `dbg()`, the program pauses and enters debug mode:

```
[debug] Breakpoint hit — :continue to resume, :help for commands

dbg> :where
process  examples/debug.march:5
main     examples/debug.march:12

dbg> filtered
[1, 3, 5] : List(Int)

dbg> :back 2
-- stepped back 2 steps

dbg> :continue
-- resuming...
```

Debug REPL commands:
```
:continue           — resume execution
:back N             — step N steps backward in time
:forward N          — step N steps forward
:goto N             — jump to step N
:where              — show current call stack
:diff N [names]     — show what changed at step N
:find               — search for a step matching a condition
:trace N            — show N steps of execution trace
:actors             — list all actors and their state history
:actor ID           — show a specific actor's message history
```

The debugger captures a full execution trace including all actor message sends and receives.

---

## Compiler Analysis

The compiler can produce structured output for debugging and analysis:

```sh
# Dump all compilation phases to trace/phases/
forge compile --dump-phases my_program.march

# Analyze a GC trace
MARCH_TRACE_GC=1 forge run my_program.march
```

With `MARCH_TRACE_GC=1` set, the runtime logs all reference-counting operations to `trace/gc/gc.jsonl`. The analysis command reports:
- Leaked objects (allocated but never freed)
- Double frees
- Negative reference counts (invariant violations)

### Visualizing Compiler Phases

Open `tools/phase-viewer.html` in a browser after running `forge compile --dump-phases`. This shows:
- Per-function TIR dumps at each pass
- Inline eligibility and reasoning
- RC density visualization (which values are RC'd most)

### Visualizing GC Events

Open `tools/gc-viewer.html` after running with `MARCH_TRACE_GC=1`:
- Timeline of alloc/free/inc_ref/dec_ref events
- Live-object count chart
- Address history for any specific object

---

## Environment Variables

| Variable | Effect |
|----------|--------|
| `MARCH_LIB_PATH` | Colon-separated paths for multi-file project discovery |
| `MARCH_TRACE_GC` | Set to `1` to log GC events to `trace/gc/gc.jsonl` |
| `MARCH_HISTORY_FILE` | REPL history file path (default: `~/.march_history`) |
| `MARCH_HISTORY_SIZE` | Max REPL history entries (default: 1000) |
| `MARCH_ENV` | `development` / `test` / `production` (read by `Config.env`) |

---

## Next Steps

- [Getting Started](getting-started.md) — set up your first project with forge
- [REPL](repl.md) — interactive exploration
- [Standard Library](stdlib.md) — what you can search with `forge search`
