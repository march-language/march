# File Module Design

Three modules for filesystem operations: **Path** (pure path manipulation), **File** (file I/O + streaming), **Dir** (directory operations). Plus a **Seq** module for composable lazy iteration.

Streaming uses a fold-based model: `Seq(a)` is a church-encoded fold `fn(b, fn(b, a) -> b) -> b`. Callback-based primitives underneath, lazy combinators on top for pipe-friendly composition. Resource lifecycle is guaranteed by a `with_stream` pattern — the file handle is scoped to a callback, ensuring cleanup.

The name `Seq` (sequence) is used instead of `Stream` to avoid collision with the async `Stream(a)` type defined in the actor/concurrency system (`specs/design.md`).

## Error Type

Shared across File and Dir:

```
type FileError = NotFound(String)
               | Permission(String)
               | IsDirectory(String)
               | NotEmpty(String)
               | IoError(String)
```

All I/O functions return `Result(value, FileError)`.

## Control Flow Type

Used by `Seq.fold_while` for explicit early termination:

```
type Step(a) = Continue(a) | Halt(a)
```

This avoids repurposing `Result` for control flow.

## Path Module (pure, no I/O)

All functions operate on strings. No Result types needed. Implemented as pure March code using string operations.

```
mod Path do
  pub fn join(a, b)            # "dir" + "file.txt" -> "dir/file.txt"
  pub fn basename(path)        # "/foo/bar.txt" -> "bar.txt"
  pub fn dirname(path)         # "/foo/bar.txt" -> "/foo"
  pub fn extension(path)       # "photo.png" -> "png", "Makefile" -> ""
  pub fn strip_extension(path) # "photo.png" -> "photo"
  pub fn is_absolute(path)    # '?' not valid in March identifiers    # starts with "/"
  pub fn components(path)      # "/foo/bar" -> ["foo", "bar"]
  pub fn normalize(path)       # "a/../b/./c" -> "b/c"
end
```

### normalize rules

- Collapses `.` and `..` segments
- Absolute paths clamp at root: `"/a/../../../b"` -> `"/b"`
- Preserves leading `..` in relative paths: `"../../a"` stays as-is
- Empty string returns `"."`
- Trailing slashes are stripped

## File Module (read/write I/O)

```
mod File do
  # Read
  pub fn read(path)           # Result(String, FileError) - whole file
  pub fn read_lines(path)     # Result(List(String), FileError)
  pub fn exists(path)         # Bool — note: '?' not valid in March identifiers
  pub fn stat(path)           # Result(FileStat, FileError)

  # Write
  pub fn write(path, data)    # Result(:ok, FileError) - creates/overwrites
  pub fn append(path, data)   # Result(:ok, FileError)
  pub fn delete(path)         # Result(:ok, FileError)
  pub fn copy(src, dest)      # Result(:ok, FileError)
  pub fn rename(src, dest)    # Result(:ok, FileError)

  # Streaming (scoped, guarantees cleanup)
  pub fn with_lines(path, f)          # Result(a, FileError) - f receives Seq(String), result returned
  pub fn with_chunks(path, size, f)   # Result(a, FileError) - f receives Seq(String) of byte chunks

  # Low-level callback (simple side-effect iteration, no Seq construction)
  # Prefer with_lines/with_chunks when the callback can fail or returns a value
  pub fn each_line(path, f)        # Result(:ok, FileError) - calls f(line) per line
  pub fn each_chunk(path, size, f) # Result(:ok, FileError) - calls f(chunk) per chunk
end
```

### Streaming with `with_lines`

The `with_*` pattern guarantees resource cleanup. The file handle is opened before calling `f`, and closed after `f` returns — regardless of success or failure. This mirrors `HttpClient.with_connection`.

```
# Process a CSV — file is opened, folded, closed automatically
File.with_lines("data.csv", fn(lines) ->
  lines
  |> Seq.drop(1)
  |> Seq.map(parse_csv_row)
  |> Seq.filter(fn(row) -> row.amount > 100 end)
  |> Seq.to_list
end)
# Returns: Result(List(Row), FileError)
```

Errors like `NotFound` or `Permission` are reported at `with_lines` call time (the file is opened eagerly). The `Seq` inside the callback is guaranteed to have a valid handle.

### FileStat

```
-- Positional constructor — record syntax not valid in variant constructor args
-- Pattern match: FileStat(size, kind, modified, accessed)
type FileStat = FileStat(Int, FileKind, Int, Int)

type FileKind = RegularFile | Directory | Symlink | Other
```

`FileKind` uses ADT constructors (not atoms) for consistency with `FileError` and future extensibility.

## Dir Module (directory I/O)

```
mod Dir do
  pub fn list(path)           # Result(List(String), FileError) - filenames only
  pub fn list_full(path)      # Result(List(String), FileError) - full paths
  pub fn mkdir(path)          # Result(:ok, FileError)
  pub fn mkdir_p(path)        # Result(:ok, FileError) - recursive, no error if exists
  pub fn rmdir(path)          # Result(:ok, FileError) - empty dirs only, NotEmpty on failure
  pub fn rm_rf(path)          # Result(:ok, FileError) - recursive delete
  pub fn exists(path)         # Bool — note: '?' not valid in March identifiers
end
```

### rm_rf behavior

- Does **not** follow symlinks — symlink entries are removed, targets are left intact
- Returns `Err` on first permission error (does not continue best-effort)
- Refuses to operate on `"/"` or `""` — returns `Err(IoError("refusing to delete root"))`

