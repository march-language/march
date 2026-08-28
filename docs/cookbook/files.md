---
layout: cookbook
title: "Cookbook: Files"
permalink: /docs/cookbook/files/
scrollmd: true
---

# Read a CSV and aggregate it

How to stream rows out of a CSV file, sum a column found by its header name, and
walk a directory to process every `.csv` in a folder. Uses the `Csv`, `Dir`, and
`Path` modules.

> Each snippet below is one module. Put your own `main` (or a `test` block)
> *inside* the module to run it; a file has a single top-level `mod`.

---

## Streaming rows with a header

`Csv.each_row_with_header(path, delimiter, mode, callback)` reads the first row
as the header and then invokes `callback(header, row)` for every remaining row;
both `header` and `row` are `List(String)`. It closes the file on EOF and never
loads the whole file into memory, so it's the right tool for large files.

```march
mod Print do
  needs IO.Console

  fn dump(path : String) do
    Csv.each_row_with_header(path, ",", :rfc4180, fn (header, row) ->
      -- pair each value with its column name
      List.each(List.zip(header, row), fn pair ->
        let (col, value) = pair
        println(col ++ ": " ++ value)))
  end

end
```

The `callback` is a two-argument lambda, `fn (header, row) ->`. `List.zip` pairs
columns with values into tuples, and `List.each` hands each tuple to a
*one*-argument lambda, so we destructure it with `let (col, value) = pair`.

The `mode` atom selects the dialect: `:rfc4180` (quoted fields, the default for
real CSV) or `:simple` (split on the delimiter, good for TSV with `"\t"`).

---

## Aggregating a column

For aggregation it's simpler to read every row eagerly with `Csv.read_all`, which
returns `Result(List(List(String)), CsvError)`. The first element is the header
row. Find the column index with `List.find_index`, then fold the rest:

```march
mod Sales do

  pfn add_cell(sum : Int, cell : String) : Int do
    match string_to_int(cell) do
      Some(n) -> sum + n
      None    -> sum     -- skip blanks / non-numeric cells
    end
  end

  pfn sum_rows(rows : List(List(String)), i : Int) : Int do
    List.fold_left(rows, 0, fn (sum, row) -> add_cell(sum, List.nth(row, i)))
  end

  -- Sum an integer column, located by its header name.
  fn sum_column(path : String, column : String) : Result(Int, String) do
    match Csv.read_all(path, ",", :rfc4180) do
      Err(_)  -> Err("cannot read " ++ path)
      Ok(Nil) -> Ok(0)
      Ok(Cons(header, rows)) ->
        match List.find_index(header, fn h -> h == column) do
          None    -> Err("no column named " ++ column)
          Some(i) -> Ok(sum_rows(rows, i))
        end
    end
  end

end
```

`List.find_index(header, fn h -> h == column)` returns `Some(i)` for the matching
column or `None`, so a missing column is a clean `Err`, not a crash.
`string_to_int` returns `Option(Int)`, letting `add_cell` skip cells that don't
parse. Pulling the fold into small `pfn` helpers keeps each `match` arm a single
expression, which reads more clearly than one deeply nested expression.

For a large column, the [Numeric Data cookbook]({{ site.baseurl
}}/docs/cookbook/numeric-data/#aggregating-a-csv-column-the-fast-path-way)
has a fast-path version of `sum_column` that hands the reduction to
`NativeArray.sum_int` instead of `List.fold_left`.

---

## Processing every CSV in a folder

`Dir.list(path)` returns `Result(List(String), DirError)` of the entry names.
Filter by extension with `Path.extension`, which returns the extension **without**
the leading dot:

```march
mod Batch do

  fn csv_files(dir : String) : Result(List(String), String) do
    match Dir.list(dir) do
      Err(_)    -> Err("cannot list " ++ dir)
      Ok(names) -> Ok(List.filter(names, fn n -> Path.extension(n) == "csv"))
    end
  end

end
```

Combine this with `Sales.sum_column` from above and `Path.join(dir, name)` (which
builds each full path from the directory and the bare entry name) to total a
column across every CSV in a directory.

---

## See also

- [Build a CLI tool]({{ site.baseurl }}/docs/build-a-cli/): wraps file processing in a runnable command.
- [Standard Library → Csv]({{ site.baseurl }}/docs/stdlib/): the full CSV API.
