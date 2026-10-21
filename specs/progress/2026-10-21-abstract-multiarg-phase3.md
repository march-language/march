Refinements: the two-argument sugar `k -> v -> Bool[p]` / `Assoc(k[p], v[p])` (multi-arg design phase 3)

Phase 3 of `specs/2026-10-18-abstract-refinements-multi-arg-design.md` (§1.1, §1.2,
§9 "Phase 3"). Phase 2 (`38635a08f`, `specs/progress/2026-10-21-abstract-multiarg-phase2.md`)
landed the long form; this phase makes the shorthand mean it.

## Before / after

```march
type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))
fn filt(a : Assoc(k, v), keep : k -> v -> Bool[p]) : Assoc(k[p], v[p]) do
  match a do
    ANil -> ANil
    ACons(k, v, t) -> if keep(k, v) do ACons(k, v, filt(t, keep)) else filt(t, keep) end
  end
end
```

| Row | Program | Before (`38635a08f`) | After |
|---|---|---|---|
| s3 | the `filt` above | W1 error: "`p` is applied to 1 of the callback's 2 arguments" (the inner arrow alone was the definer) | `p` abstract, arity 2; the return is the relation; `filt`'s return proved |
| a2 | `need_pos(filt(a, fn (_k, v) -> v > 0))` | (rejected signature) | proved, as with the long form |
| rel | `need_arel(filt(a, fn (k, v) -> v > k))` | (rejected signature) | proved |
| a1-bad | `bad(a, keep) : Assoc(k[p], v[p]) do a end` | (rejected signature) | not proved (`unreflectable-subject` skip), as with the long form |
| W2 | `… : Assoc(k, v[p])` under `k -> v -> Bool[p]` | W1 error | W2 error: "… not one slot: mark every slot it relates, `Assoc(k[p], v[p])`." |
| AR4 | `need(xs : List(Int[p]), k : Int -> Int -> Bool[p])` | W1 error | W2 error: "… not one slot (`List` has 1 type argument): mark every slot it relates, `T(Int[p], Int[p])`." |
| s2 | `k : (a, a) -> Bool[p]` | parse error "…from a ONE-argument callback; this one takes several." | parse error "A tuple domain `(a, a)` is ONE tuple argument, so `Bool[p]` over it cannot relate its parts. A callback of 2 arguments is curried: write `a -> a -> Bool[p]`." |
| ctl | `keep : k -> Bool[p]`, return `Assoc(k[p], k[p])` | two unary slot facts | unchanged (the expansion is the identity) |
| arity 1 | every `a -> Bool[p]` in the stdlib and the AR corpus | | unchanged: oracle IDENTICAL, audit byte-identical |

## What changed

