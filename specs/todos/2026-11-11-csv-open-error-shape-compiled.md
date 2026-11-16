`[P2]` Compiled Csv open failure returns an error that is not a `FileError` (2026-11-11)

When the file cannot be opened, the interpreter returns `Err(FileError("<path>: <reason>"))` as documented. A compiled binary returns an `Err` whose payload prints as the bare reason, without the constructor and without the path, and a `match` arm on `Csv.FileError(m)` does not match it. Code that handles the documented error works interpreted and falls through to its wildcard arm when compiled.

Side finding of the 2026-11-11 re-verification of the 2026-10-18 doc sweep, on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
needs IO.FileRead
-- Side finding: the shape of the open error differs by backend.
fn main(_c : Cap(IO.Console), _f : Cap(IO.FileRead)) do
  let r = Csv.read_all("no_such_file.csv", ",", :rfc4180)
  println(to_string(r))
  match r do
  Ok(Err(Csv.FileError(m))) -> println("FileError with message: " ++ m)
  Ok(Err(_)) -> println("some other CsvError")
  Ok(Ok(_)) -> println("ok?")
  Err(_) -> println("cap error")
  end
end
end
```

Expected: `Ok(Err(FileError("no_such_file.csv: No such file or directory")))` then `FileError with message: ...` on both backends

Actual (interpreted / compiled): as expected / `Ok(Err(No such file or directory))` then `some other CsvError`

Source: `csv_open` builtin as used by `read_all`/`each_row` in stdlib/csv.march (compiled side: the csv open function in the C runtime).
