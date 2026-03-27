# March Language Extension for Zed

Provides syntax highlighting, indentation, bracket matching, and code outline support for `.march` files in [Zed](https://zed.dev).

## Structure

```
zed-march/
  extension.toml              # Extension metadata + grammar source
  grammars/
    march.wasm                # Compiled tree-sitter grammar (checked in)
    march/                    # tree-sitter-march source (git submodule)
      grammar.js              # Grammar definition
      scanner.c               # Custom scanner (string interpolation, etc.)
      src/                    # Generated parser (parser.c, node-types.json)
      queries/highlights.scm  # Upstream highlight queries
      test/corpus/            # Tree-sitter test cases
  languages/march/
    config.toml               # Language config (suffixes, comments, tabs)
    highlights.scm            # Zed-specific highlight queries
    brackets.scm              # Bracket pairs
    indents.scm               # Indentation rules
    outline.scm               # Symbols for the outline panel
```

## Installing locally

Symlink (or copy) this directory into Zed's extensions folder, then restart Zed:

```bash
ln -sf ~/code/march/zed-march ~/Library/Application\ Support/Zed/extensions/installed/march
```

Restart Zed with **Cmd+Q** and reopen, or **Cmd+Shift+P** -> "zed: quit" then relaunch.

## Updating the plugin during development

When you're actively working on the grammar or highlight queries, here's the workflow to get Zed to pick up your changes.

### Changing highlight queries (fast path)

If you're only editing `.scm` files (highlights, indents, brackets, outline), you don't need to rebuild the grammar. Just edit the file and reload:

1. Edit `languages/march/highlights.scm` (or `indents.scm`, etc.)
2. **Cmd+Shift+P** -> "zed: reload extensions"

That's it. Zed re-reads the query files without a full restart.

### Changing the grammar (full rebuild)

If you've modified `grammar.js` or `scanner.c` in `grammars/march/` (the tree-sitter-march source), you need to regenerate the parser and recompile the WASM:

```bash
cd ~/code/march/zed-march/grammars/march

# 1. Regenerate parser.c / node-types.json from grammar.js
npx tree-sitter generate

# 2. Run the test corpus to catch regressions
npx tree-sitter test

# 3. Build the WASM binary
npx tree-sitter build --wasm -o ../march.wasm
```

Then reload the extension in Zed: **Cmd+Shift+P** -> "zed: reload extensions"

If "reload extensions" doesn't pick up the new WASM, do a full restart (**Cmd+Q** and reopen).

### Keeping the rev in sync

`extension.toml` pins the grammar to a specific git rev:

```toml
[grammars.march]
repository = "file:///Users/80197052/code/march/tree-sitter-march"
rev = "a0867c85..."
```

When developing locally with the symlink approach, Zed uses the WASM file directly from `grammars/march.wasm`, so the `rev` field doesn't gate what you see. But if you're distributing the extension or using Zed's built-in extension installer, update `rev` to match your latest tree-sitter-march commit:

```bash
cd ~/code/march/zed-march/grammars/march
git rev-parse HEAD
# Copy that hash into extension.toml's rev field
```

## Auto-formatting

The March formatter can be used as an external formatter in Zed. Add this to your Zed settings (`Cmd+,` → open JSON):

```json
{
  "languages": {
    "March": {
      "formatter": {
        "external": {
          "command": "forge",
          "arguments": ["format", "--stdin"]
        }
      },
      "format_on_save": "on"
    }
  }
}
```

This runs `forge format --stdin` on every save, which reads the buffer from stdin and writes the formatted output to stdout. Make sure `forge` is in your `PATH`.

### Gotchas

- **Zed caches grammars aggressively.** If "reload extensions" doesn't seem to work after a WASM rebuild, quit Zed fully and relaunch. In rare cases, clear the cache: `rm -rf ~/Library/Caches/Zed/extensions/march`.
- **The `.wasm` is checked in.** After rebuilding, remember to commit the updated `grammars/march.wasm` so others get the new parser without needing tree-sitter-cli.
- **`src/parser.c` is generated.** Don't hand-edit it. Edit `grammar.js` and run `tree-sitter generate`.
- **Two `highlights.scm` files exist.** The one in `grammars/march/queries/` is the tree-sitter-native version; the one in `languages/march/` is the Zed-specific version that Zed actually uses. Edit the latter for Zed highlighting.
- **tree-sitter-cli version matters.** If you get WASM build errors, make sure your `tree-sitter-cli` version matches what Zed expects. Check Zed's docs for the recommended version.
