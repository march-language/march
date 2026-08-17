---
layout: docs
title: Parsing
nav_order: 18
permalink: /docs/parsing/
---

# Parsing

March ships a parser combinator library, `Parse`, for turning text into
structured data — config formats, wire protocols, small languages, anything
with a grammar you own.

A combinator parser is built out of ordinary values: each piece is a
`Parser(a)`, and you compose small ones into big ones with plain function
calls. There is no separate grammar file and no code generation step.

**What makes this library worth using is the error messages.** Getting a
parser to accept valid input is the easy half; the hard half is telling
someone what is wrong with input that is *invalid*, and most of this page is
about the tools for that.

---

## Your first parser

```march
mod Main do
  needs IO.Console

  pfn is_digit(b : Int) : Bool do b >= 48 && b <= 57 end

  pfn number() : Parse.Parser(String) do
    Parse.take_while1("a number", is_digit)
  end

  fn main(_c : Cap(IO.Console)) : Unit do
    match Parse.run_all(number(), "123") do
      Ok(v)  -> println("parsed " ++ v)
      Err(e) -> println(Parse.render("123", e))
    end
  end
end
```

Two things to notice, because both are load-bearing.

**`Parse.run_all`, not `Parse.run`.** `run` succeeds as soon as *its* parser
is satisfied and silently ignores whatever is left over:

```march
Parse.run(number(), "123xyz")      -- Ok("123")  — the `xyz` is never looked at
Parse.run_all(number(), "123xyz")  -- Err — 1:4: I was expecting end of input
```

`run` is the right call when you are composing a parser into a larger one, or
deliberately parsing a prefix of a stream. At the top level it is almost
always a bug waiting to happen, so reach for `run_all` by default.

**Bytes, not characters.** Predicates take a byte code (`0`–`255`), and
positions are byte offsets. This is what keeps the scanning loop
allocation-free. Offsets are converted to line/column exactly once, at render
time, by `Parse.render` or `Parse.line_col`.

---

## The building blocks

| Combinator | What it matches |
|---|---|
| `lit(s)` | the literal string `s` |
| `byte(code)` | one byte with that code |
| `byte_if(name, pred)` | one byte satisfying `pred` |
| `take_while(pred)` | zero or more bytes, as one String |
| `take_while1(name, pred)` | one or more bytes, as one String |
| `eof()` | only at end of input |
| `pure(x)` | succeeds with `x`, consuming nothing |

Prefer `take_while1` over `many(byte_if(...))` for runs of characters. The
first slices once; the second allocates a list cell per byte and then rebuilds
a string from it.

---

## Sequencing and choice

| Combinator | Meaning |
|---|---|
| `and_then(p, q)` | both, as a tuple `(a, b)` |
| `skip_then(p, q)` | both, keep **`p`**'s value |
| `skip_first(p, q)` | both, keep **`q`**'s value |
| `map(p, f)` | transform the result |
| `alt(p, q)` | try `p`; if it fails *softly*, try `q` |
| `optional(p)` | `Some`/`None`, never fails softly |
| `many(p)` / `many1(p)` | zero-or-more / one-or-more |
| `sep_by(p, s)` / `sep_by1(p, s)` | separated lists |
| `repeat(p, n)` | exactly `n`, failing if fewer |
| `flat_map(p, f)` | choose the next parser *from the parsed value* |

`flat_map` is the one that cannot be expressed by the others: it picks what to
parse next based on what it just parsed, which is what length-prefixed formats
and indentation-sensitive grammars need.

---

## Recursive grammars need `delay`

Parsers are ordinary values built eagerly, so a rule that mentions itself would
recurse while being *constructed* — before reading a byte — and never return.
Wrap the back-edge in `delay`:

```march
pfn expr() : Parse.Parser(String) do
  Parse.alt(
    Parse.take_while1("a number", is_digit),
    Parse.skip_first(Parse.lit("("),
      Parse.skip_then(Parse.delay(fn -> expr()), Parse.lit(")"))))
end

Parse.run_all(expr(), "(((7)))")   -- Ok("7")
```

