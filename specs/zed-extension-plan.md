# March Zed Extension Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Tree-sitter grammar for March and a Zed editor extension providing syntax highlighting, bracket matching, auto-indentation, and code outline navigation.

**Architecture:** Two directories at repo root: `tree-sitter-march/` (standalone Tree-sitter grammar covering the full language spec) and `zed-march/` (Zed extension wrapper with query files). Grammar is written with TDD — each rule group gets corpus tests before implementation. External scanner handles nested block comments.

**Tech Stack:** Node.js 25, tree-sitter CLI (`npm install -g tree-sitter-cli`), C compiler (for generated parser), Zed editor for manual integration test.

---

## File Structure

**Created from scratch:**
```
tree-sitter-march/
  grammar.js                  # Single grammar definition file (~400 lines)
  package.json                # tree-sitter CLI metadata
  src/
    scanner.c                 # External scanner for nested block comments (hand-written)
    parser.c                  # Generated — never edit
    tree_sitter/              # Generated — never edit
  test/corpus/
    comments.txt              # Block comment tests (needed first: validates scanner)
    literals.txt              # Integer, float, string, bool, atom, hole
    types.txt                 # All type forms
    patterns.txt              # All pattern forms
    expressions.txt           # Operators, calls, control flow, atoms
    declarations.txt          # fn, let, type, pub fn
    modules.txt               # mod, source_file
    actors.txt                # actor, protocol
    advanced.txt              # interface, impl, sig, extern, use

zed-march/
  extension.toml              # Extension manifest (file:// URL for dev)
  languages/march/
    config.toml               # Language config (file ext, comments, brackets)
    highlights.scm            # Syntax highlighting queries
    brackets.scm              # Bracket matching (including do/end)
    indents.scm               # Auto-indentation
    outline.scm               # Code outline (fn, type, mod, actor, etc.)
```

**Reference files (read-only):**
- `lib/lexer/lexer.mll` — authoritative token definitions
- `lib/parser/parser.mly` — authoritative grammar rules
- `specs/zed-extension-design.md` — node types, precedence, highlight mapping
- `examples/list_lib.march` — integration test file
- `examples/list_lib.march` — primary integration test file (actors.march does not yet exist; use list_lib.march only)

---

## Task 1: Install tree-sitter CLI and scaffold `tree-sitter-march/`

**Files:**
- Create: `tree-sitter-march/package.json`
- Create: `tree-sitter-march/grammar.js`

- [ ] **Step 1: Install tree-sitter CLI globally**

```bash
npm install -g tree-sitter-cli
tree-sitter --version
```
Expected: `tree-sitter 0.x.x`

- [ ] **Step 2: Create `tree-sitter-march/package.json`**

```json
{
  "name": "tree-sitter-march",
  "version": "0.0.1",
  "description": "Tree-sitter grammar for the March language",
  "main": "bindings/node",
  "keywords": ["parser", "tree-sitter", "march"],
  "dependencies": {
    "nan": "*"
  },
  "tree-sitter": [
    {
      "scope": "source.march",
      "file-types": ["march"],
      "highlights": "queries/highlights.scm"
    }
  ]
}
```

- [ ] **Step 3: Create minimal `tree-sitter-march/grammar.js` skeleton**

Note: `identifier` and `type_identifier` are the **only** regex terminals for names. Contextual aliases (like `variable_pattern`, `type_constructor`, `type_variable`) are created with `alias()` — not new regexes — to avoid Tree-sitter duplicate-terminal errors.

The helper functions go **outside** the `grammar({})` call at the bottom of the file. They are used throughout all tasks.

```javascript
module.exports = grammar({
  name: 'march',

  externals: $ => [
    $.block_comment,
  ],

  extras: $ => [
    /\s/,
    $.comment,
    $.block_comment,
  ],

  word: $ => $.identifier,

  rules: {
    source_file: $ => choice(
      $.module_def,
      repeat1($._declaration),
    ),

    module_def: $ => seq(
      'mod', field('name', $.type_identifier),
      'do', repeat($._declaration), 'end',
    ),

    _declaration: $ => choice(
      $.function_def,
      $.let_declaration,
      $.type_def,
    ),

    function_def: $ => seq(
      optional('pub'), 'fn',
      field('name', $.identifier),
      '(', ')', 'do', 'end',
    ),

    let_declaration: $ => seq('let', $.identifier, '=', $._expr),

    type_def: $ => seq('type', $.type_identifier, '=', $.type_identifier),

    _expr: $ => $.integer,

    comment: _ => token(seq('--', /.*/)),
    integer: _ => /[0-9]+/,
    identifier: _ => /[a-z_][a-zA-Z0-9_']*/,
    type_identifier: _ => /[A-Z][a-zA-Z0-9_']*/,
  },
});

// Helpers — defined outside grammar({}) so they are plain JS functions.
function commaSep(rule) {
  return optional(commaSep1(rule));
}
function commaSep1(rule) {
  return seq(rule, repeat(seq(',', rule)));
}
function pipeSep1(rule) {
  // Pipe-separated list: used for match arms (optional leading | handled at call site)
  return seq(rule, repeat(seq('|', rule)));
}
```

- [ ] **Step 4: Create stub external scanner `tree-sitter-march/src/scanner.c`** (full implementation in Task 2)

