# test_codegen.ml's WithLines fixture missed `needs IO.FileRead` (2026-08-08)

`test_file_with_lines_streaming_compiled` in `test/test_codegen.ml` compiles a
`WithLines` module that calls `File.with_lines`, but the fixture only declared
`needs IO.Console`. This went unnoticed until `caps: the capability ceiling is
on by default` (#225) landed on `main`, at which point `march --compile`
started rejecting the fixture outright:

```
-- CAPABILITY CEILING --
module `WithLines` uses `IO.FileRead` but does not declare `needs IO.FileRead`
```

Confirmed via `main`'s own CI (both `test (ubuntu-24.04)` and `test
(macos-15)`) failing this exact way at commit `3e64f851` and again at
`487f39b3` — a pre-existing break on `main`, unrelated to the `file_open`
`FileError` representation fix in this same PR. Fixed by adding the missing
`needs IO.FileRead` line to the fixture module.