This is not a March quirk — every combinator library in a strict language needs
the same device. Forget it and you get a hang at construction time, not a parse
error, so it is worth recognising the symptom.

---

## Making errors good

This is the part that earns the library its keep. Three tools, each fixing a
different failure of the default message.

### `label` — replace token soup with a name

Without labels an expected-set degrades into `expected `-`, `0`..`9`, `(`, or
`fn``. Name the class instead:

```march
Parse.label("a number", Parse.take_while1("a number", is_digit))
```

A label only substitutes when the parser failed **without consuming input**. If
it got somewhere first, its inner error is more specific and is kept — so a
label can never hide real progress.

### `ctx` — say which construct you were inside

```march
Parse.ctx("entry", ...)
-- 1:9: I was expecting a number in the entry that started at 1:1
```

`ctx` records where the enclosing construct *started*, which is usually the
information that actually locates the mistake — the error is at 1:9, but the
thing that is wrong began at 1:1.

### `commit` — stop backtracking past the point of no return

By default a failed alternative just backtracks and something else gets tried,
which is how a malformed `if` ends up reported as a bad expression at the wrong
column. `commit` turns a soft failure into a hard one that `alt` will not
swallow.

**Where the commit sits decides whether the good message survives**, and
getting it wrong is silent — both spellings accept all valid input:

```march
-- WRONG: only the `=` itself is committed; a bad VALUE still backtracks
and_then(key, and_then(commit(lit("=")), value))

-- RIGHT: everything after the key is committed
then_commit(key, skip_first(lit("="), value))
```

`then_commit(p, q)` is `and_then(p, commit(q))` — the short spelling of the
right shape. `fence(p)` scopes a commit, converting a hard failure back to a
soft one so one construct's commit cannot abort a sibling.

### All three together

```march
pfn entry() : Parse.Parser((String, String)) do
  Parse.ctx("entry",
    Parse.and_then(
      Parse.skip_then(key(), Parse.skip_then(ws(), Parse.lit("="))),
      Parse.commit(Parse.skip_first(ws(), number()))))
end
```

```
"width=80"      ->  Ok(("width", "80"))
"width=  "      ->  1:9: I was expecting a number in the entry that started at 1:1
"width=80junk"  ->  1:9: I was expecting end of input
```

---

## Reporting every error, not just the first

A config file with three bad keys should report three problems. `recover` turns
a failure into a *value* and resynchronises, so `many` collects the lot in one
pass:

```march
let item = Parse.skip_then(Parse.lit("ok"), Parse.optional(Parse.lit(";")))
let p    = Parse.many(Parse.recover(item, Parse.lit(";")))

Parse.run(p, "ok;BAD;ok;NOPE")
-- Ok([Ok(..), Err(..), Ok(..), Err(..)])  — 2 parsed, 2 errors, one pass
```

The result is the partial AST and the full error list in one structure — no
side channel needed.

**Have the item consume its own separator**, as above. Otherwise the parser is
handed a separator where an item is expected, fails there too, and you get a
spurious error per separator.

---

## Rendering

`Parse.render(input, err)` produces a diagnostic in the compiler's own voice:

```
2:3: I was expecting `end` in the block that started at 1:1
```

`Parse.line_col(input, pos)` gives the raw 1-based `(line, column)` if you want
to build your own.

---

## Known limitation: `let*` does not work with `Parser` yet

[`let*`](/docs/) resolves a type's `flat_map` in the module of the *same name*
as the type. This library's type is `Parser` but its module is `Parse`, so
`let* x = some_parser()` reports that `Parser.flat_map` does not exist.

Use `flat_map` directly for now:

```march
Parse.flat_map(digit(), fn n -> Parse.repeat(item(), n))
```

Resolving this — by renaming the module, or by extending `let*`'s lookup — is
tracked in `specs/todos/2026-08-14-letstar-repl-and-parse-module-gaps.md`.