```c
#include "tree_sitter/parser.h"
#include <string.h>

enum TokenType { BLOCK_COMMENT };

void *tree_sitter_march_external_scanner_create() { return NULL; }
void tree_sitter_march_external_scanner_destroy(void *p) {}
void tree_sitter_march_external_scanner_reset(void *p) {}
unsigned tree_sitter_march_external_scanner_serialize(void *p, char *buf) { return 0; }
void tree_sitter_march_external_scanner_deserialize(void *p, const char *b, unsigned n) {}

bool tree_sitter_march_external_scanner_scan(void *payload, TSLexer *lexer,
                                              const bool *valid_symbols) {
  return false;
}
```

- [ ] **Step 5: Generate the parser**

```bash
cd tree-sitter-march && tree-sitter generate
```
Expected: Creates `src/parser.c`, `src/tree_sitter/`, `bindings/`

- [ ] **Step 6: Verify parse works on a trivial input**

```bash
echo 'mod Foo do end' | tree-sitter parse --stdin --scope source.march
```
Expected: S-expression output with `(source_file (module_def ...))`

- [ ] **Step 7: Commit scaffold**

```bash
cd ..
git add tree-sitter-march/
git commit -m "feat: scaffold tree-sitter-march grammar"
```

---

## Task 2: External scanner for nested block comments

**Files:**
- Modify: `tree-sitter-march/src/scanner.c`
- Create: `tree-sitter-march/test/corpus/comments.txt`

- [ ] **Step 1: Write failing corpus test `tree-sitter-march/test/corpus/comments.txt`**

```
================================================================================
Line comment
================================================================================

mod Foo do
  -- this is a comment
  let x = 1
end

--------------------------------------------------------------------------------

(source_file
  (module_def
    name: (type_identifier)
    (comment)
    (let_declaration
      (identifier)
      (integer))))

================================================================================
Block comment simple
================================================================================

mod Foo do
  {- a block comment -}
  let x = 1
end

--------------------------------------------------------------------------------

(source_file
  (module_def
    name: (type_identifier)
    (block_comment)
    (let_declaration
      (identifier)
      (integer))))

================================================================================
Block comment nested
================================================================================

mod Foo do
  {- outer {- inner -} outer -}
  let x = 1
end

--------------------------------------------------------------------------------

(source_file
  (module_def
    name: (type_identifier)
    (block_comment)
    (let_declaration
      (identifier)
      (integer))))
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd tree-sitter-march && tree-sitter test
```
Expected: FAIL (block_comment not yet recognised)

- [ ] **Step 3: Add `comment` token and line comment rule to `grammar.js`**

Add to the `rules` object:

```javascript
comment: _ => token(seq('--', /.*/)),
```

And register `comment` as an extra (appears anywhere without affecting structure):

```javascript
extras: $ => [
  /\s/,
  $.comment,
  $.block_comment,
],
```

- [ ] **Step 4: Implement the full external scanner in `src/scanner.c`**

```c
#include "tree_sitter/parser.h"
#include <string.h>

enum TokenType { BLOCK_COMMENT };

void *tree_sitter_march_external_scanner_create()   { return NULL; }
void  tree_sitter_march_external_scanner_destroy(void *p) {}
void  tree_sitter_march_external_scanner_reset(void *p) {}
unsigned tree_sitter_march_external_scanner_serialize(void *p, char *buf) { return 0; }
void tree_sitter_march_external_scanner_deserialize(void *p, const char *b, unsigned n) {}

bool tree_sitter_march_external_scanner_scan(
    void *payload, TSLexer *lexer, const bool *valid_symbols
) {
  if (!valid_symbols[BLOCK_COMMENT]) return false;

  /* Must start with {- */
  if (lexer->lookahead != '{') return false;
  lexer->advance(lexer, false);
  if (lexer->lookahead != '-') return false;
  lexer->advance(lexer, false);

  int depth = 1;
  while (depth > 0) {
    if (lexer->lookahead == 0) return false; /* EOF inside comment */
    if (lexer->lookahead == '{') {
      lexer->advance(lexer, false);
      if (lexer->lookahead == '-') { lexer->advance(lexer, false); depth++; }
    } else if (lexer->lookahead == '-') {
      lexer->advance(lexer, false);
      if (lexer->lookahead == '}') { lexer->advance(lexer, false); depth--; }
    } else {
      lexer->advance(lexer, false);
    }
  }
  lexer->result_symbol = BLOCK_COMMENT;
  return true;
}
```

- [ ] **Step 5: Regenerate and run tests**

```bash
cd tree-sitter-march && tree-sitter generate && tree-sitter test
```
Expected: All 3 comment tests PASS

- [ ] **Step 6: Commit**

```bash
cd ..
git add tree-sitter-march/
git commit -m "feat: add external scanner for nested block comments"
```

---

## Task 3: Literals and terminals

**Files:**
- Modify: `tree-sitter-march/grammar.js`
- Create: `tree-sitter-march/test/corpus/literals.txt`

- [ ] **Step 1: Write corpus test `test/corpus/literals.txt`**

```
================================================================================
Integer literal
================================================================================
mod Foo do let x = 42 end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier) (let_declaration (identifier) (integer))))

================================================================================
Float literal
================================================================================
mod Foo do let x = 3.14 end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier) (let_declaration (identifier) (float))))

================================================================================
String literal
================================================================================
mod Foo do let x = "hello" end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier) (let_declaration (identifier) (string))))

================================================================================
Boolean literals
================================================================================
mod Foo do let x = true end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier) (let_declaration (identifier) (boolean))))

================================================================================
Atom literal bare
================================================================================
mod Foo do let x = :ok end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier) (let_declaration (identifier) (atom))))

================================================================================
Typed hole anonymous
================================================================================
mod Foo do let x = ? end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier) (let_declaration (identifier) (typed_hole))))

================================================================================
Typed hole named
================================================================================
mod Foo do let x = ?parse_step end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier) (let_declaration (identifier) (typed_hole (identifier)))))
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd tree-sitter-march && tree-sitter test --filter literals
```

