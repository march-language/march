# March Zed Extension & Tree-sitter Grammar — Design Spec

## Overview

A Tree-sitter grammar for the March language and a Zed editor extension that provides syntax highlighting, bracket matching, auto-indentation, and code outline navigation. The grammar covers the full language design spec (not just the currently-implemented subset), so it remains useful as more language features are implemented.

## Architecture

Two separate directories at the repo root:

- **`tree-sitter-march/`** — standalone Tree-sitter grammar, reusable by any editor (Neovim, Helix, Emacs, etc.)
- **`zed-march/`** — thin Zed extension wrapper that references the grammar and provides query files

### Directory Structure

```
march/
├── tree-sitter-march/
│   ├── grammar.js              # Grammar definition
│   ├── package.json            # tree-sitter CLI metadata
│   ├── binding.gyp             # Node native binding (generated)
│   ├── bindings/               # Language bindings (generated)
│   ├── src/                    # Generated C parser (tree-sitter generate)
│   └── test/
│       └── corpus/             # Tree-sitter test cases
│           ├── literals.txt
│           ├── expressions.txt
│           ├── declarations.txt
│           ├── patterns.txt
│           ├── types.txt
│           ├── modules.txt
│           ├── actors.txt
│           ├── advanced.txt
│           └── comments.txt
│
├── zed-march/
│   ├── extension.toml          # Extension manifest
│   └── languages/
│       └── march/
│           ├── config.toml     # Language config
│           ├── highlights.scm  # Syntax highlighting queries
│           ├── brackets.scm    # Bracket matching
│           ├── indents.scm     # Auto-indentation
│           └── outline.scm     # Code outline / symbol nav
```

## Tree-sitter Grammar

### Grammar Node Types

The grammar produces these AST node types, derived from the menhir parser (`lib/parser/parser.mly`) and the full design spec (`specs/design.md`).

#### Top-level

