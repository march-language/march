---
layout: docs
title: Property Testing
nav_order: 13
permalink: /docs/property-testing/
---

# Property Testing

A property test states a rule that should hold for every input, and checks it on
hundreds of generated inputs instead of a few you picked by hand. `Check.all` takes a
generator, such as `Gen.list(Gen.int(-50, 50))`, and a function that returns `true`
when the rule holds; `march test` and `forge test` run it like any other test. The
library follows [Hedgehog](https://hedgehog.qa/).

When a property fails, the runner shrinks the failing input to the smallest one that
still fails, and the report shows that input bound to your parameter's name: a failure
found on a long list comes back as the shortest list that still fails. Shrinking is
built into the generators, so it needs no extra code.

This page covers writing and running properties first, then the generators and
combinators, then how shrinking works.

## On this page

**Start here**

- [Which tool do I need?](#which-tool-do-i-need)
- [How it fits with the rest of March](#how-it-fits-with-the-rest-of-march)

**Writing properties**

- [Quick start](#quick-start)
- [Writing properties](#writing-properties): [several assertions](#multiple-assertions), [crashes](#crash-catching)
- [Property patterns](#property-patterns): laws, round trips, invariants, model checking
- [Failure output](#failure-output)
- [Configuration](#configuration): `Check.all_with`, [reproducible seeds](#reproducible-seeds), [skipping property tests](#skipping-property-tests)

**Generators**

- [Available generators](#available-generators)
- [Combinators in depth](#combinators-in-depth)
- [How it works](#how-it-works): shrink trees, and why integrated shrinking matters

**Reference**

- [API reference](#api-reference)
- [Errors you'll see](#errors-youll-see)
- [See also](#see-also)

## Which tool do I need?

| You want | Write |
|---|---|
| A check for one specific input | A `test` with `assert`; no generator needed |
| A rule that holds for every input of a type | `Check.all(gen, fn x -> ...)` |
| Numbers from a range | `Gen.int(lo, hi)`, `Gen.float(lo, hi)` |
| Lists, options, tuples and strings | `Gen.list`, `Gen.option`, `Gen.tuple2`, `Gen.string` |
| Values of your own type | `Gen.map` over a generator of its fields |
| A second input that depends on the first | `Gen.bind` |
| More runs, bigger inputs or a fixed seed | `Check.all_with(gen, prop, config)` |
| A failing run replayed | `forge test --seed=N`, with the seed the report prints |
| The rule proved for every input, not sampled | A refinement type or a lemma; see [Refinement Types]({{ site.baseurl }}/docs/refinement-types/) |

## How it fits with the rest of March

| Concept | Where property tests meet it | Chapter |
|---|---|---|
| **Test runner** | `Check.all` runs inside a `test` block; `march test` and `forge test` run it, and `--seed` and `--skip-properties` control it. | [Tooling]({{ site.baseurl }}/docs/tooling/#testing) |
| **Refinement types and lemmas** | A property samples inputs; a refinement or a lemma proves the rule for all of them at compile time. Use a property as a first check before writing a proof, or when a proof is out of reach. | [Type System]({{ site.baseurl }}/docs/types/#which-safety-tool-for-which-job), [Lemmas]({{ site.baseurl }}/docs/lemmas/) |
| **Interfaces** | An interface can state laws, such as associativity, that every implementation must have; a property checks the same law by sampling. | [Interfaces]({{ site.baseurl }}/docs/interfaces/#laws) |
| **Standard library** | `Gen` and `Check` are stdlib modules; round-trip properties over `Base64`, `Json` and other codecs are a common first use. | [Stdlib Guide]({{ site.baseurl }}/docs/stdlib-guide/) |

---

## Quick start

```march
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

## Writing properties

A property is a function that takes a generated value and returns `Bool`:

```march
test "reverse is involutive" do
  Check.all(Gen.list(Gen.int(-50, 50)), fn xs ->
    List.length(List.reverse(List.reverse(xs))) == List.length(xs)
  )
end
```

### Multiple assertions

Use `let _ = assert ...` to chain multiple assertions. The final expression must be `true`:

```march
test "sort invariants" do
  Check.all(Gen.list(Gen.int(-100, 100)), fn xs ->
    let sorted = List.sort_by(xs, fn (a, b) -> a < b)
    let _ = assert (List.length(sorted) == List.length(xs))
    let _ = assert (List.all(List.zip(sorted, List.drop(sorted, 1)), fn pair ->
      match pair do (a, b) -> a <= b end
    ))
    true
  )
end
```

If any assertion fails, the runner catches the failure and shrinks to the minimal input that triggers it.

### Crash-catching

Properties that crash (division by zero, match failures, index out of bounds) are also caught and shrunk:

```march
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

## Property patterns

### Algebraic laws

Test mathematical properties that must hold:

```march
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

```march
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

```march
-- Length preservation: length(map(f, xs)) == length(xs)
-- Monotonicity: length(filter(p, xs)) <= length(xs)
-- Sorted output: is_sorted(sort(xs))
-- Partition: take(n, xs) ++ drop(n, xs) == xs
```

### Model checking

Compare a complex implementation against a simpler reference:

```march
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

## Failure output

A failing property is reported like a compile error: a `-- TEST FAILURE --`
header, the `Check.all` call under a caret, the run that failed, the shrunk
input bound to the property's own parameter name, why it failed, and the seed.
The interpreter (`march test`) and a compiled test binary (`forge test`) print
the same report.

```
FAIL: "list reverse is the identity"
  -- TEST FAILURE ----------------------------- test/test_lists.march

  This property does not hold. [property_failed]

  8 |       Check.all(Gen.list(Gen.int(-100, 100)), fn xs ->
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

      It failed on run 4 of 100.

      Smallest failing input (shrunk in 7 steps from `[-47, 83]`):

          xs = [0, 1]

      The property returned `false`.

      Seed 42: replay it with `forge test --seed=42`.
```

A property that takes a tuple apart with a single-arm `match` gets one line per
name, and an `assert` that fails inside it is shown with its own report (both
sides by their source text, and for `==` the first difference marked):

```
      Smallest failing input (shrunk in 3 steps from `(98, 11)`):

          a = 39
          b = 11

      It failed this assertion:

      This `<` comparison is false. [assert_failed]

      17 |           assert (a + b < 50)
                             ^^^^^^^^^^

          left `a + b`
              50
          right
              50
```

A property that crashes says so: `It panicked: int_div: division by zero`.

The names come from the compiler, which passes the property lambda's parameter
name to `Check`: a property given as a named function (`Check.all(g, my_prop)`)
is reported as `input = ...`.

---

## Configuration

### `Check.all_with`

Override defaults with `Check.all_with`:

```march
test "stress test with more runs" do
  let config = { Check.default_config() with num_runs: 500, max_size: 200 }
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

When a property fails, the report ends with the seed (or says the property's
config fixes it):

```
    Seed 1234567890: replay it with `forge test --seed=1234567890`.
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

### `Gen.map`: transform values

```march
-- Generate even numbers
let gen_even = Gen.map(Gen.int(0, 50), fn n -> n * 2)

-- Generate record-like tuples
let gen_point = Gen.map(
  Gen.tuple2(Gen.float(-1.0, 1.0), Gen.float(-1.0, 1.0)),
  fn pair -> match pair do (x, y) -> (x, y) end
)
```

### `Gen.bind`: dependent generators

When the second generator depends on the first value:

```march
-- Generate a list and a valid index into it
let gen_list_and_index = Gen.bind(
  Gen.filter(Gen.list(Gen.int(0, 100)), fn xs -> List.length(xs) > 0),
  fn xs -> Gen.map(Gen.int(0, List.length(xs) - 1), fn i -> (xs, i))
)
```

Shrinking the list automatically re-derives a valid index.

### `Gen.string_of`: custom string alphabets

```march
-- Hex strings
let hex_char = Gen.element([48, 49, 50, 51, 52, 53, 54, 55,
                            56, 57, 97, 98, 99, 100, 101, 102])
let gen_hex = Gen.string_of(hex_char)

-- Digit-only strings
let gen_digits = Gen.string_of(Gen.int(48, 57))
```

### `Gen.sized`: size-dependent generation

The runner grows the `size` parameter from 0 to 100 across runs. Use `Gen.sized` to access it:

```march
-- Cap list length at 10 regardless of runner size
let gen_short_list = Gen.sized(fn s ->
  let cap = if s > 10 do 10 else s end
  Gen.list_of_size(cap, Gen.int(0, 100))
)
```

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

Each of those nodes has its own children, recursively. This is called **integrated shrinking**: the shrink strategy is embedded in the generator, not bolted on as a separate step.

### Why integrated shrinking matters

When you compose generators with `Gen.bind`, the shrinking automatically stays coherent. If you generate a list and then an index into that list, shrinking the list won't produce an invalid index; the index is recomputed from the same random bits as the original.

This is the key advantage over QuickCheck-style property testing, where shrinking is separate and can produce invalid combinations from dependent generators.

---

## API reference

### Gen module

**Primitives:** `int(lo, hi)` (bounds required), `int_sized`, `bool`, `float`, `constant`, `element`, `ascii_char`, `lowercase_char`

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

---

## Errors you'll see

The [Error Messages tour]({{ site.baseurl }}/docs/error-messages/) shows both kinds of test failure in full, as `march test` and a compiled test binary print them:

- [A property that fails, with its shrunk input and seed]({{ site.baseurl }}/docs/error-messages/#property-counterexample)
- [An `assert ==` that fails, with the first difference marked]({{ site.baseurl }}/docs/error-messages/#assert-diff)

---

## See also

- [Tooling]({{ site.baseurl }}/docs/tooling/#testing): `forge test`, filters, seeds and verbose output
- [Lemmas]({{ site.baseurl }}/docs/lemmas/): proving a rule for every input instead of sampling it
- [Interfaces]({{ site.baseurl }}/docs/interfaces/#laws): laws an interface's implementations must satisfy
- [Stdlib Guide]({{ site.baseurl }}/docs/stdlib-guide/): the modules your properties exercise