- [ ] **Step 3: Expand terminals and literals in `grammar.js`**

Replace the minimal `_expr` and add full literal rules:

```javascript
// Terminals
identifier: _ => /[a-z_][a-zA-Z0-9_']*/,
type_identifier: _ => /[A-Z][a-zA-Z0-9_']*/,
integer: _ => /[0-9]+/,
float: _ => /[0-9]+\.[0-9]+/,
boolean: _ => choice('true', 'false'),

// String with escape sequences
string: _ => seq(
  '"',
  repeat(choice(
    /[^"\\]+/,
    seq('\\', choice('n', 't', '\\', '"')),
  )),
  '"',
),

// Atom: :name or :name(args)  -- atom_literal is the bare token
// Regex matches lexer's atom_name: ['a'-'z'] (alpha | digit | '_' | '\'')*
atom_literal: _ => seq(':', /[a-z][a-zA-Z0-9_']*/),

// Typed hole: ? or ?name
typed_hole: $ => seq('?', optional($.identifier)),

// Atom expression: :ok or :error(msg)
atom: $ => seq(
  $.atom_literal,
  optional(seq('(', commaSep($._expr), ')')),
),
```

Update `_expr` to be a choice of all these:

```javascript
_expr: $ => choice(
  $.integer,
  $.float,
  $.string,
  $.boolean,
  $.atom,
  $.typed_hole,
),
```

Also update `let_declaration` to allow patterns with optional type annotation:
```javascript
let_declaration: $ => seq(
  'let', field('pattern', $._pattern), optional($.type_annotation), '=', field('value', $._expr),
),

// _pattern expands in Task 5; stub for now.
// Use string form alias() — $.variable_pattern is not defined yet at this step.
_pattern: $ => alias($.identifier, 'variable_pattern'),
type_annotation: $ => seq(':', $._type),
// _type expands in Task 4; stub for now.
// Use string form alias() — $.type_constructor is not defined yet at this step.
_type: $ => alias($.type_identifier, 'type_constructor'),
```

**Important:** `variable_pattern` and `type_constructor` are created with `alias()` — NOT new regex terminals. This avoids duplicate-terminal conflicts in Tree-sitter.

- [ ] **Step 4: Regenerate and test**

```bash
cd tree-sitter-march && tree-sitter generate && tree-sitter test --filter literals
```
Expected: All literal tests PASS

- [ ] **Step 5: Commit**

```bash
cd ..
git add tree-sitter-march/
git commit -m "feat: add literal terminals to grammar"
```

---

## Task 4: Types

**Files:**
- Modify: `tree-sitter-march/grammar.js`
- Create: `tree-sitter-march/test/corpus/types.txt`

- [ ] **Step 1: Write corpus test `test/corpus/types.txt`**

```
================================================================================
Type constructor bare
================================================================================
mod Foo do fn f() : Int do 1 end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def name: (identifier)
    return_type: (type_constructor)
    (integer))))

================================================================================
Type application
================================================================================
mod Foo do fn f() : List(Int) do 1 end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def name: (identifier)
    return_type: (type_application
      (type_constructor) (type_constructor)))))

================================================================================
Arrow type
================================================================================
mod Foo do fn f() : Int -> Bool do 1 end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def name: (identifier)
    return_type: (arrow_type (type_constructor) (type_constructor))
    (integer))))

================================================================================
Tuple type
================================================================================
mod Foo do fn f() : (Int, Bool) do 1 end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def name: (identifier)
    return_type: (tuple_type (type_constructor) (type_constructor))
    (integer))))

================================================================================
Linear type
================================================================================
mod Foo do fn f() : linear Int do 1 end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def name: (identifier)
    return_type: (linear_type (type_constructor))
    (integer))))

================================================================================
Type variable
================================================================================
mod Foo do fn f() : a do 1 end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def name: (identifier)
    return_type: (type_variable)
    (integer))))
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd tree-sitter-march && tree-sitter test --filter types
```

- [ ] **Step 3: Implement type rules in `grammar.js`**

```javascript
_type: $ => choice(
  $.arrow_type,
  $._type_atom,
),

arrow_type: $ => prec.right(1, seq(
  field('param', $._type_atom), '->', field('return', $._type),
)),

_type_atom: $ => choice(
  $.type_application,
  $.type_constructor,
  $.type_variable,
  $.linear_type,
  $.tuple_type,
),

type_application: $ => seq(
  field('name', $.type_identifier),
  '(', commaSep1($._type), ')',
),

// Use alias() — NOT new regex terminals — to avoid duplicate-terminal conflicts.
// type_constructor wraps type_identifier (uppercase names in type position).
// type_variable wraps identifier (lowercase names in type position).
type_constructor: $ => alias($.type_identifier, $.type_constructor),
type_variable: $ => alias($.identifier, $.type_variable),

linear_type: $ => seq(
  choice('linear', 'affine'),
  field('type', $._type_atom),
),

tuple_type: $ => seq(
  '(', $._type, ',', commaSep1($._type), ')',
),
```

Also update `function_def` to support return type annotation and parameters:

