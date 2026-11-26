# File.close loses a buffered write's error (2026-11-10)

`File.open_write` streams are stdio-buffered (`fopen` in `march_file_open_write`), so
`File.write_to` usually only fills the buffer and returns `Ok(())`. A failure that only
the final write reports (disk full, `EDQUOT`, an NFS error) surfaces at `fclose`, and that
result is ignored: `File.close` is `handle_close`, whose FILE release calls
`march_file_close` -> `fh_close` -> `fclose` and discards the return value. So `File.close`
returns `Ok(())` after silent data loss. The same holds when an unclosed handle is released
by its destructor (there is nobody to report to then).

The interpreter matches: `close_out` errors are swallowed in `file_close`.

Fix options (ocap phase 2 Task 4 review, Minor 1; ruling: no new builtin in Task 4):

1. A raw stdlib-only builtin `file_flush : Int -> Result((), FileError)` (`fflush` +
   errno -> FileError), called by `File.close` inside an enter/leave bracket before
   `handle_close`. Simple; covers the explicit close, not the destructor path. A write error
   after the flush is impossible since nothing is buffered.
2. Make the release report failure: `march_handle_close` returns a status from the FILE
   releaser (`fclose`'s result) when it performs the release itself, and `handle_close`
   grows a variant that hands it back. Covers the race where close defers the release to the
   last `handle_leave` only if the error is stored in the box for a later query.

Option 1 is the smaller change and mirrors what most runtimes do (`close` = flush + close).
Test: write to a full filesystem (`/dev/full` on Linux: `open_write("/dev/full", Truncate)`,
`write_to(h, "x")`, `close(h)` must be `Err(IoError(_))`).

## Fixed (2026-11-25)

Option 1. A stdlib-only builtin `file_flush : Int -> Result((), FileError)`
(`march_file_flush` in runtime/march_runtime.c: `fflush` on a write stream, `Ok(())` on a
read stream; the interpreter flushes the out channel). `File.close` enters the handle,
flushes, leaves, then closes, and returns the flush's error; the handle is closed either
way. `File.with_open_write` closes after `f` returns and answers `Ok(Err(IoError(msg)))`
when that flush fails (it discarded the close's result before).

Test: `test/native/file_close_flush_error.march`, compiled and interpreted. It runs under
`trap '' XFSZ; ulimit -f 1`, which makes the flush of 3000 buffered bytes fail with EFBIG
on macOS and Linux, so `/dev/full` is not needed. Before the fix both engines printed
`close: ok`.

Still as before: a handle that is never closed is flushed by its release, with nobody to
report a failure to (option 2 of this file, not done). The interpreter's `file_close`
still ignores `close_out`'s error for the same reason: after the flush in `File.close`
nothing is buffered, so only the release path can reach it.
