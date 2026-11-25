# Prelude

March Standard Library Prelude

Everything in this module is auto-imported into every March program.
These are the most commonly needed functions and types.

Sections:
  1. Diverging (panic, todo, unreachable)
  2. Option helpers
  3. Result helpers
  4. List basics
  5. Combinators (identity, compose, flip, const)
  6. String helpers

Naming overlap with module-qualified APIs is intentional:

- `head`, `tail`, `is_nil`, `length`, `reverse`, `fold_left`,
  `filter`, `map` are all List-typed in the prelude (their
  signatures fix `xs : List(a)`), so `length(xs)` always means
  `List.length(xs)`.  Strings have no `length` — use
  `String.byte_size` / `String.codepoint_count` instead.  The
  absence of a generic `length` prevents silent type confusion.
- `unwrap` and `unwrap_or` operate on `Option(a)`.  For Result
  call `Result.unwrap` directly.

New code should prefer module-qualified calls for readability;
prelude names exist for short scripts and for the few cases (head,
tail, length, reverse) where the unqualified name reads better.
Prelude functions are called unqualified (`length(xs)`, not
`Prelude.length(xs)`).

