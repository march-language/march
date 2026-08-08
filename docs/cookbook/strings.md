---
layout: cookbook
title: "Cookbook: Strings"
permalink: /docs/cookbook/strings/
scrollmd: true
---

# Strings

March strings are UTF-8. The standard library lives in the `String` module.

---

## Concatenation and interpolation

`++` concatenates two strings:

```march
"Hello, " ++ "world!"
```

`${}` interpolates a value inside a double-quoted string:

```march
let name = "Alice"
"Hello, ${name}!"
```

Triple-quoted strings preserve newlines and leading whitespace:

```march
let msg = """
  line one
  line two
"""
```

---

## Common operations

```march
String.codepoint_count("hello")          -- 5 (grapheme count)
String.byte_size("hello")                -- 5 (byte count)
String.to_uppercase("hello")             -- "HELLO"
String.to_lowercase("HELLO")             -- "hello"
String.trim("  hello  ")                 -- "hello"
String.trim_start("  hello")             -- "hello"
String.trim_end("hello  ")               -- "hello"
String.contains("hello", "ell")          -- true
String.starts_with("hello", "he")        -- true
String.ends_with("hello", "lo")          -- true
String.replace("foo bar", "bar", "baz")  -- "foo baz"
String.split("a,b,c", ",")              -- ["a", "b", "c"]
String.join(["a", "b", "c"], ", ")      -- "a, b, c"
String.repeat("ab", 3)                   -- "ababab"
String.reverse("hello")                  -- "olleh"
String.pad_left("42", 5, "0")            -- "00042"
String.pad_right("hi", 5, ".")           -- "hi..."
String.is_empty("")                      -- true
```

---

## Conversions

```march
int_to_string(42)        -- "42"
float_to_string(3.14)    -- "3.14"
bool_to_string(true)     -- "true"

String.to_int("42")      -- Ok(42)
String.to_float("3.14")  -- Ok(3.14)
String.to_int("bad")     -- Err("not a valid integer: bad")
```

---

## Splitting and slicing

```march
String.split_first("key=value", "=")  -- Some(("key", "value"))
String.index_of("hello", "ll")        -- Some(2)
String.slice_bytes("hello", 1, 3)     -- "ell"
```

---

## Complete example: parsing a config line

```march
mod Config do
  needs IO.Console
  type Entry = { key : String, value : String }

  fn parse_line(line : String) : Option(Entry) do
    match String.split_first(line, "=") do
      None         -> None
      Some((k, v)) ->
        let key   = String.trim(k)
        let value = String.trim(v)
        if String.is_empty(key) do None
        else Some({ key: key, value: value })
        end
    end
  end

  fn main() do
    let lines = ["host = localhost", "# comment", "port = 8080", ""]
    let entries = List.filter_map(lines, fn l -> parse_line(l))
    List.each(entries, fn e ->
      println(e.key ++ " => " ++ e.value)
    )
  end
end
```
