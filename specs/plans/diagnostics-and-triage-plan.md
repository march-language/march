# Diagnostics and Triage — Plan

**Date:** 2026-10-05
**Status:** Proposed. Facts in §2 and the designs in Part D/T were source-checked by one
independent review (five blockers, all folded in; §20). No build was available while writing.
**Companion:** `specs/plans/incremental-codegen-cas-plan.md`, **PR #786**, not yet on `main`.
Where this plan needs a TIR verifier, provenance, pass bisection or a reducer it points at that
plan's A1, A2 and A4 instead of restating them. Merge #786 first, or read it from its branch.

---

## 1. Two questions

1. **When a statement doesn't compile, how does the compiler give a message so good that the fix
   is obvious in one read?** For a human, and for an LLM writing March, where every confusing error
   costs a full extra round-trip.
2. **When the compiler itself is broken, how does a maintainer zero in immediately** instead of
   climbing a ladder of dumps and env switches by hand?

The two share a principle: the compiler already knows the answer at the moment it fails. The
grammar's error productions know the construct; the typechecker's `reason` knows where the
expected type came from; the pipeline knows which pass changed a function. Much of the work is
keeping that knowledge instead of discarding it (§2 lists two places it is discarded today), and
printing it in one agreed shape.

## 2. What exists (surveyed 2026-10-05; counts are approximate and will drift)

**Diagnostic record.** `lib/errors/errors.ml`: `{severity; span; message; labels; notes;
code : string option; fix : fix_kind option}` with three fix constructors (`FInsert`,
`FDelete`, `FReplace`), `render_diagnostic` (Elm-style, labels rendered as secondary carets),
`render_diagnostic_json` (NDJSON for `--check-json`; emits `severity, file, span, message,
code, fix` but **not `labels` or `notes`**). `code` is set at ~25 sites with 12 distinct values,
and they are **slugs** (`unused_binding`, `unused_import`, `cap_grant`, `no_alloc*`,
`unknown_record_field`, `or_pattern_binding`, …), documented as such at `errors.ml:26`. `fix` is
set at ~33 sites (`typecheck_caps.ml`, `typecheck.ml`, `bin/main.ml`, `refinecheck/precond_infer.ml`,
`typecheck_exhaustive.ml`). Diagnostics are also built as record literals (`Err.report { … }`,
~27 sites), not only through the helpers.

**Where errors are made.** Parser and lexer raise exceptions (`Errors.ParseError (msg, hint,
pos)`, `Parser.Error`, `Lexer_error`); the typechecker, desugar, refinement and alloc-contract
passes produce `diagnostic`s; **lowering rejections are `Failure "file:line:col: error: …"`
strings** (16 `failwith` in `lib/tir/lower*.ml`, caught at `bin/main.ml` ~2650), and the resolver
and module registry also report via strings/exceptions.

**Parser.** `lib/parser/parser.mly` (2 121 lines), menhir in code mode with `--explain` only: no
`--table`, no incremental API, no `.messages`. **34** `error`-token productions raise
`ParseError` with a chosen position (`$startpos($N)`) and a hint; the `IF`/`MATCH` ones are
**duplicated** between `expr` (~1579–1623) and `expr_no_bare_lambda` (~1751–1795). Among them:
`IF expr DO block_body ELSE block_body error → "I was expecting `end` to close the if expression
here:"` (`:1579`). So the canonical `else if … end end` pitfall **already has a message**; what is
wrong is where it points (next finding). `Parse_errors.collect_parse_error` is effectively dead:
`error_raise` collects *and raises*, and the CLI exits before `take_parse_errors` is read.

**Existing bug: the chosen position is discarded.** `Errors.parse_error_diagnostic` (`errors.ml:277`)
takes its span from `Lexing.lexeme_start_p lexbuf`, i.e. the lookahead token, and the CLI calls it
with `ParseError (msg, hint, _)`, dropping the `_` (`bin/main.ml:2141`; also `:1312, 1426, 4705`,
`bin/toolchain.ml:542`, `lib/repl/repl.ml:831`). The LSP keeps the position
(`lsp/lib/analysis.ml:2396`). Every carefully placed `$startpos($N)` in the grammar is therefore
rendered at the wrong token on the command line.

