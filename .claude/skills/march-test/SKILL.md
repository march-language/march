---
name: march-test
description: Write March tests — unit tests with describe/test/assert, and property tests with Check.all. Use when adding or fixing a .march test file, in a forge project or in the compiler repo's test/stdlib/.
---

# Writing March Tests

March tests live in `test/` (or `test/stdlib/` for stdlib modules) as `.march` files. A test file is a module whose body contains `describe`/`test` blocks.

## Unit test template

```march
-- Tests for the Foo stdlib module
-- Run with: forge test test/stdlib/test_foo.march

mod TestFoo do

  -- Private helpers live at the top of the module
  pfn make_thing(n : Int) do
    -- ...
  end

  describe "group name" do
    test "describes what is being asserted" do
      let x = Foo.make()
      assert Foo.is_empty(x)
      assert (Foo.length(x) == 0)
    end

    test "another case" do
      assert (1 + 1 == 2)
    end
  end

  describe "another group" do
    test "..." do
      -- ...
    end
  end

end
```

Conventions:
- Module name: `TestFoo` for `Foo` (PascalCase)
- File name: `test_foo.march` (snake_case)
- `describe` groups related tests; `test` is a single case
- `assert expr` — parentheses around comparisons: `assert (a == b)` not `assert a == b`
- Multiple asserts per test are fine
- Use `pfn` for test-file-private helpers

## Property tests (Check.all)

`Check.all` runs a generator-produced value through a property function 100 times by default. On failure it shrinks to a minimal counterexample and reports the seed for replay.

```march
test "reverse is involutive" do
  Check.all(Gen.list(Gen.int(-1000, 1000)), fn xs ->
    list_eq_int(List.reverse(List.reverse(xs)), xs)
  )
end
```

The property function returns `Bool`. Returning `false`, raising `assert`, or crashing all count as failures.

### Common generators (from `stdlib/gen.march`)

| Generator | Produces |
|-----------|----------|
| `Gen.int(lo, hi)` | Int in `[lo, hi]` |
| `Gen.float(lo, hi)` | Float in `[lo, hi]` |
| `Gen.bool()` | Bool |
| `Gen.list(g)` | List of values from `g` |
| `Gen.option(g)` | `Option(a)` |
| `Gen.tuple2(ga, gb)` | `(a, b)` |
| `Gen.tuple3(ga, gb, gc)` | `(a, b, c)` |
| `Gen.element(xs)` | Uniform choice from list |
| `Gen.one_of([g1, g2, ...])` | Uniform choice among generators |
| `Gen.frequency([(w, g), ...])` | Weighted choice |
| `Gen.constant(x)` | Always `x` |
| `Gen.map(g, f)` | Transform output |
| `Gen.bind(g, f)` | Monadic sequencing |
| `Gen.filter(g, pred)` | Reject values failing `pred` |

### Unpacking tuple generators

A tuple generator's callback takes the tuple and must `match` it:

```march
Check.all(Gen.tuple2(Gen.int(-100, 100), Gen.int(-100, 100)), fn pair ->
  match pair do
  (a, b) -> a + b == b + a
  end
)
```

### Custom config with Check.all_with

Use `Check.all_with(gen, prop, config)` when you need a specific seed, run count, or shrink budget:

```march
let config = {
  num_runs: 1000,
  seed: Some(42),
  max_shrink_steps: 500,
  max_size: 100
}
Check.all_with(Gen.int(-100, 100), fn n -> n < 50, config)
```

### Helper equality functions

Property bodies often need pointwise equality on structures. Put these as `pfn` in the module:

```march
pfn list_eq_int(xs : List(Int), ys : List(Int)) : Bool do
  if List.length(xs) != List.length(ys) do false
  else List.all(List.zip(xs, ys), fn p -> match p do (a, b) -> a == b end)
  end
end
```

## Running tests

```bash
forge test                                    # all tests
forge test test/stdlib/test_foo.march         # one file
forge test --filter=reverse                   # matching tests only
forge test --seed=42                          # deterministic property seed
forge test --skip-properties                  # skip Check.all tests
forge test -v                                 # print each test name
forge test --coverage                         # collect coverage
```

The `MARCH_PROP_SEED` env var also sets the seed if `--seed` isn't passed (`forge test --seed=N` sets it).

### In the compiler repo

The stdlib's own tests (`test/stdlib/*.march`) are run by a dedicated executable, not by
`forge test`:

```bash
scripts/run-tests.sh stdlib_march       # every test/stdlib/*.march
```

A new `test/stdlib/test_FOO.march` must be registered in `test/test_stdlib_march.ml`. A guard
there fails the suite for a `test_*.march` file that is neither registered nor on its allowlist of
older unregistered files; do not add a new file to that allowlist. The other stdlib executable,
`run_stdlib` (`scripts/run-tests.sh stdlib`), holds the OCaml alcotest groups, not `.march` files.
A single file also runs on its own with `march test test/stdlib/test_FOO.march`.

## When tests fail

1. For unit tests: read the assertion, figure out what invariant was violated.
2. For property tests: the report includes the shrunk counterexample and seed. Replay with `forge test --seed=<N>` to reproduce deterministically while debugging.
3. If a property shrinks to something surprising (e.g. empty list), that's often a missing base-case in the implementation.

## Doctests

`forge test` also runs doctests extracted from `doc """..."""` annotations (the `march>` blocks under `## Examples`). See the **`march-docs`** skill for doctest format and conventions. Doctests count toward the test totals and report failures alongside unit tests.

## Reference files

- `stdlib/check.march` — the property runner
- `stdlib/gen.march` — generator library
- `test/stdlib/test_check.march` — examples of Check.all / Check.all_with
- `test/stdlib/test_properties.march` — real property tests for stdlib
