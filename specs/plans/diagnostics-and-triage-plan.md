# Diagnostics and Triage — Plan

**Date:** 2026-10-05
**Status:** Proposed. Written from reading the source (no build available in the authoring
environment); **not yet independently reviewed**, see §19.
**Companion:** `specs/plans/incremental-codegen-cas-plan.md` (the "observability plan"). Where
this plan needs a verifier, provenance, bisection or a reducer it points at that plan's A1, A2
and A4 rather than restating them.

---

## 1. Two questions

1. **When a statement doesn't compile, how does the compiler give a message so good that the
   fix is obvious in one read?** For a human, and for an LLM writing March, where every
   confusing error costs a full extra round-trip.
2. **When the compiler itself is broken, how does a maintainer zero in immediately** instead of
   climbing a ladder of dumps and env switches by hand?

The two share a principle: the compiler already knows the answer at the moment it fails. The
parser knows which construct is unclosed; the typechecker knows where the other type came from;
the pipeline knows which pass changed a function. The work is to keep that knowledge and print it,
not to compute something new.

## 2. What exists (surveyed 2026-10-05)

**Diagnostics.** `lib/errors/errors.ml`'s record is already the right shape:
`{severity; span; message; labels; notes; code : string option; fix : fix_kind option}` with
`FDelete`/`FReplace` mechanical fixes, `render_diagnostic` (Elm-style, coloured) and
`render_diagnostic_json` for `--check-json` (NDJSON, consumed by `forge fix`). But `code` is
set at about four sites in the 9 300-line `typecheck.ml`, so nearly every diagnostic is
identifiable only by its text; and `fix` is populated through helpers (`error_with_fix`,
`warning_with_code_and_fix`) at few sites.