- `lib/parser/parser.mly`, semantic actions only (no production change; menhir still
  reports **7** shift/reduce conflicts):
  - `abstract_definer_arrow` marks the codomain it generates with the binder
    `Some "_"` (a user cannot write `{_ : Bool | …}`).
  - When the codomain is `TyArrow (d2, …)` ending in that marked definer
    (`definer_chain`), the outer arrow extends the chain: it binds its own domain (the
    user's binder, else `"$x" ^ string_of_int (depth + 1)`) and prepends it to `p`'s
    arguments (`prepend_definer_arg`). The innermost binder stays `$x`, so an arity-1
    definer's output is byte-for-byte what it was apart from the marker.
    `k -> v -> Bool[p]` is
    `({$x2 : k | true}) -> ({$x : v | true}) -> {_ : Bool | _ == p($x2, $x)}`;
    three domains give `p($x3, $x2, $x)`.
  - A chain whose domains name one binder twice is a parse error ("`x` names two of
    them").
  - The tuple-domain message (s2) is corrected and writes the whole chain, e.g. for
    `(a, b) -> c -> Bool[p]`: "A callback of 3 arguments is curried: write
    `a -> b -> c -> Bool[p]`". `()` as a domain has its own message.
- `lib/ast/ast.ml` `show_ty`: the marked codomain prints `Bool[p]`, and a domain
  carrying a synthetic `$x…` binder prints as its base, so the chain prints
  `k -> v -> Bool[p]` (and `v -> Bool[p]` at arity 1). The long form is not
  prettified.
- `lib/format/format.ml`: `definer_chain` prints a marked chain of any length as the
  shorthand (`k -> v -> Bool[p]`, `({ x : Int | x > 0 }) -> v -> Bool[q]`). The old
  case matched an UNMARKED arity-1 codomain; it now matches only the marked one (see
  the rulings), so a user's spelled-out long form prints as written.
- `lib/refinecheck/refine_abstract.ml`:
  - `expand_markers` / `expand_markers_fn`: the pre-pass. For each `DFn` (nested
    `mod`s included), `nary_arities` finds every name with a well-formed chain
    definer of n ≥ 2 arguments. In each type application, exactly n slots marked
    `T[p]` become `T({$s0 : k | true}, {$s1 : v | p($s0, $s1)})` (the relation on the
    last marked slot; binder numbers continue across the signature's applications).
    Any other count is left as written, and `check_nary` reports each marked slot as
    W2. A decl with nothing to expand is returned physically unchanged.
  - `check_nary`'s W2 single-slot message: the fix is the sugar (`mark every slot it
    relates, `Assoc(k[p], v[p])``); an application with fewer slots than `p` relates
    says so and uses `T(…)`.
- `lib/refinecheck/refine_check.ml` `check_module`: expands `m.mod_decls` (and
  `pre_desugar_decls`, so the audit's pre/post comparison sees the same signatures)
  before anything else. The module record is reused when nothing was expanded.

## Tests

New group `abstract-multiarg-sugar` in `test/test_refinecheck.ml`, 13 cases,
registered after `abstract-multiarg`. RED evidence: the final test files were run in a
worktree of the base `38635a08f` with only the test files replaced plus a one-line
identity stub `expand_markers_fn fd = fd` (so the file compiles; never committed):
`11 failures! in 0.041s. 13 tests run.` The two passing on base are controls by
design (6, 11). RED lines (assertion, Expected → Received):

| # | Case | RED on base |
|---|---|---|
| 0 | s3 roles = s1 long form, `D=` included | `[("p", ["+"; "D="])]` → `[("p", ["+"; "+"; "D="])]` |
| 1 | chain binders `$x2, $x`; a named domain keeps `x`; three give `$x3, $x2, $x` | `[["$x2"; "$x"]]` → `[["$x"]]` |
| 2 | the expansion is `Assoc({$s0 : k \| true}, {$s1 : v \| p($s0, $s1)})` | "did not expand to the long form" (stub) |
| 3 | W2: `Assoc(k, v[p])`, fix `Assoc(k[p], v[p])` | `single slot:` `true` → `false` (base: the W1 message) |
| 4 | W2: three marked slots of a two-argument `p` (`Tri(k[p], v[p], v[p])`) | `count:` `true` → `false` |
| 5 | the sugar has no misuse error | `[]` → `["… is applied to 1 of the callback's 2 arguments …"]` |
| 6 | control: `Assoc(k[p], k[p])` with a one-argument `p` keeps two unary facts, expansion is `==` the input | passes on base |
| 7 | s2: "is ONE tuple argument", "write `a -> a -> Bool[p]`" | `one argument:` `true` → `false` (base: "…takes several.") |
| 8 | a chain naming `x` twice is a parse error | `duplicate:` `true` → `false` (base: parsed) |
| 9 | `show_ty`: `k -> v -> Bool[p]`, `v -> Bool[p]`, round-trip, long form not prettified | `"k -> v -> Bool[p]"` → `"k -> { $x : v \| ... } -> { Bool \| ... }"` |
| 10 | a1 through sugar: `filt`'s return proved, the same verdicts as the long form | `all proved` → `[("skipped", "unconstrained-subject"); …]` |
| 11 | a1-bad through sugar: not proved | passes on base (control: base proves nothing either) |
| 12 | a2 / rel / m4 through sugar: `[proved; too-weak]`, `[proved]`, equal to the long form | `[proved; too-weak]` → `[("skipped", "parametric-source-unproved"); …]` |

Edited existing tests, deliberately:
- **AR phase 4's "a curried Bool[p] proves nothing and violates nothing"**
  (`abstract-sugar`) is rewritten as "a curried Bool[p] on one slot is a W2 error naming
  the fix". Its program (`need(xs : List(Int[p]), k : Int -> Int -> Bool[p])`) has been
  rejected since phase 2 (W1), so the old (0 proved, 0 violated) assertion was vacuous.
  It now asserts exactly one `abstract_refinement_misuse` error, the W2 text "takes 2
  arguments, so it relates 2 slots of one type application" and the fix "mark every slot
  it relates, `T(Int[p], Int[p])`". RED on base: `single slot:` `true` → `false` (base
  gives the W1 message).
- Phase 2's "W2: a two-argument p on a single slot is an error naming the relation"
  (`abstract-multiarg`): its fix assertion was the long form, which phase 2's ruling
  said phase 3 would reword. It now asserts `Assoc(k[p], v[p])`. RED on base: `fix:`
  `true` → `false`.
- `test/test_fmt.ml`: new case "two-argument abstract refinement shorthand" (parses,
  idempotent, `pred : k -> v -> Bool[p]`, `({ x : Int | x > 0 }) -> v -> Bool[q]`, a
  long form stays long, no `$x`). RED on base: `named domain keeps its binder` `true` →
  `false`.

Grammar corpus (`specs/lang/grammar/`):
- `parse/p43_abstract_refinement_two_argument_sugar.march`: on base it is rejected (the
  W1 error); now `--check` exit 0 with `filt`'s return proved (3 proved, 0 skipped).
- `reject/r20_bool_sugar_two_argument_single_slot.march`: `-- EXPECT-ERROR: not one slot:
  mark every slot it relates, `Assoc(k[p], v[p])``.
- `reject/r19`'s `-- EXPECT-ERROR:` and its INDEX row carry the new s2 text. INDEX
  counts: 60 = 43 parse + 17 reject. `check_grammar.sh`: `60 passed, 0 failed`.

Golden error corpus: neither the s2 nor the W2 message appears in
`test/errors/*.expected`; nothing to regenerate.

Tree-sitter: no `grammar.js`, `known-failures.txt` or `keyword-allowlist.txt` change.
`scripts/check-tree-sitter.sh`: `tree-sitter: 1663/1667 files parse clean; 4 known
failures` / `check-tree-sitter: ok`, so p43 parses. One local trap: an untracked,
ignored CAS directory `examples/choreo_demo/.march/` (dated 2026-10-13, from an
earlier session) matches the ratchet's `find -name '*.march'`, and with it present the
ratchet falsely reports `test/imports/test_sibling_parse_error/test_b.march` as a stale
known failure. Moving the directory aside gives the green run above (restored after);
CI has no such directory. A clean base worktree is green too.

## Verification

- **Arity-1 equivalence (AR phase 4's D6, re-run).**
  - `scripts/refine-oracle.sh`: baseline at `38635a08f` before any edit (549
    fixtures, 8726 lines, as in phase 2). After the change: `REFINEMENT DIAGNOSTICS
    IDENTICAL (8726 lines over 549 fixtures)`.
  - The oracle was shown to go RED. A first perturbation renamed the marked codomain's
    binder to `zz`: still IDENTICAL, which shows that no reader depends on the
    codomain binder's name (the predicate's `_` is the subject either way); that is
    the fact the marker relies on. A second perturbation applied the arity-1 definer's
    `p` to `$y` instead of its binder `$x`: `DIAGNOSTICS CHANGED — 3050 differing
    lines` (for example `native_actor_call_timeout: skipped
    (abstract-refinement-uninstantiated): 32`, because the stdlib combinators' own
    definers stopped being well-formed). The file was restored (`cmp` against the saved
    copy) and rebuilt.
  - Audit: `UPDATE_SNAPSHOTS=1` over group `audit-baseline` rewrote
    `test/refine_audit/*.baseline` with no diff (byte-identical); the group then
    passes without the variable. `--refine-audit` over the 15 AR files (every
    `specs/lang/types` fixture and stdlib module mentioning `Bool[` or `_ == p(`, and
    p42), base binary vs this one, private `HOME`: identical (415 lines each).
  - `specs/lang/types/check_types.sh`: `492 passed, 0 failed`.
- Menhir: `menhir --explain lib/parser/parser.mly` writes `parser.conflicts` with 7
  conflicts, before and after; dune's build prints `7 states have shift/reduce
  conflicts`. (Dune does not keep `parser.conflicts` under `_build/default/lib/parser/`
  in this tree, so the count was taken by running menhir directly into the scratchpad,
  at the base and at the final parser.)
- `scripts/check-docs.sh`: `doc-lint passed`.
- Full `scripts/run-tests.sh`: `All suites passed.`, exit 0. refinecheck `1462 tests
  run` (1449 + 13); compiler 1451, eval 289, codegen 719, run_stdlib 896, stdlib_march
  80, jit 43, lsp 383 + 5 + 37 + 10 + 8, errors 290. `test_fmt` (not in the script):
  `41 tests run`, all passing.
- The final oracle run, on the final binary: IDENTICAL again (8726 lines over 549
  fixtures).

## Rulings

- Ruling: a count of marked slots other than n is left unexpanded and reported by
  `check_nary`'s existing single-slot W2 (one error per marked slot), whose fix is now
  the sugar. Why: one code path for every single-slot occurrence (`v[p]` and `{v |
  p(_)}` alike), and no double report. Cost if wrong: three markers give three errors
  where one "marks 3 slots" message would do.
- Ruling: the arity is read with `is_known = fun _ -> false`, before any table exists,
  and only from a WELL-FORMED chain definer (its arguments are exactly the chain's
  binders). Why: the pass runs before `Refine_check` builds the measure tables that
  `known_predicate_fn` reads. Cost if wrong: a known two-argument predicate named in a
  well-formed chain definer would expand its markers too, into exactly the relation the
  markers spell; a malformed definer expands nothing and W1 reports it.
- Ruling: expanded binders are numbered across the whole signature (`$s0, $s1` in the
  first application, `$s2, $s3` in the next), not restarted per application. Why: no
  two applications can then share a binder name, whatever nesting the readers apply.
  Cost if wrong: ledger text (`p($s2, $s3)` rather than `p($s0, $s1)`).
- Ruling: the formatter prints only a MARKED definer as the shorthand. Before, it also
  turned a user's unmarked long form `({x : a | true}) -> {Bool | _ == p(x)}` into
  `a -> Bool[p]`. Under an outer arrow (`Int -> ({x : a | true}) -> {Bool | _ ==
  p(x)}`) that shorthand would now re-parse as a two-argument definer, a different
  signature. Cost if wrong: a long form a user wrote stays long after `march fmt`.
- Ruling: a chain naming one binder in two domains is a parse error. Why: `p(x, x)`
  passes W1 (the arguments equal the binders) but cannot say which argument is which.
  Cost if wrong: none (such a signature meant nothing).
- Ruling: the W2 fix for an application with fewer slots than `p` relates
  (`List(Int[p])` under `Int -> Int -> Bool[p]`) says "`List` has 1 type argument" and
  shows `T(Int[p], Int[p])` from the definer's bases. Why: `List(Int[p], Int[p])` is
  not a type. Cost if wrong: message text.
- Ruling: the marker changes the core-AST dump of every arity-1 definer: the codomain's
  `"binder"` is `{"txt": "_"}` instead of `null` (`--emit-core-ast`, measured on t312).
  The typechecker reads `None` and `Some "_"` the same (`TRefine (_, "_", _)`), and no
  golden pins that JSON. `scripts/types-oracle.sh` would show those lines; it was not
  run, since this phase changes the AST by design. Cost if wrong: a consumer of the
  JSON keyed on `binder: null`.

## Not done

- `Map.filter` (phase 4).
- The unused-definer warning's example still shows the long form (`T({x0 : k | true},
  …)`); it is a warning, and the long form is still accepted.
