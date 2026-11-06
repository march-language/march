A failing test reads like a compile error (2026-11-05).

Before, a failed `assert (a == b)` printed `assert failed at file:line` and both values
(interpreted) or just `assertion failed` (compiled, which is what `forge test` runs). A plain
`assert cond` said `condition was false`. A property failure was a block of `counterexample:` /
`raised:` / `reproduce with seed:` lines behind `error: panic:`, and a panic in a test body
was its bare message.

Now each is a report in the diagnostic house style, printed the same interpreted and compiled:

- **`assert`.** A `-- TEST FAILURE --` header, a sentence (`The two sides of this == are not
  equal. [assert_failed]`), and the asserted expression under a caret. For a comparison it
  shows both sides, each labelled by its source text (`left user`, `right expected`; a literal
  has no label). For `==` it marks the first difference: the differing element, field or
  constructor argument, a list length mismatch, or a string's first differing character. It
  then says where (`They first differ at .tags[1]`). A value wider than 60 columns is shown
  elided, as only the path to the difference (`[…, 170, …]`). A long string gets a window
  around the difference. For `!=` it prints the shared value. When both sides print the same,
  it says so (custom `Eq`, NaN).
- **`Check.all`.** The header points at the `Check.all` call. The report gives the run that
  failed and the shrunk input bound to the property's own parameter name (`xs = [0, 1]`, or
  one line per name when the property `match`es a tuple apart), with the original input it
  shrank from. Then why it failed: `false`, a panic, or the inner assertion's whole report.
  Last is the seed, with `forge test --seed=N` (or a note that the config fixes it).
- **Panic in a test body.** `This test panicked: <message> [test_panicked]` with the test's
  `test "..."` line under the caret.

New codes: `assert_failed`, `property_failed` and `test_panicked`, in a new `TEST FAILURE`
category. They have no `--explain` pages: a page's pointer prints once per process, which
would make interpreted and compiled output differ.

How:

- `lib/errors/test_report.ml` renders headers through `Errors.render_diagnostic` (no colour, so
  a compiled constant and the interpreter's copy match). It also holds the value differ, which
  works on printed forms: it parses `to_string` output back into lists, tuples, records
  (`{ k: v }` and a derived Show's `Name { k = v }`), constructor applications, strings and
  leaves, so it needs no types. An unreadable value is one leaf.
- Interpreter: `Eval`'s `EAssert` arm builds the report on failure. Operands are printed with
  `show_dispatch`, the same as `to_string`, and a String operand is quoted.
- Compiled: `Lower_expr`'s `EAssert` arm binds both operands once and compares them with the
  original operator, at the original spans, so dispatch is unchanged. On failure it calls the
  new codegen builtin `__assert_fail(meta, to_string(l), to_string(r))`. `meta` is the header
  rendered at compile time, plus the operator, the source labels and quoting flags.
  `march_assert_fail` (runtime/march_runtime.c) is a line-for-line C port of the differ and
  renderer, and panics with the report. `__test_header`, emitted first in each test body by
  `Lower_tests`, gives `march_test_run` the test's panic header. The failure buffer grew from
  4 KiB to 16 KiB.
- `Check.all` / `Check.all_with` with a lambda property are rewritten by desugar into
  `Check.all_reported(g, prop, cfg, header, names)`. The report is built in March
  (stdlib/check.march), so both backends print it the same. Not done in a module that declares
  its own `Check`. A non-lambda property reports its input as `input = …`.
- Both runners print a report as it is. They indent only non-empty lines, wrap any other panic
  in the test's header, and drop the old `error: panic:` prefix. The `FAIL: "name"` lines,
  dots, the `Finished: N tests, M failures` / `=== … ===` summaries and the exit codes are
  unchanged.
- `Gen.one_of` now shrinks toward its earlier alternatives (`bind(int(0, n - 1), …)`, which
  makes the same draw, so generated values are unchanged).

Tests: `test/run_test_reports.exe` (suite `test_reports`, registered in run-tests.sh and
affected.sh) runs `test/test_reports/*.march` interpreted and compiled, and both must equal the
`.expected` golden: 13 assertion cases, 3 properties, 2 panics and a plain record.
`test/stdlib/test_check.march`'s shrink test now looks for `n = 50`.

Docs: docs/error-messages.md has a new section, "12. Test failures", with a failing
`assert ==` and a failing property. Its outputs are generated:
`<!-- error-tour: <name> --test -->` makes scripts/gen-error-tour.py run `march test`
(MARCH_PROP_SEED=42) and keep the `FAIL:` blocks. scripts/gen-lang-docs.py's marker regex
accepts the option. The playground only checks programs, so it doesn't list them.
docs/property-testing.md's failure examples and the march-test skill show the new output.

Also fixed on the way: compiled `__try_call` turned `false` into `true`
(specs/progress/2026-11-05-compiled-try-call-false-passed.md).

Left open: specs/todos/2026-11-05-test-report-followups.md,
specs/todos/2026-11-05-compiled-record-eq-helper-collision.md,
specs/todos/2026-11-05-to-string-container-strings-and-atoms.md.