**Parse errors.** `lib/parser/parser.mly` (2 121 lines) is menhir in code mode with `--explain`
only: no `--table`, no incremental API, no `.messages` file. Messages come from ~40 hand-written
`error` productions, each raising `Errors.ParseError (message, hint, position)` (e.g. "A file
may have only one top-level `mod`", "I was expecting `do` to start the module body"), plus
`Parse_errors.collect_parse_error` for declaration-level recovery. Anything they don't cover falls
to the driver's `"I got stuck here:"` at menhir's lookahead token (`bin/main.ml:2146`). The
`else if … end end` pitfall in CLAUDE.md is the canonical case: the parser only notices at the
next declaration or EOF, far from the unclosed `if`.

**Token filter.** `lib/parser/token_filter.ml` (656 lines) sits between lexer and parser,
suppressing `NL` outside match arms via lookahead. It already keeps a context stack
(`type context = Match | Block | Paren | With`, `Stack.t`) with depth counters, but records no
positions and no opening keyword.

**Type errors.** `Typecheck_unify.report_mismatch env ~span ?occurs_violation ~reason expected
found` builds "expected X but got Y" with a `reason` (`string_of_reason`) and a per-argument
mismatch note. It receives **one** span. Types carry no origin, so "where did the other type come
from" is not available at the report site. `Typecheck_env.edit_distance` exists and "Did you
mean" appears at four sites (`typecheck.ml:734, 1474, 2431, 5304`; `typecheck_caps.ml:325`).

**Tests.** `test/test_compiler.ml` has 24 substring assertions on messages; there is no golden
corpus of rendered diagnostics. `specs/lang/golden/` (50 programs) is a *passing* corpus.

**Triage today.** `--dump-phases` / `MARCH_DUMP_TXT=<stage|all>` (TIR per pass, `tir-trmc`
since #782), `--timings`, `--emit-llvm`, `MARCH_NO_{UNBOX,HOF_SPEC,INLINE_RC}`, `--no-opt`,
`MARCH_SANITIZE`, `MARCH_TRACE_GC`, `MARCH_REPR_AUDIT`, `MARCH_ALIAS_AUDIT`, the interp-vs-
compiled differential oracle (`test/test_oracle.ml`), `scripts/ir-oracle.sh` (byte-stable
`.ll` hashes over ~240 programs). All exist; none is wired together, and none names a pass or a
function on its own.

---

# Part D — Diagnostics

## 3. The standard a message must meet

Every error answers four questions, at the right position, in this order:

| | The `else if` pitfall as the example |
|---|---|
| **Where did it go wrong?** | the `if` on line 12, not the EOF where the parser noticed |
| **What was expected, what was seen?** | "this `if` needs its own `end`; I reached `fn` instead" |
| **What is the fix?** | `fix: FReplace` inserting ` end`, shown as a diff |
| **Why is the rule so?** | "`else if` is a nested `if` in the else position, so each closes separately" + a code |

The acceptance test for "super good" is operational (D8): given only the error text, a model
fixes the program in one turn.

## 4. D1 — Open-construct stack in the token filter

**Problem.** Structural errors are reported where menhir gave up, which is by construction after
the mistake. Missing `end`, the `end end` chain, an unclosed `match`, `do` without `end`: all
surface as "I got stuck here" at the next declaration keyword or at EOF.

**Design.** Extend the filter's existing context stack with position and keyword:
```
type opener = { kw : string; (* "if" | "do" | "match" | "fn" | "mod" | "type" | "with" | … *)
                pos : Lexing.position; depth : int }
```
pushed on every block opener the filter already recognises (it must already see `DO`, `MATCH`,
`WITH`, `LPAREN` to do its job) and popped on `END`/`RPAREN`. Expose
`Token_filter.open_constructs : unit -> opener list` (innermost first). When the driver catches
`Parser.Error`:
- lookahead is `EOF` or a declaration keyword (`FN`/`PFN`/`TYPE`/`MOD`/`ACTOR`/`APP`) and the
  stack is non-empty → report at the **innermost opener**: "this `if` (line 12) is still open
  when the next declaration starts" with the rule note, and a `fix` inserting `end` before the
  lookahead;
- lookahead is `END` with an empty stack → "this `end` closes nothing";
- otherwise fall through to D2.

Special-case the chain: if the innermost opener is `if` and the stack below it holds another
`if` whose body contains `else`, the note says "`else if` is a nested `if`; each one needs its own
`end`" and the fix inserts the right number of `end`s.

**Acceptance.** Every program in CLAUDE.md's "Surface syntax notes" that today produces "I got
stuck here" at the wrong place produces a message at the opener; D7's corpus pins them.
**Effort.** 1–2 sessions. **Risk.** The filter's stack and the grammar's notion of a block can
disagree (e.g. `fn x -> body` has no `end`); the stack must only push constructs that the
*filter* already tracks as blocks, and the driver must treat its answer as a hint ("still open")
rather than a certainty.

## 5. D2 — Expected-token sets from menhir

**Problem.** Forty hand-written `error` productions cover the pitfalls someone has already met.
The long tail still gets "I got stuck here".

**Design.** Build the grammar with `--table` and drive it through menhir's incremental API
(`Parser.MenhirInterpreter`), so on `HandlingError env` the driver has the LR state. Two uses:
- **Acceptable-token probe**: for each terminal, `MenhirInterpreter.acceptable` tells whether it
  could continue; print the set as "I expected one of: `do`, `->`, `=`", filtered to a
  human-meaningful subset (never list 60 tokens; cap at 6, prefer keywords and punctuation).
- **`parser.messages`** with `--compile-errors`: hand-written messages per error state for the
  states that recur, generated into `Parser_messages.message : int -> string`. Start with the
  states the D7 corpus hits; `menhir --list-errors` enumerates the rest and `--update-errors`
  keeps the file in step when the grammar changes. CI runs `--compare-errors` so a grammar change
  that orphans a message fails the build rather than silently losing it.

The ~40 existing `error` productions stay: they carry pitfall *names* ("March uses `do`/`end`,
not `then`") that a token set cannot. D1 runs first (structural), then the production message if
one fired, then D2's state message, then the acceptable-token set as the floor.

**Risk.** `--table` is slower than code mode (menhir documents roughly 2–5×); parse is a small
share of compile time (B0 will say exactly), but measure before and after with
`scripts/compile-time-bench.sh --corpus small`. The token filter re-queues tokens after
lookahead; the incremental API's `offer` loop must feed it the same stream, so the filter's
`make` wrapper is the single supply point.
**Effort.** 2 sessions for the switch and the probe; messages accrue over time.

## 6. D3 — Codes on every diagnostic, and `--explain`

**Problem.** Without codes, the LSP matches message text to pick a quick-fix, an LLM skill cannot
say "on this error do X", and nobody can count which errors users hit.

**Design.**
- Code format `E####`/`W####`/`H####` with ranges by phase: `E0xxx` lexer/parser, `E1xxx`
  resolver/modules, `E2xxx` typecheck, `E3xxx` capabilities, `E4xxx` refinement, `E5xxx`
  lowering/compile-only rejections, `E6xxx` linearity/session. Assigned once, never reused.
- Mechanically: make `code` **required** on the `Errors.error`/`warning`/`hint` constructors
  (a `~code` label), so the compiler stops building without one. The migration is one PR per
  phase; `Err.error ctx ~span "…"` call sites become `Err.error ctx ~span ~code:"E2001" "…"`.
  Where a site reports several distinct conditions through one helper, split the code at the
  helper's call sites, not inside the helper.
- **Catalogue**: `specs/lang/errors/E2001.md` per code: meaning, a minimal failing program, the
  fixed program, why the rule exists, related codes. Generated into `docs/errors/` by
  `scripts/gen-lang-docs.py` (extend it to walk the `errors/` subdirectory; today it walks
  `specs/lang/*.md`), so doc-lint's Check F covers it. A doc-lint check that every code the
  compiler can emit has a page: `grep -o 'code:"[EWH][0-9]\{4\}"' lib -r | sort -u` against
  `ls specs/lang/errors/`.
- **`march --explain E2001`** prints the page (and the LSP's diagnostic carries
  `codeDescription.href` to the generated URL). The CLI renderer appends `[E2001]` to the
  headline and `run march --explain E2001 for the full story` once per distinct code per run.
- `--check-json` already carries `code`; `forge fix` and the LSP switch to keying on it (D4).

**Effort.** Infrastructure ½ session; migration ~1 session per phase (typecheck is the big one:
134 report sites); catalogue pages are written as codes land, one paragraph each, with the D7
corpus program as the failing example so the two never drift.

## 7. D4 — Mechanical fixes for the known pitfalls

**Problem.** `fix` exists but is rarely set. Every mechanical fix becomes an LSP quick-fix (via
`code_actions_diag.ml`, keyed on D3's code instead of message text) and a `forge fix` auto-apply.

**Design.** Populate `fix` for every diagnostic whose repair is a deterministic text edit:

| Pitfall (CLAUDE.md) | Fix |
|---|---|
| `then` after `if` | `FReplace` `then` → `do` |
| missing `else` | `note` only: there is no safe default branch to insert |
| `else if … end` with one `end` short | D1: insert `end` |
| `module Name do` | `FReplace` → `mod` |
| `let? x = e` as last expression | note only (needs a value) |
| `fn _ -> f()` passed where a 0-arg callback is expected | `FReplace` `fn _ ->` → `fn ->` (only when the arity mismatch diagnostic fires) |
| `;` between expressions | `FReplace` `;` → newline |
| unused binding | `FReplace` name → `_name` (exists for some) |
| missing `needs X` for a known module | insert `needs X` after the `mod … do` line |
| unknown name with a unique edit-distance-1 match | `FReplace` with the match (D6) |

Rule: a `fix` is set only when applying it cannot change the meaning of a program that was
*intended* differently; otherwise it's a `note`. Every fix gets a D7 corpus entry whose expected
output includes the post-fix program compiling.

**Effort.** ½ session per fix; the first few share plumbing.

## 8. D5 — Type errors that show both origins

**Problem.** `report_mismatch` has one span. "Expected `Int` but got `String`" at the `+` says
nothing about where the `String` came from.

**Design.** Thread an **origin** alongside the type where the checker already has it, without
putting spans into `ty` (which would change hashing, `Serialize`, and every pattern match on
types):
- `check_expr`/`infer_expr` already return a type for a sub-expression it just checked; at the
  unification call sites that produce mismatches (the `report_mismatch` callers), pass
  `?found_at:span` = the span of the sub-expression whose type is `found`. That is a local change
  at each caller, not a change to the type representation.
- For a variable, the origin is its binding site: `env` lookups return the binder's span (the env
  already maps names to types; add the span to the entry) so the label can say "`name` was bound
  here as `String`".
- `report_mismatch` emits `labels = [{lbl_span = found_at; lbl_message = "this is `String`"};
  {lbl_span = expected_at; lbl_message = "but `+` needs `Int` here"}]`, and the existing
  `reason` becomes the `note`.
- Renderer: `render_diagnostic` already prints labels; check the two-label layout reads well when
  spans are on the same line and when 200 lines apart (print both excerpts).

**Effort.** 2–3 sessions: the mechanical part is wide (134 sites) but each is a one-argument
change; the binder-span-in-env change is the one design decision.

## 9. D6 — "Did you mean" at every name resolution

`edit_distance` is used at four sites. Make it the default for **every** unresolved name:
function, module, constructor, record field, capability, type. Two extra rules beyond distance:
- the name exists in a module not in scope → "`map` is `List.map`; add `needs List`" (with a D4
  fix), rather than a distance suggestion;
- the name exists with different case or qualification → say so specifically.
Cap at three suggestions; prefer names of the same kind (a function for a function). Reuse the
LSP's completion index if it is cheaper than scanning the env.
**Effort.** 1 session.

## 10. D7 — Golden error corpus

**Problem.** 24 substring assertions pin fragments of 24 messages. A message improvement can
regress a neighbour silently, and nothing pins position or fix.

**Design.** `test/errors/<code>_<slug>.march` with a paired `.expected` holding the **full rendered
diagnostic** (text, caret positions, labels, notes, code, and the fix rendered as a diff), run by
a new `test/run_errors.exe` (alcotest, one case per file, `UPDATE_ERRORS=1` to regenerate like
the TIR snapshots). The corpus seeds from: every CLAUDE.md pitfall, every D4 fix, one program per
D3 code (the same program the catalogue page shows), and the ~40 parser `error` productions.
`--check-json` output for each is pinned too (a second `.json.expected`), so the machine form
can't drift from the human one.

The diff **is** the review artifact for any message change, the same discipline as
`test/snapshots/`. **Effort.** 1 session for the driver; the corpus grows with D3/D4.

## 11. D8 — The one-turn metric

Run the D7 corpus programs (and the differential oracle's real programs with one injected error
each) through a model with the prompt "here is the program and the compiler's error; fix it", and
count the share fixed in one turn. Not a CI gate (cost, nondeterminism); a script,
`scripts/error-one-turn.sh`, run before and after a diagnostics PR and quoted in it. The number
is the definition of "super good" this plan uses, and it will show which classes of error are
still confusing after D1–D6.

---

# Part T — Triage: zeroing in when the compiler is broken

## 12. The ladder as it stands

1. **Compiler or program?** run interpreted and compiled; divergence → compiler.
2. **Which stage?** `MARCH_DUMP_TXT=all` and read forward to the first wrong TIR.
3. **Which optional pass?** flip `MARCH_NO_UNBOX`, `MARCH_NO_HOF_SPEC`, `MARCH_NO_INLINE_RC`,
   `--no-opt`. None helps → a mandatory pass (mono/defun/Perceus/drop/escape/TRMC).
4. **Which commit?** `git bisect run` with `scripts/ir-oracle.sh check` (byte-stable `.ll`, so
   zero flakiness). Underused.
5. **Which object?** `MARCH_SANITIZE=1` build, `MARCH_TRACE_GC=1`, `MARCH_REPR_AUDIT=1`.
6. **Shrink.** Manual.

Every rung exists. The work is to run them for the maintainer and to make the compiler name the
pass and function itself.

## 13. T1 — `scripts/triage.sh FILE`

One command, one screen. Runs the ladder's rungs 1, 2, 3 and 5 and prints:

```
triage: foo.march  (march 7c87cb4e, --opt 2)
interp   : exit 0, 14 lines of output
compiled : exit 0, 14 lines           → outputs DIFFER at line 9  (interp: 42 / compiled: 41)
switches : MARCH_NO_UNBOX=1 → compiled output matches interp   ← blamed: unboxing
           MARCH_NO_HOF_SPEC=1 → still differs
           MARCH_NO_INLINE_RC=1 → still differs
           --no-opt → still differs
stages   : first stage where fn set changes: tir-mono (+13 fns); dumps in /tmp/triage.XXXX/
sanitize : clean
next     : MARCH_DUMP_TXT=mono,fusion march --compile foo.march  (diff /tmp/triage.XXXX/tir-lower.txt tir-mono.txt)
```
- Interp vs compiled: both runs, output diff, exit codes; `--expect FILE` to compare against a
  known-good output instead of the interpreter (for interpreter-only features or when the
  interpreter is what's suspected).
- Switches: each in turn, compared against the reference; the first that fixes it is the blame.
  When A4's `--disable-pass` lands, the list becomes every optional pass, enumerated from the
  compiler (`march --list-passes`), and `--bisect-pass` replaces this block.
- Stages: `--dump-phases` once; per stage, function count and the names added/removed; flag the
  first stage where the *reference* function's body changed (`--fn NAME`).
- Sanitize: a `MARCH_SANITIZE=1` compile+run if the compiled run crashed or if `--deep`.
- Everything into a kept temp dir, path printed, with the exact next command to run.

**Effort.** 1 session. Shell plus the switches that exist; nothing new in the compiler.

## 14. T2 — Bisect recipes that are known to work

Document and wrap the two bisections that are already reliable:
- `scripts/bisect-ir.sh GOOD BAD FILE`: `git bisect run` over `ir-oracle`-style `.ll` hashing of
  one file (build `bin/main.exe` at each step; `--emit-llvm`; compare to the GOOD hash). Finds
  the commit that changed codegen for a program in O(log n) builds with no flakiness.
- `scripts/bisect-output.sh GOOD BAD FILE [--expect OUT]`: same, keyed on compiled program
  output. For behaviour regressions where the `.ll` legitimately changed.
Both print the blamed commit and its `specs/progress/` entry if the commit message names one.
**Effort.** ½ session.

## 15. T3 — The "immediate" tier (owned by the observability plan)

These make rungs 2–3 and 6 disappear; they are specified in the companion plan and listed here
so this plan's ordering is honest about what it depends on:
- **A1 TIR verifier**: the compiler says "after `perceus`, `Foo.bar`: `t` has 2 incs and 3 decs
  on the `Node` path". Replaces reading dumps for the mandatory passes.
- **A4 `--bisect-pass` / `--reduce`**: blamed pass and a minimal repro, attached to the oracle
  failure automatically. T1 adopts them as they land.
- **A2 provenance / `--debug-info`**: compiled crashes, ASan and `perf` name March functions
  and lines instead of `$lam39788$apply$4781+0x4c`.

## 16. T4 — Compiled panics with a March backtrace (depends on A2)

Once frames carry provenance, the runtime's panic path prints `at Main.go (main.march:42)` per
frame, including the specialisation (`List.map$Int$String`) and the actor/supervisor context
(which actor, spawned where). The same information goes into `--check-json`-style NDJSON on
`MARCH_PANIC_JSON=1` so an LLM reading a crash gets structure, not an address.
**Effort.** 1 session after A2.

---

## 17. Consumers

| Consumer | What it gets from this plan |
|---|---|
| **LSP** | quick-fixes keyed on code (D3+D4) instead of message text; `codeDescription` links to `--explain` pages; two-span diagnostics render as related-information (D5) |
| **`forge fix`** | every D4 fix auto-applies; codes make its rules declarative |
| **`march-lang` skill / LLMs** | "on `E2001` do X" instead of prose matching; D1 messages name the fix; D8 measures the result |
| **Maintainers** | T1 one-screen triage; T2 flake-free bisection; T3/T4 as the companion plan lands |

## 18. Order, effort, risks, open questions

**Order.** T1 first (one session, pays on the next bug, no dependencies). Then D1 and D3's
infrastructure in parallel; D7's driver as soon as D1 has something to pin. D4/D5/D6 follow D3
(they key on codes). D2 after B0's numbers say what `--table` may cost. D8 once D1–D4 exist.
T2 any time. T4 waits on A2.

**Effort.** T1 1, T2 ½, D1 1–2, D2 2, D3 ½ + ~1 per phase, D4 ~½ each, D5 2–3, D6 1, D7 1 + growth,
D8 ½ sessions. Roughly three weeks of sessions for the whole of Part D, most of it independent.

**Risks.**

| Risk | Mitigation |
|---|---|
| D1's stack disagrees with the grammar (arrow-form `fn`, `with … do`, protocol blocks) | push only constructs the filter already tracks; message says "still open", a hint not a verdict; D7 pins false positives red |
| `--table` slows parsing | measure with `compile-time-bench.sh --corpus small`; D2's probe can stay on code mode via a second grammar build if needed |
| Making `~code` required is a 134-site typecheck migration | one PR per phase; a temporary `E9999` placeholder is **not** allowed (doc-lint rejects it) |
| Catalogue pages rot | each page's failing program **is** the D7 corpus file; doc-lint checks every emitted code has a page |
| D5's binder-span-in-env changes a hot path | spans are already in `type_map`; measure typecheck with `--timings` before/after |
| Message churn breaks the 24 existing substring tests | migrate them into D7's corpus in the same PR |

**Open questions.**
1. Code ranges: per-phase numeric blocks (above) or short prefixes (`P`, `T`, `C`)? Plan assumes
   numeric with phase ranges; decide before the first migration PR.
2. Does `gen-lang-docs.py` tolerate a subdirectory, or does `specs/lang/errors/` need its own
   generator stanza?
3. D5: binder span in the env entry vs. a side table keyed by binder name + scope depth.
4. D2: incremental API everywhere, or only re-parse with `--table` *after* a code-mode failure
   (zero cost on the happy path, two grammars to keep in step)?
5. D8: which model, how many programs, and does the metric live in `specs/benchmarks.md`
   (dated snapshot) or nowhere in-repo?

## 19. Review record

**Not yet reviewed.** Facts in §2 were checked against the source on 2026-10-05
(`errors.ml`, `parser.mly`, `token_filter.ml`, `typecheck_unify.ml:67–128`, `typecheck_env.ml:1359`,
`test_compiler.ml`, `bin/main.ml:2140–2160`, `dune-project`). The designs in D1, D2 and D5 have not
had an independent read; the companion plan's history (four blockers found per review, twice)
says one is owed before D1 or D5 starts.