| Node | March syntax |
|------|-------------|
| `source_file` | Root node; contains either a single `module_def` (matching the current menhir parser's `MOD name DO ... END` start rule) or bare declarations at the top level (future-proofing for scripts/REPL). The grammar accepts both forms. |
| `module_def` | `mod Name do ... end` |

#### Declarations

| Node | March syntax |
|------|-------------|
| `function_def` | `fn name(...) do ... end` / `pub fn name(...) do ... end` |
| `let_declaration` | `let pat = expr` |
| `type_def` | `type Name = A \| B(Int)`, `type Name = { x : Int }`, or `type Name = Int` (alias; alias form not yet in parser). Variant arms may also be atoms: `type Msg = :ok(Int) \| :error(String)` |
| `actor_def` | `actor Name do state { ... } init expr on Msg(...) do ... end end` |
| `protocol_def` | `protocol Name do ... end` |
| `interface_def` | `interface Name(a) do ... end` |
| `impl_def` | `impl Interface(Type) do ... end` |
| `sig_def` | `sig Name do ... end` |
| `extern_def` | `extern "lib" : Cap(T) do ... end` |
| `use_declaration` | `use Module.{name1, name2}` / `use Module.*` (from design spec, not yet in parser) |

**Not-yet-parsed declaration bodies** — These constructs are specified in `specs/design.md` but not yet in the menhir parser. The Tree-sitter grammar includes them for full spec coverage:

- **`interface_def`**: Body contains method signatures (`fn name : Type`) and optional default implementations (`fn name(params) do ... end`). May have superclass constraints: `interface Fractional(a) : Num(a) do ... end`.
- **`impl_def`**: Body contains method implementations and optional associated type assignments. May have `when` constraints: `impl Eq(a) for List(a) when Eq(a) do ... end`.
- **`sig_def`**: Body contains opaque type declarations (`type Tree(a)`) and function signatures (`fn insert : (a, Tree(a)) -> Tree(a)`).
- **`extern_def`**: Body contains foreign function declarations with explicit parameter types and return types.
- **`protocol_def`**: Body contains message steps (`Client -> Server : Msg(Type)`), `loop do ... end` blocks, and choice branches.
- **`use_declaration`**: Named imports (`use M.{a, b}`) and wildcard imports (`use M.*`).

#### Expressions

Listed from lowest to highest precedence:

| Prec | Node | Operators / Syntax |
|------|------|-------------------|
| 1 | `pipe_expression` | `\|>` (left-assoc) |
| 2 | `or_expression` | `\|\|` (left-assoc) |
| 3 | `and_expression` | `&&` (left-assoc) |
| 4 | `comparison_expression` | `==` `!=` `<` `>` `<=` `>=` (non-assoc) |
| 5 | `additive_expression` | `+` `-` `++` (left-assoc) |
| 6 | `multiplicative_expression` | `*` `/` `%` (left-assoc) |
| 7 | `unary_expression` | `-x` `!x` (right-assoc / prefix) |
| — | `call_expression` | `f(x, y)` |
| — | `constructor_expression` | `Some(42)`, `Nil` |
| — | `field_expression` | `x.name` (left-assoc) |

Other expression nodes (not precedence-sensitive):

| Node | March syntax |
|------|-------------|
| `lambda_expression` | `fn x -> expr` / `fn (x, y) -> expr` |
| `if_expression` | `if cond then e1 else e2` |
| `match_expression` | `match expr with \| ... end` |
| `match_arm` | `\| pat -> body` / `\| pat when guard -> body` |
| `block_expression` | `do ... end` |
| `record_expression` | `{ x = 1, y = 2 }` |
| `record_update` | `{ base with x = 1 }` |
| `tuple_expression` | `(a, b)` or `()` (unit/empty tuple) |
| `list_expression` | `[1, 2, 3]` |
| `typed_hole` | `?name`, `?` |
| `atom` | `:ok`, `:error(msg)` |
| `send_expression` | `send(cap, msg)` |
| `spawn_expression` | `spawn(Actor)` |
| `respond_expression` | `respond(value)` (actor handler response; not yet in parser but `RESPOND` token exists in lexer) |

#### Patterns

| Node | Example |
|------|---------|
| `wildcard_pattern` | `_` |
| `variable_pattern` | `name` |
| `constructor_pattern` | `Some(x)` |
| `atom_pattern` | `:ok`, `:error(msg)` |
| `tuple_pattern` | `(a, b)` |
| `literal_pattern` | `0`, `-1`, `3.14`, `"hello"`, `true` (includes negative numeric literals) |
| `record_pattern` | `{ x, y = p }` (in AST as `PatRecord`, not yet in parser) |
| `as_pattern` | `pat as name` (in AST as `PatAs`, not yet in parser) |

#### Types

| Node | Example |
|------|---------|
| `arrow_type` | `a -> b` |
| `type_application` | `List(Int)` |
| `type_variable` | `a` |
| `type_constructor` | `Int`, `String` |
| `tuple_type` | `(a, b)` |
| `linear_type` | `linear T`, `affine T` |
| `record_type` | `{ x : Int, y : Float }` (in AST as `TyRecord`, not yet in parser) |
| `type_nat` | Type-level natural literal: `3` in `Vector(3, Float)` (in AST as `TyNat`, not yet in parser) |
| `type_nat_op` | Type-level arithmetic: `n + m` in `Vector(n + m, a)` (in AST as `TyNatOp`, not yet in parser) |

#### Literals & Terminals

| Node | Example |
|------|---------|
| `integer` | `42`, `0` |
| `float` | `3.14` |
| `string` | `"hello"` with escape sequences |
| `boolean` | `true`, `false` |
| `identifier` | lowercase names: `x`, `greet`, `acc'` |
| `type_identifier` | uppercase names: `Int`, `Some`, `Counter` |
| `atom_literal` | `:ok`, `:error` (bare terminal token; `atom` in expressions and `atom_pattern` in patterns are higher-level nodes that may include arguments like `:error(msg)`) |
| `comment` | `-- line comment` |
| `block_comment` | `{- nested block comment -}` |

### Precedence Implementation

Tree-sitter uses `prec()`, `prec.left()`, and `prec.right()` instead of cascading grammar rules. The precedence table mirrors the menhir grammar exactly:

| Level | Operators | Associativity | Tree-sitter |
|-------|-----------|---------------|-------------|
| 1 | `\|>` | left | `prec.left(1, ...)` |
| 2 | `\|\|` | left | `prec.left(2, ...)` |
| 3 | `&&` | left | `prec.left(3, ...)` |
| 4 | `==` `!=` `<` `>` `<=` `>=` | none | `prec(4, ...)` |
| 5 | `+` `-` `++` | left | `prec.left(5, ...)` |
| 6 | `*` `/` `%` | left | `prec.left(6, ...)` |
| 7 | unary `-` `!` | right | `prec.right(7, ...)` |

### Tricky Grammar Points

These aspects of March's syntax need special care in the Tree-sitter grammar:

1. **`do`/`end` blocks as both delimiters and expressions** — `do ... end` appears in function bodies, module bodies, actor bodies, and as a standalone expression. The grammar must distinguish these contexts via parent rule, not by the keywords themselves.

2. **Block `let` without `in`** — `let x = expr` in a block is followed by subsequent expressions that see the binding. Tree-sitter handles this naturally as a sequence of statements within a block node.

3. **Multi-head function clauses** — consecutive `fn name(...)` clauses with the same name are logically one function. The Tree-sitter grammar treats each clause as a separate `function_def` node (same as the menhir parser before grouping). Highlighting doesn't need grouping — each clause highlights identically.

4. **`state` as contextual keyword** — `state` is a keyword in actor definitions but also usable as a variable name in expressions (the menhir parser has `| STATE { EVar (mk_name "state" $loc) }` in `expr_atom`). Tree-sitter will handle this via Tree-sitter's `word` token and context-dependent matching.

5. **Nested block comments** — `{- ... {- ... -} ... -}` requires tracking nesting depth. Tree-sitter's external scanner (written in C) handles this, since the default regex-based lexer can't count nesting.

6. **Atoms vs. colon in type annotations** — `:ok` is an atom but `:` before a type is a type annotation. The lexer distinguishes these: atoms require a lowercase letter immediately after `:` with no whitespace. The Tree-sitter grammar mirrors this via token precedence.

7. **Optional leading pipe in match** — `match expr with | Pat -> body end` has an optional `|` before the first arm (menhir: `option(PIPE)` after `WITH`). The grammar must accept both `match x with | A -> ...` and `match x with A -> ...`.

8. **Negative literal patterns** — The menhir parser allows `MINUS INT` and `MINUS FLOAT` in patterns (e.g., `| -1 -> ...`). The Tree-sitter grammar must handle the unary minus as part of the literal pattern, not as a separate unary expression.

9. **`respond` as keyword-like function** — `respond(value)` in actor handlers looks like a function call but uses the `RESPOND` keyword token. The grammar treats it as a keyword-prefixed expression (similar to `send` and `spawn`).

### Deferred Features

These design spec features are **not** included in the Tree-sitter grammar:

- **String interpolation** (`"Hello, ${name}!"`) — The lexer does not yet implement this. When added, the grammar will need an `interpolation` node inside strings and a Tree-sitter injection query to highlight interpolated expressions. Deferred to avoid speculative grammar design.

- **REPL input parsing** — The menhir parser has `repl_input` and `expr_eof` start symbols for the REPL. Tree-sitter grammars have a single entry point (`source_file`), so REPL-specific parsing is not applicable.

## Zed Extension

### extension.toml

```toml
[package]
id = "march"
name = "March"
version = "0.0.1"
schema_version = 1
authors = ["March Contributors"]
description = "March language support for Zed"

[grammars.march]
repository = "file:///path/to/tree-sitter-march"
rev = ""
```

For development, `file://` points to the local grammar directory. When published, this switches to a GitHub HTTPS URL + commit SHA.

### config.toml

```toml
name = "March"
grammar = "march"
path_suffixes = ["march"]
line_comments = ["-- "]
block_comment = ["{- ", " -}"]
tab_size = 2

brackets = [
  { start = "(", end = ")", close = true, newline = true },
  { start = "[", end = "]", close = true, newline = true },
  { start = "{", end = "}", close = true, newline = true },
  { start = "\"", end = "\"", close = true, newline = false, not_in = ["string", "comment"] },
]

word_characters = ["_", "'"]
```

The `'` in `word_characters` matches the lexer's `ident = alpha (alpha | digit | '\'')*` rule — March identifiers allow primes (e.g., `x'`, `acc'`).

### highlights.scm

Mapping strategy from grammar nodes to Zed highlight groups:

| Category | Highlight group | What matches |
|----------|----------------|-------------|
| Keywords | `@keyword` | `fn`, `let`, `do`, `end`, `if`, `then`, `else`, `match`, `with` (in match and record update), `when`, `type`, `mod`, `actor`, `protocol`, `interface`, `impl`, `for` (in `impl ... for`), `sig`, `extern`, `pub`, `linear`, `affine`, `unsafe`, `on`, `send`, `spawn`, `state`, `init`, `respond`, `loop`, `as`, `use`, `where` (constraint clauses in design spec) |
| Numbers | `@number` | Integer and float literals |
| Strings | `@string` | String literals |
| String escapes | `@string.escape` | `\n`, `\t`, `\\`, `\"` inside strings |
| Booleans | `@boolean` | `true`, `false` |
| Atoms | `@label` | `:ok`, `:error`, etc. |
| Function defs | `@function` | Function name in `fn name(...)` definitions |
| Function calls | `@function.call` | Function name at call sites |
| Types | `@type` | Type names: `Int`, `String`, `List`, etc. |
| Constructors | `@constructor` | ADT constructors: `Some`, `None`, `Ok`, `Err`, `Cons`, `Nil` |
| Variables | `@variable` | Regular identifiers |
| Parameters | `@variable.parameter` | Function parameter names |
| Modules | `@module` | Module names after `mod` |
| Properties | `@property` | Record field names |
| Operators | `@operator` | All binary/unary operators, `\|>`, `->`, `=` |
| Brackets | `@punctuation.bracket` | `()`, `[]`, `{}` |
| Delimiters | `@punctuation.delimiter` | `,`, `.`, `\|`, `:` |
| Comments | `@comment` | Both `--` line and `{- -}` block comments |
| Typed holes | `@special` | `?`, `?name` |

