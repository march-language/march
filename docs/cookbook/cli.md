---
layout: cookbook
title: "Cookbook: CLI"
permalink: /docs/cookbook/cli/
scrollmd: true
---

# A CLI that takes args and files

How to read command-line arguments, parse simple flags by hand, read files, and
exit with meaningful codes. For a full guided walkthrough that scaffolds a
project end-to-end, see [Build a CLI tool](../../build-a-cli/).

---

## Reading arguments

`System.argv()` returns the argument vector as a `List(String)`. The first
element is the executable path; the rest are the user's arguments.

<!-- scroll:skip -->
```march
fn main() do
  match System.argv() do
    [_exe]            -> IO.warn("usage: greet <name>")
    [_exe, name]      -> println("Hello, " ++ name ++ "!")
    _                 -> IO.warn("too many arguments")
  end
end
```

Pattern-matching the whole list is the cleanest way to handle a fixed argument
shape. `_exe` discards the program name.

---

## Usage messages and exit codes

Send usage and errors to **stderr** with `IO.warn` (it adds a newline), keeping
stdout clean for real output. Set the process exit code with `System.exit(n)`;
returning an `Int` from `main` does *not* affect the exit status.

<!-- scroll:skip -->
```march
fn main() do
  match System.argv() do
    [_exe, path] -> run(path)
    _ ->
      IO.warn("usage: tool <file>")
      System.exit(2)   -- 2 = bad usage, by convention
  end
end
```

| Code | Meaning |
|------|---------|
| `0`  | success (the default if `main` returns normally) |
| `1`  | a runtime failure (couldn't read a file, etc.) |
| `2`  | wrong invocation (missing/bad arguments) |

---

## Manual flag parsing

There's no built-in flag library; for small tools, fold over the argument list
and pick out the flags you care about. Here we support a `-n` count flag and
treat everything else as a filename:

<!-- scroll:skip -->
```march
mod Repeat do
  needs IO.Console

  type Args = Args(Int, Option(String))

  fn parse(argv : List(String)) : Args do
    -- drop the executable name, then walk the rest
    List.fold_left(List.drop(argv, 1), Args(1, None), fn (acc, arg) ->
      match acc do
        Args(count, file) ->
          match arg do
            "-v" -> Args(count + 1, file)   -- repeated -v bumps the count
            _    -> Args(count, Some(arg))  -- a non-flag is the filename
          end
      end)
  end

  fn main() do
    match parse(System.argv()) do
      Args(_count, None) ->
        IO.warn("usage: repeat [-v ...] <text>")
        System.exit(2)
      Args(count, Some(text)) ->
        List.each(List.range(0, count), fn _ -> println(text))
    end
  end

end
```

`List.drop(argv, 1)` skips the program name. `List.fold_left(list, init, fn)`
threads an `Args` accumulator through every argument; `fn (acc, arg) ->` is a
two-argument lambda (note the parentheses).

---

## Reading the file

`File.read` returns `Result(String, FileError)`. Match on it so a missing file
becomes a clean error instead of a crash:

<!-- scroll:skip -->
```march
fn run(path : String) do
  match File.read(path) do
    Ok(text) -> println(text)
    Err(_)   ->
      IO.warn("cannot read " ++ path)
      System.exit(1)
  end
end
```

To read line by line without loading the whole file, use `File.read_lines`
(eager, returns `Result(List(String), FileError)`) or `File.each_line(path, f)`
for streaming side effects.

---

## Complete example

```march
mod Cat do
  needs IO.Console
  needs IO.FileRead
  needs IO.Process

  fn dump(path : String) do
    match File.read(path) do
      Ok(text) -> print(text)
      Err(_) ->
        IO.warn("cat: " ++ path ++ ": cannot read")
        System.exit(1)
    end
  end

  fn main() do
    match System.argv() do
      [_exe] ->
        IO.warn("usage: cat <file> [<file> ...]")
        System.exit(2)
      _ ->
        -- every argument after the program name is a file
        List.each(List.drop(System.argv(), 1), fn p -> dump(p))
    end
  end

end
```

This `cat` clone reads every file argument, prints each to stdout, reports
unreadable files to stderr, and exits non-zero on the first failure.
