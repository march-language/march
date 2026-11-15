# ocap phase 2b: `File.open_dir` / `open_dir_write` take phase 1's `CapError` shape

Logged 2026-11-12. Ruling R2 (specs/plans/2026-11-10-ocap-p2-handles-plan.md, "If
phase 1 lands first") applied to Task 7's directory handles after the branch merged
phase 1 (see 2026-11-11-ocap-p2b-merge-p1-wrapping.md for the Socket/Udp/Tls opens).

## Wrapped (before -> after)

- `File.open_dir(path)`: `Result(File.Dir, FileError)` ->
  `Result(Result(File.Dir, FileError), CapError)`, `Authority.check("IO.FileRead", path)`
  before the open (the capability `dir_open` is charged).
- `File.open_dir_write(path)`: same shape, `Authority.check("IO.FileWrite", path)`
  (the capability `dir_open_write` is charged).
- The raw opens are the private `File.open_dir_raw` / `open_dir_write_raw`, allowlisted in
  test/test_cap_check_coverage.ml like `File.open_raw`. `dir_open` / `dir_open_write` have
  `Checked { gated = false }` rows in lib/caps/cap_ops.ml (phase 2 gates them itself:
  they are already stdlib-only).

## Not wrapped

- `File.open_in`, `open_write_in`, `list_in`, `close_dir`: they take a `File.Dir` the
  caller already opened through a checked open and open no new authority (spec §6: using a
  handle needs no authority), as `Tls.connect(s, ..)` stayed unwrapped.

## Tests

- test/stdlib/test_file_dir.march and test_codegen.ml's dir_beneath_symlink_linux use
  `Authority.must(File.open_dir*(..))`.
- test/cap_conformance/file_refused.march: both opens refused by the launch grant.
