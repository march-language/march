# Elm-Style Error Messages — Audit and Improvement Plan

**Goal:** Every diagnostic the March compiler emits should be friendly, specific, and
actionable — no jargon, no internal compiler terms, always pointing at the right code
and suggesting a concrete fix. Elm is the gold standard. This document audits every
diagnostic, rates it, and gives an improved version.

---

## Current State

### Diagnostic counts by file

| File | Errors | Warnings | Hints | Total |
|------|--------|----------|-------|-------|
| `lib/lexer/lexer.mll` | 5 | 0 | 0 | 5 |
| `lib/parser/parser.mly` | ~25 | 0 | 0 | ~25 |
| `lib/desugar/desugar.ml` | 1 | 0 | 0 | 1 |
| `lib/typecheck/typecheck.ml` | ~65 | ~8 | ~5 | ~78 |
| `lib/eval/eval.ml` | ~120 | 0 | 0 | ~120 |
| `bin/main.ml` (import resolver) | 3 | 0 | 0 | 3 |
| **Total** | **~219** | **~8** | **~5** | **~232** |

### Quality distribution

| Grade | Count | Description |
|-------|-------|-------------|
| A — Elm-quality already | ~35 | Parser "I was expecting" messages; type mismatch; linearity; typed hole |
| B — Good but missing detail | ~40 | Some typecheck errors have the right tone but lack code examples |
| C — Terse but usable | ~80 | Session type errors, protocol errors, constructor errors |
| D — Internal / cryptic | ~77 | Most eval builtins ("print_int: expected int"), desugar failwith |

The eval builtins are the largest single category. They are D-grade because they look like
internal assertions rather than user-facing errors. In a compiled path they would never
fire (the type checker would catch them), but in the tree-walking interpreter they can
surface to users when stdlib type errors slip through.

---

## Message Style Guide

### Do

- **Name the thing** the user wrote. "I cannot find a `greet` variable" beats
  "unbound variable".
- **Show expected and found** for every type mismatch:
  `I expected String but this is Int.`
- **Use "I was expecting" for syntax errors** — same as Elm. It makes the message
  feel like the compiler is talking to you, not logging at you.
- **Suggest the fix in code**, not prose. "Try `let x = …`" beats "use a let binding".
- **Show where the expectation came from**: "This is the declared return type of
  `process_request`." points at the annotation, not the mismatch site.
- **Offer Did-you-mean** whenever a name isn't found and there are near-matches.
- **Spell out linearity rules briefly** — not everyone knows what "linear" means.
  "Linear values must be used exactly once — they cannot be copied or ignored."
- **Tell the user what's missing**, not just that something is wrong. For missing
  fields, say which field. For missing match arms, say which case.
- **Use backticks for code, never quotes**: `` `foo` `` not `"foo"`.
- **End notes with a period.** Don't leave fragments.

### Don't

- ❌ Use the word "unification", "subsumption", "instantiation", "skolem" in user messages.
- ❌ Print raw OCaml `Failure` or `Invalid_argument` exceptions to users.
- ❌ Say "expected two ints" without naming the operator.
- ❌ Say "expected non-empty list" without saying which function was called.
- ❌ Include internal constructor names like `TArrow`, `TCon`, `TRecord`.
- ❌ Print bare `parse error` without showing what was found and what was expected.
- ❌ Use the "arity mismatch" jargon — say "expects N arguments, but you gave it M".
- ❌ Emit `panic: %s` at users unless it's a user-called `panic()`.

### Multi-line error format

For errors that need a code snippet:

```
-- TYPE MISMATCH -------------------------------- src/main.march

Something is off with the body of `process_request`.

5 |     response = 42
              ^^

I expected String (this function's return type) but found Int.

Note: The return type is declared on line 2:
2 |   fn process_request(req: Request): String do
                                        ^^^^^^
```

Key rules:
1. Header bar with error kind and file name (already done by `render_parse_error`)
2. One-sentence summary of the problem
3. Source snippet with underline — gutter format `N | `
4. "I expected X but found Y" on its own line
5. "Note:" lines for additional context
6. Blank line between sections

---

## Priority Tiers

- **P1** — Hits every beginner on their first program (type mismatches, unknown variable,
  parse errors, unused binding, non-exhaustive match)
- **P2** — Hits every intermediate user (constructor arity, linearity, import errors,
  function arity, interface/impl errors)
- **P3** — Expert / niche (session types, protocol validation, capability system,
  actor handlers, MPST errors)
- **P4** — Runtime-only eval errors (should rarely be seen; the type checker should catch
  these first; improve them last or by improving the type checker)

---

## Full Message Catalogue with Improvements

### LEXER — `lib/lexer/lexer.mll`

---

#### LEX-1 · Unexpected character · P1

**Current:**
```
Unexpected character: %c
```
**Rating:** C — tells you what char but not what's valid there.

**Improved:**
```
-- UNEXPECTED CHARACTER -------------------------------- file.march

I ran into a character I don't know how to handle here:

3 |   let x = 42 @ 10
                  ^

`@` is not a valid character in March.

Note: If you meant to use an operator, the arithmetic operators are
`+`, `-`, `*`, `/`, and `%`. For bitwise ops, see `int_and`, `int_or`.
```

The hint should be populated dynamically when a commonly-confused character is used:
- `@` → "Did you mean `++` for string concatenation, or an atom like `:at`?"
- `$` → "Variables in March don't need a `$` prefix — just write the name."
- `#` → "March uses `--` for comments, not `#`."
- `\` → "Lambda syntax is `fn x -> expr`, not `\x -> expr`."
- `;` → "March doesn't use semicolons to separate statements — use newlines."

---

#### LEX-2 · Unterminated block comment · P2

**Current:**
```
Unterminated block comment
```
**Rating:** C — no pointer to where the comment opened.

**Improved:**
```
-- UNTERMINATED COMMENT -------------------------------- file.march

I reached the end of the file while inside a block comment.

