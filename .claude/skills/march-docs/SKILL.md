---
name: march-docs
description: Write March doc strings and doctests (doc annotations rendered by `forge doc`; `march>` doctests run by `forge test`). Use when documenting a public function, type or module, or fixing a doctest.
---

# Writing March docs and doctests

March has two documentation conventions, both living in `.march` source:

1. **Module-level comment** — a `--` comment at the top of the file describing the module's purpose and design.
2. **`doc` annotations** — attached to `fn`, `pfn`, `type`, and `interface` declarations; rendered by `forge doc` as HTML and used as doctest sources.

## Module-level comment

Two to ten lines at the top of the `.march` file, before `mod X do`:

```march
-- List module: immutable singly-linked list operations.
--
-- List(a) = Cons(a, List(a)) Nil  (built-in constructors)
--
-- Design:
-- - Partial functions (head, tail, nth, last) panic on empty/out-of-bounds
-- - Safe variants use the _opt suffix and return Option
-- - fold_left is the primitive; fold_right recurses on the structure
-- - sort uses merge sort

mod List do
  -- ...
end
```

Cover: what the module is, key types it exposes, and non-obvious design decisions (naming conventions, error-signaling policy, algorithm choices).

## Short doc (single sentence)

For simple, self-explanatory functions, use the `doc "..."` form:

```march
doc "Returns the first element. Panics on empty list."
fn head(xs : List(a)) : a do
  match xs do
  Cons(h, _) -> h
  Nil        -> panic("List.head: empty list")
  end
end
```

One line. Describe the behavior and flag partial/panicking behavior.

## Long doc (multi-paragraph + examples)

Use `doc """..."""` for functions that need prose, caveats, or examples:

```march
doc """
Returns [start, start+1, ..., stop-1]. Returns [] if start >= stop.

## Examples

    march> List.range(0, 5)
    [0, 1, 2, 3, 4]
    march> List.range(3, 7)
    [3, 4, 5, 6]
    march> List.range(5, 5)
    []
"""
fn range(start : Int, stop : Int) : List(Int) do
  -- ...
end
```

Markdown is supported in the rendered output: headings, code blocks, inline `code`, bold, italic, links.

## Doctests (`march>` blocks)

Anything under a `## Examples` section with the `march>` prefix is a **doctest**. Doctests are extracted and run automatically by `forge test` — no separate invocation.

### Format

```
    march> <March expression>
    <expected output, exactly as the REPL would print it>
```

- **Indentation** is auto-detected (the block's minimum leading whitespace is stripped), so a doc
  string inside `mod X do` (conventionally 6 spaces) works the same as a top-level one.
- **One expression per `march>` line.** Continue a long expression on `...>` lines:
  ```
  march> List.map(
  ...>   [1, 2, 3],
  ...>   fn x -> x + 1)
  [2, 3, 4]
  ```
- **The next non-`march>` line(s) are the expected output.** Multi-line expected output is fine;
  the extractor reads until the next `march>` or the end of the block.
- **Expected panics:** `** panic: <message>` as the expected line.
- **Setup:** a `march> let x = ...` line with no expected output chains onto the next example, so
  `x` stays bound.
- **No expected output** at all means the example only has to run without crashing.

Doctests run in the interpreter (`march test`, which `forge test` calls).

### What to put in expected output

Exactly what the REPL prints:

```
march> List.singleton(42)
[42]
march> List.singleton("hi")
["hi"]
```

Strings are printed with quotes; lists with brackets; `Option` as `Some(x)` / `None`.

### Doctests that need a stable environment

Doctests run with whatever process env is in place. For env-sensitive code, use a variable name that will never be set:

```
march> Env.get("MARCH_DOCTEST_NEVER_SET", "fallback")
"fallback"
```

Convention: prefix non-existent env vars with `MARCH_DOCTEST_` to signal intent.

### When *not* to add a doctest

- Functions whose output depends on wall-clock time, randomness, or filesystem state (unless you can pin it).
- Functions that panic or require a specific runtime state — put those in a regular `test` block instead.
- Trivial wrappers where the one-line `doc "..."` is self-evident.

## Running

```bash
forge test                        # runs unit tests + property tests + doctests
forge test stdlib/list.march      # just one file's tests and doctests
forge test --filter=range         # match name
```

Doctests count toward the totals and show up alongside unit test failures.

## Rendering HTML

```bash
forge doc                 # project sources -> doc/
forge doc -o site/api     # another output directory
forge doc --private       # include pfn functions
forge doc --stdlib        # the stdlib only
```

Doc strings become rendered module pages; `march>` blocks are shown as code examples (not re-run).

## Conventions checklist

When adding or changing a public function:

- [ ] Has a `doc` annotation (short or long, as appropriate)
- [ ] If it panics, says so in the doc
- [ ] Long docs include `## Examples` with at least one `march>` block
- [ ] At least one doctest covers a non-trivial case (not just the happy path)
- [ ] `forge test` passes after the change

## See also

- `march-test` skill — for unit tests and `Check.all` property tests
- `forge test` flags: `--verbose`, `--filter=PATTERN`, `--skip-properties`