**No single parse entry point.** `Token_filter.make Lexer.token` is instantiated inline at ~30
sites (`bin/main.ml` ×6, `lib/repl/repl.ml` ×12, `lsp/lib/analysis.ml` ×3, `lsp/lib/workspace.ml`,
`lib/resolver/resolver.ml`, `lib/modules/module_registry.ml`, `lib/format`, `lib/lint`,
`lib/search` ×2, `forge/lib` ×6, `js/march_browser_compile.ml`), each with its own
`Parser.Error`/`ParseError` handling (~11 catch sites). The filter's state is captured in the
closure `make` returns and is unreachable afterwards.

**Token filter.** `lib/parser/token_filter.ml` (656 lines) keeps `type context = Match | Block |
Paren | With` on a `Stack.t`. It pushes `Block` on **every `DO`** and pops on `END`; the only
keyword-aware pushes are `MATCH` (via a pending-depth stack), `GETS → With`, `CHOOSE BY → Match`.
It does not see `IF`/`FN`/`MOD`/`TYPE`/`ACTOR` as openers and records no positions.

**Type errors.** `Typecheck_unify.report_mismatch env ~span ?occurs_violation ~reason expected
found` is called only from inside `unify` (six sites in `typecheck_unify.ml`). `unify env ~span
~reason` itself has ~58 call sites (42 `typecheck.ml`, 15 `typecheck_unify.ml`, 1
`typecheck_caps.ml`). `reason` (`typecheck_types.ml:41–48`: `RAnnotation of span | RFnReturn of
string * span | RFnArg of span * int | RMatchArm of span | RLetBind of span | RBuiltin | RBecause`)
**already carries the expected side's origin**, and `report_mismatch` already emits a label "the
expected type comes from here" from `span_of_reason` (`:260–268`). What is missing is the
**provided** side's origin. Argument naming is inverted from what the words suggest: per the
convention comment (`:70–72`), `expected` = the type inferred for the expression (provided) and
`found` = the type the context requires. `env.vars : scheme StrMap.t` (`typecheck_env.ml:187`)
carries no binder span; `type_map : (span, ty) Hashtbl.t` maps *use* spans to types and cannot
recover a binder.

**Did you mean.** `Typecheck_env.edit_distance` wrapped by `suggest_var_in_scope`,
`suggest_ctors`, `suggest_module_name` (`typecheck_env.mli:16, 302, 307`); also
`lib/caps/cap_lattice.ml:148`. ~10 "Did you mean" sites across `typecheck_env.ml`,
`typecheck.ml`, `typecheck_unify.ml:219`, `typecheck_caps.ml`.

**Existing error corpora.** `specs/lang/types/reject/` (241 programs) and
`specs/lang/grammar/reject/` (14) each carry `-- EXPECT-ERROR: <fragment>`, run by
`check_types.sh`/`check_grammar.sh` as `grep -qF` on the output; doc-lint Check C counts them.
`scripts/error-cards/` renders real `--check` output for four samples. Message-text assertions in
the alcotest suites: ~90 in `test_compiler.ml`, 58 in `test_codegen.ml`, 51 in
`test_refinecheck.ml`, 8 in `test_eval.ml`, plus `test_alloc_contract.ml`. Nothing pins the full
rendered diagnostic (caret positions, labels, notes, fix).

**LSP.** Already sets `code` and `relatedInformation` (from `labels`) and flattens `notes` into
the message (`lsp/lib/analysis.ml:152–184`); `code_actions_diag.ml` matches the literal slugs
`"unused_binding"`/`"unused_import"` (`:502, 646, 946`) and otherwise re-derives edits from
message text; it consumes no `fix`. `codeDescription` is never set.

**`forge fix`.** `forge/lib/cmd_fix.ml:17–45` applies every `--check-json` line with a non-null
`fix`, ignoring code and message. `--check-json` runs only after typecheck (`bin/main.ml` ~2474),
so **parse errors never reach it**: the parse path prints to stderr and exits.

