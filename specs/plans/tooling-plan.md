# Tooling — Implementation Plan

## Current State

### Tree-Sitter Grammar (`tree-sitter-march/`)

**What exists**:
- Complete grammar definition in `grammar.js` (~350 rules, 13 KB)
- External scanner in `src/scanner.c` (for nested block comments)
- Auto-generated `src/parser.c` from grammar
- Test corpus: 9 files covering types, patterns, expressions, declarations, actors, literals, comments, modules, advanced
- Highlights query: `queries/highlights.scm`

**Status**: Functionally complete for current language syntax. Covers all expression forms, patterns, declarations, actors, protocols, interfaces, modules.

### Zed Extension (`zed-march/`)

**What exists**:
- Extension manifest: `extension.toml`
- Language config: `languages/march/config.toml`
- Query files: `highlights.scm`, `indents.scm`, `brackets.scm`, `outline.scm`
- Compiled grammar: `march.dylib`
- Submodule reference to tree-sitter-march

**Status**: Working syntax highlighting, bracket matching, auto-indentation, code outline in Zed editor.

### What's Missing

**LSP (Language Server Protocol)** — No language server exists. No hover information, go-to-definition, find-references, diagnostics, or code actions in any editor.

**Other editor support** — Only Zed is supported. No VS Code extension, no Neovim/Helix tree-sitter integration, no Emacs mode.

**LLM integration** — Per `specs/design.md`, the language is designed with LLM-friendliness in mind (regular syntax, strong types as documentation). No tooling exists to leverage this.

**Formatter** — No `march fmt` command. No auto-formatting.

**Linter** — No `march lint`. Warnings are emitted by the compiler but there's no dedicated linter pass.

**Documentation generator** — No `march doc`. Docstrings exist in the language syntax but aren't extracted.

**REPL enhancements** — The REPL exists with syntax highlighting and completion, but:
- No type-on-hover (`:type` command exists but is manual)
- No inline documentation
- No fuzzy completion (prefix-only)

---

## Target State

Per `specs/zed-extension-design.md`, `specs/zed-extension-plan.md`, `specs/design.md`:

1. **LSP server**: Full language server with hover, go-to-definition, find-references, diagnostics, completions, code actions, rename
2. **Multi-editor support**: VS Code, Neovim, Helix via tree-sitter; Emacs via tree-sitter or LSP
3. **Formatter**: `march fmt` with opinionated defaults and configurable style
4. **Documentation generator**: `march doc` extracts docstrings into HTML/markdown
5. **LLM integration**: Type signatures as context for LLM code generation; structured prompts from March types

---

## Implementation Steps

### Phase 1: LSP Server — Foundation (High complexity, Medium risk)

**Step 1.1: Create LSP binary project**
- New directory: `lsp/` or integrate into `bin/`
- Use OCaml `lsp` or `linol` library for LSP protocol handling
- Set up JSON-RPC transport over stdin/stdout
- Implement `initialize`, `shutdown`, `exit` lifecycle methods
- Estimated effort: 3 days

**Step 1.2: Diagnostics (error reporting)**
- File: `lsp/diagnostics.ml`
- Run the compiler pipeline (lex → parse → desugar → typecheck) on each file save
- Map `errors.ml` diagnostics to LSP `Diagnostic` objects with severity, range, message
- Publish diagnostics via `textDocument/publishDiagnostics`
- Estimated effort: 3 days
- Dependency: Existing error infrastructure in `lib/errors/errors.ml` already has spans

**Step 1.3: Go-to-definition**
- File: `lsp/definition.ml`
- Build a symbol table during typechecking that maps each identifier use to its definition span
- On `textDocument/definition` request, look up the symbol at cursor position
- Handle: local variables, function definitions, type definitions, module members
- Estimated effort: 5 days
- Risk: The current type checker doesn't build a use→def map; need to instrument it

**Step 1.4: Hover information**
- File: `lsp/hover.ml`
- On `textDocument/hover`, look up the type of the expression at cursor position
- Display inferred type, doc comment (if any), and definition location
- Requires a span→type map from the type checker (similar to type threading for TIR)
- Estimated effort: 3 days

**Step 1.5: Completion**
- File: `lsp/completion.ml`
- On `textDocument/completion`, provide:
  - Local variables in scope
  - Module members (after `.`)
  - Type constructors
  - Keywords and snippets
- Reuse existing REPL completion logic from `lib/repl/complete.ml`
- Estimated effort: 4 days

**Step 1.6: Find references**
- File: `lsp/references.ml`
- On `textDocument/references`, find all uses of a symbol across the project
- Requires building a project-wide symbol index
- Estimated effort: 4 days
- Risk: Multi-file projects need incremental re-indexing on change

