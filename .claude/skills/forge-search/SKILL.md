---
name: forge-search
description: Search the March stdlib and a project's dependencies for functions, types and constructors, by name, type signature or doc text, and find every caller of a name. Use before grepping when looking for March code.
---

# forge search

`forge search` is the primary way to find March code. It indexes the stdlib and all dependencies, and supports fuzzy-name, type-signature, and doc-keyword search. **Use this before grepping or reading files when looking for a module, function, or type.**

## Modes

### By name (default)

```bash
forge search List.map
forge search reverse
forge search Json
```

Fuzzy/substring match against module-qualified names.

### By type signature (`-t`)

Hoogle-style search. Find functions matching a given type:

```bash
forge search -t "List(Int) -> Int"
forge search -t "a -> a -> Bool"
forge search -t "Option(a) -> a -> a"
```

Great for: "I know the shape of what I need but not what it's called."

### By doc keyword (`-d`)

Search docstrings:

```bash
forge search -d "encode"
forge search -d "parse json"
```

Useful when the name might not contain the concept you're looking for.

### Who calls it (`--callers`)

Reverse references: every resolved call, constructor use and type use of a name.

```bash
forge search --callers List.map
forge search --callers ClusterNode.start
```

Use it before deleting or renaming a declaration, and before grepping to check whether something
is still used.

### Combinations

You can combine modes — e.g. a doc search narrowed by a name fragment:

```bash
forge search -d "decode" Json
```

## Useful flags

| Flag | Purpose |
|------|---------|
| `-n N`, `--limit=N` | Max results (default 20) |
| `--plain` | Plain text, no colours (for piping or an agent) |
| `--json` | JSON output (for tooling) |
| `--callers=NAME` | Reverse-reference search (above) |
| `--rebuild` | Rebuild the index (run this after installing new deps) |

## Workflow

1. **Start with name search** if you have any idea what it might be called.
2. **Fall back to type search** if you can express the signature but not the name.
3. **Use doc search** for conceptual queries where naming is unclear.
4. **Run `--rebuild`** once after adding a dependency, then normal searches work.

If nothing turns up, try broadening: shorter query, fewer type constraints, check with `-n 50` in case the hit is ranked low.