## Seq Module (lazy fold combinators)

`Seq(a)` is `Seq(fn(b, fn(b, a) -> b) -> b)` — a church-encoded fold. The `b` type variable is universally quantified at each use site (not rank-2) — in practice, `Seq` is a simple wrapper around a closure and the typechecker handles polymorphism at call sites of `fold`, `to_list`, etc.

Enum operates on lists eagerly; Seq operates lazily over streams of values (files, generated sequences). Use Enum for in-memory lists, Seq for I/O or large/infinite sequences.

```
mod Seq do
  # Construction
  pub fn from_list(list)        # Seq(a) - wraps a list as a sequence
  pub fn empty()                # Seq(a)
  pub fn unfold(seed, f)        # Seq(a) - f(seed) -> Option((value, next_seed))
  pub fn concat(s1, s2)         # Seq(a) - s1 followed by s2

  # Transformation (lazy - returns new Seq)
  pub fn map(seq, f)            # Seq(b)
  pub fn filter(seq, f)         # Seq(a)
  pub fn flat_map(seq, f)       # Seq(b) - f returns Seq(b)
  pub fn take(seq, n)           # Seq(a) - first n items
  pub fn drop(seq, n)           # Seq(a) - skip first n
  pub fn zip(s1, s2)            # Seq((a, b))
  pub fn batch(seq, n)          # Seq(List(a)) - groups of n

  # Consumption (eager - runs the fold)
  pub fn to_list(seq)           # List(a)
  pub fn fold(seq, acc, f)      # b - f(acc, item) -> acc
  pub fn fold_while(seq, acc, f) # b - f(acc, item) -> Step(b), terminates on Halt
  pub fn each(seq, f)           # :ok - side effects per item
  pub fn count(seq)             # Int
  pub fn find(seq, f)           # Option(a)
  pub fn any(seq, f)            # Bool — '?' not valid in March identifiers
  pub fn all(seq, f)            # Bool
end
```

**Key property:** transformation combinators are lazy (wrap the fold function), consumption combinators are eager (run it). A pipeline reads nothing until a terminal operation like `to_list` or `fold` drives it.

Early termination for `take`, `find`, etc. uses a "done" flag in the accumulator. `fold_while` provides explicit short-circuit via `Step(a)`.

`batch` (not `chunk`) groups elements into sublists to avoid confusion with I/O chunking terminology.

## Implementation Notes

### Builtins Required

New OCaml builtins in `eval.ml`:

- `file_read(path)` — read entire file as string
- `file_write(path, data)` — write/overwrite file
- `file_append(path, data)` — append to file
- `file_delete(path)` — remove file
- `file_exists(path)` — check existence
- `file_stat(path)` — size, kind, timestamps
- `file_copy(src, dest)` — copy file
- `file_rename(src, dest)` — move/rename
- `file_open(path)` — open for reading, return fd (Int)
- `file_read_line(fd)` — read one line from open handle, returns `Option(String)`
- `file_read_chunk(fd, size)` — read chunk from open handle, returns `Option(String)`
- `file_close(fd)` — close handle
- `dir_list(path)` — list directory entries
- `dir_mkdir(path)` — create directory
- `dir_mkdir_p(path)` — create directory recursively
- `dir_rmdir(path)` — remove empty directory
- `dir_rm_rf(path)` — remove recursively
- `dir_exists(path)` — check directory existence

All I/O builtins return `Result` variants (Ok/Err with FileError constructors). `path_*` functions are pure March — no builtins needed.

### Streaming Implementation

`File.with_lines(path, f)`:
1. Calls `file_open(path)` — returns `Result(fd, FileError)`
2. On `Ok(fd)`, constructs a `Seq(String)` whose fold calls `file_read_line(fd)` in a loop
3. Passes the `Seq` to `f`, captures the result
4. Calls `file_close(fd)` (always, even if `f` raised an error)
5. Returns `Ok(result)` or the original `Err`

### Path Module

All pure March code using string operations. `normalize` is the most complex — it splits on `/`, processes `.`/`..` segments with a stack, and rejoins.

## Usage Examples

### Read a config file

```
let config = File.read("config.txt")
|> Result.map(parse_config)
|> Result.unwrap_or(default_config())
```

### Process a large CSV

```
File.with_lines("data.csv", fn(lines) ->
  lines
  |> Seq.drop(1)
  |> Seq.map(parse_csv_row)
  |> Seq.filter(fn(row) -> row.amount > 100 end)
  |> Seq.to_list
end)
```

### Copy matching files between directories

```
match Dir.list_full("/src") with
| Ok(files) ->
  files
  |> Enum.filter(fn(f) -> Path.extension(f) == "march" end)
  |> Enum.each(fn(f) ->
    let dest = Path.join("/dest", Path.basename(f))
    File.copy(f, dest)
  end)
| Err(e) -> println("Error: ${e}")
end
```

### Stream with early termination

```
File.with_lines("huge.log", fn(lines) ->
  lines
  |> Seq.filter(fn(l) -> String.contains(l, "CRITICAL") end)
  |> Seq.take(5)
  |> Seq.to_list
end)
```

### Fold with explicit stop

```
File.with_lines("numbers.txt", fn(lines) ->
  lines
  |> Seq.map(fn(l) -> String.to_int(l) |> Result.unwrap_or(0) end)
  |> Seq.fold_while(0, fn(sum, n) ->
    if sum + n > 1000 then Halt(sum)
    else Continue(sum + n)
  end)
end)
```
