---
layout: docs
title: Try It Out
nav_order: 2.3
permalink: /docs/playground/
description: "Interactive March REPL: try March expressions in your browser, no install needed."
---

# Try March in your browser

The playground below runs a full March interpreter compiled to WebAssembly-friendly JavaScript via js_of_ocaml. No install, no account: just type and run.

{% include playground.html %}

---

## What you can try

**Arithmetic and strings**

```march
1 + 2 * 3
"hello, " ++ "world"
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

**Result propagation with `let?`**

```march
fn safe_div(a : Int, b : Int) : Result(Int, String) do
  if b == 0 do
    Err("division by zero")
  else
    Ok(a / b)
  end
end

fn compute(a : Int, b : Int, c : Int) : Result(Int, String) do
  let? x = safe_div(a, b)
  let? y = safe_div(x, c)
  Ok(y + 1)
end

compute(100, 5, 4)    -- Ok(6)
compute(100, 0, 4)    -- Err("division by zero")  (short-circuits at first let?)
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

- No file I/O, no HTTP **server**, no Unix processes
- HTTP **client** requests work: `HttpClient.get` / `HttpClient.post` run via
  the browser's `fetch`/`XHR`. Limited to CORS-permitted or same-origin URLs,
  whole (non-streaming) responses only, and each request briefly blocks the page.
- No LLVM compilation / native performance
- Actor `spawn` runs synchronously (no scheduler); `Task` runs eagerly at spawn time (no real concurrency)
- Standard library modules loaded: prelude, option, result, list, task, map, set, array, math, string, sort, seq, enum, random, json, http, http_transport, http_client, vault, and a few others

For the full language including actors, supervision trees, session types, and native compilation, see [Installation]({{ site.baseurl }}/docs/installation/).