```javascript
function_def: $ => seq(
  optional('pub'), 'fn',
  field('name', $.identifier),
  '(', optional(commaSep($.fn_param)), ')',
  optional(seq(':', field('return_type', $._type))),
  optional($.when_guard),
  'do', field('body', $.block_body), 'end',
),

fn_param: $ => choice(
  $.named_param,
  $._pattern,
),

named_param: $ => seq(
  optional(choice('linear', 'affine')),
  field('name', $.identifier),
  ':', field('type', $._type),
),

when_guard: $ => seq('when', $._expr),

block_body: $ => seq(
  $._block_expr,
  repeat($._block_expr),
),

_block_expr: $ => choice(
  $.let_declaration,
  $._expr,
),
```

- [ ] **Step 4: Regenerate and test**

```bash
cd tree-sitter-march && tree-sitter generate && tree-sitter test --filter types
```
Expected: All type tests PASS

- [ ] **Step 5: Commit**

```bash
cd ..
git add tree-sitter-march/
git commit -m "feat: add type rules to grammar"
```

---

## Task 5: Patterns

**Files:**
- Modify: `tree-sitter-march/grammar.js`
- Create: `tree-sitter-march/test/corpus/patterns.txt`

- [ ] **Step 1: Write corpus test `test/corpus/patterns.txt`**

```
================================================================================
Wildcard pattern
================================================================================
mod Foo do fn f(x) do match x with | _ -> 1 end end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def name: (identifier)
    (wildcard_pattern)
    (match_expression
      (identifier)
      (match_arm (wildcard_pattern) (integer))))))

================================================================================
Variable pattern
================================================================================
mod Foo do fn f(x) do match x with | n -> n end end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def name: (identifier)
    (variable_pattern)
    (match_expression
      (identifier)
      (match_arm (variable_pattern) (identifier))))))

================================================================================
Constructor pattern with args
================================================================================
mod Foo do fn f(x) do match x with | Some(n) -> n end end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def name: (identifier)
    (variable_pattern)
    (match_expression
      (identifier)
      (match_arm
        (constructor_pattern name: (type_identifier) (variable_pattern))
        (identifier))))))

================================================================================
Tuple pattern
================================================================================
mod Foo do fn f(x) do match x with | (a, b) -> a end end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def name: (identifier)
    (variable_pattern)
    (match_expression
      (identifier)
      (match_arm
        (tuple_pattern (variable_pattern) (variable_pattern))
        (identifier))))))

================================================================================
Negative literal pattern
================================================================================
mod Foo do fn f(x) do match x with | -1 -> true end end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def name: (identifier)
    (variable_pattern)
    (match_expression
      (identifier)
      (match_arm (literal_pattern (integer)) (boolean))))))

================================================================================
Atom pattern bare
================================================================================
mod Foo do fn f(x) do match x with | :ok -> true end end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def name: (identifier)
    (variable_pattern)
    (match_expression
      (identifier)
      (match_arm (atom_pattern (atom_literal)) (boolean))))))
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd tree-sitter-march && tree-sitter test --filter patterns
```

- [ ] **Step 3: Implement pattern rules in `grammar.js`**

```javascript
_pattern: $ => choice(
  $.wildcard_pattern,
  $.variable_pattern,
  $.constructor_pattern,
  $.atom_pattern,
  $.tuple_pattern,
  $.literal_pattern,
),

wildcard_pattern: _ => '_',

// alias() — not a new regex — to avoid duplicate-terminal conflict with `identifier`.
variable_pattern: $ => alias($.identifier, $.variable_pattern),

constructor_pattern: $ => seq(
  field('name', $.type_identifier),
  optional(seq('(', commaSep1($._pattern), ')')),
),

atom_pattern: $ => seq(
  $.atom_literal,
  optional(seq('(', commaSep1($._pattern), ')')),
),

tuple_pattern: $ => seq(
  '(', $._pattern, ',', commaSep1($._pattern), ')',
),

literal_pattern: $ => choice(
  $.integer,
  $.float,
  $.string,
  $.boolean,
  seq('-', $.integer),
  seq('-', $.float),
),
```

Also add `match_expression` and `match_arm` to `_expr`:

```javascript
match_expression: $ => seq(
  'match', field('value', $._expr), 'with',
  optional('|'), pipeSep1($.match_arm),
  'end',
),

match_arm: $ => seq(
  field('pattern', $._pattern),
  optional($.when_guard),
  '->',
  field('body', $.block_body),
),
```

Note: `commaSep`, `commaSep1`, and `pipeSep1` helpers were added to the file in Task 1 Step 3. Do not redefine them here.

- [ ] **Step 4: Regenerate and test**

```bash
cd tree-sitter-march && tree-sitter generate && tree-sitter test --filter patterns
```
Expected: All pattern tests PASS

- [ ] **Step 5: Commit**

```bash
cd ..
git add tree-sitter-march/
git commit -m "feat: add pattern rules to grammar"
```

---

## Task 6: Expressions — operators and control flow

**Files:**
- Modify: `tree-sitter-march/grammar.js`
- Create: `tree-sitter-march/test/corpus/expressions.txt`

- [ ] **Step 1: Write corpus test `test/corpus/expressions.txt`**