5 |   {- This comment was opened here
       ^

Block comments in March use `{-` to open and `-}` to close. Add a
closing `-}` at the end of your comment.
```

**Implementation note:** The lexer needs to track the opening position of the
block comment and pass it through to the error.

---

#### LEX-3 · Unterminated string literal · P1

**Current:**
```
Unterminated string literal
```
**Rating:** C — no pointer to opening `"`.

**Improved:**
```
-- UNTERMINATED STRING ---------------------------------- file.march

I reached the end of the line while inside a string literal.

7 |   let msg = "Hello, world
                 ^

Strings in March must be closed before the end of the line. Add a
closing `"` to finish the string.

Note: For multi-line strings, use triple quotes:
    let msg = """
        Hello,
        world
    """
```

---

#### LEX-4 · Unterminated triple-quoted string · P2

**Current:**
```
Unterminated triple-quoted string
```
**Rating:** C — no pointer to opening `"""`.

**Improved:**
```
-- UNTERMINATED STRING ---------------------------------- file.march

I reached the end of the file while inside a triple-quoted string.

12 |   let banner = """
                    ^^^

Triple-quoted strings in March must end with `"""`. Add a closing
`"""` on a new line:

    let banner = """
        Hello, world
    """
```

---

#### LEX-5 · Unterminated string interpolation · P2

**Current:**
```
Unterminated string interpolation
```
**Rating:** C — no pointer to opening `{`.

**Improved:**
```
-- UNTERMINATED INTERPOLATION -------------------------- file.march

I reached the end of the line while inside a string interpolation.

4 |   let s = "Hello, {name
                        ^

String interpolations use `{expr}` inside a string. Add a closing
`}` to finish the interpolation:

    let s = "Hello, {name}"
```

---

### PARSER — `lib/parser/parser.mly`

The parser messages are **already Elm-quality** (A grade) — they use "I was expecting X"
framing, include hint blocks with concrete code examples, and underline the problem token.
Only a few need polishing.

---

#### PAR-1 · Missing `do` for module body · A

**Current:** `"I was expecting `do` to start the module body here:"`
with hint `"mod Name do\n    ...\nend"`

**Status:** No change needed. ✓

---

#### PAR-2 · File doesn't start with `mod` · A

**Current:** `"March programs must start with a module declaration:"`
with hint `"mod Main do\n    fn main() do\n        ...\n    end\nend"`

**Status:** No change needed. ✓

---

#### PAR-3 · Parse error in declaration (generic recovery) · C → B

**Current:**
```
Parse error in declaration
```
**Rating:** C — tells you nothing about what was found or expected.

**Improved:**
```
I ran into something unexpected while reading a declaration.

Declarations in a module body can be:
- `fn name(params) do ... end`
- `let name = expr`
- `type Name = Variant | Variant(Type)`
- `mod Name do ... end`
- `use Module`

If you're continuing a previous expression, check for a missing `end`
or mismatched parentheses above this line.
```

---

#### PAR-4 · `if` without `else` · A

**Current:** `"March 'if' expressions always need an 'else' branch:"`
with hint showing both branches.

**Status:** No change needed. ✓

---

#### PAR-5 · Lambda missing `->` · A

**Current:** `"I was expecting '->' to start the lambda body here:"`

**Status:** No change needed. ✓

---

#### PAR-6 · Match arm missing `->` · B → A

**Current:** `"I was expecting '->' in the match arm here:"`

**Improved** (add hint):
```
MESSAGE: "I was expecting `->` in the match arm here:"
HINT: "Pattern -> result_expression"
```
The hint is currently missing for this case. Adding it makes it consistent with the
other parser errors.

---

#### PAR-7 · REPL `name = ...` without `let` · A

**Current:** `"unexpected '%s = ...' -- did you mean 'let %s = ...'?"`

**Status:** No change needed (good REPL UX). ✓

---

### DESUGAR — `lib/desugar/desugar.ml`

---

#### DSG-1 · Module has both `main()` and `app` declaration · C → B

**Current (OCaml `failwith`, not a proper diagnostic):**
```
A module cannot define both main() and an app declaration
```
**Rating:** C — this is a bare `failwith` that gets caught and printed as an unformatted
exception, not a proper `Errors.error` with span and source location.

**Improved:** Convert to a proper `Errors.error` with span pointing at both declarations:
```
-- CONFLICTING DECLARATIONS --------------------------- file.march

A module can have a `main()` function or an `app` declaration,
but not both.

12 |   fn main() do
          ^^^^

23 |   app MyApp do
          ^^^^^

Remove one of them. Use `app` when you want a supervised actor system.
Use `fn main()` for a simple top-level program.
```

**Implementation:** Replace the `failwith` in `desugar.ml` with an `Errors.error`
call that records both spans.

---

### TYPECHECK — `lib/typecheck/typecheck.ml`

---

#### TC-1 · Type mismatch (core) · A

**Current:** Uses `report_mismatch` which produces "I expected X but found Y." with
contextual notes and secondary labels. This is already Elm-quality.

**Status:** No change needed. ✓

---

#### TC-2 · Unknown type name · C → B

**Current:**
```
Unknown type '%s'
```
**Rating:** C — no suggestion, no context.

**Improved:**
```
-- UNKNOWN TYPE -------------------------------------- file.march

I cannot find a type called `Colour`.

5 |   fn paint(c: Colour): Unit do
                   ^^^^^^

Note: The types in scope are: Int, Float, Bool, String, List, Option,
Result, Map, Set, ...

If you meant `Color` (US spelling), March uses whatever spelling
you declared. If this is a custom type, make sure it's declared in
this file or imported with `use`.
```

**Implementation:** Pass the environment's type table to the error site, build a
`did_you_mean` suggestion from the known types (same levenshtein distance logic as
the variable not-found case).

---

#### TC-3 · Type constructor wrong arity · C → B

**Current:**
```
type '%s' expects %d type parameter(s), got %d
type '%s' is parameterized; expected %d type argument(s)
```
**Rating:** C — technically correct but dry.

**Improved:**
```
-- TYPE ARGUMENT MISMATCH ----------------------------- file.march

`Result` expects 2 type arguments, but you gave it 1.

8 |   fn load(): Result(String) do
                        ^^^^^^

`Result` holds a success value and an error value, so it needs both:

    Result(SuccessType, ErrorType)

For example:
    fn load(): Result(String, String) do
    fn load(): Result(User, Error) do
```

---

#### TC-4 · Unknown constructor in pattern or expression · C → B

**Current:**
```
Unknown constructor '%s' in pattern
Unknown constructor '%s'
```
**Rating:** C — no suggestion.

**Improved:**
```
-- UNKNOWN CONSTRUCTOR -------------------------------- file.march

I cannot find a constructor called `Succ` in any type.

14 |   match n do
15 |     Succ(x) -> x + 1
          ^^^^

Note: These names look similar: `Some`, `None`, `Ok`, `Err`, `Nil`,
`Cons`.

If `Succ` belongs to a type you defined, make sure the type is
declared above this point. Constructors are case-sensitive.
```

---

#### TC-5 · Ambiguous constructor (defined in multiple types) · B

**Current (Hint):**
```
Constructor '%s' is defined in multiple types: %s. Consider qualifying: TypeName.%s
```
**Rating:** B — gives the right advice but could be clearer.

**Improved:**
```
-- AMBIGUOUS CONSTRUCTOR ------------------------------ file.march

`Send` is defined in multiple types and I'm not sure which one you mean.

9 |   match msg do
10 |    Send(data) -> ...
         ^^^^

It could be:
- `Protocol.Send`
- `Command.Send`

Qualify the constructor to disambiguate:

    Protocol.Send(data) -> ...
```

---

#### TC-6 · Constructor arity mismatch in pattern · C → B

**Current:**
```
Constructor '%s' expects %d argument(s) but pattern has %d
```
**Rating:** C — no example.

**Improved:**
```
-- WRONG NUMBER OF FIELDS ----------------------------- file.march

The `Ok` constructor holds 1 value, but this pattern has 2.

7 |   Ok(value, extra) -> value
      ^^^^^^^^^^^^^^^^^

`Ok` is declared as `Ok(a)` — it wraps a single value. Fix the
pattern:

    Ok(value) -> value
```

---

#### TC-7 · Constructor arity mismatch in expression · C → B

**Current:**
```
Constructor '%s' expects %d argument(s) but got %d
```
**Rating:** C — same as TC-6.

**Improved:**
```
-- WRONG NUMBER OF ARGUMENTS -------------------------- file.march

`Some` expects 1 argument, but you gave it 2.

12 |   let x = Some(1, 2)
                ^^^^^^^^^

`Some` wraps a single value. Did you mean to wrap a tuple?

    Some((1, 2))    -- wraps the pair as one value
    Some(1)         -- just the first value
```

---

#### TC-8 · Non-exhaustive pattern match · B → A

**Current:**
```
Non-exhaustive pattern match — missing: %s
Non-exhaustive pattern match
```
**Rating:** B — gives the missing cases but no example of what to add.

**Improved:**
```
-- INCOMPLETE MATCH ----------------------------------- file.march

This match is missing cases. The `Color` type has 3 variants, but
only 2 are covered:

5 |   match color do
      ^^^^^^^^^^^^^

Missing:
- `Blue`

Add the missing case:

    match color do
      Red   -> "red"
      Green -> "green"
      Blue  -> "blue"   -- add this
    end

Or use a wildcard to handle all remaining cases:

    match color do
      Red -> "red"
      _   -> "other"
    end
```

---

#### TC-9 · Variable not found · A

**Current:**
```
I cannot find a '%s' variable.
```
with Did-you-mean suggestions generated from nearby names.

**Status:** Good. Consider adding:
- If the name is a capitalized word (potential constructor or module), suggest
  checking whether it's a type or constructor name.
- If a module import is missing, suggest `use ModuleName`.

---

#### TC-10 · Unused let binding · B → A

**Current (Warning, code: "unused_binding"):**
```
'%s' is not used (prefix with _ to suppress)
```
**Rating:** B — the advice is right but the framing is terse.

**Improved:**
```
-- UNUSED BINDING ------------------------------------- file.march

`total` is never used.

8 |   let total = List.sum(prices)
          ^^^^^

If this is intentional, prefix the name with `_` to silence this
warning:

    let _total = List.sum(prices)

If you meant to use `total` later, check that you spelled it
correctly everywhere it's used.
```

---

#### TC-11 · Unused function return value · B → A

**Current (Warning):**
```
expression result is unused
```
**Rating:** C — no pointer to what expression, no suggestion.

**Improved:**
```
-- UNUSED VALUE --------------------------------------- file.march

The return value of this expression is being thrown away.

14 |   List.map(transform, items)
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^

If this function has a side effect you want but no return value you
need, assign the result to `_`:

    let _ = List.map(transform, items)

If you expected this to modify `items` in place, note that March
functions return new values — they don't mutate their arguments.
```

---

#### TC-12 · Calling a non-function · C → B

**Current:**
```
this expression is not a function, it has type %s
```
**Rating:** C — "this expression" is vague; type may be cryptic.

**Improved:**
```
-- NOT A FUNCTION ------------------------------------- file.march

`count` is not a function — it's an Int.

11 |   count(items)
       ^^^^^

You cannot call a value that isn't a function. Did you mean to use
`count` directly, or call a different function with `items`?

    List.count(items)   -- if you wanted the List function
    count               -- if you just wanted the value
```

---

#### TC-13 · Function called with wrong number of arguments · B → A

**Current:**
```
function expects %d argument(s), but got %d
```
**Rating:** B — correct but needs to name the function and identify the extra/missing arg.

**Improved (extra args):**
```
-- EXTRA ARGUMENT ------------------------------------- file.march

`add` expects 2 arguments, but you gave it 3.

7 |   add(1, 2, 3)
              ^^^^ this argument is extra

`add` is declared as:
    fn add(a: Int, b: Int): Int

Remove the extra argument, or check if you meant a different function.
```

**Improved (missing args):**
```
-- MISSING ARGUMENT ----------------------------------- file.march

`add` expects 2 arguments, but you only gave it 1.

7 |   add(1)
      ^^^^^^

`add` is declared as:
    fn add(a: Int, b: Int): Int

You still need to provide: b (Int)

Note: If you want a partially-applied function, March uses explicit
lambdas:
    fn (b) -> add(1, b)
```

---

#### TC-14 · Multi-head function clause arity mismatch · C → B

**Current:**
```
clause for '%s' has %d params but first clause has %d
```
**Rating:** C — no example.

**Improved:**
```
-- CLAUSE ARITY MISMATCH ------------------------------ file.march

All clauses of `greet` must have the same number of parameters, but
this clause has 2 while the first clause has 1.

8 |   fn greet(name, title) do
                     ^^^^^ unexpected extra parameter

The first clause:
4 |   fn greet(name) do
      ^^^^^^^^^^^^^^^^

Either add the missing parameter to the first clause, or remove the
extra one from this clause.
```

---

#### TC-15 · Function has no clauses · C → B

**Current:**
```
function '%s' has no clauses
```
**Rating:** C — should never happen normally but if it does, needs context.

**Improved:**
```
-- EMPTY FUNCTION ------------------------------------- file.march

`process` has no body.

12 |   fn process

A function needs at least one clause with a body:

    fn process(input: String): String do
        input
    end
```

---

#### TC-16 · Linear value used more than once · A

**Current:**
```
The linear value `%s` is used more than once here.
Linear values must be consumed exactly once — they cannot be copied or ignored.
```
**Rating:** A — explains the rule. ✓

Consider adding a note pointing to the first use:
```
Note: `conn` was first used here:
5 |   Chan.send(conn, msg)
      ^^^^^^^^^^^^^^^^^^^^
```

---

#### TC-17 · Linear value never used · A

**Current:**
```
The linear value `%s` was never used.
Linear values must be consumed exactly once — did you mean to pass it somewhere?
```
**Rating:** A — explains the rule and gives a hint. ✓

---

#### TC-18 · Linear value captured by closure · B → A

**Current:**
```
Linear value '%s' is captured by a closure, which may duplicate it
```
**Rating:** B — the grammar is a bit terse, and "duplicate" may not be obvious.

**Improved:**
```
-- LINEAR VALUE IN CLOSURE ---------------------------- file.march

`conn` is a linear value, but it's captured by a closure that might
be called more than once.

9 |   let handler = fn () -> Chan.send(conn, msg)
                                       ^^^^

Linear values must be used exactly once. A closure could be called
multiple times, which would use `conn` more than once.

To fix this: pass `conn` as a parameter to the closure instead of
capturing it:

    let handler = fn (c) -> Chan.send(c, msg)
    handler(conn)
```

---

#### TC-19 · @tailcall function has non-tail recursive call · B → A

**Current:**
```
function '%s' is marked @tailcall but has a non-tail recursive call
```
**Rating:** B — tells you the problem but not where the non-tail call is or how to fix it.

**Improved:**
```
-- NON-TAIL RECURSIVE CALL ---------------------------- file.march

`sum` is marked `@tailcall`, but this recursive call is not in tail
position.

12 |   n + sum(rest)
           ^^^^^^^^^

A tail call is the very last thing a function does — no further
computation can happen after it returns. Here, `+` happens after
`sum(rest)` returns, so it's not a tail call.

Rewrite using an accumulator parameter:

    @tailcall
    fn sum(list, acc) do
        match list do
          Nil -> acc
          Cons(x, rest) -> sum(rest, acc + x)
        end
    end
    fn sum(list) do sum(list, 0) end
```

---

#### TC-20 · @tailcall suggestion warnings · B

**Current:**
```
function '%s' has a recursive call that is not in tail position; consider @tailcall
function '%s' is tail-recursive; consider adding @tailcall
```
**Rating:** B — useful but could show the declaration line.

These are warnings so the bar is lower. The messages are reasonable as-is.

---

#### TC-21 · Field access on type without fields · C → B

**Current:**
```
type '%s' has no field '%s'
```
**Rating:** C — no suggestion.

**Improved:**
```
-- UNKNOWN FIELD -------------------------------------- file.march

`User` has no field called `age`.

5 |   user.age
           ^^^

`User` has these fields: `name` (String), `email` (String), `id` (Int)

Did you mean `user.name`?
```

---

#### TC-22 · Record update on non-record · C → B

**Current:**
```
record update on a non-record type: %s
```
**Rating:** C — "record update" jargon.

**Improved:**
```
-- INVALID UPDATE ------------------------------------- file.march

`{ ... | ... }` syntax only works on record values, but this has
type `Int`.

8 |   { n | value = 42 }
        ^

If `n` is supposed to be a record, check its type declaration. If you
meant to create a new record, use:

    { value = 42 }
```

---

#### TC-23 · Record update on field that doesn't exist · C → B

**Current:**
```
record type '%s' has no field '%s'
```
**Rating:** C — same as TC-21.

**Improved:**
```
-- UNKNOWN FIELD -------------------------------------- file.march

`Point` has no field called `z`.

12 |   { p | z = 0.0 }
                ^

`Point` has: `x` (Float), `y` (Float)

If you want to add a new field to `Point`, update its type declaration:

    type Point = { x: Float, y: Float, z: Float }
```

---

#### TC-24 · Import: module not found · C → B

**Current:**
```
module '%s' not found in scope
Module `%s` not found (looked for `%s` in the source directory)
```
**Rating:** C — doesn't tell you what IS in scope or where it looked.

**Improved:**
```
-- UNKNOWN MODULE ------------------------------------- file.march

I cannot find a module called `Colour`.

3 |   use Colour
          ^^^^^^

I looked for:
- `colour.march` in the same directory as this file
- The built-in stdlib modules (List, Map, String, …)

These module names look similar:
- `Color` — not found

If this is a stdlib module, check the exact spelling. Available
stdlib modules include: List, Map, Set, Array, Option, Result,
String, Math, File, Dir, Http, Json, …
```

---

#### TC-25 · Import: name not in module · C → B

**Current:**
```
name '%s' not found in module '%s'
'%s' is not exported by module '%s'
```
**Rating:** C — no suggestion of what IS exported.

**Improved:**
```
-- NOT EXPORTED --------------------------------------- file.march

`String` does not export `split_by`.

4 |   use String.{split_by}
                  ^^^^^^^^

`String` exports these functions that look similar:
- `split` (splits on a separator string)
- `split_first` (splits on first occurrence)

Did you mean `String.split`?
```

---

#### TC-26 · Circular import · C → B

**Current:**
```
Circular import: module `%s` imports itself (directly or transitively)
```
**Rating:** C — doesn't show the cycle path.

**Improved:**
```
-- CIRCULAR IMPORT ------------------------------------ file.march

This import creates a circular dependency.

2 |   use Orders
          ^^^^^^

The import chain is:
  Inventory → Orders → Inventory (cycle!)

March modules cannot import each other in a circle. To break the
cycle, extract the shared code into a third module that both can
import.
```

---

#### TC-27 · Capability: extern without `needs` · B → A

**Current:**
```
extern '%s' requires capability %s but module does not declare `needs %s`
```
**Rating:** B — already tells you exactly what to add.

**Improved (add the fix inline):**
```
-- MISSING CAPABILITY --------------------------------- file.march

Using `file_read` requires the `IO.FileRead` capability, but this
module doesn't declare it.

8 |   file_read(path)
      ^^^^^^^^^

Add `needs IO.FileRead` to the top of your module:

    mod MyModule do
        needs IO.FileRead

        ...
    end
```

---

#### TC-28 · Capability: unused `needs` · B

**Current (Warning):**
```
module declares `needs %s` but never uses it
```
**Rating:** B — clear enough for a warning.

---

#### TC-29 · Interface: unknown interface · C → B

**Current:**
```
unknown interface '%s' in constraint
unknown interface '%s'
```
**Rating:** C — no suggestion.

**Improved:**
```
-- UNKNOWN INTERFACE ---------------------------------- file.march

I cannot find an interface called `Printable`.

5 |   fn show[T: Printable](x: T): String do
                  ^^^^^^^^^

If `Printable` is defined in another module, import it first:

    use MyModule.{Printable}

The built-in interfaces are: Eq, Ord, Show, Hash, Iterable.
```

---

#### TC-30 · Impl: missing required superclass · C → B

**Current:**
```
impl %s(%s) requires %s(%s) but no such impl exists
```
**Rating:** C — terse.

**Improved:**
```
-- MISSING IMPL --------------------------------------- file.march

To implement `Ord` for `Color`, you first need an `Eq` implementation,
but none exists.

12 |   impl Ord(Color) do
            ^^^^^^^^^^^

`Ord` requires `Eq` as a prerequisite. Add an `Eq` implementation:

    impl Eq(Color) do
        fn equal(a, b) do
            match (a, b) do
              (Red, Red) -> true
              (Blue, Blue) -> true
              _ -> false
            end
        end
    end
```

---

#### TC-31 · Impl: method not in interface · C → B

**Current:**
```
method '%s' is not declared in interface '%s'
```
**Rating:** C — no suggestion.

**Improved:**
```
-- EXTRA METHOD --------------------------------------- file.march

`stringify` is not part of the `Show` interface, so this impl cannot
define it.

18 |   fn stringify(x) do ...
          ^^^^^^^^^

The `Show` interface declares these methods: `show`

Remove `stringify` from this impl, or check if you meant `show`.
```

---

#### TC-32 · Impl: missing required method · C → B

**Current:**
```
impl %s(%s) is missing method '%s'
```
**Rating:** C — correct but dry.

**Improved:**
```
-- INCOMPLETE IMPL ------------------------------------ file.march

This `Show` implementation for `Color` is missing the `show` method.

5 |   impl Show(Color) do
      ^^^^^^^^^^^^^^^^^

`Show` requires you to implement: `show`

Add the missing method:

    impl Show(Color) do
        fn show(c) do
            match c do
              Red   -> "Red"
              Green -> "Green"
              Blue  -> "Blue"
            end
        end
    end
```

---

#### TC-33 · Protocol: empty protocol · C → B

**Current:**
```
protocol '%s' is empty — must have at least one message step
```
**Rating:** C — accurate but no example.

**Improved:**
```
-- EMPTY PROTOCOL ------------------------------------- file.march

The `Ping` protocol has no steps.

3 |   protocol Ping between Client, Server do
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

A protocol needs at least one message step. For example:

    protocol Ping between Client, Server do
        Client -> Server: PingMsg
        Server -> Client: PongMsg
    end
```

---

#### TC-34 · Session type errors (Chan.send/recv/close/choose/offer) · D → C

These are a large family of errors that fire when the session type protocol is violated.
They are currently very terse:

```
Chan.send expects a Chan argument, but got %s
Chan.send: next protocol step for '%s' is not a send
Chan.send: expected message of type %s, but got %s
Chan.send: session is complete — no more sends allowed
```

**General approach:** For session type errors, always tell the user:
1. What step the protocol is currently at
2. What operation they're trying to do
3. What they should do instead

**Improved (wrong step type):**
```
-- PROTOCOL STEP MISMATCH ----------------------------- file.march

The next step in the `Ping` protocol is to receive a message, but
you're trying to send one.

9 |   Chan.send(conn, PingMsg)
      ^^^^^^^^^^^^^^^^^^^^^^^^^

The `Ping` protocol for the `Client` role at this point expects:
    receive PongMsg

To receive instead:
    let (conn2, pong) = Chan.recv(conn)
```

**Improved (session complete):**
```
-- PROTOCOL COMPLETE ---------------------------------- file.march

The `Ping` protocol is finished, but you're trying to send another
message.

15 |   Chan.send(conn, ExtraMsg)
       ^^^^^^^^^^^^^^^^^^^^^^^^^^

The session on `conn` has completed all its steps. You should call
`Chan.close(conn)` instead of sending more messages.
```

**Improved (wrong message type):**
```
-- WRONG MESSAGE TYPE --------------------------------- file.march

The `Ping` protocol expects a `PongMsg` here, but you're sending an
`Int`.

12 |   Chan.send(conn, 42)
                        ^^

The next step in the protocol is:
    send PongMsg

Try:
    Chan.send(conn, PongMsg)
```

---

#### TC-35 · Typed hole · A

**Current:**
```
FOUND HOLE

This hole has type: %s

Local bindings in scope:
  name : Type
  ...
```
**Rating:** A — excellent. Shows the type, shows the local scope. ✓

---

#### TC-36 · Actor handler errors · C → B

**Current:**
```
handler for '%s' must return the actor state type
handler for '%s' expects %d parameter(s) but message has %d field(s)
handler param '%s' has type %s but message field has type %s
```
**Rating:** C — terse, no example.

**Improved (return type):**
```
-- HANDLER RETURN TYPE -------------------------------- file.march

The `on Tick` handler must return the actor's state type (`Counter`),
but it returns `Unit`.

24 |   on Tick do
25 |       print("tick")
26 |   end

Actor handlers must return the updated state. Add a return expression:

    on Tick do
        print("tick")
        state    -- return the (possibly updated) state
    end
```

**Improved (parameter count):**
```
-- HANDLER PARAMETERS --------------------------------- file.march

The `on Click(x, y)` handler has 2 parameters, but the `Click`
message only has 1 field.

18 |   on Click(x, y) do
                    ^ unexpected

`Click` is declared as: `Click(Int)` (1 field)

Match the number of parameters to the message's fields:

    on Click(x) do
        ...
    end
```

---

### EVAL — `lib/eval/eval.ml`

The eval errors are mostly **D-grade** runtime assertions that look like internal errors.
Since the tree-walking interpreter is the primary execution mode, these are user-visible.

The fundamental improvement strategy for eval errors:

1. **Name the function** being called — "print_int: expected Int" → "`print_int` expects
   an Int argument, but got Bool"
2. **Show the value** that was passed, not just its type
3. **Explain why** this can't work — often because the value is the wrong type
4. **Suggest what to do** — use a different function, convert the type, etc.

Since there are ~120 eval errors following the same pattern, this section groups them
by category and gives one improved template per category, then lists all messages that
follow the pattern.

---

#### EVAL-1 · Unbound variable at runtime · C → A

**Current:**
```
unbound variable: %s
```
**Rating:** C — this should be caught by the type checker; when it reaches eval it means
there's a type checker bug. The message should reflect this.

**Improved:**
```
Runtime error: unbound variable `x`.

This should have been caught during type-checking. If you're seeing
this message, please report it as a compiler bug at:
    https://github.com/march-lang/march/issues
```

---

#### EVAL-2 · Applied non-function value · C → B

**Current:**
```
applied non-function value: %s
```
**Rating:** C — "applied" is compiler jargon.

**Improved:**
```
Runtime error: `42` is not a function and cannot be called.

This value has type Int. If you meant to call a function that returns
42, try `let result = myFunction()`.
```

---

#### EVAL-3 · Arity mismatch at runtime · C → B

**Current:**
```
arity mismatch: expected %d args, got %d
```
**Rating:** C — "arity mismatch" is jargon.

**Improved:**
```
Runtime error: this function expects %d arguments, but was called with %d.
```

---

#### EVAL-4 · FFI stub not registered · C → B

**Current:**
```
extern %s:%s -- no OCaml stub registered for this symbol (FFI is only available in the compiled path)
```
**Rating:** C — internal language. Good for a note, but the main message should be clearer.

**Improved:**
```
The extern function `%s.%s` is not available in interpreted mode.

Foreign functions (declared with `extern`) only work when compiling
March to native code with `march compile`. The tree-walking interpreter
cannot call external C functions.
```

---

#### EVAL-5 · Arithmetic operators with wrong types · D → C

**Current (all follow this pattern):**
```
builtin %s: expected two ints
builtin %s: expected two numbers of the same type
builtin %s: incompatible operand types
division by zero
```
**Rating:** D — "builtin" is an internal term.

**Template for improved arithmetic errors:**
```
Runtime error: `+` expects two Int values, but the right side is %s.

If you meant floating-point addition, use `+.` instead:
    3.14 +. 2.71
```

Specific operator improvements:

| Current | Improved |
|---------|----------|
| `builtin +: expected two ints` | `` `+` expects two Int values. For Float addition, use `+.` `` |
| `builtin -: expected two ints` | `` `−` expects two Int values. For Float subtraction, use `-.` `` |
| `builtin *: expected two ints` | `` `*` expects two Int values. For Float multiplication, use `*.` `` |
| `division by zero` | `Division by zero. Check that the divisor is not 0 before dividing.` |
| `builtin %: expected two non-zero ints` | `` `%` expects two non-zero Int values. The second operand (divisor) was 0. `` |
| `builtin +.: expected two floats` | `` `+.` expects two Float values. For Int addition, use `+`. `` |
| `builtin &&: expected two bools` | `` `&&` expects two Bool values, but found %s. `` |
| `builtin not: expected bool` | `` `not` expects a Bool value, but found %s. `` |
| `builtin ++: expected two strings` | `` `++` expects two String values. For concatenation with non-strings, convert first: `int_to_string(n) ++ s`. `` |

---

#### EVAL-6 · Standard library builtins with wrong argument type · D → C

These ~60+ messages all follow the pattern `"name: expected type"`.

**Current:**
```
print_int: expected int
head: expected non-empty list
Option.unwrap: called on None
Result.unwrap: called on Err(%s)
```

**Template for all stdlib type errors:**
```
`print_int` expects an Int, but got %s.

To print other types, use:
- `print_float` for Float
- `print` for String
- `bool_to_string(b) |> print` for Bool
```

Specific high-priority ones:

| Current | Improved |
|---------|----------|
| `head: expected non-empty list` | `` `List.head` called on an empty list. Check `is_nil(list)` before calling `head`. `` |
| `tail: expected non-empty list` | `` `List.tail` called on an empty list. Check `is_nil(list)` before calling `tail`. `` |
| `Option.unwrap: called on None` | `` `Option.unwrap` called on `None`. Use `Option.unwrap_or(default, opt)` to provide a fallback, or pattern match: `match opt do Some(v) -> v | None -> default end` `` |
| `Result.unwrap: called on Err(%s)` | `` `Result.unwrap` called on `Err(%s)`. Use `Result.unwrap_or(default, result)` or handle the error with a match. `` |
| `string_slice: expected string, int, int` | `` `String.slice` expects (String, Int, Int) — the string, start index, and end index. `` |

---

#### EVAL-7 · Actor and runtime system errors · C → B

**Current:**
```
self: called outside an actor handler
receive: mailbox is empty (async receive requires a non-empty mailbox)
receive: called outside an actor handler
spawn: unknown actor '%s'
send: first argument must be a Pid or Cap, got %s
```

**Improved templates:**

```
-- SELF OUTSIDE HANDLER
`self()` can only be called inside an actor's `on` handler, not in
regular functions. If you need the actor's Pid, pass it as a parameter.

-- RECEIVE OUTSIDE HANDLER
`receive` can only be called inside an actor's `on` handler.

-- EMPTY MAILBOX
`receive` was called but the mailbox is empty. In asynchronous mode,
`receive` expects at least one pending message. Either send a message
first or use pattern matching in an `on` handler instead.

-- UNKNOWN ACTOR
`spawn` cannot find an actor called `%s`. Make sure the actor is
declared in this module with `actor %s do ... end`.
```

---

#### EVAL-8 · Channel runtime errors · C → B

**Current:**
```
Chan.send: channel %s#%d is already closed
Chan.recv: channel %s#%d is already closed
Chan.close: channel %s#%d was already closed
```

**Improved:**
```
`Chan.send` failed: this channel is already closed.

Once a channel session is complete and `Chan.close` has been called,
no more messages can be sent. Check that you're not reusing a closed
channel endpoint.
```

---

#### EVAL-9 · Assert failures · B → A

**Current:**
```
assert failed: %s != %s
assert: condition was false
assert: expected Bool, got %s
```

**Improved:**
```
-- ASSERTION FAILED
assert(a == b) failed:
  left:  %s
  right: %s

-- CONDITION FALSE
assert: this condition evaluated to false.

-- NOT BOOL
assert: expected a Bool expression, but this has type %s.
```

---

#### EVAL-10 · Panic/todo/unreachable · A

**Current:**
```
panic: %s
panic
todo: %s
todo: not yet implemented
unreachable: reached unreachable code
```
**Rating:** A for `panic` and `unreachable` — these are user-invoked intentional errors.
`todo` is fine too. No change needed. ✓

---

### MAIN.ML — `bin/main.ml` (import resolver error reporting)

The import resolver uses `Printf.eprintf "%s:%d:%d: error: %s\n"` for structured
errors, which is IDE-friendly but unfriendly for human readers. The underlying messages
are already covered above (TC-24, TC-26). The improvement here is the **rendering layer**.

#### MAIN-1 · Render diagnostic with source snippet · B → A

Currently, import errors are printed as:
```
foo.march:12:5: error: Module `Bar` not found (looked for `bar.march` in the source directory)
```

This should use the same `render_parse_error` / source-snippet format used by the parser.
The import resolver already has `span` information — it should use the full diagnostic
renderer so the error looks like:

```
-- UNKNOWN MODULE ------------------------------------------ foo.march

I cannot find a module called `Bar`.

12 |   use Bar
           ^^^

I looked for `bar.march` in the same directory.
```

**Implementation:** The resolver already produces `(mod_name, span, msg)` tuples.
Pass these through `Errors.report ctx ~span msg` so they get rendered the same way
as typecheck errors.

---

## Implementation Plan

### Phase 1 — Infrastructure (required before anything else)

**1.1 Centralize diagnostic rendering**

Currently there are two rendering paths:
- `render_parse_error` (in `errors.ml`) — Elm-style header bar, gutter, underline
- `Printf.eprintf "%s:%d:%d: error: %s\n"` — IDE-style, used in `main.ml` for import
  errors and test runner

Unify them. Add a `render_diagnostic` function to `errors.ml` that takes a `diagnostic`
and the source text and produces the full Elm-style output. Use this everywhere.

```ocaml
val render_diagnostic : src:string -> ?filename:string -> diagnostic -> string
```

**1.2 Thread source text through the pipeline**

The typecheck errors currently don't include source snippets. The source text is
available in `main.ml`. Thread it through to `Typecheck.check_module` so that
`report_mismatch` can show the relevant source lines.

**1.3 Add `Did-you-mean` utility**

Implement a general Levenshtein/trigram distance function and export it from `errors.ml`:

```ocaml
val did_you_mean : string -> string list -> string list
(** [did_you_mean name candidates] returns up to 3 names from [candidates]
    that are closest to [name] by edit distance. *)
```

Use this in:
- Unknown type name (TC-2)
- Unknown constructor (TC-4)
- Unknown interface (TC-29)
- Import not found (TC-24, TC-25)

**1.4 Extend `diagnostic` type with a `code_snippet` field**

```ocaml
type diagnostic = {
  severity : severity;
  span : Ast.span;
  message : string;
  labels : label list;
  notes : string list;
  code : string option;
  suggestion : suggestion option;   (* NEW: machine-readable fix suggestion *)
}

and suggestion = {
  sug_span : Ast.span;
  sug_replacement : string;
  sug_description : string;
}
```

This enables:
- IDE quickfix integration
- Automated test assertions on fixes
- Future `--fix` flag

---

### Phase 2 — P1 errors (highest user impact)

Implement improvements for these first — every beginner hits them:

1. **TC-2** — Unknown type name (add did-you-mean)
2. **TC-4** — Unknown constructor (add did-you-mean, show example)
3. **TC-8** — Non-exhaustive match (show missing cases as examples)
4. **TC-10** — Unused binding (add code example with `_` prefix)
5. **TC-11** — Unused return value (add `let _ =` suggestion)
6. **TC-12** — Not a function (name the non-function, suggest alternatives)
7. **TC-13** — Wrong argument count (show which arg is extra/missing)
8. **LEX-1** — Unexpected character (add commonly-confused char hints)
9. **LEX-3** — Unterminated string (add triple-quote hint)
10. **DSG-1** — Both main() and app (convert to proper `Errors.error`)

---

### Phase 3 — P2 errors

11. **TC-3** — Type constructor arity (add example)
12. **TC-6, TC-7** — Constructor arity in pattern/expression (add example)
13. **TC-14** — Multi-head clause arity mismatch
14. **TC-21, TC-23** — Field access / record update (show valid fields)
15. **TC-24, TC-25** — Import errors (show search path, suggest alternatives)
16. **TC-26** — Circular import (show the cycle)
17. **TC-27** — Capability missing (add `needs X` code snippet)
18. **TC-30, TC-31, TC-32** — Impl errors (add concrete examples)
19. **LEX-2, LEX-4, LEX-5** — Unterminated comment/interpolation
20. **PAR-3** — Generic parse error in declaration
21. **PAR-6** — Match arm missing `->` (add hint)

---

### Phase 4 — P3 / session type errors

22. **TC-34** — Session type errors (show protocol step, suggest next action)
23. **TC-33** — Protocol validation (add examples)
24. **TC-36** — Actor handler errors (add return type example)
25. **TC-28** — Unused capability warning

---

### Phase 5 — P4 / eval errors

26. **EVAL-5** — Arithmetic type errors (name the operator)
27. **EVAL-6** — Stdlib type errors (template: name the function, show type, suggest)
28. **EVAL-4** — FFI stub not registered (clearer message)
29. **EVAL-7** — Actor system runtime errors
30. **EVAL-8** — Channel runtime errors
31. **EVAL-9** — Assert failures

---

## Testing Strategy

### Add error snapshot tests

For each improved message, add a `test/errors/` directory with:
- `test_tc_01_unknown_type.march` — source that triggers the error
- `test_tc_01_unknown_type.expected` — the expected error output

The test runner compares compiler output against the expected file. This prevents
regression and documents the expected format.

### Test each message category

The alcotest suite in `test/test_march.ml` should include a section for error messages:

```ocaml
let test_unknown_type () =
  let src = {|
    mod Test do
      fn foo(): Colour do 1 end
    end
  |} in
  let output = compile_to_error src in
  check string "has did-you-mean" true
    (String.contains output "Color")

let () = run "error messages" [
  "unknown type did-you-mean", `Quick, test_unknown_type;
  ...
]
```

---

## Summary by Priority

| Pri | Message | File | Grade Now | Grade After |
|-----|---------|------|-----------|-------------|
| P1 | Type mismatch | typecheck.ml | A | A |
| P1 | Variable not found | typecheck.ml | A | A |
| P1 | Parser "I was expecting" | parser.mly | A | A |
| P1 | Unknown type | typecheck.ml | C | B |
| P1 | Unknown constructor | typecheck.ml | C | B |
| P1 | Non-exhaustive match | typecheck.ml | B | A |
| P1 | Unused binding | typecheck.ml | B | A |
| P1 | Unused return value | typecheck.ml | C | B |
| P1 | Not a function | typecheck.ml | C | B |
| P1 | Wrong arg count | typecheck.ml | B | A |
| P1 | Unexpected character | lexer.mll | C | B |
| P1 | Unterminated string | lexer.mll | C | B |
| P1 | Both main+app | desugar.ml | D | B |
| P2 | Constructor arity | typecheck.ml | C | B |
| P2 | Clause arity mismatch | typecheck.ml | C | B |
| P2 | Field not found | typecheck.ml | C | B |
| P2 | Import not found | typecheck.ml | C | B |
| P2 | Circular import | main.ml | C | B |
| P2 | Missing capability | typecheck.ml | B | A |
| P2 | Impl errors (3 kinds) | typecheck.ml | C | B |
| P2 | Unterminated comment | lexer.mll | C | B |
| P3 | Session type errors | typecheck.ml | C | C |
| P3 | Protocol errors | typecheck.ml | C | C |
| P3 | Actor handler errors | typecheck.ml | C | B |
| P3 | Linear in closure | typecheck.ml | B | A |
| P3 | @tailcall non-tail | typecheck.ml | B | A |
| P4 | Arithmetic type errors | eval.ml | D | C |
| P4 | Stdlib builtin errors | eval.ml | D | C |
| P4 | Option/Result unwrap | eval.ml | C | B |
| P4 | Actor runtime errors | eval.ml | C | B |
| P4 | Channel runtime errors | eval.ml | C | B |
| P4 | Assert failures | eval.ml | B | A |

---

## Appendix: Messages That Already Meet the Elm Bar

These need no changes:

1. **Type mismatch** (`report_mismatch`) — uses "I expected X but found Y", contextual
   labels, secondary spans, argument-level mismatch notes. Excellent.

2. **Variable not found** — "I cannot find a `foo` variable. These names look similar:
   `bar`, `baz`." with Did-you-mean. Excellent.

3. **Typed hole** — "FOUND HOLE / This hole has type: T / Local bindings in scope: ..."
   showing all in-scope variables and their types. Excellent.

4. **All parser "I was expecting" messages** — with code example hints. Excellent.

5. **Linearity: used more than once** — explains the rule, names the value, actionable.

6. **Linearity: never used** — explains the rule with a specific suggestion.

7. **Panic / todo / unreachable** — user-invoked, correct behavior.

8. **REPL `x = ...` without `let`** — immediate correction with example. Excellent.

9. **Missing `else` branch** — explains why `if` needs `else`, gives example.

10. **Protocol: self-send warning** — explains the issue clearly.
