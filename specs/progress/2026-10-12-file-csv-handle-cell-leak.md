# `[P3]` File and CSV handle cells were never released (FIXED)

Found by the 2026-10-12 LSan sweep: `close_returns_ok_atom` and
`csv_niche_row` report the 24-byte `march_file_open` cell and the 40-byte
`march_csv_open` cell, one per open.

`file_open` / `csv_open` return `Result(Int, _)`: the handle is a heap cell
(field 0 the `FILE*`) passed around as an `Int`, so Perceus never counts or
releases it. `file_close` / `csv_close` close the stream and zero field 0
(so a second close is a no-op, which `close_returns_ok_atom` pins), but
cannot free the cell: the program may still hold the Int and close it again.
Every open leaks one cell.

Options: an opaque heap type for the handle (`FileHandle`) so RC owns the
cell and its destructor closes a still-open stream; or a runtime handle table
indexed by the Int, with a generation so a stale handle is detected rather
than reused.

## Fixed 2026-10-12 (runtime handle table)

The contained option was the second one: a runtime handle table with a
generation. No representation change at the March level was needed, since
the handle stays an `Int`.

- `fh_open` puts the `FILE*` (and, for CSV, the delimiter and mode) in a slot
  of a mutex-guarded table and returns `-2 * (1 + (slot | gen << 24))`.
  `fh_close` fcloses the stream, bumps the slot's generation and puts the slot
  on a free list. `fh_lookup` returns NULL for a closed or stale handle. All
  three are in `runtime/march_runtime.c`; `march_file_open`, `march_file_close`,
  `march_file_read_line`, `march_file_read_chunk`, `march_csv_open`,
  `march_csv_close` and `march_csv_next_row` go through them.
- **Why a negative even number.** The handle travels as the `Ok` payload of a
  `Result(Int, _)` and through any generic slot. Compiled code untags such a
  slot conditionally (an arithmetic shift only when the value is odd), so an
  even value comes back unchanged under either slot convention, just as the
  old raw pointer did. A negative value also fails `IS_HEAP_PTR`, so no RC op
  can ever take it for a cell. The magnitude stays below 2^56, inside a 63-bit
  Int.
- **Kept behaviour.** A second close is a no-op returning `:ok` (pinned by
  `close_returns_ok_atom`), and a read after close is end of stream. New: a
  closed handle whose slot was reused by a later open still reads as closed,
  because the generations differ. Before, the zeroed cell gave the same answer
  only because the cell was never freed.
- The interpreter keeps its own handles (`lib/eval/eval.ml`) and is unchanged.

**Verification.** `test/native/file_handle_leak_probe.march`, 300 opens each:
`file_open` + read + `file_close` 301 -> 0 objects; `Csv.read_all` 301 -> 0.
The stale-handle legs print the same results before and after. Run on the
Linux arm64 ASAN error pass over the full native sweep, at 1 and 14
schedulers: clean, including `close_returns_ok_atom`, `csv_niche_row` and the
new probe.