**Triage today.** `--dump-phases` writes `trace/phases/phases.json` (+ legacy `march-phases/`)
**relative to the CWD**, as a node/edge graph for `tools/phase-viewer.html` (function names
recoverable, bodies not; `lib/dump/dump.ml`). Readable per-stage bodies come from
`MARCH_DUMP_TXT=<stage|all>` on **stderr** (`bin/main.ml` ~2633); `Opt`'s per-pass snapshots are
"phases only, never MARCH_DUMP_TXT" (`contract_pipeline.ml:220`). `--timings`, `--emit-llvm`,
`MARCH_NO_{UNBOX,HOF_SPEC,INLINE_RC}`, `--no-opt`, `MARCH_SANITIZE`, `MARCH_TRACE_GC`,
`MARCH_REPR_AUDIT`, `MARCH_ALIAS_AUDIT` exist. `MARCH_NO_TRMC` was removed 2026-09-21. The
differential oracle (`test/test_oracle.ml`) compares interpreted vs compiled over real files.
`scripts/ir-oracle.sh` hashes `--emit-llvm` over a **fixed** corpus (`test/native`,
`test/snapshots/src`, `bench`); it has no single-file mode. `menhir >= 20230608`
(`dune-project:21`) supports `--table`, `acceptable`, `--compile-errors`.

---

# Part D — Diagnostics

## 3. The standard a message must meet

Every error answers four questions, at the right position, in this order:

| | The `else if` pitfall as the example |
|---|---|
| **Where did it go wrong?** | the `if` on line 12, not the `fn` on line 20 where the parser noticed |
| **What was expected, what was seen?** | "this `if` needs its own `end`; I reached `fn` instead" |
| **What is the fix?** | `fix: FInsert` of `end`, shown as a diff |
| **Why is the rule so?** | "`else if` is a nested `if` in the else position, so each closes separately" + a code |

