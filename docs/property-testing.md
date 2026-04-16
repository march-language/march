---
layout: page
title: Property Testing
nav_order: 13
---

# Property Testing

March includes a built-in property testing library inspired by [Hedgehog](https://hedgehog.qa/). Instead of writing individual test cases with specific inputs, you describe **properties** that should hold for all values of a type, and the library generates hundreds of random inputs to verify them.

When a property fails, the library automatically **shrinks** the failing input to the smallest counterexample that still fails — without any extra work from you.

---

## Quick start

```elixir
mod MyTests do

  test "addition is commutative" do
    Check.all(Gen.tuple2(Gen.int(-100, 100), Gen.int(-100, 100)), fn pair ->
      match pair do
      (a, b) -> a + b == b + a
      end
    )
  end

end
```

Run it:

```sh
march test my_tests.march
```

That's it. `Check.all` runs the property 100 times with growing input sizes. If it passes, the test passes silently. If it fails, you get a minimal counterexample.

---

## How it works

### Generators produce values with built-in shrink trees

Every generator returns not just a value, but a **rose tree** of shrink candidates. When `Gen.int(0, 100)` generates `87`, the tree looks like:

```
87
├── 0      (target)
├── 43     (halfway)
├── 65     (three-quarters)
├── 76
├── 81
├── 84
├── 85
└── 86
```

Each of those nodes has its own children, recursively. This is called **integrated shrinking** — the shrink strategy is embedded in the generator, not bolted on as a separate step.

### Why integrated shrinking matters

When you compose generators with `Gen.bind`, the shrinking automatically stays coherent. If you generate a list and then an index into that list, shrinking the list won't produce an invalid index — the index is re-derived from the same random bits as the original.

This is the key advantage over QuickCheck-style property testing, where shrinking is separate and can produce invalid combinations from dependent generators.

---

## Writing properties

A property is a function that takes a generated value and returns `Bool`:

```elixir
test "reverse is involutive" do
  Check.all(Gen.list(Gen.int(-50, 50)), fn xs ->
    List.length(List.reverse(List.reverse(xs))) == List.length(xs)
  )
end
```

### Multiple assertions

Use `let _ = assert ...` to chain multiple assertions. The final expression must be `true`:

```elixir
test "sort invariants" do
  Check.all(Gen.list(Gen.int(-100, 100)), fn xs ->
    let sorted = List.sort_by(xs, int_lt)
    let _ = assert (List.length(sorted) == List.length(xs))
    let _ = assert (is_sorted(sorted))
    true
  )
end
```

If any assertion fails, the runner catches the failure and shrinks to the minimal input that triggers it.

### Crash-catching

Properties that crash (division by zero, match failures, index out of bounds) are also caught and shrunk:

```elixir
test "safe_divide handles all inputs" do
  Check.all(Gen.tuple2(Gen.int(-100, 100), Gen.int(-100, 100)), fn pair ->
    match pair do
    (a, b) ->
      let _ = safe_divide(a, b)
      true
    end
  )
end
```

If `safe_divide` panics for some input, the runner finds the minimal crashing input.

---

## Available generators

### Primitives

| Generator | Produces | Shrinks toward |
|-----------|----------|----------------|
| `Gen.int(lo, hi)` | Integer in `[lo, hi]` | 0 (or nearest bound) |
| `Gen.bool()` | `true` or `false` | `false` |
| `Gen.float(lo, hi)` | Float in `[lo, hi)` | 0.0 (or nearest bound) |
| `Gen.constant(x)` | Always `x` | No shrinking |
| `Gen.element(xs)` | Uniform from list | First element |
| `Gen.int_sized()` | Integer in `[0, size]` | 0 |

### Strings and characters

| Generator | Produces | Shrinks toward |
|-----------|----------|----------------|
| `Gen.ascii_char()` | Char code 32-126 | `'a'` (97) |
| `Gen.lowercase_char()` | Char code 97-122 | `'a'` |
| `Gen.string()` | ASCII string | Shorter, simpler chars |
| `Gen.lowercase_string()` | Lowercase string | Shorter |
| `Gen.string_of(char_gen)` | String from custom char generator | Shorter, simpler |

### Collections

| Generator | Produces | Shrinks toward |
|-----------|----------|----------------|
| `Gen.list(gen)` | List, length `[0, size]` | Shorter, simpler elements |
| `Gen.list_of_size(n, gen)` | List of exactly `n` | Simpler elements |
| `Gen.option(gen)` | `None` ~25%, `Some(x)` ~75% | `None` first |
| `Gen.tuple2(ga, gb)` | 2-tuple | Each component independently |
| `Gen.tuple3(ga, gb, gc)` | 3-tuple | Each component independently |

### Combinators

| Combinator | Purpose |
|------------|---------|
| `Gen.map(gen, f)` | Transform values; shrinking inherited |
| `Gen.filter(gen, pred)` | Rejection sampling; up to 100 attempts |
| `Gen.bind(gen, f)` | Dependent generators; shrinking stays coherent |
| `Gen.one_of(gens)` | Uniform choice among generators |
| `Gen.frequency(pairs)` | Weighted choice: `[(3, gen_a), (1, gen_b)]` |
| `Gen.sized(f)` | Access the size hint: `fn size -> gen` |

---

## Combinators in depth

### `Gen.map` — transform values

```elixir
-- Generate even numbers
let gen_even = Gen.map(Gen.int(0, 50), fn n -> n * 2)

-- Generate record-like tuples
let gen_point = Gen.map(
  Gen.tuple2(Gen.float(-1.0, 1.0), Gen.float(-1.0, 1.0)),
  fn pair -> match pair do (x, y) -> (x, y) end
)
```

### `Gen.bind` — dependent generators

When the second generator depends on the first value:

```elixir
-- Generate a list and a valid index into it
let gen_list_and_index = Gen.bind(
  Gen.filter(Gen.list(Gen.int(0, 100)), fn xs -> List.length(xs) > 0),
  fn xs -> Gen.map(Gen.int(0, List.length(xs) - 1), fn i -> (xs, i))
)
```

Shrinking the list automatically re-derives a valid index.

### `Gen.string_of` — custom string alphabets

```elixir
-- Hex strings
let hex_char = Gen.element([48, 49, 50, 51, 52, 53, 54, 55,
                            56, 57, 97, 98, 99, 100, 101, 102])
let gen_hex = Gen.string_of(hex_char)

-- Digit-only strings
let gen_digits = Gen.string_of(Gen.int(48, 57))
```

### `Gen.sized` — size-dependent generation

The runner grows the `size` parameter from 0 to 100 across runs. Use `Gen.sized` to access it:

```elixir
-- Cap list length at 10 regardless of runner size
let gen_short_list = Gen.sized(fn s ->
  let cap = if s > 10 do 10 else s end
  Gen.list_of_size(cap, Gen.int(0, 100))
)
```

---

## Configuration

### `Check.all_with`

Override defaults with `Check.all_with`:

```elixir
test "stress test with more runs" do
  let config = { Check.default_config() with num_runs = 500, max_size = 200 }
  Check.all_with(Gen.list(Gen.int(0, 100)), fn xs ->
    List.length(xs) >= 0
  , config)
end
```

**Config fields:**

| Field | Default | Description |
|-------|---------|-------------|
| `num_runs` | 100 | Number of random inputs to test |
| `seed` | `None` | Fixed seed (`Some(42)`); overrides env/clock |
| `max_shrink_steps` | 1000 | Max shrink attempts before giving up |
| `max_size` | 100 | Maximum size hint passed to generators |

### Reproducible seeds

When a property fails, the output includes the seed:

```
property failed after 23 run(s)
  counterexample: 50
  returned false
  shrunk 3 step(s) from: 94
  reproduce with seed: 1234567890
```

Re-run with the same seed:

```sh
march test my_tests.march --seed=1234567890
forge test --seed=1234567890
```

### Skipping property tests

Property tests run hundreds of iterations and can be slow. Skip them for fast feedback:

```sh
march test --skip-properties
forge test --skip-properties
```

All `Check.all` calls return immediately without running.

---

## Failure output

A failing property produces a report like:

```
FAIL: "list is always non-empty"
  error: panic: property failed after 1 run(s)
    counterexample: []
    returned false
    shrunk 0 step(s) from: []
    reproduce with seed: 1776290875
```

For assertion failures, the assertion diagnostic is included:

```
FAIL: "values are bounded"
  error: panic: property failed after 5 run(s)
    counterexample: 10
    raised: assert 10 < 10
      left:  10
      right: 10
    shrunk 2 step(s) from: 13
    reproduce with seed: 42
```

For crashes:

```
FAIL: "no division by zero"
  error: panic: property failed after 21 run(s)
    counterexample: 0
    raised: int_div: division by zero
    shrunk 0 step(s) from: 0
    reproduce with seed: 99
```

---

## Property patterns

### Algebraic laws

Test mathematical properties that must hold:

```elixir
-- Commutativity: a + b == b + a
-- Associativity: (a + b) + c == a + (b + c)
-- Identity: a + 0 == a
-- Inverse: a - a == 0
-- Distributivity: a * (b + c) == a*b + a*c
-- Idempotence: sort(sort(xs)) == sort(xs)
-- Involution: reverse(reverse(xs)) == xs
```

### Round-trip properties

Encode and decode should cancel:

```elixir
test "base64 round-trip" do
  Check.all(Gen.lowercase_string(), fn s ->
    let encoded = Base64.encode(Bytes.from_string(s))
    match Base64.decode(encoded) do
    Ok(decoded) -> Bytes.to_string(decoded) == s
    Err(_)      -> false
    end
  )
end
```

### Structural invariants

Operations should preserve certain properties:

```elixir
-- Length preservation: length(map(f, xs)) == length(xs)
-- Monotonicity: length(filter(p, xs)) <= length(xs)
-- Sorted output: is_sorted(sort(xs))
-- Partition: take(n, xs) ++ drop(n, xs) == xs
```

### Model checking

Compare a complex implementation against a simpler reference:

```elixir
test "BigInt mul matches Int for small values" do
  Check.all(Gen.tuple2(Gen.int(-100, 100), Gen.int(-100, 100)), fn pair ->
    match pair do (a, b) ->
      BigInt.to_string(BigInt.mul(BigInt.from_int(a), BigInt.from_int(b)))
        == int_to_string(a * b)
    end
  )
end
```

---

## API reference

### Gen module

**Primitives:** `int`, `int_sized`, `bool`, `float`, `constant`, `element`, `ascii_char`, `lowercase_char`

**Strings:** `string`, `lowercase_string`, `string_of`

**Collections:** `list`, `list_of_size`, `option`, `tuple2`, `tuple3`

**Combinators:** `map`, `filter`, `bind`, `one_of`, `frequency`, `sized`

**Tree inspection (advanced):** `tree_root`, `tree_children`, `tree_singleton`, `tree_map`, `tree_bind`, `tree_filter`, `run`

### Check module

| Function | Signature | Description |
|----------|-----------|-------------|
| `Check.all(gen, prop)` | `Generator(a), (a -> Bool) -> Unit` | Run property with defaults |
| `Check.all_with(gen, prop, config)` | `..., CheckConfig -> Unit` | Run with custom config |
| `Check.default_config()` | `-> CheckConfig` | `{num_runs=100, seed=None, max_shrink_steps=1000, max_size=100}` |
