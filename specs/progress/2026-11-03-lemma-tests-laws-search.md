# Lemma uses beyond refinement: tests, miscompile check, specs, docs, search (2026-11-03)

Ideas 1, 2, 3 (without the status marks), 4 (text level) and 10 of
`specs/todos/2026-11-02-lemma-uses-beyond-refinement.md`. The others stay there.

## What landed

- **`march --check --lemma-test FILE`** (`lib/refinecheck/lemma_test.ml`, `bin/main.ml`
  `run_lemma_test`). For every valid lemma of the entry file
  (`Refine_check.lemma_defs`: qualified name, definition, admitted), the theorem `P` is
  evaluated in the interpreter (`Witness.eval_classified`, the witness interpreter's fuel
  and effect veto) on the parity net's inputs (`Reflect_parity.inputs`: boundary Ints,
  then `draws` = 100 random tuples from `seed` = 20261031; type variables drawn as Int;
  duplicates dropped). An input outside a refined parameter is skipped. A nested
  module's members get bare-name aliases, as the theorem names them.
  - **Idea 1.** An unproved lemma: `COUNTEREXAMPLE` with the input (RED), else
    `tested, not proved: N inputs`.
  - **Idea 2.** An admitted lemma: false in the interpreter is `FALSE` (RED). Then a
    harness program (`Lemma_test.harness`) is compiled with `--compile --opt 0` and run:
    module `LemmaHarness`, `use <lemma's module>.*`, one `pfn lemma_law__i(<params as
    written>) : Bool` per lemma whose body is the theorem as written
    (`March_ast.Lemma_source.parts`), and a `main` that panics `lemma-law-false i j` at
    the first false input. It runs up to 12 random inputs per lemma, only ones the
    interpreter decided. A panic marker is `COMPILED-FALSE`, any other nonzero exit is
    `COMPILED-FAILURE` (both RED). A harness that does not compile (a private function
    in the theorem, a `use` clash) is reported, not RED.
  - Overflow is `overflow?` (D8), never a counterexample. A parameter sort with no
    generator is `not-tested`.
  - The entry file's directory joins `MARCH_LIB_PATH` for the harness compile.
  - `MARCH_LEMMA_TEST_PERTURB=interp|compiled` (test-only) negates one side's verdict on
    admitted lemmas, so each RED path can be shown.
- **`forge test`** (`Cmd_test.run_lemma_tests`) runs `march --check --lemma-test` on every
  project source with a line that is exactly `@[lemma]`, after the tests pass, and fails
  the run on RED or on a failed check. Files without a lemma cost nothing.
- **Idea 10.** `specs/lang/refinement-types.md` (regenerated into `docs/`) and the
  `march-lang`, `march-test` and `forge-search` skills: state laws as lemmas in a
  `cap verified` module, where `lemma_unproved` is an error.
- **Idea 3 (march_doc, separate repo).** `Parser.parse_laws`/`file_laws`/`laws_about`
  read each `@[lemma]`'s theorem from its signature line; `DocHtml.render_module_laws`
  adds a "Laws" list to each function whose name a theorem calls (`name(` with no
  identifier character before it). `render_module_try` keeps its API (no laws).
  Proved/not-proved marks are NOT shown: it would need a z3 check per file during
  `forge doc`. Stays in the todo.
- **Idea 4, text level** (`lib/search/search.ml`). An `@[lemma]` is a `Lemma` entry with
  `law = Some (theorem as written, functions it calls)` (`Lemma_source.calls`).
  `--law TEXT` matches a theorem containing TEXT (case and spaces ignored) or calling a
  function named TEXT; a name search also returns lemmas whose theorem calls the name
  (score 0.75). Output prints `law: P  (about: f, g)`; the JSON carries `law`. Index
  version 3 → 4. Shape matching (`f(f(x)) == x`) is out of scope.
- `March_ast.Lemma_source` is the one source-text reader shared by the harness and
  search.

## Tests

- `test/test_refine_lemma.ml` group `reflect-lemma`, 7 new cases (`lemma_tests`):
  `lemma_test_counterexample`, `lemma_test_tested`, `lemma_test_refined_param`,
  `lemma_test_admitted` (interpreter + 12 compiled inputs per lemma for `cat_nil`,
  `cat_assoc`, `rev_cat`), `lemma_test_miscompile_red` (both perturbations RED),
  `lemma_test_erased`, `verified_unproved`.
- `forge/test/test_build_check.ml`: a counterexample fails `run_lemma_tests`, a true
  unproved lemma passes, a file with `@[lemma]` only in a comment is skipped.
- `test/test_search.ml` group `lemmas`, 5 cases.
- march_doc: `test/test_parser.march` (2) and `test/test_html.march` (2).

Each new test fails without its feature: the lemma-test rows and the `forge test` /
search / march_doc functions do not exist without it. `lemma_test_refined_param` fails if
the refinement filter is dropped (`n = -1` is a counterexample to `twice(n) >= n`).
