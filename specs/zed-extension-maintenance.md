# Zed Extension Maintenance

## Directory structure

```
tree-sitter-march/   ← grammar source (its own git repo — required by Zed)
  grammar.js         ← edit this to change the grammar
  src/parser.c       ← generated; must be committed for Zed to compile
  src/scanner.c      ← hand-written external scanner (nested block comments)
  src/tree_sitter/   ← tree-sitter runtime headers; must be committed
  test/corpus/       ← corpus tests (.txt files)
  queries/           ← highlights.scm copy (for tree-sitter CLI highlighting)

zed-march/           ← Zed extension (tracked in main repo)
  extension.toml     ← points at tree-sitter-march repo + commit SHA
  languages/march/
    config.toml      ← language config (file suffix, comment syntax, brackets)
    highlights.scm   ← syntax highlighting captures
    brackets.scm     ← bracket pair matching (do/end, parens, etc.)
    indents.scm      ← auto-indent rules
    outline.scm      ← outline panel (functions, types, modules)
```

## Changing the grammar

1. Edit `tree-sitter-march/grammar.js`
2. Regenerate the C parser:
   ```bash
   cd tree-sitter-march
   tree-sitter generate
   ```
3. Run corpus tests:
   ```bash
   tree-sitter test
   ```
4. Parse the example file to catch regressions:
   ```bash
   tree-sitter parse ../examples/list_lib.march
   ```
   Expected: no `ERROR` or `MISSING` nodes.
5. Commit **inside** the tree-sitter-march repo:
   ```bash
   git add -A
   git commit -m "feat: ..."
   git rev-parse HEAD   # copy this SHA
   ```
6. Update the SHA in `zed-march/extension.toml`:
   ```toml
   [grammars.march]
   repository = "file:///Users/80197052/code/march/tree-sitter-march"
   rev = "<new SHA here>"
   ```
7. Reinstall in Zed: `Cmd+Shift+P` → **zed: install dev extension** → select `zed-march/`
8. Commit the extension.toml change in the main repo:
   ```bash
   cd ..
   git add tree-sitter-march/ zed-march/extension.toml
   git commit -m "chore: update grammar rev"
   ```

## Changing highlight / indent / outline queries

Edit files in `zed-march/languages/march/`. No grammar rebuild needed.

Reinstall in Zed to pick up changes. No SHA update required (Zed reads these
directly from the extension directory, not from the grammar repo).

If you also want `tree-sitter highlight` to work from the CLI, keep
`tree-sitter-march/queries/highlights.scm` in sync manually (or symlink it).

## Adding corpus tests

Corpus tests live in `tree-sitter-march/test/corpus/*.txt`. Format:

```
================================================================================
Test name
================================================================================
source code here
--------------------------------------------------------------------------------
(expected s-expression)
```

Run with `tree-sitter test` or filter with `tree-sitter test --filter <name>`.

To see the actual parse output for a snippet:
```bash
echo 'mod Foo do let x = 1 end' | tree-sitter parse /dev/stdin
# or write to a temp file:
echo 'let x = 1' > /tmp/t.march && tree-sitter parse /tmp/t.march
```

## Key grammar constraints

- **Only two regex terminals for names**: `identifier` (`/[a-z_][a-zA-Z0-9_']*/`)
  and `type_identifier` (`/[A-Z][a-zA-Z0-9_']*/`). Never add a third regex that
  matches the same character class — it causes duplicate-terminal conflicts.
- **Contextual name roles** (`variable_pattern`, `type_constructor`,
  `type_variable`) are created with `alias()`, not new regex rules.
- **Aliased nodes double-nest** in the CST: e.g. `(variable_pattern
  (variable_pattern))`. Highlight queries should target the inner node.
- `state`, `init`, `on` are NOT in the `reserved` list because they are also
  valid identifiers in expression position (e.g. `{ state with count = 1 }`).

## Operator precedence reference

| Level | Operators          | Associativity |
|-------|--------------------|---------------|
| 1     | `\|>`              | left          |
| 2     | `\|\|`             | left          |
| 3     | `&&`               | left          |
| 4     | `==` `!=` `<` `>` `<=` `>=` | left |
| 5     | `+` `-` `++`       | left          |
| 6     | `*` `/` `%`        | left          |
| 7     | `-` `!` (unary)    | right         |
| 8     | `f()` `Con()`      | —             |
| 9     | `.field`           | left          |

## Two git repos

`tree-sitter-march/` contains a nested git repo (`.git/`) distinct from the
main march repo. This is required because Zed checks out grammar repos by SHA.

- Changes to grammar files must be committed in **both** repos to stay in sync:
  the inner repo (for Zed) and the outer repo (for the march project history).
- `src/parser.c` and `src/tree_sitter/` are tracked in the inner repo but
  gitignored in the outer repo (they are generated/runtime files).
