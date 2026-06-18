---
layout: cookbook
title: "Coming from Python / TypeScript"
permalink: /docs/coming-from-python/
---

# Coming from Python / TypeScript

March is statically typed and functional, but it borrows the clarity and pragmatism you already know. This page maps familiar patterns to their March equivalents.

---

## Functions

Python/TS functions map almost directly:

| Python / TypeScript | March |
|---------------------|-------|
| `def add(x, y): return x + y` | `fn add(x, y) do x + y end` |
| `const add = (x, y) => x + y` | `fn add(x, y) do x + y end` |
| `def greet(name="World"):` | `fn greet(name \\ "World") do` |
| No explicit `return` | Last expression is the return value |
| `_helper()` (private by convention) | `pfn helper()` (enforced by compiler) |

---

## No `null` — use `Option`

March has no `null` or `undefined`. A value that might be absent is `Option(a)`:

```march
fn find_user(id : Int) : Option(User) do
  -- returns Some(user) or None
end

match find_user(42) do
  None       -> println("not found")
  Some(user) -> println(user.name)
end
```

`Option.unwrap_or(None, default)` is the safe equivalent of `x or default` in Python.

---

## No exceptions — use `Result`

Instead of `try/except`, functions that can fail return `Result(ok, err)`:

```march
fn parse_int(s : String) : Result(Int, String) do
  -- Ok(n) or Err("not a valid integer")
end
```

Chain fallible operations with `let?` — it short-circuits on `Err` the same way Python's `try` block does, but it's in the type:

```march
fn run(input : String) : Result(Int, String) do
  let? n    = parse_int(input)
  let? user = fetch_user(n)
  Ok(user.score)
end
```

---

## No classes — modules + types

```python
# Python
class Counter:
    def __init__(self): self.count = 0
    def increment(self): self.count += 1
    def get(self): return self.count
```

```march
type Counter = { count : Int }

fn new_counter() : Counter do { count = 0 } end
fn increment(c : Counter) : Counter do { c with count = c.count + 1 } end
fn get(c : Counter) : Int do c.count end
```

Data and functions are separate. For mutable shared state, use an `actor` or `Vault`.

---

## No `for` loops — higher-order functions

```python
# Python
doubled = [x * 2 for x in nums if x > 0]
total   = sum(x for x in nums)
```

```march
let doubled =
  nums
  |> List.filter(fn x -> x > 0)
  |> List.map(fn x -> x * 2)

let total = List.fold_left(nums, 0, fn (acc, x) -> acc + x)
```

---

## Types are inferred — annotate at boundaries

TypeScript-style annotations are optional in March. The compiler infers everything:

```march
fn double(n) do n * 2 end   -- inferred: Int -> Int
```

Annotate at public function boundaries for documentation and error clarity:

```march
fn fetch(id : Int) : Result(User, String) do ... end
```

---

## Pattern matching replaces `isinstance` chains

```python
# Python
if isinstance(shape, Circle):
    return 3.14 * shape.r ** 2
elif isinstance(shape, Rect):
    return shape.w * shape.h
```

```march
match shape do
  Circle(r)  -> 3.14159 *. r *. r
  Rect(w, h) -> w *. h
end
```

The compiler checks exhaustiveness — missing a case is a compile error, not a silent bug.

---

## What's the same

- String concatenation: `"hello " ++ name` (vs `f"hello {name}"`)
- List literals: `[1, 2, 3]`
- Tuple literals: `(1, "hello")`
- Boolean operators: `&&`, `||`, `!`
- Arithmetic: `+`, `-`, `*`, `/` for ints; `+.`, `-.`, `*.`, `/.` for floats
- `println(...)` for output
