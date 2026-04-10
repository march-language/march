---
layout: page
title: Try It Out
nav_order: 2
description: "Interactive March REPL — try March expressions in your browser, no install needed."
---

# Try March in your browser

The playground below runs a full March interpreter compiled to WebAssembly-friendly JavaScript via js_of_ocaml. No install, no account — just type and run.

{% include playground.html %}

---

## What you can try

**Arithmetic and strings**

```march
1 + 2 * 3
"hello" <> " " <> "world"
```

**Let bindings and functions**

```march
let double = fn x -> x * 2
double(21)
```

**Pattern matching**

```march
type Shape = Circle(Float) | Rect(Float, Float)

let area = fn s ->
  match s do
    Circle(r)    -> 3.14159 *. r *. r
    Rect(w, h)   -> w *. h
  end

area(Circle(5.0))
```

**Standard library**

```march
List.map([1, 2, 3, 4, 5], fn x -> x * x)
List.filter(List.range(1, 20), fn x -> x % 2 == 0)
```

**Multi-line input**: press **Shift+Enter** to add a new line, **Enter** to run.

---

## Limitations

The browser playground runs the March **interpreter** (tree-walking eval), not the compiled native backend. A few things work differently:

- No file I/O, no HTTP server, no Unix processes
- No LLVM compilation / native performance
- Actor `spawn` runs synchronously (no scheduler)
- Standard library modules loaded: prelude, option, result, list, map, set, array, math, string, sort, seq, enum, random, json, and a few others

For the full language including actors, supervision trees, session types, and native compilation, see [Installation]({{ site.baseurl }}/installation).
