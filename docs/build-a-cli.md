---
layout: docs
title: Build a CLI Tool
nav_order: 4.5
permalink: /docs/build-a-cli/
scrollmd: true
---

# Build a CLI Tool

This tutorial builds a real command-line program from scratch: **`mcount`**, a
small clone of `wc` that counts the lines, words, and bytes in a file. Along the
way you'll touch every part of the workflow: scaffolding a project with
`forge`, reading command-line arguments, reading a file, processing text,
writing tests, and compiling a native binary.

By the end you'll have a single self-contained binary you can drop on your
`$PATH`.

---

## 1. Scaffold the project

`forge` is March's build tool. Create a new app:

```sh
forge new mcount
cd mcount
```

This lays out a minimal project:

```
mcount/
├── forge.toml          # project manifest
├── lib/
│   └── mcount.march    # entry point (has main())
└── test/
    └── mcount_test.march
```

`forge.toml` is the manifest:

```toml
[package]
name = "mcount"
version = "0.1.0"
type = "app"
description = ""
author = ""
license = ""

[deps]
```

The generated `lib/mcount.march` just prints a greeting. We'll replace it.

Run it as-is to confirm the toolchain works:

```sh
forge run
# Hello from mcount!
```

---

## 2. Read the arguments

A CLI needs its arguments. `System.argv()` returns the full argument vector as a
`List(String)`, with the executable path as the first element:

<!-- scroll:skip -->
```march
mod Mcount do
  needs IO.Console
  needs IO.Process
  fn main() do
    match System.argv() do
      [_exe, path] -> println("counting " ++ path)
      _ ->
        IO.warn("usage: mcount <file>")
        System.exit(2)
    end
  end
end
```

Two things worth calling out:

- **`IO.warn` writes to stderr** (with a trailing newline), which is where usage
  and error messages belong; that keeps them out of any pipe consuming stdout.
- **`System.exit(n)` sets the process exit code.** Returning an `Int` from
  `main` does *not* set the exit code, so reach for `System.exit` when you want a
  non-zero status. We use `2` for "wrong usage", matching the Unix convention.

We pattern-match the whole `argv` list. `[_exe, path]` matches exactly two
elements; anything else (no file, or too many) falls through to the usage
branch.

---

## 3. Read the file

`File.read` returns a `Result(String, FileError)`: `Ok` with the contents, or
`Err` if the file is missing or unreadable. Match on it so a bad path produces a
clean error instead of a crash:

<!-- scroll:skip -->
```march
match File.read(path) do
  Ok(text) -> report(path, text)
  Err(_)   ->
    IO.warn("mcount: cannot read " ++ path)
    System.exit(1)
end
```

Exit code `1` signals a runtime failure (distinct from the `2` for bad usage).

---

## 4. Process the text

Now the actual counting. We split the text into lines, split each line into
words, and use `String.byte_size` for the byte count:

<!-- scroll:skip -->
```march
fn count(text : String) : (Int, Int, Int) do
  let lines = String.split(text, "\n")
  let line_count = List.length(lines)
  let words =
    lines
    |> List.flat_map(fn line -> String.split(line, " "))
    |> List.filter(fn w -> w != "")
  let word_count = List.length(words)
  let byte_count = String.byte_size(text)
  (line_count, word_count, byte_count)
end
```

`List.flat_map` runs `String.split` over every line and concatenates the
resulting word lists; `List.filter` drops the empty strings that show up from
runs of whitespace. The function returns a 3-tuple, which the caller
destructures with a tuple pattern.

---

## 5. The full program

Putting it together, replace `lib/mcount.march` with:

```march
mod Mcount do
  needs IO.Console
  needs IO.FileRead
  needs IO.Process

  -- Count lines, words, and bytes in a string.
  fn count(text : String) : (Int, Int, Int) do
    let lines = String.split(text, "\n")
    let line_count = List.length(lines)
    let words =
      lines
      |> List.flat_map(fn line -> String.split(line, " "))
      |> List.filter(fn w -> w != "")
    let word_count = List.length(words)
    let byte_count = String.byte_size(text)
    (line_count, word_count, byte_count)
  end

  fn report(path : String, text : String) : Unit do
    let (lines, words, bytes) = count(text)
    println(String.from_int(lines) ++ " " ++
            String.from_int(words) ++ " " ++
            String.from_int(bytes) ++ " " ++ path)
  end

  fn main() do
    match System.argv() do
      [_exe, path] ->
        match File.read(path) do
          Ok(text) -> report(path, text)
          Err(_)   ->
            IO.warn("mcount: cannot read " ++ path)
            System.exit(1)
        end
      _ ->
        IO.warn("usage: mcount <file>")
        System.exit(2)
    end
  end

end
```