```
================================================================================
Binary arithmetic
================================================================================
mod Foo do let x = 1 + 2 * 3 end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (let_declaration (identifier)
    (additive_expression
      (integer)
      (multiplicative_expression (integer) (integer))))))

================================================================================
Pipe operator
================================================================================
mod Foo do let x = a |> f end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (let_declaration (identifier)
    (pipe_expression (identifier) (identifier)))))

================================================================================
Function call
================================================================================
mod Foo do let x = f(1, 2) end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (let_declaration (identifier)
    (call_expression function: (identifier) (integer) (integer)))))

================================================================================
Constructor with args
================================================================================
mod Foo do let x = Some(42) end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (let_declaration (identifier)
    (constructor_expression name: (type_identifier) (integer)))))

================================================================================
Field access
================================================================================
mod Foo do let x = rec.field end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (let_declaration (identifier)
    (field_expression (identifier) (identifier)))))

================================================================================
Lambda single param
================================================================================
mod Foo do let f = fn x -> x end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (let_declaration (identifier)
    (lambda_expression (identifier) (identifier)))))

================================================================================
If then else
================================================================================
mod Foo do let x = if true then 1 else 2 end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (let_declaration (identifier)
    (if_expression (boolean) (integer) (integer)))))

================================================================================
Tuple expression
================================================================================
mod Foo do let x = (1, 2) end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (let_declaration (identifier)
    (tuple_expression (integer) (integer)))))

================================================================================
Record expression
================================================================================
mod Foo do let x = { a = 1, b = 2 } end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (let_declaration (identifier)
    (record_expression
      (record_field (identifier) (integer))
      (record_field (identifier) (integer))))))

================================================================================
Record update
================================================================================
mod Foo do let x = { s with count = 1 } end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (let_declaration (identifier)
    (record_update
      (identifier)
      (record_field (identifier) (integer))))))
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd tree-sitter-march && tree-sitter test --filter expressions
```

- [ ] **Step 3: Implement full expression rules in `grammar.js`**

Replace the stub `_expr` with the full operator precedence hierarchy:

```javascript
_expr: $ => choice(
  $.pipe_expression,
  $.or_expression,
  $.and_expression,
  $.comparison_expression,
  $.additive_expression,
  $.multiplicative_expression,
  $.unary_expression,
  $.call_expression,
  $.constructor_expression,
  $.field_expression,
  $.lambda_expression,
  $.if_expression,
  $.match_expression,
  $.block_expression,
  $.record_expression,
  $.record_update,
  $.tuple_expression,
  $.list_expression,
  $.send_expression,
  $.spawn_expression,
  $.respond_expression,  // RESPOND keyword token — must be a grammar rule, not an identifier
  $.atom,
  $.typed_hole,
  $.integer,
  $.float,
  $.string,
  $.boolean,
  $.identifier,
),

pipe_expression: $ => prec.left(1, seq(
  field('left', $._expr), '|>', field('right', $._expr),
)),
or_expression: $ => prec.left(2, seq(
  field('left', $._expr), '||', field('right', $._expr),
)),
and_expression: $ => prec.left(3, seq(
  field('left', $._expr), '&&', field('right', $._expr),
)),
comparison_expression: $ => prec(4, seq(
  field('left', $._expr),
  field('operator', choice('==', '!=', '<', '>', '<=', '>=')),
  field('right', $._expr),
)),
additive_expression: $ => prec.left(5, seq(
  field('left', $._expr),
  field('operator', choice('+', '-', '++')),
  field('right', $._expr),
)),
multiplicative_expression: $ => prec.left(6, seq(
  field('left', $._expr),
  field('operator', choice('*', '/', '%')),
  field('right', $._expr),
)),
unary_expression: $ => prec.right(7, seq(
  field('operator', choice('-', '!')),
  field('operand', $._expr),
)),

// Postfix / primary
call_expression: $ => prec(8, seq(
  field('function', $._expr),
  '(', optional(commaSep($._expr)), ')',
)),
constructor_expression: $ => prec(8, seq(
  field('name', $.type_identifier),
  '(', optional(commaSep($._expr)), ')',
)),
field_expression: $ => prec.left(9, seq(
  field('object', $._expr), '.', field('field', $.identifier),
)),

// Non-precedence expressions
lambda_expression: $ => seq(
  'fn',
  choice(
    field('param', $.identifier),
    seq('(', optional(commaSep($.fn_param)), ')'),
  ),
  '->',
  field('body', $._expr),
),
if_expression: $ => seq(
  'if', field('condition', $._expr),
  'then', field('then', $._expr),
  'else', field('else', $._expr),
),
block_expression: $ => seq('do', $.block_body, 'end'),
tuple_expression: $ => seq(
  '(', $._expr, ',', commaSep1($._expr), ')',
),
list_expression: $ => seq('[', optional(commaSep($._expr)), ']'),
record_expression: $ => seq(
  '{', commaSep1($.record_field), '}',
),
record_update: $ => seq(
  '{', field('base', $._expr), 'with', commaSep1($.record_field), '}',
),
record_field: $ => seq(field('name', $.identifier), '=', field('value', $._expr)),

send_expression: $ => seq('send', '(', $._expr, ',', $._expr, ')'),
spawn_expression: $ => seq('spawn', '(', $._expr, ')'),
// respond is a keyword in the lexer (RESPOND token); must be a grammar rule, not an identifier call
respond_expression: $ => seq('respond', '(', $._expr, ')'),
```

Also add `$.respond_expression` to the `_expr` choice list above.

- [ ] **Step 4: Regenerate and test**

```bash
cd tree-sitter-march && tree-sitter generate && tree-sitter test --filter expressions
```
Expected: All expression tests PASS

- [ ] **Step 5: Commit**

```bash
cd ..
git add tree-sitter-march/
git commit -m "feat: add full expression rules with operator precedence"
```

---

## Task 7: Declarations — fn, let, type

**Files:**
- Modify: `tree-sitter-march/grammar.js`
- Create: `tree-sitter-march/test/corpus/declarations.txt`

- [ ] **Step 1: Write corpus test `test/corpus/declarations.txt`**

