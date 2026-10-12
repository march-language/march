# File and directory builtins, and print_stderr, leaked their String arguments

**Fixed** 2026-10-12. Found by the LSan pass of the native sanitizer sweep
(`scripts/native-sanitize-sweep.sh -l`): seven `*_leak_probe` fixtures
(`timer_leak_probe`, `simd_leak_probe`, `native_arr_fold_leak_probe`, ...)
each reported one `march_string_concat` string from `march_main`: the line
`IO.warn` printed (`print_stderr(s ++ "\n")`). Listed as one-shot in
`specs/todos/2026-10-12-lsan-sweep-remaining-leaks.md`; it is per call.

## The bug

`print_stderr` and the path-taking file builtins (`file_exists`,
`dir_exists`, `file_open`, `file_read`, `file_write`, `file_append`,
`file_delete`, `file_copy`, `file_rename`, `file_stat`, `dir_mkdir`,
`dir_mkdir_p`, `dir_rmdir`, `dir_rm_rf`, `dir_list`) sat in
`Borrow.extern_owned_builtins`, so Perceus handed each a reference to every
String argument and released nothing after the call. The C implementations
only read the bytes (`fwrite`, `fopen`, `stat`, `remove`, `rename`, `mkdir`,
`opendir`; an error copies the path into a new string). Every call leaked its
path (and `file_write` / `file_append` their data); every `IO.warn` and every
line of the stderr logger appender leaked the line.

## The fix

The sixteen builtins move to `Borrow.extern_borrow_table` with every String
argument borrowed. The handle-taking builtins (`file_close`,
`file_read_line`, `file_read_chunk`) take an Int and stay owned.

## Verification

- `test/native/file_path_builtins_leak_probe.march`, 200 calls each: a missing
  file (exists + read), write / append / read / delete, `Dir.mkdir_p` /
  `Dir.exists` / `Dir.rm_rf`, and `IO.warn`: 200 / 400 / 200 / 200 leaked
  objects before, 0 after. The path is read again after every call.
- Linux arm64 ASAN error pass and LSan pass on the probe and the seven
  `*_leak_probe` fixtures that reported the `IO.warn` line: no errors, and
  the line is no longer reported.

The file and CSV HANDLE cells themselves (`march_file_open` /
`march_csv_open`) still leak: the handle is typed `Int`, so nothing counts
references to it. Filed as `specs/todos/2026-10-12-file-csv-handle-cell-leak.md`.
