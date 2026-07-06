# Resolved Surface Grammar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development to execute this plan task-by-task.

**Goal:** Produce a **normative, resolved surface-grammar reference** for March — a new `specs/lang/grammar.md` chapter that states the *actual* language the parser accepts, unambiguously, reconciling the three-layer parse pipeline (lexer → `token_filter` → menhir) that `lib/parser/parser.mly` leaves implicit — backed by a **parse/reject conformance corpus** (`specs/lang/grammar/`) run against the real parser and wired into CI. Satisfies roadmap §6's "surface grammar (resolved)" Level-1/2 acceptance criterion.

**Architecture:** March's precedence is *mostly structural* — a stratified expression grammar (`expr → expr_or → … → expr_add → expr_mul → … → expr_app → expr_field → expr_atom`) with only **7 precedence/associativity declarations** (`parser.mly:214–220`) resolving residual conflicts; menhir reports ~59 shift/reduce conflicts it resolves by default. (That "~59" figure is INHERITED from the 2026-07-05 consolidation survey — it is NOT re-derived in this pass, since regenerating menhir's `.conflicts` report needs the forbidden `dune build`; no task depends on the exact count. The chapter validates the resolution EMPIRICALLY — value-producing corpus programs witness the actual parse — rather than auditing conflicts one-by-one. State this substitution honestly in the doc; do not imply a conflict-by-conflict audit.) The genuinely non-context-free part is `lib/parser/token_filter.ml` (a stateful token-stream transformer doing significant-newline glomming + match/`cond`-arm-boundary lookahead) sitting between the lexer and menhir. So a "resolved grammar" is a **hybrid**: a clean resolved EBNF for the context-free grammar (strata + precedence stated explicitly) PLUS a normative description of the two preprocessing layers (lexer significant-newline / string-interpolation; the `token_filter` transformation) that the EBNF assumes as its input. Scope this pass to the **core** (expressions, statements/blocks, patterns, types, common declaration forms); the DSL-heavy declaration forms (actors, capabilities, protocols, transitions, supervise) get a lighter documented appendix.

**Tech Stack:** Markdown (EBNF in fenced blocks); `lib/parser/{parser.mly,lexer.mll,token_filter.ml}` are the sources of truth; the pre-built compiler `_build/default/bin/main.exe --check` is the conformance oracle; `scripts/check-docs.sh` (shell) is the doc-freshness gate.

## Global Constraints

- **Base = current `origin/main`** (`0ba042cf` or later; fetch + rebase if it moved — docs-only, expect clean). Branch: `docs/core-march-types-skeleton` (the reference lives under `specs/lang/`).
- **⚠️ DO NOT run `dune build`/`dune runtest`/`dune exec`.** Concurrent compiler sessions saturate the shared dune daemon; any build hangs 600s and kills the agent. No compiler code changes here. The compiler is PRE-BUILT at `_build/default/bin/main.exe` — invoke it DIRECTLY for corpus checks (`_build/default/bin/main.exe --check <file>`, no daemon). `scripts/check-docs.sh` is pure shell. If a task seems to need `dune`, STOP and report.
- **Faithfulness — cite the sources by line, RE-GREP for live lines.** Every grammar rule / precedence claim / token_filter rule cites `parser.mly`/`lexer.mll`/`token_filter.ml` by line. Line numbers DRIFT — `grep -n` the construct in the CURRENT file and cite the live line; never trust a number from this plan or from memory.
- **Resolved, not transcribed.** The value is stating what parser.mly leaves IMPLICIT: the precedence/associativity resolution (the 7 declarations + how the strata encode the rest), the `token_filter` pre-pass as normative rules, and reachability (which productions are unreachable from surface syntax). A pure copy of parser.mly's rules is NOT the deliverable.
- **Corpus naming:** this corpus uses `parse/` + `reject/` (vs the `accept/`+`reject/` of `types/`) — `parse/` reads truer for a grammar corpus ("must parse"). This is an intentional, acknowledged divergence, not an oversight; the harness shape is otherwise identical to `check_types.sh`.
- **Reject messages may be generic.** Some `reject/` programs will fail with menhir's GENERIC fallback (`I got stuck here`, `Parse error in declaration`) rather than a bespoke diagnostic (verified live: `{ x } -> x` and `pub fn` give generic messages; `then` and `let?`-last give custom ones). A generic message is still parse-shaped and safe to pin — do NOT hunt for a custom diagnostic that doesn't exist; pin whatever the live compiler actually prints.
- **Conformance corpus — capture-not-guess, isolate parse from type.** `parse/` programs must `--check` **exit 0** (kept WELL-TYPED so exit 0 isolates "it parsed+typed"; the tricky part is the SYNTAX, keep types trivial). `reject/` programs must `--check` **exit 1** AND their output must contain a pinned **parse-error** substring (first-line `-- EXPECT-ERROR:`), CAPTURED from the live compiler — and it must be a PARSE diagnostic (e.g. `I don't recognize \`then\` here`, `I was expecting`), NOT a type error. If a "should-not-parse" program actually parses (or a "should-parse" program fails to parse), that is a finding — the grammar is mis-described OR a real parser bug: STOP, reproduce, file in `specs/todos.md` (the grammar flywheel), do NOT commit a corpus program that reddens the harness.
- **Docs-only.** Only `specs/lang/grammar.md`, `specs/lang/grammar/**`, `specs/lang/index.md`, `test/dune`/`ci.yml` (CI wiring, Task 6), and bookkeeping. ZERO `lib/`/`bin/`/`runtime/`/`stdlib/` changes — a task that needs one has found a parser bug to FILE, not fix.
- **`grammar.md` is normative; `surface-syntax.md` stays the cheatsheet.** Cross-link them (the cheatsheet points at grammar.md for the precise grammar; grammar.md points at the cheatsheet for the friendly overview). Do NOT duplicate; do NOT modify the two conformance-tested core references.
- **Process:** no `git stash`; explicit `git add <path>` by name; no Co-Authored-By. Commit per task as specified.