```
================================================================================
Function definition with return type
================================================================================
mod Foo do
fn greet(name : String) : String do
  "hello"
end
end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def
    name: (identifier)
    (named_param name: (identifier) type: (type_constructor))
    return_type: (type_constructor)
    (string))))

================================================================================
Public function
================================================================================
mod Foo do pub fn add(a : Int, b : Int) : Int do a end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def
    name: (identifier)
    (named_param name: (identifier) type: (type_constructor))
    (named_param name: (identifier) type: (type_constructor))
    return_type: (type_constructor)
    (identifier))))

================================================================================
Function with guard
================================================================================
mod Foo do fn f(n : Int) : String when n < 0 do "neg" end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def
    name: (identifier)
    (named_param name: (identifier) type: (type_constructor))
    return_type: (type_constructor)
    (when_guard (comparison_expression (identifier) (integer)))
    (string))))

================================================================================
Function with pattern param
================================================================================
mod Foo do fn fact(0) : Int do 1 end end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (function_def
    name: (identifier)
    (literal_pattern (integer))
    return_type: (type_constructor)
    (integer))))

================================================================================
Type definition variant
================================================================================
mod Foo do type Option(a) = Some(a) | None end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (type_def
    name: (type_identifier)
    (type_params (type_variable))
    (variant name: (type_identifier) (type_variable))
    (variant name: (type_identifier)))))

================================================================================
Type definition record
================================================================================
mod Foo do type Point = { x : Float, y : Float } end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (type_def
    name: (type_identifier)
    (record_type_field name: (identifier) type: (type_constructor))
    (record_type_field name: (identifier) type: (type_constructor)))))

================================================================================
Let declaration with type annotation
================================================================================
mod Foo do let x : Int = 42 end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (let_declaration
    (variable_pattern)
    (type_annotation (type_constructor))
    (integer))))
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd tree-sitter-march && tree-sitter test --filter declarations
```

- [ ] **Step 3: Expand `type_def` rule in `grammar.js`**

```javascript
type_def: $ => seq(
  'type',
  field('name', $.type_identifier),
  optional($.type_params),
  '=',
  choice(
    seq($.variant, repeat(seq('|', $.variant))),  // variant/sum type
    seq('{', commaSep1($.record_type_field), '}'), // record type
    $._type,                                        // alias
  ),
),

type_params: $ => seq('(', commaSep1($.type_variable), ')'),

variant: $ => seq(
  field('name', choice($.type_identifier, $.atom_literal)),
  optional(seq('(', commaSep1($._type), ')')),
),

record_type_field: $ => seq(
  optional(choice('linear', 'affine')),
  field('name', $.identifier), ':', field('type', $._type),
),
```

Also expand `_declaration`:

```javascript
_declaration: $ => choice(
  $.function_def,
  $.let_declaration,
  $.type_def,
  $.actor_def,
  $.interface_def,
  $.impl_def,
  $.sig_def,
  $.extern_def,
  $.protocol_def,
  $.use_declaration,
),
```

Add stubs for the unimplemented declarations (will fill in Task 8):

```javascript
actor_def: $ => seq('actor', $.type_identifier, 'do', 'end'),
interface_def: $ => seq('interface', $.type_identifier, '(', $.type_variable, ')', 'do', 'end'),
impl_def: $ => seq('impl', $._type, 'do', 'end'),
sig_def: $ => seq('sig', $.type_identifier, 'do', 'end'),
extern_def: $ => seq('extern', $.string, ':', $._type, 'do', 'end'),
protocol_def: $ => seq('protocol', $.type_identifier, 'do', 'end'),
use_declaration: $ => seq('use', $.type_identifier, '.', choice(
  seq('{', commaSep1($.identifier), '}'),
  '*',
)),
```

- [ ] **Step 4: Regenerate and test**

```bash
cd tree-sitter-march && tree-sitter generate && tree-sitter test --filter declarations
```
Expected: All declaration tests PASS

- [ ] **Step 5: Commit**

```bash
cd ..
git add tree-sitter-march/
git commit -m "feat: add declaration rules (fn, let, type)"
```

---

## Task 8: Modules, actors, and advanced declarations

**Files:**
- Modify: `tree-sitter-march/grammar.js`
- Create: `tree-sitter-march/test/corpus/modules.txt`
- Create: `tree-sitter-march/test/corpus/actors.txt`
- Create: `tree-sitter-march/test/corpus/advanced.txt`

- [ ] **Step 1: Write `test/corpus/modules.txt`**

```
================================================================================
Module with declarations
================================================================================
mod MyMod do
  type Foo = A | B
  fn f() : Int do 1 end
end
--------------------------------------------------------------------------------
(source_file
  (module_def
    name: (type_identifier)
    (type_def name: (type_identifier)
      (variant name: (type_identifier))
      (variant name: (type_identifier)))
    (function_def name: (identifier)
      return_type: (type_constructor)
      (integer))))

================================================================================
Source file bare declarations (no mod wrapper)
================================================================================
fn f() : Int do 1 end
--------------------------------------------------------------------------------
(source_file
  (function_def name: (identifier)
    return_type: (type_constructor)
    (integer)))
```

- [ ] **Step 2: Write `test/corpus/actors.txt`**

```
================================================================================
Actor definition
================================================================================
mod Foo do
actor Counter do
  state { count : Int }
  init { count = 0 }
  on Increment() do
    { state with count = state.count + 1 }
  end
end
end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (actor_def
    name: (type_identifier)
    (actor_state
      (record_type_field name: (identifier) type: (type_constructor)))
    (actor_init (record_expression (record_field (identifier) (integer))))
    (actor_handler
      name: (type_identifier)
      (record_update
        (identifier)
        (record_field (identifier)
          (additive_expression
            (field_expression (identifier) (identifier))
            (integer))))))))
```

