---
layout: cookbook
title: "Coming from Python"
permalink: /docs/coming-from-python/
---

# Coming from Python

You know Python: dynamic types, exceptions, `for` loops, classes. March keeps the readability but moves the safety checks to compile time instead of runtime.

---

## Functions

```march
-- Python: def add(x, y): return x + y
fn add(x, y) do x + y end
```

No `return` keyword: the last expression is the result. No colon. No indentation rules: `do...end` delimits the body.

Type annotations are optional (the compiler infers them) but good for documentation:

```march
fn add(x : Int, y : Int) : Int do x + y end
```

Private functions use `pfn`, enforced by the compiler, not just a `_` naming convention:

```march
pfn helper(s : String) : String do String.to_uppercase(s) end
```

---

## No `None`: use `Option`

There's no `None` that silently infects your program. A value that might be absent has type `Option(a)`:

```march
fn find_user(id : Int) : Option(User) do
  -- returns Some(user) or None
end

match find_user(42) do
  None       -> println("not found")
  Some(user) -> println(user.name)
end
```

The compiler forces you to handle both cases. No `AttributeError: 'NoneType' object has no attribute 'name'` surprises.

`Option.unwrap_or` is the safe equivalent of `x or default`:

```march
Option.unwrap_or(find_user(42), default_user)
```

---

## No exceptions: use `Result`

Instead of `try/except`, functions that can fail return `Result(ok, err)`:

```march
fn parse_int(s : String) : Result(Int, String) do
  String.to_int(s)
end
```

Chain fallible operations with `let?`: it propagates the error up and returns early, like a `try` block that's in the type:

```march
fn run(input : String) : Result(Int, String) do
  let? n    = parse_int(input)
  let? user = fetch_user(n)
  Ok(user.score)
end
```

If `parse_int` returns `Err("not a valid integer")`, `run` immediately returns that error; `fetch_user` never runs. No exception handler needed.

---

## No classes: modules + record types

```python
# Python
class Counter:
    def __init__(self): self.count = 0
    def increment(self): self.count += 1
    def get(self): return self.count
```

March keeps data and functions separate. Records hold data; functions in the same module operate on them:

```march
type Counter = { count : Int }

fn new() : Counter do { count: 0 } end
fn increment(c : Counter) : Counter do { c with count: c.count + 1 } end
fn get(c : Counter) : Int do c.count end
```

`{ c with count: ... }` creates a new record with one field changed; values are immutable by default. For mutable shared state, use `actor` or `Vault`.

---

## No `for` loops: higher-order functions

```python
# Python
doubled = [x * 2 for x in nums if x > 0]
total   = sum(nums)
first   = next((x for x in nums if x > 10), None)
```

```march
let doubled = nums |> List.filter(fn x -> x > 0) |> List.map(fn x -> x * 2)
let total   = List.fold_left(nums, 0, fn (acc, x) -> acc + x)
let first   = List.find(nums, fn x -> x > 10)
```

`|>` is the pipe operator: it passes the left side as the first argument to the right side.

---

## Pattern matching replaces `isinstance` and `if/elif`

```python
# Python
if isinstance(shape, Circle):
    return 3.14 * shape.r ** 2
elif isinstance(shape, Rect):
    return shape.w * shape.h
else:
    return 0
```

```march
match shape do
  Circle(r)  -> 3.14159 *. r *. r
  Rect(w, h) -> w *. h
  Point      -> 0.0
end
```

The compiler checks exhaustiveness: if you add a new constructor to `Shape` later, every `match` that doesn't cover it becomes a compile error.

`match do` without a subject replaces `if/elif/else` chains:

```march
match do
  score >= 90 -> "A"
  score >= 80 -> "B"
  _           -> "C"
end
```

---

## Static typing without the ceremony

You're used to Python being dynamic. March is fully static but the type checker is mostly invisible:

```march
fn double(n) do n * 2 end       -- inferred: Int -> Int
let xs = [1, 2, 3]              -- inferred: List(Int)
let pair = ("hello", 42)        -- inferred: (String, Int)
```

Annotate at module boundaries for documentation and better error messages:

```march
fn fetch(id : Int) : Result(User, String) do ... end
```

---

## Concurrency & shared state

Python reaches for a class with mutable `self` state, plus `threading` or
`asyncio` for concurrency. March has no mutable objects: **state that changes
over time lives in an actor**, a process you talk to by message.

```python
# Python
class Counter:
    def __init__(self):
        self.count = 0
    def inc(self, n):
        self.count += n
```

```march
-- March: state lives in an actor; messages drive the transitions
actor Counter do
  state { value : Int }
  init  { value: 0 }

  on Increment(n : Int) do
    { state with value: state.value + n }
  end
end
```

You `spawn` the actor and `send` it messages; it owns its state and no other code can touch it.

| Python | March |
|--------|-------|
| `class` with mutable `self` | `actor` with `state { … }` |
| `threading.Thread` / `asyncio` task | `Task.async(fn () -> …)` + `Task.await` |
| `asyncio.gather(...)` | `Task.await_many([...])` |
| module-level / `global` mutable state | a `Vault` (in-memory key-value store) |

See [Actors](actors.md) and [Choosing a concurrency primitive](actors.md#choosing-a-concurrency-primitive).

---

## Numeric arrays (NumPy users)

Python's list comprehensions are fine for everyday code, but for large
numeric workloads you reach for NumPy. March's equivalent is `NativeArray`:
a flat, contiguous array (not `List`'s linked cells or `Array`'s trie) that
`march --compile` can auto-vectorize into real SIMD instructions:

```python
# Python / NumPy
arr = np.arange(1_000_000, dtype=np.float64)
doubled = arr * 2.0
total = doubled.sum()
```

```march
let arr = NativeArray.make_float(1_000_000, 0.0)
let doubled = NativeArray.map_float(arr, fn x -> x *. 2.0)
let total = NativeArray.sum_float(doubled)
```

The accurate comparison, not an overclaim: on a same-machine benchmark at 5M
elements, March **ties or beats** NumPy on `sum` and is **competitive**
(within 3x, and beating hand-written OCaml/Rust) on `map`; narrowing to
`NativeArray`'s `f32` element width (50% of the bytes, double the SIMD lanes)
closes most of the remaining gap, beating NumPy on `sum` and `map` and
reaching parity on `map2`. See [SIMD Benchmarks](/docs/simd-benchmarks/) for
the full numbers and methodology, and [SIMD & Native Arrays](/docs/simd/)
for what does and doesn't vectorize. There's also an explicit `Simd` module
(128-bit vector types) for when you need guaranteed vector codegen instead
of an optimizer decision, covered in the same guide.

---

## What's the same

- `println(...)` for output
- List literals: `[1, 2, 3]`
- Tuple literals: `(1, "hello")`
- Boolean: `true`, `false`, `&&`, `||`, `!`
- String concatenation: `"hello " ++ name` (instead of f-strings)
- Integer arithmetic: `+`, `-`, `*`, `/`; float arithmetic adds `.`: `+.`, `-.`, `*.`, `/.`
