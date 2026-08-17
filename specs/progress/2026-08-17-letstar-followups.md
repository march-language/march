`[P3]` - [x] **Both `let*` follow-ups from `specs/todos/2026-08-14-letstar-repl-and-parse-module-gaps.md`. Done 2026-08-17.**

## 1. `let*` now works with the parser combinator library

`let*` resolves `M`'s `flat_map` in the module named `M`. The combinator
library's type was `Parser` but its module was `Parse`, so `let*` over a
parser reported "`Parser.flat_map` doesn't exist" — **the one library the
sugar was designed for was the one library it did not work with** (the
plan's own §4.3 worked example is a parser).

**Chosen fix: rename the module `Parse` → `Parser`**, so type and module
names agree the way they already do for `Option`/`Result`/`List`.

The alternative — teaching `let*` a second resolution path, falling back to
the module that DECLARES the type (available as `ctor_info.ci_module`) —
was investigated and rejected. It would avoid the `Parser.Parser(a)` stutter
that external type annotations now carry, but `<M>.flat_map` is constructed
independently in **three** layers, each from its own tables:

- `lib/typecheck/typecheck.ml`'s `ELetStar` (`env.vars` / `resolve_qualified_var`)
- `lib/tir/lower.ml` (emits `head_name ^ ".flat_map"` from `type_map`)
- `lib/eval/eval.ml`'s `ELetStar` (`type_name_of_value` + runtime env)

Adding a fallback means adding it to all three and keeping them in agreement
forever. This codebase has been bitten by exactly that shape before, and the
drift was **fail-open** — see `lib/ast/calls.ml`'s header, written after the
same walk existed in three copies. The rename needs no compiler change at
all. If a second library ever wants to break the convention, revisit then,
as one decision rather than two.

**What changed:** `stdlib/parse.march` → `stdlib/parser.march` with
`mod Parse` → `mod Parser`; the manifest entry in
`lib/modules/stdlib_manifest.ml`; the 129 `Parse.` call sites in the two
test files; `docs/parsing.md`.

Also had to update `test/test_stdlib_march.ml`'s **own** stdlib load list,
which is separate from the production manifest — the drift this repo has hit
before. Symptom was `unbound variable: Parser.run` in every parser test while
the module itself compiled fine.

**Verified:** the plan's §4.3 motivating example (a count prefix choosing how
many items follow — genuinely context-sensitive, not expressible
applicatively) now runs interpreted and compiled at `--opt 2`. Corpus witness
`specs/lang/types/accept/t185_letstar_parser_combinator.march`.

## 2. `let*` at the REPL

`let?` had a dedicated `ReplLetQ` form; `let*` had none, so `let* x = e` at a
prompt was a parse error.

**Semantics.** There is no continuation at a prompt, so this cannot be the
ordinary `ELetStar` expansion. `Eval.letstar_repl_bind` runs the value's own
`flat_map` with a callback that captures the value it is handed and returns
the **original monadic value** — which is well-typed as the callback's `M(b)`
for any `M`, without needing a generic `pure` the language does not have.
`flat_map`'s result is discarded; only the captured payload matters.

Binds the **first** value yielded. For `Option`/`Result` there is at most
one, so that is exactly "unwrap" and matches `let?`. For a multi-value monad
like `List` the callback runs per element and the first wins, which is the
reading `let* x = [1,2,3]` most naturally suggests. A value that yields
**nothing** (`None`, `Err`, `[]`) binds nothing and says so, rather than
silently leaving the name unbound.

**What changed:** `ReplLetStar` in `lib/ast/ast.ml`; `LET STAR` productions
in `repl_input` and `repl_sequence` (**no new grammar conflicts** — 10 before,
10 after); `Typecheck.check_letstar_repl`, which shares `ELetStar`'s exact
resolution so a prompt can never resolve a different `flat_map` than the same
line inside a function; `Eval.letstar_repl_bind`; and the three REPL front
ends (terminal, notty TUI, browser).

**One real gap found while testing.** `type_name_of_value` reads
`ctor_type_tbl`, which is populated from March-source `DType` declarations.
`Option`/`Result`/`List` are **builtin** types with no such declaration, so in
a REPL session they resolved to `None` and `let* x = Some(1)` — the first
thing anyone would try — reported "cannot determine the type", while a
user-defined type worked. Fixed with a contained builtin-constructor map in
`letstar_repl_bind`, mirroring the same builtin triple eval already spells
out for its collision seed. A user-defined type needs none of it.

## Verification

- 7 new tests in `test/test_eval.ml` covering `Option`, `Result`, `List`
  (first-value), a user-defined type, and all three yields-nothing cases.
  They go through `parse_repl`, so they also pin the new `LET STAR`
  productions. Proven non-vacuous by sabotage: capturing the LAST value
  instead of the first fails exactly the List test, and only that test.
- `specs/lang/types/accept/t185_letstar_parser_combinator.march`, checked
  and run.
- Manual REPL session: `Some`/`Ok`/list bind; `None`/`Err`/`[]` report and
  bind nothing; a non-monadic RHS (`let* d = 5`) is rejected at typecheck
  with the `Int.flat_map` message and leaves no binding behind.
- `march test stdlib/parser.march` — 151 doctests pass after the rename.
- Full local suite.