- [ ] **Step 3: Write `test/corpus/advanced.txt`**

```
================================================================================
Interface definition
================================================================================
mod Foo do
interface Eq(a) do
  fn eq : a -> a -> Bool
end
end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (interface_def
    name: (type_identifier)
    param: (type_variable)
    (method_sig
      name: (identifier)
      type: (arrow_type
        (type_variable)
        (arrow_type (type_variable) (type_constructor)))))))

================================================================================
Impl definition
================================================================================
mod Foo do
impl Eq(Int) do
  fn eq(a : Int, b : Int) : Bool do a == b end
end
end
--------------------------------------------------------------------------------
(source_file (module_def name: (type_identifier)
  (impl_def
    interface: (type_identifier)
    type: (type_constructor)
    (function_def
      name: (identifier)
      (named_param name: (identifier) type: (type_constructor))
      (named_param name: (identifier) type: (type_constructor))
      return_type: (type_constructor)
      (comparison_expression (identifier) (identifier))))))
```

- [ ] **Step 4: Run tests — expect failure**

```bash
cd tree-sitter-march && tree-sitter test --filter "modules|actors|advanced"
```

- [ ] **Step 5: Implement full actor, interface, impl, sig, extern, protocol rules**

```javascript
actor_def: $ => seq(
  'actor', field('name', $.type_identifier), 'do',
  $.actor_state,
  $.actor_init,
  repeat($.actor_handler),
  'end',
),
actor_state: $ => seq('state', '{', commaSep($.record_type_field), '}'),
actor_init: $ => seq('init', $._expr),
actor_handler: $ => seq(
  'on', field('name', $.type_identifier),
  '(', optional(commaSep($.fn_param)), ')',
  'do', $.block_body, 'end',
),

interface_def: $ => seq(
  'interface',
  field('name', $.type_identifier),
  '(', field('param', $.type_variable), ')',
  optional(seq(':', commaSep1($.superclass_constraint))),
  'do',
  repeat(choice($.method_sig, $.function_def)),
  'end',
),
superclass_constraint: $ => seq(
  $.type_identifier,
  '(', commaSep1($._type), ')',
),
method_sig: $ => seq('fn', field('name', $.identifier), ':', field('type', $._type)),

impl_def: $ => seq(
  'impl',
  field('interface', $.type_identifier),
  '(',
  field('type', $._type),
  ')',
  optional(seq('for', field('for_type', $._type))),
  optional(seq('when', commaSep1($.superclass_constraint))),
  'do',
  repeat($.function_def),
  'end',
),

sig_def: $ => seq(
  'sig', field('name', $.type_identifier), 'do',
  repeat(choice($.method_sig, $.sig_type_decl)),
  'end',
),
sig_type_decl: $ => seq('type', $.type_identifier, optional($.type_params)),

extern_def: $ => seq(
  'extern', $.string, ':', field('cap_type', $._type), 'do',
  repeat($.extern_fn),
  'end',
),
extern_fn: $ => seq(
  'fn', field('name', $.identifier),
  '(', optional(commaSep($.fn_param)), ')',
  ':', field('return_type', $._type),
),

protocol_def: $ => seq(
  'protocol', field('name', $.type_identifier), 'do',
  repeat($.protocol_step),
  'end',
),
protocol_step: $ => choice(
  $.protocol_message,
  $.protocol_loop,
),
protocol_message: $ => seq(
  field('sender', $.type_identifier), '->',
  field('receiver', $.type_identifier), ':',
  $.type_identifier,
  optional(seq('(', commaSep1($._type), ')')),
),
protocol_loop: $ => seq('loop', 'do', repeat($.protocol_step), 'end'),
```

- [ ] **Step 6: Regenerate and test**

```bash
cd tree-sitter-march && tree-sitter generate && tree-sitter test
```
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
cd ..
git add tree-sitter-march/
git commit -m "feat: add actor, interface, impl, sig, extern, protocol rules"
```

---

## Task 9: Integration test with example files

**Files:** None (read-only test)

- [ ] **Step 1: Parse `examples/list_lib.march`**

```bash
cd tree-sitter-march && tree-sitter parse ../examples/list_lib.march
```
Expected: Full S-expression tree with no `ERROR` or `MISSING` nodes

- [ ] **Step 2: Fix any errors**

If `ERROR` nodes appear, identify the failing rule and fix it. Re-run after each fix:
```bash
tree-sitter generate && tree-sitter parse ../examples/list_lib.march
```

- [ ] **Step 4: Run full test suite**

```bash
tree-sitter test
```
Expected: All tests PASS

- [ ] **Step 5: Commit any fixes**

```bash
cd ..
git add tree-sitter-march/
git commit -m "fix: resolve grammar issues found in integration test"
```

---

## Task 10: Zed extension scaffold

**Files:**
- Create: `zed-march/extension.toml`
- Create: `zed-march/languages/march/config.toml`

- [ ] **Step 1: Create `zed-march/extension.toml`**

Replace `/absolute/path` with the actual absolute path to `tree-sitter-march/`:

```toml
[package]
id = "march"
name = "March"
version = "0.0.1"
schema_version = 1
authors = ["March Contributors"]
description = "March language support for Zed"

