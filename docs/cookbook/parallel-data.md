---
layout: cookbook
title: "Cookbook: Parallel Data"
permalink: /docs/cookbook/parallel-data/
---

# Parallel Data

The `RRB` and `Parallel` modules let you process large collections across multiple CPU cores with
minimal ceremony. This chapter walks through every public function with copy-and-run examples.

---

## What's in the box

| Module | Purpose |
|--------|---------|
| `RRB` | Persistent sequence (`Vec`) for building and slicing data |
| `Parallel` | Map-reduce on `Vec` using spawned tasks |

`Parallel` depends on `RRB`: you always build a `Vec` first, then hand it to `Parallel`.

---

## RRB.Vec — the persistent sequence

### Building a Vec

```march
-- From a list
let v = RRB.from_list([1, 2, 3, 4, 5])

-- From an integer range [lo, hi)
let r = RRB.range(0, 100)    -- Vec of 0..99

-- By index
let sq = RRB.tabulate(5, fn i -> i * i)   -- Vec [0, 1, 4, 9, 16]

-- One element
let s = RRB.singleton(42)

-- Empty
let e : Vec(Int) = RRB.empty()
```

### Inspecting a Vec

```march
let v = RRB.from_list([10, 20, 30])

RRB.length(v)    -- 3
RRB.is_empty(v)  -- false
RRB.get(v, 1)    -- 20
RRB.to_list(v)   -- [10, 20, 30]
```

### Modifying a Vec

`Vec` is persistent — every operation returns a new `Vec`. The original is unchanged.

```march
let v  = RRB.from_list([1, 2, 3])
let v2 = RRB.push(v, 4)       -- [1, 2, 3, 4]
let v3 = RRB.concat(v, v2)    -- [1, 2, 3, 1, 2, 3, 4]

-- v is still [1, 2, 3]
```

### Sequential operations

```march
let v = RRB.range(1, 6)

-- map
let doubled = RRB.map(v, fn x -> x * 2)   -- Vec [2, 4, 6, 8, 10]

-- fold_left (left-to-right accumulation)
let sum = RRB.fold_left(v, 0, fn (acc, x) -> acc + x)   -- 15

-- each (side effects only)
RRB.each(v, fn x -> print_int(x))
```

### Slicing

A `Slice` is a zero-copy view into a `Vec`. Create one with `slice`, traverse it with `fold`.

```march
let v = RRB.range(0, 10)

-- slice(v, lo, hi) — half-open range [lo, hi)
let s = RRB.slice(v, 2, 6)

-- fold over the slice
let total = RRB.fold(s, 0, fn (acc, x) -> acc + x)   -- 2+3+4+5 = 14
```

Indices are clamped: `slice(v, -99, 999)` covers the whole `Vec` without panicking.

---

## Parallel — map-reduce on Vec

Every `Parallel` function follows this pattern:

1. **Chunk** the input into N slices (one per worker).
2. **Spawn** a task for each slice.
3. **Merge** results left-to-right as tasks finish.

The number of workers defaults to `System.cpu_count()`. Use the `_n` variants for a custom count.

### Parallel.pmap — order-preserving parallel transform

```march
let nums = RRB.range(1, 1_000_001)

-- double every element (parallel, same order as input)
let doubled = Parallel.pmap(nums, fn n -> n * 2)

-- explicit worker count
let result = Parallel.pmap_n(nums, fn n -> n * n, 4)
```

`pmap` is equivalent to `RRB.map` on the interpreter (single-threaded). Real parallelism kicks in
when you compile with `forge build`.

### Parallel.preduce — parallel transform + reduce

```march
let scores = RRB.from_list([88, 92, 75, 95, 60, 84])

-- sum of squares
let sum_sq = Parallel.preduce(scores, 0, fn n -> n * n, fn (a, b) -> a + b)

-- maximum score
let top = Parallel.preduce(scores, -2147483648, fn n -> n, fn (a, b) -> if a > b do a else b end)
```

The merge function must be **associative** and `zero` must be its identity. Commutativity is not
required.

```march
-- explicit 8 workers
let total = Parallel.preduce_n(scores, 0, fn n -> n, fn (a, b) -> a + b, 8)
```

### Convenience wrappers

These cover the most common reductions:

```march
let v = RRB.range(1, 101)   -- 1..100

Parallel.psum(v)                           -- 5050
Parallel.psum_float(RRB.from_list([1.5, 2.5, 3.0]))  -- 7.0
Parallel.pcount(v, fn n -> n % 2 == 0)   -- 50
Parallel.pany(v, fn n -> n > 99)         -- true
Parallel.pall(v, fn n -> n > 0)          -- true
```

---

## Worked examples

### Word frequency counter

Count how often each word appears in a large corpus in parallel.

```march
fn word_counts(words: Vec(String)): Map(String, Int) do
  Parallel.preduce(
    words,
    Map.empty(),
    fn w -> Map.singleton(w, 1),
    fn (a, b) -> Map.merge_with(a, b, fn (x, y) -> x + y)
  )
end
```

### Parallel image filter

Apply an expensive per-pixel transform to an image stored as a `Vec` of RGBA tuples.

```march
type Pixel = Pixel(Int, Int, Int, Int)   -- r g b a

fn grayscale(p: Pixel): Pixel do
  match p do Pixel(r, g, b, a) ->
    let lum = (r * 299 + g * 587 + b * 114) / 1000
    Pixel(lum, lum, lum, a)
  end
end

fn parallel_grayscale(pixels: Vec(Pixel)): Vec(Pixel) do
  Parallel.pmap(pixels, grayscale)
end
```

### Statistical summary

Compute mean and variance in two parallel passes.

```march
fn mean(v: Vec(Float)): Float do
  let n   = Float.of_int(RRB.length(v))
  let sum = Parallel.psum_float(v)
  sum /. n
end

fn variance(v: Vec(Float)): Float do
  let m  = mean(v)
  let n  = Float.of_int(RRB.length(v))
  let sq = Parallel.preduce(v, 0.0, fn x -> (x -. m) *. (x -. m), fn (a, b) -> a +. b)
  sq /. n
end
```

### Parallel filter

`Parallel` has no built-in `pfilter`. Build it from `preduce`:

```march
fn pfilter(v: Vec(a), pred: a -> Bool): Vec(a) do
  Parallel.preduce(
    v,
    RRB.empty(),
    fn x -> if pred(x) do RRB.singleton(x) else RRB.empty() end,
    fn (a, b) -> RRB.concat(a, b)
  )
end
```

---

## Performance notes

| Concern | Guidance |
|---------|---------|
| Work per element too small | Spawning tasks has overhead; use `List.pmap` for simple arithmetic on small lists |
| Skewed workloads | Use `pmap_n` / `preduce_n` with a larger chunk count (e.g. `workers * 4`) |
| Merge is expensive | Merge runs on the main thread; prefer commutative numeric reductions over `RRB.concat` chains |
| Results must be in order | `pmap` preserves order; `preduce` does not guarantee any element-ordering in intermediate merges |

The interpreter runs tasks sequentially, so timing in the REPL will not reflect compiled performance.
Benchmark with `forge build --release`.

---

## Interpreter vs. compiled

| Feature | Interpreter | Compiled |
|---------|-------------|---------|
| Correct results | Yes | Yes |
| Multi-core | No (sequential) | Yes |
| `task_spawn` overhead | Negligible | Real OS threads |

The API is identical in both modes. This means you can develop and test in the interpreter, then
compile to get real parallelism without changing a line of code.