## Target structure

```
specs/lang/
  grammar.md                    # NEW — the normative resolved grammar chapter
  grammar/
    check_grammar.sh            # harness: parse/ must --check exit 0; reject/ must exit 1 + pinned parse-error substring
    INDEX.md                    # maps each corpus program → the grammar rule it anchors
    parse/    p01_*.march …     # must-parse (well-typed) programs exercising tricky syntax
    reject/   r01_*.march …     # must-fail-to-parse programs, each with -- EXPECT-ERROR: <parse substring>
  index.md                      # umbrella — add a "Grammar (resolved, normative)" chapter row
```

---

## Task 1: Scaffold — the preprocessing-layer chapter (lexer + token_filter) + corpus harness

**Files:** Create `specs/lang/grammar.md` (skeleton + the lexer/token_filter sections); `specs/lang/grammar/check_grammar.sh`; a few seed `parse/`+`reject/` programs; `specs/lang/grammar/INDEX.md`; add a chapter row to `specs/lang/index.md`.

**Deliverable:**
- `specs/lang/grammar.md` skeleton: chapter-status header (`> Part of the March Language Reference — see specs/lang/index.md`), a version/date line, §1 "The three-layer pipeline" (lexer → `token_filter` → menhir, with a one-paragraph overview + a note that `parser.mly` is the ultimate authority and this chapter states its *resolved* behavior).
- **§2 Lexical layer** — cite `lib/lexer/lexer.mll` (re-grep live lines): the token classes (identifiers upper/lower, literals int/float/string/bool/atom, operators, keywords, layout), significant vs insignificant whitespace, and the ONE non-context-free lexer behavior the survey flagged: **string-interpolation brace-depth tracking**. State it precisely as a normative rule.
- **§3 The `token_filter` pre-pass** — cite `lib/parser/token_filter.ml` (the `make` transformer, re-grep). This is the hard part: read the whole file and state, as normative rules, what it does to the token stream — the significant-**newline glomming** (when a newline separates block expressions vs is absorbed) and the **match/`cond`-arm-boundary lookahead** (how it distinguishes an arm boundary from a block continuation). Present each rule with a tiny before/after token-stream example. Be honest that this layer is not context-free and is why the EBNF (Tasks 2–5) takes a filtered token stream as input. **Shadow-grammar hazard (verified real):** `token_filter.ml`'s `is_pattern_start` predicate (re-grep it) is a HAND-MAINTAINED duplicate of the first-token set of `simple_pattern`/`pattern` — a reviewer found it already drifted out of sync across checkouts (missing `FLOAT` + soft-keyword cases). At write time, `grep` `soft_lower_name` + `simple_pattern` + `pattern` in the CURRENT `parser.mly` and cross-check `is_pattern_start` against them; document in the prose that this predicate is a manually-synced shadow of the pattern grammar (an instance of exactly the "resolved, not transcribed" hazard this chapter exists to surface) — do NOT just describe today's snapshot as if it were derived.
- `specs/lang/grammar/check_grammar.sh`: mirror `specs/lang/types/check_types.sh` — for each `parse/*.march` run `$MARCH_BIN --check`, require exit 0; for each `reject/*.march` require exit 1 AND the output to contain the file's `-- EXPECT-ERROR:` substring. Exit 0 iff all pass. Print a `=== grammar: N passed, M failed ===` summary.
- Seed corpus (enough to prove the harness): ≥2 `parse/` (e.g. a program exercising significant-newline block separation; a match with multi-expression arms — the token_filter's domain) and ≥2 `reject/` (e.g. `if x then …` → capture `I don't recognize \`then\``; a mis-formed arm). Capture every reject substring live.
- `specs/lang/grammar/INDEX.md`: table mapping each program → the grammar section/rule it anchors (seed it; later tasks extend).
- `specs/lang/index.md`: add a chapter-map row `| Grammar (resolved, normative) | [\`grammar.md\`](grammar.md) | canonical |` (place it near `surface-syntax.md`). Add a one-line note in surface-syntax.md's intro pointing at grammar.md for the precise grammar (if surface-syntax.md is awkward to touch, instead note the relationship in grammar.md §1 only — do not do heavy edits to the cheatsheet).