### brackets.scm

```scheme
("(" @open ")" @close)
("[" @open "]" @close)
("{" @open "}" @close)
("do" @open "end" @close)
```

### indents.scm

Indent triggers (nodes that increase indent level):
- `function_def`, `module_def`, `actor_def`, `interface_def`, `impl_def`, `sig_def`, `extern_def`, `protocol_def`
- `if_expression`, `match_expression`, `match_arm`
- `block_expression`

Dedent triggers:
- `end` keyword
- `|` (match arm separator)

### outline.scm

Symbols shown in the outline panel:

| Node | Context keyword | Display |
|------|----------------|---------|
| `function_def` | `fn` | `fn name` |
| `type_def` | `type` | `type Name` |
| `module_def` | `mod` | `mod Name` |
| `actor_def` | `actor` | `actor Name` |
| `interface_def` | `interface` | `interface Name` |
| `impl_def` | `impl` | `impl Interface(Type)` |
| `protocol_def` | `protocol` | `protocol Name` |
| `let_declaration` | `let` | `let name` (top-level only) |

## Test Corpus

Tree-sitter tests in `test/corpus/*.txt`, each containing named test cases with source input and expected S-expression parse trees.

### Test Files

| File | Cases | Coverage |
|------|-------|---------|
| `literals.txt` | 5-6 | Integers, floats, strings (with escapes), booleans, atoms, typed holes |
| `expressions.txt` | 8-10 | Binary ops at each precedence, unary ops, pipes, calls, constructors, field access, lambdas, if/then/else, match, tuples, lists, records, record updates, do/end blocks, send, spawn |
| `declarations.txt` | 5-6 | `fn` (single/multi-clause, with guards), `let`, `pub fn`, `type` (variant/record) |
| `patterns.txt` | 4-5 | Wildcard, variable, constructor, atom, tuple, literal, nested |
| `types.txt` | 4-5 | Constructors, variables, arrows, tuples, parameterized types, linear/affine |
| `modules.txt` | 3-4 | Module with mixed declarations, nested access |
| `actors.txt` | 3-4 | Actor with state/init/handlers, protocol definitions |
| `advanced.txt` | 4-5 | Interfaces, impls (with constraints), sigs, extern blocks |
| `comments.txt` | 3-4 | Line comments, nested block comments, comments between declarations |

**Total: ~40-50 test cases.**

The `examples/list_lib.march` file serves as an integration smoke test — if the grammar parses it without errors, the core grammar is solid.

## External Scanner

The Tree-sitter grammar requires an **external scanner** (written in C, in `src/scanner.c`) for one feature:

- **Nested block comments**: `{- ... {- ... -} ... -}` requires counting nesting depth, which Tree-sitter's regex-based lexer cannot do.

The external scanner tracks `{-` / `-}` nesting and emits a `block_comment` token when the outermost comment closes. This is a well-established pattern — OCaml, Haskell, and Kotlin Tree-sitter grammars all use external scanners for nested comments.

## Development Workflow

1. Write `grammar.js` in `tree-sitter-march/`
2. Run `tree-sitter generate` to produce the C parser in `src/`
3. Write test cases in `test/corpus/`
4. Run `tree-sitter test` to validate
5. Write query files in `zed-march/languages/march/`
6. Install dev extension in Zed: command palette → "zed: install dev extension" → select `zed-march/`
7. Open a `.march` file to verify highlighting
8. Iterate on grammar and queries

Prerequisites: `tree-sitter` CLI (via `npm install -g tree-sitter-cli`), Node.js, a C compiler.
