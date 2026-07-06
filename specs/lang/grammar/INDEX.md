# Grammar corpus index (Task 1 seed: p01–p02 parse, r01–r02 reject)

Navigable map of the resolved-grammar conformance corpus: each program in
this directory (`specs/lang/grammar/parse/*.march`,
`specs/lang/grammar/reject/*.march`) to the grammar section/rule it anchors
in `specs/lang/grammar.md`. See that document for the full per-rule prose.

## The `--check` parse/reject harness model

Like `specs/lang/types/` (the static-semantics corpus), this corpus has only
**one** parser to check against — it runs identically regardless of whether
the pipeline continues to `eval` or `--compile`. The anchor is the compiler's
own `--check` mode (`march --check file.march`: exit 0 = parsed [+ typed],
exit 1 + a diagnostic = rejected):

- **`parse/*.march`** — must parse: `march --check file.march` must exit
  **0**. Kept **well-typed** so exit 0 unambiguously isolates "this parsed"
  (not "this parsed but then failed to typecheck") — the tricky part these
  programs are meant to exercise is the *syntax*, so the types are kept
  trivial.
- **`reject/*.march`** — must fail to **parse**: `march --check file.march`
  must exit **1**, AND its output must contain the exact substring named in
  the program's own first-line annotation, `-- EXPECT-ERROR: <substring>`.
  The pinned substring must be a **parse** diagnostic (e.g. `` I don't
  recognize `then` here ``, `I got stuck here`), never a type error — this
  corpus isolates the parser, not the typechecker. Some substrings are
  menhir's generic fallback message rather than a bespoke one; that is
  expected and intentional (see `grammar.md` §1's honesty note on this).

Run the whole corpus:

```
MARCH_BIN=$PWD/_build/default/bin/main.exe bash specs/lang/grammar/check_grammar.sh
```

Exit 0 iff every program behaves as declared (currently 4/4 — 2 parse, 2
reject; Task 1 seed only).

**Naming note:** this corpus uses `parse/` + `reject/` (not `accept/` +
`reject/` like `types/`) — an intentional, acknowledged divergence: "must
parse" reads truer for a grammar corpus than "must accept". The harness
shape is otherwise identical to `types/check_types.sh`.

## Program index

| Program | Grammar section / rule anchored | What it witnesses |
|---|---|---|
| [`parse/p01_block_newline_separation.march`](parse/p01_block_newline_separation.march) | §3.3 (newline-glom, `Block` context, baseline swallow-by-default) | A plain `fn ... do ... end` body with three `let`-bound block expressions separated only by source newlines; every `NL` between them is deleted by `token_filter` before menhir sees the stream (no context is `Match`, so the "swallow by default" rule applies throughout). Prints the correct sum, evidencing the block parsed as three sequential statements, not one runaway expression. |
| [`parse/p02_match_multi_expr_arms.march`](parse/p02_match_multi_expr_arms.march) | §3.3 (newline-glom inside `Match`, the arm-boundary lookahead), §3.4 (`is_pattern_start` used as the lookahead's pre-filter) | A `match` with two arms, each a **multi-expression body** (`let`/`let`/final-expr). Exercises every branch of the arm-boundary state machine: `NL` after `ARROW` suppressed, `NL` after each internal `let` suppressed (bails on `LET` at depth 0), and the `NL` before the second arm's `Square(side) ->` correctly emitted as the arm separator (lookahead reaches `ARROW` at depth 0 after crossing the `LPAREN...RPAREN` of `Square(side)`). Run (non-`--check`) it prints `36` then `16` — the *only* correct output if the arm boundary resolved exactly where §3.3 says it does, so this is a value-witness, not just a parse-witness. |
| [`reject/r01_then_keyword_rejected.march`](reject/r01_then_keyword_rejected.march) | §1 honesty note / (future §4) — `THEN` is a lexer token with no production that can ever complete a parse | `if true then ... else ... end` — `then` only appears in `parser.mly`'s dedicated error-recovery production (`IF; _c = expr; THEN; ...; error`), which unconditionally raises a diagnostic; there is no path from `THEN` to a value. Captured live: `` I don't recognize `then` here — March uses do/end blocks instead. `` |
| [`reject/r02_record_pattern_in_arm_unreachable.march`](reject/r02_record_pattern_in_arm_unreachable.march) | §3.4 (cross-check corollary: `LBRACE` is correctly absent from `is_pattern_start`, since no pattern production starts with it) / (future §6) — `PatRecord` has no surface production | `match 1 do { x } -> x end` — a record-shaped pattern in an arm position. `simple_pattern`/`pattern` have no production beginning with `LBRACE`, so `token_filter`'s `is_pattern_start` (§3.4) correctly does not list it either, and menhir rejects the construct outright with its generic fallback. Captured live: `I got stuck here`. This double-checks as a §3.4 witness now and will be promoted to the primary reachability witness for `PatRecord` in Task 4's §6. |

Later tasks (2–5) will extend this table with the expression-precedence,
block/statement, pattern/type, and declaration-form corpora; see
`specs/plans/2026-07-06-resolved-grammar-plan.md` for the task breakdown.
