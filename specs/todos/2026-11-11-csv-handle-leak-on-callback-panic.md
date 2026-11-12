`[P2]` Csv.each_row and each_row_with_header leak the file handle when the callback panics (2026-11-11)

Both functions call `csv_close` only after the row loop returns. A panic in the callback unwinds past it, and the handle stays open. A caller that survives the panic (`__try_call`, a supervised actor, a test runner) loses one fd per failed call. `File.with_lines` solves the same problem with `try_finally`. `read_all` has no callback and is not affected.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
needs IO.FileRead
-- Each call opens data.csv and panics in the callback. If the handle were
-- closed on the panic path, the fd table would never fill up.
-- Run under `ulimit -n 128`.
fn burn(n) do
  if n == 0 do :ok
  else
    let _ = __try_call(fn _ ->
      let _ = Csv.each_row("data.csv", ",", :rfc4180, fn _ -> panic("boom"))
      true)
    burn(n - 1)
  end
end
fn main(_c : Cap(IO.Console), _f : Cap(IO.FileRead)) do
  println("before: " ++ to_string(Csv.read_all("data.csv", ",", :rfc4180)))
  burn(300)
  println("after 300 panicking each_row calls: " ++ to_string(Csv.read_all("data.csv", ",", :rfc4180)))
end
end
```

Run with a low fd limit (`ulimit -n 128`) next to a three-line `data.csv`. `each_row_with_header` behaves the same.

Expected: the second `read_all` succeeds

Actual (interpreted / compiled): `Ok(Err(FileError("data.csv: Too many open files")))` / `Ok(Err(Too many open files))`

Source: `each_row`, `each_row_with_header` in stdlib/csv.march.