**Step 1.7: Rename symbol**
- File: `lsp/rename.ml`
- On `textDocument/rename`, compute all reference locations and produce text edits
- Validate rename is safe (no shadowing, no conflicts)
- Estimated effort: 3 days
- Dependency: Step 1.6 (find references)

**Step 1.8: Code actions**
- File: `lsp/actions.ml`
- Quick fixes for common errors:
  - Missing `needs` declaration → add `needs Cap(X)` to module
  - Missing import → add `use Module`
  - Unused variable → prefix with `_`
  - Missing pattern branch → add wildcard
- Estimated effort: 5 days

### Phase 2: Formatter (Medium complexity, Low risk)

**Step 2.1: Define formatting rules**
- Document: `specs/formatting.md`
- Indentation: 2 spaces
- Line width: 80 characters (configurable)
- Rules for: function definitions, match expressions, pipe chains, records, type annotations
- Estimated effort: 1 day (spec), 2 days (discussion)

**Step 2.2: Implement pretty-printer**
- New file: `lib/format/format.ml`
- Wadler-Lindig pretty-printer algorithm (or use OCaml's `Format` module)
- Input: parsed AST → Output: formatted source text
- Handle comments: attach comments to AST nodes during parsing, emit in formatting
- Estimated effort: 8 days
- Risk: Comment preservation is the hardest part of formatters; comments between tokens need careful handling

**Step 2.3: `march fmt` command**
- File: `bin/main.ml`
- `march fmt file.march` — format a single file (write in-place or to stdout)
- `march fmt --check file.march` — check if file is formatted (exit code 0/1)
- `march fmt .` — format all `.march` files in directory
- Estimated effort: 1 day

### Phase 3: Documentation Generator (Low complexity, Low risk)

**Step 3.1: Docstring extraction**
- Files: `lib/parser/parser.mly`, `lib/ast/ast.ml`
- Docstrings: `/// This function does X` (line doc) or `/** ... */` (block doc)
- Attach docstrings to the following declaration in the AST
- Store as `doc: string option` on `DFn`, `DType`, `DInterface`, `DActor`
- Estimated effort: 2 days (parser may already handle `///` as special comments)

**Step 3.2: Documentation model**
- New file: `lib/docs/docs.ml`
- Extract from AST: function name, type signature, docstring, module path
- Build a `doc_module` tree mirroring the module structure
- Estimated effort: 2 days

**Step 3.3: HTML output**
- New file: `lib/docs/html.ml`
- Generate static HTML documentation pages
- Style inspired by Rust's `rustdoc` or Elixir's `ExDoc`
- Syntax-highlighted code examples in docstrings
- Cross-references: function names link to their definition
- Estimated effort: 5 days

**Step 3.4: `march doc` command**
- File: `bin/main.ml`
- `march doc` — generate documentation for the current project
- `march doc --open` — generate and open in browser
- Output to `_build/doc/`
- Estimated effort: 1 day

### Phase 4: Multi-Editor Support (Low complexity, Low risk)

**Step 4.1: VS Code extension**
- New directory: `vscode-march/`
- Package.json with language configuration, grammar reference
- Point to tree-sitter-march grammar for tokenization
- LSP client configuration (point to `march lsp` binary)
- Estimated effort: 3 days

**Step 4.2: Neovim integration**
- Documentation: `docs/editors/neovim.md`
- Tree-sitter parser installation via `:TSInstall march`
- Query files for highlights, indents, textobjects
- LSP configuration for `nvim-lspconfig`
- Estimated effort: 2 days

**Step 4.3: Helix integration**
- File: add March to Helix's `languages.toml` format
- Tree-sitter grammar reference, query files
- LSP configuration
- Estimated effort: 1 day

### Phase 5: LLM Integration Features (Medium complexity, Low risk)

**Step 5.1: Type signature extraction for LLM context**
- New file: `lib/llm/context.ml`
- Extract all function signatures, type definitions, and interface constraints from a module
- Output as a structured prompt fragment for LLM code generation
- E.g., "Given these types and functions, write a function that..."
- Estimated effort: 3 days

**Step 5.2: Structured error context for LLM repair**
- File: `lib/errors/errors.ml` or `lib/llm/repair.ml`
- On compilation error, produce a structured context block:
  - The error message
  - The relevant source code
  - The expected type vs. actual type
  - Available functions with matching types
- This can be piped to an LLM for automatic repair suggestions
- Estimated effort: 3 days

**Step 5.3: `march assist` command**
- File: `bin/main.ml`
- `march assist "implement sorting for my custom type"` — generates code given a natural language prompt + project context
- Collects type signatures, current file, and error messages as LLM context
- Calls external LLM API (configurable provider)
- Estimated effort: 5 days
- Risk: API key management; LLM output quality varies

### Phase 6: Linter (Low complexity, Low risk)

**Step 6.1: Define lint rules**
- New file: `lib/lint/lint.ml`
- Rules:
  - Unused variables (already warned by type checker, but make it a dedicated pass)
  - Unused imports
  - Overly broad capability declarations (already warned)
  - Shadow warnings (variable shadows outer binding)
  - Style: prefer `match` over nested `if/else`
  - Complexity: function too long, too many parameters
- Estimated effort: 5 days

**Step 6.2: `march lint` command**
- File: `bin/main.ml`
- `march lint file.march` — run linter, output warnings
- `march lint --fix file.march` — auto-fix simple issues (unused imports)
- Estimated effort: 1 day

---

## Dependencies

```
Phase 1 (LSP) ← no blockers; can start immediately
    Steps 1.6, 1.7 depend on 1.3

Phase 2 (Formatter) ← no blockers
Phase 3 (Doc generator) ← no blockers
Phase 4 (Multi-editor) ← depends on Phase 1 (LSP) for full functionality
Phase 5 (LLM) ← depends on Phase 1 (error infrastructure)
Phase 6 (Linter) ← no blockers

Cross-plan dependencies:
- LSP hover types depend on type threading (optimization-plan.md / type-system-completion-plan.md)
- Formatter interacts with tree-sitter grammar for AST-preserving formatting
```

## Testing Strategy

### LSP
1. **Protocol compliance**: Use LSP test harness to verify request/response format
2. **Diagnostics**: Open file with type error → diagnostic published with correct range
3. **Go-to-def**: Click on function call → jumps to function definition
4. **Hover**: Hover over variable → shows inferred type
5. **Completion**: Type `List.` → shows List module members
6. **Multi-file**: Definition in module A, usage in module B → go-to-def crosses files
7. **Performance**: 10,000-line project → diagnostics within 500ms of file save

### Formatter
1. **Idempotence**: `fmt(fmt(code)) == fmt(code)` — formatting twice gives same result
2. **Correctness**: Formatted code compiles and produces identical output to unformatted
3. **Comment preservation**: All comments preserved in output
4. **Consistency**: All stdlib files format cleanly

### Doc Generator
1. **Extraction**: Docstring on function appears in generated HTML
2. **Cross-references**: Function name in docstring links to definition
3. **Completeness**: All public functions documented; warning for undocumented public API
4. **Rendering**: HTML renders correctly in browser

## Open Questions

1. **LSP library choice**: OCaml has `lsp` (from ocaml-lsp), `linol`, and custom implementations. Which provides the best balance of features and maintainability?

2. **Incremental parsing for LSP**: Should the LSP re-parse the entire file on each keystroke, or use tree-sitter for incremental parsing (fast) and only run the full compiler pipeline on save?

3. **Formatter philosophy**: Should March have a single opinionated format (like Go's `gofmt`) or allow configuration (like Prettier)? Opinionated is simpler to implement and reduces bikeshedding.

4. **LLM provider**: Should `march assist` support multiple LLM providers (OpenAI, Anthropic, local models) or start with one? How to handle API key configuration securely?

5. **Tree-sitter grammar maintenance**: When language syntax evolves, the tree-sitter grammar must be updated in sync. Should we auto-generate parts of the grammar from the parser definition?

6. **Debugging in LSP**: Should the LSP support the Debug Adapter Protocol (DAP) for integrated debugging? This would connect the time-travel debugger to editors.

## Estimated Total Effort

| Phase | Effort | Risk |
|-------|--------|------|
| Phase 1: LSP server | 30 days | Medium |
| Phase 2: Formatter | 12 days | Low |
| Phase 3: Doc generator | 10 days | Low |
| Phase 4: Multi-editor | 6 days | Low |
| Phase 5: LLM integration | 11 days | Medium |
| Phase 6: Linter | 6 days | Low |
| **Total** | **75 days** | |

## Suggested Priority

1. **Phase 1 Steps 1.1–1.4** (LSP basics: diagnostics, go-to-def, hover) — highest impact for developer experience
2. **Phase 1 Step 1.5** (completion) — essential for productivity
3. **Phase 2** (formatter) — important for community consistency
4. **Phase 4 Step 4.1** (VS Code) — largest editor market share
5. **Phase 3** (doc generator) — important for library ecosystem
6. **Phase 6** (linter) — quality of life
7. **Phase 5** (LLM) — innovative but not essential for v1
8. **Phase 1 Steps 1.6–1.8** (advanced LSP) — nice to have
