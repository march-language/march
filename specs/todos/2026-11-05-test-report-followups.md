`[P3]` Test-failure reports: follow-ups (from specs/progress/2026-11-05-test-failure-reports.md).

- **Panic location.** A panic in a test body points at the `test "..."` line, not the line
  that panicked. The interpreter knows the line (its frame stack). Compiled code records a site
  only for `panic` / `todo` / `unreachable` (`march_panic_site`), not for a division by zero, a
  match failure or a runtime check. Pointing at the panic line needs a site for every
  runtime panic on the compiled side, or the two backends would print different reports.
- **`Gen.frequency` does not shrink toward its first alternative.** It picks with
  `Random.choice_weighted`, which has no index to shrink. Shrinking needs an index draw that
  consumes the same RNG (as `one_of` now does with `bind(int(0, n - 1), …)`).
- **Strings inside a property's input print unquoted** (`s = hello`). `Check` is generic and
  prints with `to_string`, which leaves a top-level String bare. The assert path quotes a
  String operand because it knows the type statically.
- **Custom `Show`.** The differ reads printed forms back. A custom `show` that prints
  something it can't parse is compared as one leaf: correct, but the caret marks the whole
  value.
- **JS target.** `__assert_fail` throws the header only (the value diff is native); fine for
  the browser REPL, worth a diff if JS tests become a thing.
- **`--explain` pages** for `assert_failed` / `property_failed` / `test_panicked`. A page's
  pointer prints once per process, so the interpreter would print it once and a compiled binary
  under every report (its header is rendered per assert at compile time). Adding pages needs the
  pointer suppressed for these codes first.