**Verify (NO dune):**
- `MARCH_BIN=$PWD/_build/default/bin/main.exe bash specs/lang/grammar/check_grammar.sh` → all pass, exit 0.
- `scripts/check-docs.sh` exits 0 (grammar.md is now globbed under `specs/lang/`; a dead source pointer fails it — cite only live lines).
- Every cited `lexer.mll`/`token_filter.ml` line, spot-checked, contains the claimed construct.

**Commit:** `docs(spec): resolved-grammar scaffold — lexer + token_filter layers + corpus harness`.

---

## Task 2: The resolved expression grammar (the precedence ladder)

**Files:** `specs/lang/grammar.md` (§4 Expressions); `specs/lang/grammar/{parse,reject}/*.march`; `INDEX.md`; umbrella (no status change needed).

**Deliverable:**
- **§4 Expressions** — state the stratified expression grammar as resolved EBNF, one production per stratum, cited to the `expr_*` rules in `parser.mly` (re-grep: `expr`, `expr_or`/`expr_and`/logical, comparison, `expr_add`, `expr_mul`, unary/`MINUS`, `expr_app`, `expr_field`, `expr_atom`, plus pipe `|>`). For EACH stratum state its **associativity** (left/right/non) and where it sits in the **precedence order**, and reconcile it against the 7 declarations (`parser.mly:214–220`) and the `%prec` annotations (`parser.mly` — re-grep the 5 sites). Include a single **precedence table** (tightest-binding to loosest) as the reader's quick reference. Explicitly resolve the survey's flagged points: `then` is a token but has NO production (it can never parse — cross-ref the reject); the pipe/`let?` surface forms and where they sit; and **list comprehensions** — `[ <expr> for <pattern> in <expr> (, <guard>)? ]` (re-grep `FOR`/`desugar_list_comp` in `parser.mly`, ~:1232–1237) — an `expr_atom`-level bracket-delimited form that binds a `pattern` and is desugared in-parser. State its grammar and note the desugaring. Corpus: add ≥1 `parse/` (a comprehension that runs to the expected list) and ≥1 `reject/` (a malformed comprehension — capture the live parse error).
- Corpus: **≥4 `parse/`** pinning precedence/associativity by CONSTRUCTION (well-typed programs whose only correct parse matches the stated rule — e.g. `a - b - c` computing left-assoc; `1 + 2 * 3` = 7 not 9; a pipe chain; field-access vs application binding). Where a program's RESULT witnesses the parse (e.g. `10 - 3 - 2 == 5`), prefer that. **≥2 `reject/`**: `then` used as `if … then` (capture `I don't recognize \`then\``); and one more genuine expression-level parse error (capture live). 

