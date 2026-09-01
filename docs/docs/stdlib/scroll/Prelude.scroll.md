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

## fn with_cap(_c, f) do f(()) end

Runs `f` with `c` installed as the capability its operations dispatch
  through, so a test can substitute an implementation:


  At runtime this simply calls `f` — the capability is consumed by the
  compiler's capability-passing elaboration, which rewrites calls inside `f`
  to route through `c`'s dictionary. Outside a `--test` build the elaboration
  does not run and this is exactly `f(())`.

```march
  with_cap(mock, fn _ -> code_under_test())
```

