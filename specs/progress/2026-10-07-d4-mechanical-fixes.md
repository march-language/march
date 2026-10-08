# DONE 2026-10-07: D4, mechanical fixes for the known pitfalls + the LSP fix adapter

Diagnostics plan (`specs/plans/diagnostics-and-triage-plan.md`) §8. Builds on D0
(`Parse` as the one entry point), D1 (opener-anchored structural errors), D3
(codes) and D7 (the golden corpus, which every fix here lands in).

## What landed

The pitfall table of §8, row by row:

| Pitfall | Code | Where | Fix |
|---|---|---|---|
| `then` after `if` | `then_keyword` | the two `IF … THEN … error` productions | `FReplace` `then` → `do` |
| `module Name do` | `module_keyword` | token filter promotes `module` + upper-case name to `MODULE_KW`; productions at the program start and in `decl` (nested) | `FReplace` `module` → `mod` |
| `elif` / `elsif` | `elif_keyword` | token filter promotes `elif`/`elsif` to `ELIF` when a condition-start token follows; `IF … DO block_body ELIF error` in both `if` nonterminals | note only (the chain's missing `end`s go at its far end; no single safe edit) |
| `;` between expressions | `semicolon_separator` | the **lexer** (`';'` rule raising `Lexer_error_fix`); `Parse.run` builds the fix | `FReplace` of `;` + following blanks → `"\n" ^ indent`, or `""` when the `;` ends its line |
| `else if` one `end` short | (D1) | already done | already done |
| missing `else` | `parse_error` | already a note (the hint shows the shape); no safe default branch | none, by design |
| `fn _ ->` where a 0-arg call is made | `arity_mismatch` | **new check**: `env.lambda_arities` records `let name = fn … -> …` (arity, lambda span, the `fn _` extent); `EApp` of such a name with the wrong count reports, labels the binding, and returns the peeled type | `FReplace` `fn _` → `fn`, only for a 1-param `_` lambda called with 0 args |
| `let? x = e` last | `let_question_last` | already a note in the message | none, by design |
| unused binding | `unused_binding` | exists | exists |
| missing `needs`, unknown name | D6 | **not done**: D6 (did-you-mean) has not landed | – |

Neither `module` nor `elif` is a lexer keyword: `stdlib/logger.march` names a
parameter `module`, and the repo's history with reserving words (`restart`)
says not to. Both are minted by the token filter's existing one-token-lookahead
mechanism, so `let elif = 1`, `elif + 1`, `module : String` all still parse.
The tree-sitter grammar is unchanged: no new keyword, and the new fixtures are
reject programs under `test/errors/`, which the ratchet skips
(`scripts/check-tree-sitter.sh`: ok).

**The `fn _ ->` row needed a diagnostic first.** §8 assumed an arity-mismatch
diagnostic; there was none for lambdas. `run(fn _ -> 42)` where `run` calls
`cb()` typechecks (`a -> T` unifies with `() -> T`), panics interpreted and
prints 42 compiled, and the type system cannot see it. The let-bound case
(`let cb = fn _ -> 42` then `cb()`) typechecked as the lambda itself and failed
later as a confusing `type_mismatch` ("expected `Int` but got `a -> Int`"). That
case is now a real `arity_mismatch`; the HOF case remains undetectable
statically and is out of scope.

**Plumbing.** `ParseError` is a 3-tuple matched at ~40 sites, so a production's
code and fix ride `Errors.parse_error_extra`, set on every `error_raise` (to
`None, None` when it has nothing) and read-and-cleared by `Parse.run`. The four
direct `raise ParseError` sites in parser.mly were converted to `error_raise`
so nothing can leave a stale pair. The lexer got `Lexer_error_fix {msg; code;
note; replace}` beside `Lexer_error`.

**LSP adapter** (`lsp/lib/code_actions_diag.ml`, `fix_actions`): `Analysis.diag_to_lsp`
and the parse-diagnostic path put the fix in the LSP diagnostic's `data` as the
`--check-json` fix object; the adapter turns any `replace`/`insert`/`delete`
into a `QuickFix` `CodeAction` (preferred, linked to its diagnostic) when the
cursor is on the diagnostic's range or on the fix's own lines (the lambda fix
edits the binding, not the call). Parse diagnostics in the LSP now also carry
their code. Four tests in `lsp/test/test_lsp_actions.ml`.

**D7 corpus.** `test/run_errors.ml` now has a second phase: every program that
carried a fix is re-checked with all its fixes applied (forge's semantics,
bottom-up) and the `.expected` ends with `after fix: exit N` plus the first
diagnostic headline if N ≠ 0. All seven new fix cases end `after fix: exit 0`.
Of the 95 pre-existing fix cases, 72 still fail after their fix (an unused-binding
fix in a program whose point is another error), which is informational and
unchanged behaviour. `parse_error_1` was renamed `then_keyword_1` (its code
changed); `specs/lang/errors/parse_error.md`'s example is now a missing `do`.
New cases: `then_keyword_1`, `module_keyword_{1,2}`, `semicolon_separator_{1,2}`,
`elif_keyword_1`, `arity_mismatch_{1,2}`, `parse_error_1`; `parse_error_3`
(grammar reject r01) moved to `then_keyword` with a fix.

Four `march --explain` pages: `then_keyword`, `module_keyword`, `elif_keyword`,
`semicolon_separator` (rendered to `docs/errors/`).

## Verified

- menhir conflicts unchanged at 11.
- `run_compiler -q`, `run_eval -q`, `run_stdlib -q`, `test_lsp` (383), `run_errors`
  (286) green; `scripts/check-docs.sh` and `scripts/check-tree-sitter.sh` ok.
- Oracles: none applies (no codegen or TIR change; the typecheck change adds a
  diagnostic and changes the result type only of a call that was already an
  error at runtime).