**Verify (NO dune):** `check_grammar.sh` all-pass; `scripts/check-docs.sh` 0; the precedence table matches what the live compiler actually does (spot-check 2–3 associativity claims by running a value-witnessing program with the pre-built binary).

**Commit:** `docs(spec): resolved-grammar — expression precedence ladder + associativity`.

---

## Task 3: Statements, blocks, and significant-newline semantics

**Files:** `specs/lang/grammar.md` (§5 Blocks & statements); corpus; `INDEX.md`.

**Deliverable:**
- **§5 Blocks & statements** — the block grammar (`block_body`, `block_expr`: `let` / `let?` / bare-expr sequencing), the `if`/`match`/`cond` (scrutinee-less `match do`) forms, and how **newlines separate block expressions** (tying back to §3's token_filter rules — this is where the newline-glom matters most). State the resolved rules for: multi-expression match arms vs arm boundaries (the token_filter lookahead in action), `let?` position constraints (cannot be last in a block), and `if` requiring `else` (no bare `if`). Cite `parser.mly`'s block/`if`/`match`/`cond` rules (re-grep).
- Corpus: **≥3 `parse/`** (a multi-statement block with `let` bindings; a match with multi-expression arms + a following arm — proving the boundary resolves; an `if/else if/else` chain that parses). **≥2 `reject/`** — genuinely NEW parse errors: a `let?` as the last block expression (capture the real message), and `if` without `else` OR a bare `if x do … end` if that's a parse/typecheck error (capture live; if it's actually accepted, that's a finding — note it). 

**Verify (NO dune):** `check_grammar.sh` all-pass; `check-docs` 0; the multi-expression-arm parse program actually runs to the right value (pre-built binary) to prove the boundary resolved as documented.

**Commit:** `docs(spec): resolved-grammar — blocks, statements, significant-newline`.

---

## Task 4: Patterns and types

**Files:** `specs/lang/grammar.md` (§6 Patterns, §7 Types); corpus; `INDEX.md`.

**Deliverable:**
- **§6 Patterns** — the `simple_pattern` grammar (re-grep `simple_pattern` in `parser.mly`): `_`, variable names (incl. soft keywords), literals (int/float/string/bool, negative numerics), parenthesised, tuple, list-literal, constructor patterns `C(...)`, atom patterns. **Reachability:** state explicitly that **`PatRecord` and `PatAs` are implemented in the AST/interpreter but have NO surface production** (unreachable — the same fact the operational + typing references note; cross-ref them). Where `simple_pattern` is used more narrowly than full `pattern` (e.g. `let?` / `let` bindings accept only `simple_pattern`), state the restriction.
- **§7 Types** — the type-expression grammar (re-grep the `ty`/type rules): base types, `TArrow` (`->`), `TCon` with args `Foo(a, b)`, tuple types `(a, b)`, record types `{ l: t, … }`, type variables / generics, `Option`/`Result` sugar if any. State arrow associativity.
- Corpus: **≥3 `parse/`** (a nested constructor+tuple pattern in a match; a function with a rich type annotation exercising arrow-associativity + generics + a record type). **≥2 `reject/`** — genuinely new: a **record pattern** `{ x } ->` used where a pattern is expected (capture the real parse error — this witnesses PatRecord-unreachability), and an **as-pattern** `x as y` (capture; witnesses PatAs-unreachability). If either UNEXPECTEDLY parses, that's a finding (the reachability claim is wrong) — file it.

**Verify (NO dune):** `check_grammar.sh` all-pass; `check-docs` 0; the record-pattern + as-pattern rejects reproduce their pinned parse-error substrings live.

**Commit:** `docs(spec): resolved-grammar — patterns (incl. unreachable PatRecord/PatAs) + types`.

---

## Task 5: Declaration forms + DSL appendix

**Files:** `specs/lang/grammar.md` (§8 Declarations, §9 DSL appendix); corpus; `INDEX.md`.

**Deliverable:**
- **§8 Declarations (core)** — the common top-level/module forms (re-grep each in `parser.mly`): `mod … do … end`, `fn`/`pfn` (incl. **multi-head** clauses merged into one match — state how consecutive same-name `fn` heads combine), `let` decls, `type`/`ptype` (variant/record/generic), `use`/`import`/`alias`, `interface`/`impl`, `derive`/`satisfy`. State the one-top-level-`mod`-per-file rule (cross-ref: the compiler gives a specific diagnostic). Visibility (`fn` public, `pfn` private; `type` public, `ptype` private; no `pub` keyword).
- **§9 DSL appendix (lighter)** — the DSL-heavy declaration forms (`actor`/actor handlers, `app`/`on_start`/`on_stop`, `supervise`, `protocol`/`choose`, `transitions`, the `cap …` directives, `needs`, `proof cap`): sketch each form's shape and cite its `parser.mly` rule, but do NOT resolve every production in full detail — state clearly that these are documented-but-not-exhaustively-resolved in this pass, deferring to `parser.mly` for the exact grammar, and note them as future-deepening work.
- Corpus: **≥3 `parse/`** (a multi-head `fn` that parses+runs correctly; an `interface`+`impl` pair; a `type` with generics + a record variant). **≥2 `reject/`** — genuinely new: a `pub fn` (obsolete keyword — capture the real parse error), and a second top-level `mod` in one file OR another decl-level parse error (capture live).

**Verify (NO dune):** `check_grammar.sh` all-pass; `check-docs` 0; the multi-head `fn` parse program runs to the expected value (pre-built binary).

**Commit:** `docs(spec): resolved-grammar — declaration forms + DSL appendix`.

---

## Task 6: Consolidate + CI-wire + closeout

**Files:** `specs/lang/grammar.md` (finalize); `specs/lang/grammar/INDEX.md` (finalize); `test/dune` (+ `.github/workflows/ci.yml`); `specs/lang/index.md`; `specs/progress.md`, `specs/todos.md`.

**Deliverable:**
- Finalize `specs/lang/grammar.md`: coherent front-to-back read; a top "how to read this grammar" note (EBNF conventions + the "filtered token stream" assumption); the version line → `v1 · <date> · core grammar resolved (DSL forms sketched)`; every §'s citations spot-verified live; a "known parser findings" subsection if the corpus surfaced any (cross-ref `specs/todos.md`).
- **CI-wire** `check_grammar.sh` into a **separate slow lane** — add a `grammar-check` dune alias to `test/dune` mirroring the existing `types-check` alias (sets `MARCH_BIN=%{exe:../bin/main.exe}`, runs the harness, NOT attached to `runtest`) + a `dune build @grammar-check` step in `.github/workflows/ci.yml`. **Verify the wired lane runs green** by running the exact command CI will run (this ONE `dune build @grammar-check` is permitted despite the no-dune rule — but if it hangs on the contended daemon, fall back to running `check_grammar.sh` directly, commit, and note in the report that CI-lane execution must be confirmed once the daemon frees; do NOT block the task on a daemon hang).
- Update `specs/lang/index.md`: grammar chapter `canonical`; ensure the corpus dir is mentioned in the "Conformance corpora" section.
- Bookkeeping: `specs/progress.md` (append the resolved-grammar milestone — the chapter, the N-program corpus, the CI lane, roadmap §6 "surface grammar (resolved)" satisfied for the core); `specs/todos.md` (Done entry; note the DSL-forms full resolution + any filed parser findings as follow-ups).

**Verify (NO dune except the one gated `@grammar-check` build):** `check_grammar.sh` all-pass; `scripts/check-docs.sh` 0; a full corpus tally in the report; the grammar chapter reads coherently and every § cross-links correctly.

**Commit:** `docs(spec): finalize resolved-grammar reference + CI-wire grammar-check`.

---

## Self-review checklist (run before executing)

1. **The `token_filter` layer is actually formalized** (Task 1 §3), not hand-waved — it's the one non-CF piece and the whole reason parser.mly is "ambiguous."
2. **Precedence is RESOLVED, not just transcribed** (Task 2): the precedence table + associativity claims are stated AND witnessed by value-producing corpus programs.
3. **Parse-vs-type isolation** holds in the corpus: `parse/` programs are well-typed (exit 0 = parsed+typed); `reject/` substrings are PARSE diagnostics, not type errors.
4. **Reachability claims** (PatRecord/PatAs unreachable, `then` never parses) are each witnessed by a `reject/` program that reproduces the real parse error live.
5. **No compiler change** — any "the grammar doc can't match the parser without a code change" is a filed parser finding (the grammar flywheel), not an edit.
6. **Citations are live** — every `parser.mly`/`lexer.mll`/`token_filter.ml` line re-grepped, not carried from this plan.
