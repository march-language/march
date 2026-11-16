Diagnostics: blame on written code, and syntax habits from other languages (2026-11-07)

Probed with common mistakes (the 2026-11-06 literature survey's "never blame what the user
didn't write", and 18 syntax habits from other languages). Carets were already on user code;
what pointed at the desugared program was the wording and a few spans.

## Blame

- **Call arguments.** `Typecheck.call_arg_payload` gives every call of a named function
  (not a protocol step, not an operator) a reason that names the callee, and the parameter
  when `callee_call_arities` knows it: "This is argument #2 of `Option.unwrap_or`, its
  parameter `default`." A pipe desugars `xs |> f(p)` to `f(xs, p)` with the pipe's span,
  which starts at `xs`; that is how a piped call is recognised. Its first argument is "the
  value piped into `f`" and the rest are numbered as written. The reason is
  `RBecause (RFnArg (call_span, i), text)`, so the label is unchanged.
  `report_cap_mismatch` now unwraps `RBecause` to find the call.
- **`let?`.** In `check_expr`'s fallback, `relocate_letq_mismatch` moves the mismatch from
  checking a `let?` / `let*` against its expected type onto the continuation's value
  expression (`letq_value_leaf`). It moves only that check's diagnostics, so an error in
  the binding itself (`let? x = 42`) stays on the binding. `let?`'s own "the code after
  `let?` must produce a Result" check reports at the same expression, so the two merge.
- **Cascades (`Errors.suppress_cascades`).**
  - A `type_mismatch` whose span contains a `callback_arity_mismatch`'s is dropped:
    `List.map(xs, fn (a, b) -> …)` no longer also reports `List(Int -> Int)` against the
    declared result.
  - A `type_mismatch` inside a "does not implement Num" `missing_impl` is dropped.
- **Not done:** weighing all the evidence for a type before blaming (Helium's majority
  vote). `Option.unwrap_or(Some(1), "none")` in a function returning `String` still blames
  `"none"`, not the `1`.

## Syntax habits

Read off the source text in `Parse.syntax_patterns`, which runs before `refine_structural`
on a generic parse error (the grammar is unchanged, so the tree-sitter grammar needs
nothing). Each fix is re-checked as usual (`Fix_verify.verify_parse`).

- **Braces after a header:** `do` for the `{`, and `end` for the matching `}` on its own
  line at the same indentation.
- **`type T = | A | B`:** the leading `|` and its space are deleted.
- **`) -> Int do`:** the arrow is replaced with `:`. The production's own message
  ("expecting `do`") is the trigger.
- **`def` / `defp` / `function` / `func` / `fun`:** replaced with `fn` / `pfn`.
- **A trailing comma before `)` or `]`:** deleted.
- **An operator with nothing on its right:** reported at the operator. No fix.
- **An unclosed `(` / `[` before the error line:** found by `scan_open`, which skips
  comments and strings, `${…}` included. It is reported at the opener. The fix appends the
  closer at the end of that line when the rest of the line balances.
- **Unterminated string (lexer):** reported at the start of the first string that runs
  past its own line, because a missing quote flips every later one; otherwise at the open
  string. The fix (a close quote at the end of that line) is maybe-incorrect: plain
  strings may span lines.
- **`return`:** the typechecker's unbound-variable branch says March has none. The fix
  deletes `return `.
- **`"…" + n`:** the String `missing_impl` gets a note about `++` and `int_to_string`.

Corpus: 15 new cases (syntax_error_7..11, parse_error_21..22, lex_error_1..2,
unbound_variable_2, missing_impl_6..7, type_mismatch_54, type_mismatch_57, callback_arity_mismatch_1).
