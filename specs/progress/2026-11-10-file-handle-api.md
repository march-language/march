# File.Handle: open, open_write, read_line, read_chunk, write_to, seek, close, with_open (2026-11-10)

Ocap phase 2, Task 4 (plan: `specs/plans/2026-11-10-ocap-p2-handles-plan.md`).

- `stdlib/file.march`: `FileError` gains `Closed` (last, so the runtime's
  `FILEERR_*` tags are unchanged) and derives `Eq`; `type WriteMode = Truncate | Append`;
  `open`, `open_write`, `read_line`, `read_chunk`, `write_to`, `seek`, `close`, `with_open`,
  `with_open_write`. Each use goes through one private `with_raw`, which brackets the raw
  call with `handle_enter` / `handle_leave` (kind FILE = 1), so a concurrent `close` defers
  the release until the use leaves. `with_lines`, `with_chunks`, `each_line` and
  `each_chunk` keep their signatures and now open a handle.
- Three raw builtins, at every builtin site (typecheck signature + cap table,
  `path_arg_builtins`, `Cap_symbols.table`, `cap_infer`, `llvm_builtins` row + preamble,
  borrow table, defun direct-call list, purity, the golden preamble, interpreter, C):
  - `file_open_write : String -> Int -> Result(Int, FileError)`: `fopen` `"wb"` / `"ab"`
    into the existing `fh_open` table; `IO.FileWrite`; path at argument 0.
  - `file_write_handle : Int -> String -> Result((), FileError)`: no capability.
  - `file_seek : Int -> Int -> Result(Int, FileError)`: absolute; returns the new offset,
    tagged `(n<<1)|1` in the `Ok` payload like `tcp_connect`'s fd. No capability.
- Interpreter: write streams are `out_channel`s; a table (`write_chans`) remembers them so
  `file_seek` uses `seek_out`, `file_close` flushes with `close_out`, and the read builtins
  return `None` on them.
- Tests: `test/stdlib/test_file_handle.march` (stdlib_march, and a `march test` rule in
  `test/dune` that typechecks it); `test/native/file_handle_box_leak_probe.march` (10 000
  open + drop without close, 10 000 open + close + drop, then the `/dev/fd` count is
  unchanged). With the FILE release removed from `march_handle_dtor` the probe reads
  `fds before 4, after 10004`.
- Deferred to Task 10: the "handle needs no capability" test is in the file, commented out
  and marked `-- passes after Task 10`. Besides the ceiling still charging `IO.FileRead`, a
  module-level `needs ()` line does not parse today (only the fn-level bound does).
