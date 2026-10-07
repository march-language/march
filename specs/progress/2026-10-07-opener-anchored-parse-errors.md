# DONE 2026-10-07: D1, opener-anchored parse errors

Diagnostics plan (`specs/plans/diagnostics-and-triage-plan.md`) §5. Builds on
D0 (`Parse`, the one entry point), D3 (codes) and D7 (the golden corpus the
acceptance cases live in).

## The problem

A missing `end` is reported where the grammar gives up, which is after the
mistake, usually at the end of the file or the next `fn`. The `else if … end`
pitfall produced "Parse error in declaration" with the caret at the next
declaration.

## What landed

- **`Token_filter.make_with_state`** (`lib/parser/token_filter.ml`): wraps
  `make` and watches the filtered token stream, the one the parser sees. It
  keeps a stack of open constructs, each with its opening keyword's position.
  - **Pending-opener register.** An opening keyword (`if fn pfn match mod actor
    app with test describe setup setup_all supervise extern protocol loop
    on_start on_stop sig transitions interface impl`) is held in a register
    keyed by paren depth. The next `do` at that depth consumes it.
  - **`->` clears it.** An arrow-form lambda (`fn x -> body`) and a match arm
    never get a `do`.
  - **Bare `do`.** A `do` with nothing pending opens a "do" construct.
  - **`choose by R: … end`** (parser.mly:1072) is the one construct that closes
    with `end` but has no `do`. It is pushed at its `by`.
  - **`end`** pops the innermost construct and records the pair. An `end` with
    nothing open is remembered as stray.
  - **`else`** marks the innermost `if`. An `if` right after that `else` marks it
    as heading an `else if` chain.
  - **Declaration keywords** seen while something is open are recorded with a
    snapshot of the open constructs.
  - **`match` and `choose` positions.** The filter peeks one raw token after
    these two and re-queues it, so the lexbuf already points past them when they
    are returned. Their own positions are captured below the filter.
    `make` itself is unchanged, so the parser's view, and every AST span, is
    byte-identical.
- **`Parse.run`** uses it. When a parse fails with the lookahead at EOF or a
  declaration keyword, it picks the culprit and overrides the diagnostic's
  **span and fix only**, in this order of evidence:
  0. a declaration keyword on a later line at or left of an open construct's
     indentation (a `fn` written while the previous one is open);
  1. an `end` on a later line left of its opener's indentation, which belongs
     to an outer block (the `else if` chain);
  2. the innermost open construct.
  If 0 and 1 both apply, whichever comes first in the file wins.
  - **Messages.** A message an error production chose is kept. menhir's
    "I got stuck here" and the uninformative production "Parse error in
    declaration" are replaced. They become "This `if` (line N) needs its own
    `end`: the `end` on line M belongs to an outer block." or "This `fn` (line N)
    has no matching `end`."
  - **Notes.** "I only noticed at <where>." When the culprit is an `if` heading
    an `else if` chain, the chain note is added ("each `if` needs its own `end`:
    a two-branch chain ends `end end`").
  - **Fix.** An `FInsert` of one `end` per construct that must close, each at
    its opener's indentation, placed after the last non-blank line before the
    evidence.
  - **Stray `end`.** An `end` with nothing open gets an `FDelete` of its line
    when the line holds only `end`. A production message there is kept.
- Every suggested fix was applied and re-checked: all eight acceptance programs
  parse after their fix.

## Acceptance (D7 corpus, `test/errors/`)

| case | file |
|---|---|
| `else if` chain one `end` short | `parse_error_11` |
| missing `end` on `fn` | `parse_error_12` |
| missing `end` on `match` | `parse_error_13` |
| missing `end` on `mod` | `parse_error_14` |
| stray `end` | `parse_error_15` |
| negative: arrow-form lambda inside an `if` | `parse_error_16` |
| negative: `with … else` arms | `syntax_error_6` |
| negative: `choose by` block | `parse_error_17` |

The 269 existing corpus entries are unchanged: no reject program hit the
override. `check_grammar.sh`: 55/55. The `Parse` caret tests in `test_compiler.ml`
pass unchanged.

`lib/parser/parser.mly` and `lexer.mll` are untouched (only `token_filter.ml`
and `parse.ml`), so the tree-sitter rule does not fire.

## Known limits

- The evidence is indentation-based; a file with unconventional indentation
  falls back to rule 2 (innermost open construct). Only the span, notes and fix
  are affected, never whether a program parses.
- Opening keywords outside the list above open a bare "do" construct, which is
  still reported, at the `do`.