[grammars.march]
repository = "file:///Users/80197052/code/march/tree-sitter-march"
rev = ""
```

- [ ] **Step 2: Create `zed-march/languages/march/config.toml`**

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

- [ ] **Step 3: Install in Zed**

Open Zed → command palette (`Cmd+Shift+P`) → "zed: install dev extension" → select the `zed-march/` directory.

- [ ] **Step 4: Open a `.march` file and verify no crash**

Open `examples/list_lib.march` in Zed. The file should open without errors (no highlighting yet — that comes in Task 11).

- [ ] **Step 5: Commit**

```bash
git add zed-march/
git commit -m "feat: scaffold Zed extension for March"
```

---

## Task 11: highlights.scm

**Files:**
- Create: `zed-march/languages/march/highlights.scm`

- [ ] **Step 1: Create `zed-march/languages/march/highlights.scm`**

```scheme
; Keywords — control flow
["fn" "let" "do" "end" "if" "then" "else" "match" "with" "when"] @keyword

; Keywords — declarations
["type" "mod" "actor" "protocol" "interface" "impl" "sig" "extern"] @keyword

; Keywords — modifiers
["pub" "linear" "affine" "unsafe"] @keyword

; Keywords — actor / concurrency
["on" "send" "spawn" "state" "init" "respond" "loop" "for" "as" "use" "where"] @keyword

; Literals
(integer) @number
(float) @number
(string) @string
(boolean) @boolean

; Atoms
(atom_literal) @label
(atom) @label

; Typed holes
(typed_hole) @special

; Comments
(comment) @comment
(block_comment) @comment

; Function definitions
(function_def name: (identifier) @function)

; Function calls
(call_expression function: (identifier) @function.call)

; Type names (in type position)
(type_constructor) @type
(type_application name: (type_identifier) @type)

; Constructor expressions and patterns
(constructor_expression name: (type_identifier) @constructor)
(constructor_pattern name: (type_identifier) @constructor)

; Module names
(module_def name: (type_identifier) @module)

; Actor / interface / impl names
(actor_def name: (type_identifier) @type)
(interface_def name: (type_identifier) @type)
(type_def name: (type_identifier) @type)

; Parameters
(named_param name: (identifier) @variable.parameter)

; Record fields
(record_field name: (identifier) @property)
(record_type_field name: (identifier) @property)

; Variable references
(identifier) @variable

; Operators
["+" "-" "*" "/" "%" "++" "==" "!=" "<" ">" "<=" ">=" "&&" "||" "!" "|>" "->" "="] @operator

; Punctuation
["(" ")" "[" "]" "{" "}"] @punctuation.bracket
["," "." "|" ":"] @punctuation.delimiter
```

- [ ] **Step 2: Reinstall dev extension and verify highlighting**

In Zed command palette: "zed: install dev extension" again to reload.
Open `examples/list_lib.march` — keywords should be highlighted, functions a different colour, types another.

- [ ] **Step 3: Commit**

```bash
git add zed-march/
git commit -m "feat: add syntax highlighting queries"
```

---

## Task 12: brackets.scm, indents.scm, outline.scm

**Files:**
- Create: `zed-march/languages/march/brackets.scm`
- Create: `zed-march/languages/march/indents.scm`
- Create: `zed-march/languages/march/outline.scm`

- [ ] **Step 1: Create `brackets.scm`**

```scheme
("(" @open ")" @close)
("[" @open "]" @close)
("{" @open "}" @close)
("do" @open "end" @close)
```

- [ ] **Step 2: Create `indents.scm`**

Zed indent queries use `@indent` on the opening token and `@outdent` on the closing token (not on the whole node):

```scheme
; Indent after 'do' keyword (covers fn, mod, actor, match, block bodies)
(_ "do" @indent)

; Indent after 'then' and 'else' in if expressions
(_ "then" @indent)
(_ "else" @indent)

; Indent after '->' in match arms and lambdas
(match_arm "->" @indent)
(lambda_expression "->" @indent)

; Outdent on 'end'
(_ "end" @outdent)

; Outdent on closing brackets
(_ ")" @outdent)
(_ "]" @outdent)
(_ "}" @outdent)
```

- [ ] **Step 3: Create `outline.scm`**

```scheme
(function_def
  "fn" @context
  name: (identifier) @name) @item

(type_def
  "type" @context
  name: (type_identifier) @name) @item

(module_def
  "mod" @context
  name: (type_identifier) @name) @item

(actor_def
  "actor" @context
  name: (type_identifier) @name) @item

(interface_def
  "interface" @context
  name: (type_identifier) @name) @item

(impl_def
  "impl" @context
  interface: (type_identifier) @name) @item

(protocol_def
  "protocol" @context
  name: (type_identifier) @name) @item

(let_declaration
  "let" @context
  (variable_pattern) @name) @item
```

- [ ] **Step 4: Reinstall dev extension and verify**

Reload extension in Zed. Verify:
- `do`/`end` jump-to-bracket works (Ctrl+M or editor default)
- Outline panel shows functions, types, modules
- Opening `(` auto-closes

- [ ] **Step 5: Commit**

```bash
git add zed-march/
git commit -m "feat: add brackets, indents, and outline queries"
```

---

## Definition of Done

- [ ] `tree-sitter test` passes all corpus tests
- [ ] `tree-sitter parse examples/list_lib.march` produces no `ERROR` nodes
- [ ] Zed extension installed as dev extension
- [ ] Opening a `.march` file in Zed: keywords highlighted, functions/types/constructors coloured
- [ ] `do`/`end` matched as bracket pair
- [ ] Outline panel shows top-level declarations
