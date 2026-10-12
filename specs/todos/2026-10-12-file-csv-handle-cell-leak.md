# `[P3]` File and CSV handle cells are never released

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