Today the `else if` case gets the right *words* ("I was expecting `end` to close the if expression
here:") at the wrong *place* (the lookahead token) with no fix and no code. The acceptance test for
"super good" is operational (D8): given only the error text, a model fixes the program in one turn.

## 4. D0 — One parse entry point, and stop discarding the position

**Prerequisite for everything below.** Two defects, one fix.

- `March_parser.Parse` with `module_ : ?filename -> string -> (Ast.module_, diagnostic list)
  result`, plus `expr`/`repl_input` variants for the REPL and LSP. It owns the one `Token_filter`
  instance, catches `Parser.Error`, `ParseError` and `Lexer_error`, converts each to a
  `diagnostic` (code, span from the *exception's position*, hint as `note`), and returns it.
  Nothing else constructs the filter or catches these exceptions.
- `Errors.parse_error_diagnostic` takes `~pos:Lexing.position` (and `?len`) instead of a lexbuf;
  the lexbuf-based form stays only as a fallback for `Parser.Error`, which carries no position.
- Migrate the ~30 instantiation sites and ~11 catch sites: CLI, toolchain, LSP, REPL, resolver,
  module registry, format, lint, search, forge, browser. Each becomes a call to `Parse.*` plus
  "print/collect the diagnostics". The LSP and REPL get the CLI's messages for free from then on,
  and the CLI gets the LSP's correct positions.
- Parse diagnostics flow through `--check-json` (today they exit before it; D4 needs this), with
  `labels` and `notes` added to `render_diagnostic_json` while we're there (D5/D7 need them).

**Acceptance.** The `then` production's message appears at `then`, not the token after, on the
CLI; one D7 case pins it. `Parse_errors` is deleted. **Effort.** 1–2 sessions, mostly mechanical.

## 5. D1 — Open-construct tracking in the token filter

**Problem.** Structural errors (missing `end`, the `end end` chain, an unclosed `match`) are
reported where the grammar gave up, which is by construction after the mistake, and with a generic
hint.

**Design.**
- A **pending-opener register** keyed by paren depth, the way `pending_match_depths` already
  works: on `IF`/`FN`/`PFN`/`MOD`/`ACTOR`/`TYPE`/`TEST`/`WITH`/`SUPERVISE`/… record
  `{kw; pos; mutable saw_else}`; consume it into the opener stack at the next `DO`; **clear it on
  `ARROW`** (arrow-form lambda `fn x -> body` never gets a `DO`, `parser.mly:1566`). A bare `do`
  with no pending keyword pushes `{kw = "do"}`. Pop on `END`. Constructs that close with `END` but
  have no `DO` (`choose by …: … end`, `extern … end`, the with-`else` arms) are pushed on their own
  keyword, each listed explicitly with its grammar line.
- Set `saw_else` on the innermost `if` opener when `ELSE` is seen in a `Block` context (the filter
  today handles `ELSE` only for `With`).
- `Token_filter.make_with_state : lexer -> lexer * (unit -> opener list)`; `make` stays as the
  wrapper. Only `Parse` (D0) uses the state.
- In `Parse`, on any parse failure where the lookahead is `EOF` or a declaration keyword and the
  stack is non-empty: **override the span** with the innermost opener's position, keep the
  production's message if one fired (it names the construct), add the chain note when the opener
  is an `if` with `saw_else` sitting above another `if`, and a `fix: FInsert` of one `end` per
  unclosed opener at the lookahead. Lookahead `END` with an empty stack → "this `end` closes
  nothing". Otherwise fall through to D2.

**Acceptance.** D7 cases for: `end end` chain, missing `end` on `fn`/`match`/`mod`, stray `end`,
arrow-form lambda inside an `if` (must **not** report a false opener), `choose by` block,
`with … else` arms. **Effort.** 1–2 sessions after D0.

**Risk.** The filter's view and the grammar's can disagree; the override is applied only to the
*span* and *fix*, the message stays the grammar's, and the D7 negatives are the guard.

## 6. D2 — Expected-token sets from menhir

**Problem.** 34 hand-written productions cover known pitfalls; the long tail still gets "I got
stuck here".

**Design.** `(flags --explain --table)` plus `menhirLib` in `lib/parser/dune` and a `menhirLib`
opam dependency. Only `Parse` (D0) drives the incremental API; the ~100 monolithic `Parser.module_`
callers keep working unchanged under `--table`. On `HandlingError env`:
- probe `MenhirInterpreter.acceptable` per terminal → "I expected one of: `do`, `->`, `=`", capped
  at six, keywords and punctuation first;
- `parser.messages` with `--compile-errors` → `Parser_messages.message : int -> string` for states
  that recur, seeded from the D7 corpus; dune's menhir stanza has no `.messages` support, so
  `--compile-errors`, `--compare-errors` (CI: a grammar change that orphans a message fails the
  build) and `--update-errors` are hand-written `(rule)`s. Because the `IF`/`MATCH` productions are
  duplicated across `expr` and `expr_no_bare_lambda`, every such state comes in pairs; the
  `.messages` file says so, or the duplication is removed first.
- The supplier is `MenhirInterpreter.lexer_lexbuf_to_supplier` over the filter (it restores
  `lex_start_p`/`lex_curr_p` on re-queue, so positions stay right); the offer loop must also catch
  the `ParseError` the filter itself raises (its curried-call guard).

Order of precedence in `Parse`: D1 span override → production message → `.messages` state message
→ acceptable-token set as the floor.

**Risk.** `--table` is slower than code mode. Parse time is small; measure with `--timings` over
`bench/*.march` and `test/snapshots/src` before/after (or `scripts/compile-time-bench.sh --corpus
small` once #786's harness is on `main`). Fallback: keep code mode for the happy path and re-parse
with the table parser only after a failure (two grammar builds to keep in step).
**Effort.** 2 sessions; messages accrue.

## 7. D3 — A code on every diagnostic, and `--explain`

**Problem.** Without a code on *every* diagnostic, the LSP matches message text for quick-fixes, an
LLM skill cannot say "on this error do X", and nobody can count which errors users hit.

**Design.**
- **Keep slugs.** Codes already exist as slugs and the LSP keys on them (`"unused_binding"`); a
  numeric scheme would break that for no gain. Code = `snake_case` slug, unique, never reused,
  listed in one registry module `Errors.Code` (`let unused_binding = "unused_binding"`, …) so
  typos are compile errors and "every emitted code" is `Code.all`, not a grep.
- Make `code : string` **non-optional** on the record. That catches the ~27 record-literal sites
  that a required label on the helpers would miss. Migration one PR per producer: parser/lexer
  (via D0's conversion), typecheck, caps, refinecheck, alloc-contract, desugar. Helpers that report
  several conditions (`report_double_use`, `report_linear_never_used`, `warn_unused_params`, the
  `warn_*` in `refine_check.ml`, …) take `~code` at their call sites.
- **Lowering and resolver first need to produce diagnostics at all**: convert the 16 `failwith
  "file:line:col: error: …"` in `lib/tir/lower*.ml` and the resolver/module-registry string errors
  into `diagnostic`s (the positioned text is already there; this is plumbing). Until then those
  phases are out of D3's scope and the plan says so.
- **Catalogue**: `specs/lang/errors/<slug>.md` per code: meaning, minimal failing program, fixed
  program, why the rule exists. `scripts/gen-lang-docs.py` uses an explicit `CHAPTERS` table, so
  the errors directory gets its own table/loop generating `docs/errors/<slug>.html`; doc-lint
  **Check G** (next to F in `scripts/check-docs.sh`): `Code.all` ⊆ pages and pages ⊆ `Code.all`.
- **`march --explain <slug>`** prints the page; the renderer appends `[slug]` to the headline and,
  once per run per distinct code, "run `march --explain slug`". The LSP sets
  `codeDescription.href` to the generated page URL.

**Effort.** Registry + non-optional field + parser/typecheck migration: 2 sessions; other
producers ½ each; lowering/resolver conversion 1; pages written as codes land, each page's failing
program being the D7 corpus file for that code so the two never drift.

## 8. D4 — Mechanical fixes for the known pitfalls

**Problem.** `fix` exists (~33 sites) but the common syntax pitfalls have none, the LSP consumes
no `fix` at all, and parse errors never reach `forge fix` (D0 fixes the last).

**Design.** Populate `fix` where the repair is a deterministic text edit, and add the two adapters
that make a `fix` useful everywhere:

| Pitfall | Where it's detected today | Fix |
|---|---|---|
| `then` after `if` | lexer keyword + production `parser.mly:1589` | `FReplace` `then` → `do` |
| `module Name do` | lexes as `LOWER_IDENT`; no production | new production; `FReplace` → `mod` |
| `elif`/`elsif` | `LOWER_IDENT`; none | new production; note "write `else if … end end`" |
| `;` between expressions | `Lexer_error "Unexpected character"` (`lexer.mll:231`) | the **lexer** raises with `FReplace` `;` → newline |
| `else if` one `end` short | production `:1579`, wrong position | D1: position + `FInsert end` |
| missing `else` | production | note only: no safe default branch |
| `fn _ ->` where a 0-arg callback is expected | arity-mismatch diagnostic | `FReplace` → `fn ->` (only under that diagnostic) |
| `let? x = e` as last expression | typecheck | note only |
| unused binding | exists | `FReplace` name → `_name` (exists) |
| missing `needs X` for a known module | D6 | `FInsert` `needs X` after the `mod … do` line |
| unknown name, unique distance-1 match | D6 | `FReplace` |

- **LSP adapter**: a generic `fix_kind → CodeAction` in `code_actions_diag.ml`, so every
  `fix` is a quick-fix with no per-message code. The slug-matched actions stay for the actions
  that need more than a text edit.
- **`forge fix`** already applies any non-null `fix`; with D0 it sees parse fixes too. No new
  rule machinery.

Rule: a `fix` is set only when applying it cannot change the meaning of a program that was
*intended* differently; otherwise a `note`. Every fix has a D7 case whose expected output includes
the post-fix program compiling. **Effort.** ½ session per fix; adapters ½ each.

## 9. D5 — Type errors that show the provided side's origin

**Problem.** `report_mismatch` already labels where the *expected* type comes from (via `reason`).
It cannot say where the *provided* type came from: "expected `Int` but got `String`" at the `+`
with no pointer to the `String`.

**Design.**
- Thread `?provided_at:span` through `unify env ~span ~reason ?provided_at` and into
  `report_mismatch`, paired with the parameter the convention calls `expected` (the inferred type
  of the expression). Only the **top-level** `unify` call for a sub-expression sets it (recursive
  calls over type arguments pass `None`), so the change is at the ~58 `unify` call sites, each a
  one-argument addition where the caller has the sub-expression's span in hand (it does: it just
  inferred it).
- For a variable, the origin is its binder. Add `binder_spans : span StrMap.t` to `env`,
  populated wherever `vars` is extended (the ~10 binding sites: `let`, params, patterns, `with`),
  so the label can read "`name` was bound here as `String`". `report_mismatch` already receives
  `env`.
- Labels: `{provided_at, "this is `String`"}` + the existing `{span_of_reason, "the expected
  type comes from here"}`; the primary caret stays at `~span`. Check `render_diagnostic`'s layout
  with three carets on one line and with spans 200 lines apart (print each excerpt once).

**Effort.** 2 sessions. The ~58-site threading is mechanical; the binder table is the one
design decision (open question §19.3).

## 10. D6 — "Did you mean" at every name resolution

Extend the existing `suggest_var_in_scope` / `suggest_ctors` / `suggest_module_name` helpers to
every unresolved-name site (functions, modules, constructors, record fields, capabilities, types)
rather than calling `edit_distance` anew, and add two rules beyond distance: the name exists in a
module not in scope → "`map` is `List.map`; add `needs List`" with a D4 `FInsert`; the name exists
with different case/qualification → say so. Cap at three; prefer same-kind names. The typechecker
cannot depend on `lsp/lib`, so no shared index; the env scan is fine. **Effort.** 1 session.

## 11. D7 — Golden rendered-diagnostic corpus

**Problem.** The `EXPECT-ERROR` corpora (241 + 14 programs) pin a *fragment* of the message by
`grep -qF`; ~200 alcotest assertions pin other fragments. Nothing pins position, labels, notes,
code or fix, so any of those can regress silently, and D1/D5 are all about position and labels.

**Design.** `test/errors/<slug>_<n>.march` + `.expected` (the full `render_diagnostic` text with
carets, labels, notes, `[slug]`, and the fix rendered as a diff) + `.json.expected` (the
`--check-json` line, so the machine form can't drift from the human one), run by
`test/run_errors.exe`, regenerated with `UPDATE_ERRORS=1` like the TIR snapshots.
- **Seed from the existing corpora**, don't replace them: every `specs/lang/*/reject/` program
  gets a `test/errors` twin (a script does it; the `EXPECT-ERROR` fragment must appear in the
  `.expected`, which keeps doc-lint Check C's counts and the `check_*.sh` greps honest), plus one
  program per D3 slug (the catalogue page's example), every D4 fix, every D1 negative.
- The ~200 alcotest message assertions migrate into the corpus **as each is touched**, not in one
  PR; the risk table says why.

The `.expected` diff is the review artifact for any message change. **Effort.** 1 session for the
driver and seeding script; growth with D3/D4.

## 12. D8 — The one-turn metric

`scripts/error-one-turn.sh`: run the D7 programs (and oracle programs with one injected error
each) through a model with "here is the program and the compiler's error; fix it", count the share
fixed in one turn. Not a CI gate (cost, nondeterminism); run before and after a diagnostics PR and
quoted in it. This is the definition of "super good" the plan uses, and it will show which error
classes stay confusing after D1–D6. **Effort.** ½ session.

---

# Part T — Triage: zeroing in when the compiler is broken

## 13. The ladder as it stands

1. **Compiler or program?** interpreted vs compiled; divergence → compiler.
2. **Which stage?** `MARCH_DUMP_TXT=all` (stderr) and read forward to the first wrong TIR.
3. **Which optional pass?** `MARCH_NO_UNBOX`, `MARCH_NO_HOF_SPEC`, `MARCH_NO_INLINE_RC`,
   `--no-opt`. None helps → a mandatory pass (mono/defun/perceus/drop/escape/trmc).
4. **Which commit?** `git bisect run` over `--emit-llvm` hashes (byte-stable) or program output.
5. **Which object?** `MARCH_SANITIZE=1` build, `MARCH_TRACE_GC=1`, `MARCH_REPR_AUDIT=1`.
6. **Shrink.** Manual.

Every rung exists. The work is to run them for the maintainer, and (via #786) to make the compiler
name the pass and function itself.

## 14. T1 — `scripts/triage.sh FILE`

One command, one screen (a task for it is already queued: branch `tools/triage-script`).

```
triage: foo.march  (march 7c87cb4e, --opt 2)   artifacts: /tmp/triage.XXXX/
interp   : exit 0, 14 lines
compiled : exit 0, 14 lines           → outputs DIFFER at line 9  (interp: 42 / compiled: 41)
switches : MARCH_NO_UNBOX=1    → matches interp     ← blamed: unboxing
           MARCH_NO_HOF_SPEC=1 → still differs
           MARCH_NO_INLINE_RC=1 → still differs
           --no-opt            → still differs
stages   : tir-lower 12 fns · tir-trmc 12 · tir-mono 25 (+13) · … · tir-opt 25
           --fn go: body first changes at tir-mono
sanitize : not run (no crash; --deep to force)
next     : diff /tmp/triage.XXXX/tir-lower.txt /tmp/triage.XXXX/tir-mono.txt
```
- Interp vs compiled, or `--expect FILE` against a known-good output; interpreted run time-boxed.
- Switches: the four above, verified by grep at run time; first fixer is "blamed". When #786's
  `--disable-pass` lands, the list comes from the compiler and `--bisect-pass` replaces the block.
- Stages: `MARCH_DUMP_TXT=all` split by its `===== <stage> =====` headers into per-stage files
  (**stderr**, not `--dump-phases`, which writes a viewer graph to `trace/phases/` relative to
  CWD and omits bodies; note `Opt`'s inner passes are phases-only). Per stage: function count and
  names added/removed; `--fn NAME` reports where that function's body first changes.
- Sanitize on crash or `--deep`. Private `HOME` + fresh project dir so caches can't confuse it.

**Effort.** 1 session. Nothing new in the compiler.

## 15. T2 — Bisect wrappers that are known to work

- `scripts/bisect-ir.sh GOOD BAD FILE`: `git bisect run` keyed on the `--emit-llvm` hash of one
  file (`ir-oracle.sh` is corpus-only; the single-file hashing is new but small). Rebuild per step
  with `dune build --root . bin/main.exe`.
- `scripts/bisect-output.sh GOOD BAD FILE [--expect OUT]`: keyed on compiled program output; needs
  a full `dune build --root .` per step because a targeted `bin/main.exe` build does **not** restage
  `runtime/` (CLAUDE.md), and runtime changes are exactly what output bisection is for.
Both print the blamed commit and its `specs/progress/` entry if the message names one.
**Effort.** ½ session.

## 16. T3 — The "immediate" tier (owned by #786)

Listed so this plan is honest about dependencies; specified in the companion plan:
**A1 TIR verifier** ("after `perceus`, `Foo.bar`: `t` has 2 incs and 3 decs on the `Node`
path"), **A4 `--bisect-pass` / `--reduce`** (blamed pass and minimal repro attached to an oracle
failure), **A2 provenance / `--debug-info`** (crashes, ASan and `perf` name March lines).

## 17. T4 — Compiled panics with a March backtrace (after A2)

Per-frame `at Main.go (main.march:42)` with the specialisation (`List.map$Int$String`) and the
actor/supervisor context; `MARCH_PANIC_JSON=1` (new) emits the same as NDJSON. **Effort.** 1
session after A2.

---

## 18. Consumers

| Consumer | What it gets |
|---|---|
| **CLI** | correct positions for every grammar error (D0); opener-anchored structural errors (D1); codes + `--explain` (D3) |
| **LSP** | the same messages as the CLI (D0, one entry point); `fix → CodeAction` adapter (D4); `codeDescription` links; provided-side `relatedInformation` (D5) |
| **REPL** | same as the LSP; it parses through the same entry point after D0 |
| **`forge fix`** | parse-level fixes at last (D0 + D4); nothing else changes |
| **`march-lang` skill / LLMs** | "on `unused_binding` do X" instead of prose matching; D1 messages name the fix; D8 measures the result |
| **Maintainers** | T1 one-screen triage; T2 flake-free bisection; T3/T4 as #786 lands |

## 19. Order, effort, risks, open questions

**Order.** T1 now (queued). **D0 first** in Part D: everything else is anchored on it, and it
fixes a user-visible bug (wrong carets) on its own. Then D3's registry + non-optional field, D1
and D7's driver in parallel. D4/D5/D6 after D3. D2 after a `--table` timing check. D8 once D1–D4
exist. T2 any time. T4 after A2.

**Effort.** T1 1, T2 ½, D0 1–2, D1 1–2, D2 2, D3 2 + ½ per producer + 1 for lowering/resolver
conversion, D4 ~½ each + 1 for adapters, D5 2, D6 1, D7 1 + growth, D8 ½ sessions. Roughly three
to four weeks of sessions for Part D; most items independent once D0 and D3's registry exist.

**Risks.**

| Risk | Mitigation |
|---|---|
| D0's ~30-site migration regresses an obscure caller (forge, browser, search) | each site becomes one call; CI covers forge/lsp/search suites; the REPL and LSP suites pin their error paths |
| D1's view disagrees with the grammar (arrow lambdas, `choose by`, `extern`) | override span/fix only, never the message; one D7 negative per construct |
| `--table` slows parsing | measure first; two-grammar fallback (code mode happy path, table on failure) |
| Non-optional `code` breaks the LSP's slug matching | codes **stay** slugs; registry constants replace literals in `code_actions_diag.ml` |
| ~200 message assertions churn under D1/D5 | migrate per-touch into D7; never in one PR |
| Catalogue pages rot | the page's example **is** the D7 corpus file; Check G enforces both directions |
| D5's `binder_spans` on a hot path | spans are already computed; measure typecheck with `--timings` |
| #786 not merged when this starts | only T3/T4 and D2's bench reference depend on it; everything else stands alone |

**Open questions.**
1. Slug registry: one flat module, or per-phase submodules (`Code.Parse.then_instead_of_do`)?
2. `.messages` duplication: de-duplicate the `expr`/`expr_no_bare_lambda` `IF`/`MATCH` error
   productions first, or carry paired states?
3. D5 binder origin: `binder_spans` in `env` (assumed) vs. recovering from the LSP-style `def_map`
   computed outside the checker.
4. D2: incremental API always, or re-parse with the table parser only after failure?
5. D8: which model, how many programs, where the number lives (dated snapshot in
   `specs/benchmarks.md`, or nowhere in-repo).
6. Lowering `failwith` → diagnostics: keep `exit 1` on first error, or collect and continue the
   way typecheck does?

## 20. Review record

### First draft, reviewed 2026-10-05 against the source
Five blockers, eight should-fixes, five nits; all folded in.
- **Blockers:** (1) there is no single "driver" — the filter is instantiated at ~30 sites with
  ~11 separate catch sites, so D1/D2 as written had no place to live → **D0** added as the
  prerequisite. (2) The CLI already **discards** the position the grammar's error productions
  compute (`parse_error_diagnostic` reads the lexbuf) → §2 names it as an existing bug; D0's first
  commit fixes it. (3) The `else if` example was misdiagnosed: a production already produces the
  right message; the defect is position and hint → §2/§3/D1 rewritten around that. (4) D5 was
  aimed at the wrong function and the wrong side: `report_mismatch` is called only from `unify`,
  the *expected* side's origin already exists via `reason`, and the argument naming is inverted
  from the words → D5 rewritten as `?provided_at` through the ~58 `unify` sites plus
  `binder_spans`. (5) The companion plan is on PR #786's branch, not `main` → stated; T3/T4 marked
  as dependencies.
- **Should-fixes:** corrected counts (12 slug codes at ~25 sites, ~33 `fix` sites, three `fix`
  constructors, 34 error productions with the `IF`/`MATCH` ones duplicated, ~200 message
  assertions not 24, `Parse_errors` effectively dead); the token filter pushes `Block` on every
  `DO`, so D1 needs a pending-opener register and `make_with_state`; `--table` needs `menhirLib`
  and hand-written `.messages` rules; **codes stay slugs** (the LSP keys on them) and the field
  goes non-optional to catch record literals; lowering/resolver emit strings, not diagnostics;
  `--check-json` lacks `labels`/`notes` and never carries parse errors; `forge fix` applies any
  `fix` (no rules exist to make "declarative"); the LSP consumes no `fix` (adapter added); `;` is
  a lexer error; the `EXPECT-ERROR` corpora (255 programs) exist and D7 now seeds from them;
  `--dump-phases` is a CWD-relative viewer graph without bodies (T1 uses `MARCH_DUMP_TXT`);
  `ir-oracle.sh` is corpus-only.
- **Nits:** `gen-lang-docs.py` uses an explicit `CHAPTERS` table; a code check must read a
  registry, not grep; the typechecker cannot depend on `lsp/lib`; the REPL is a consumer.

### Still unverified
Timing cost of `--table`; whether any construct defeats D1's pending-opener rule beyond those
listed; the exact set of binding sites for `binder_spans`.