---

## 6. Going further: top-N words

A word counter is more interesting if it reports the most frequent words. We can
tally them in a `Map`, turn it into a list, and sort with `List.sort_by`. Here's
a standalone version that ranks the top 3 words in a string:

```march
mod TopWords do
  needs IO.Console

  fn tally(words : List(String)) : Map(String, Int) do
    List.fold_left(words, Map.empty(), fn (counts, word) ->
      Map.insert(counts, word, Map.get_or(counts, word, 0, Map.str_cmp) + 1, Map.str_cmp))
  end

  fn main() do
    let words =
      "the cat sat on the mat the cat"
      |> String.split(" ")
      |> List.filter(fn w -> w != "")
    let counts = tally(words)
    let pairs = Map.to_list(counts)
    -- sort_by takes a 2-arg comparator; we sort so higher counts come first
    let ranked = List.sort_by(pairs, fn (a, b) ->
      let (_, ca) = a
      let (_, cb) = b
      ca > cb)
    List.each(List.take(ranked, 3), fn pair ->
      let (word, n) = pair
      println(word ++ ": " ++ String.from_int(n)))
  end

end
```

`List.fold_left(list, init, fn)` threads the `Map` accumulator through every
word. `Map.get_or(m, key, default, cmp)` reads the running count (defaulting to
`0`), and `Map.insert(m, key, val, cmp)` returns an updated map; March's `Map`
is immutable and takes an explicit comparator (`Map.str_cmp` for string keys).
`List.sort_by(xs, cmp)` calls `cmp(a, b)` and keeps `a` first when it returns
`true`; comparing `ca > cb` puts the biggest count first.

Running it prints:

```
the: 3
cat: 2
mat: 1
```

Since `TopWords.main` works on an inline string literal (no argv, no files), you
can drop it in its own file and run it directly; `main()` is invoked
automatically:

```sh
march topwords.march
```

---

## 7. Write a test

`forge` discovers test files under `test/`. A test module is plain March: write
functions that return `Bool`, and a `main` that runs them and reports. Replace
`test/mcount_test.march`:

```march
mod McountTest do
  needs IO.Console

  fn count(text : String) : (Int, Int, Int) do
    let lines = String.split(text, "\n")
    let words =
      lines
      |> List.flat_map(fn line -> String.split(line, " "))
      |> List.filter(fn w -> w != "")
    (List.length(lines), List.length(words), String.byte_size(text))
  end

  fn test_counts() : Bool do
    let (l, w, b) = count("a b c\nd e")
    l == 2 && w == 5 && b == 9
  end

  fn test_empty() : Bool do
    let (l, w, b) = count("")
    l == 1 && w == 0 && b == 0
  end

  fn main() do
    if test_counts() && test_empty() do
      println("All tests passed.")
    else
      println("Tests failed.")
    end
  end

end
```

Run the suite:

```sh
forge test
# All tests passed.
```

(In a real project you'd factor `count` into a library module and `use` it from
both `main` and the test; we inline it here to keep the example self-contained.)

---

## 8. Build the binary

`forge build` compiles a standalone native executable via LLVM: no runtime, no
interpreter:

```sh
forge build
# built: .march/build/debug/mcount
```

Then run it on a real file:

```sh
.march/build/debug/mcount lib/mcount.march
# 39 128 1036 lib/mcount.march

echo $?      # 0 — success
.march/build/debug/mcount     # no file:  prints usage to stderr, exits 2
echo $?      # 2
.march/build/debug/mcount /no/such/file
echo $?      # 1
```

You now have a complete CLI: argument parsing, file I/O, text processing,
distinct exit codes, a test suite, and a native binary.

---

## Where to go next

- [CLI recipe](/docs/cookbook/cli/): flags, multiple files, and error handling
  patterns for larger tools
- [Read a CSV and aggregate it](/docs/cookbook/files/): process structured data files
- [Parse a config file](/docs/cookbook/config/): TOML/YAML config with env overrides
- [Standard Library](/docs/stdlib-guide/): the "What do I use for…?" index and full module
  reference
- [Cookbook](/docs/cookbook/): task-focused recipes for everything else
