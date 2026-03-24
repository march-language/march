# March Testing Library — Design Spec

**Date:** 2026-03-23
**Status:** Implementation in progress

---

## Overview

March's built-in testing library is inspired by ExUnit (Elixir) and Rust's built-in `#[test]` system. Tests are first-class language constructs — not library calls or macros. The compiler understands test declarations and can provide richer diagnostics (assertion rewriting) without any macro system.

---

## Surface Syntax

### Test declarations

```march
mod MyTests do
  test "addition works" do
    assert 1 + 1 == 2
  end

  test "string concat" do
    let s = "hello" ++ " " ++ "world"
    assert s == "hello world"
  end
end
```

A `test` block is a top-level declaration (like `fn`). It has:
- A string name (for display and filtering)
- A `do...end` body that is a block expression

### Assertions

```march
assert expr                   -- basic: fails if expr is false
assert lhs == rhs             -- equality: shows both sides on failure
assert lhs != rhs             -- inequality: shows both sides on failure
assert lhs < rhs              -- comparison: shows both sides on failure
```

**Compiler-assisted assertion rewriting:** The compiler (desugar pass) recognizes
`assert e1 <op> e2` where `<op>` is `==`, `!=`, `<`, `>`, `<=`, `>=`, and rewrites
it to a form that captures both sides. At eval time, if the assertion fails, the
error message shows:

```
FAIL test "addition works"
  Assertion failed: 1 + 2 == 4
    left:  3
    right: 4
```

For non-comparison asserts:

```
FAIL test "something truthy"
  Assertion failed: is_valid(x)
```

### Lifecycle hooks

```march
mod MyTests do
  setup do
    -- Runs before each test in this module
    -- Side-effects only (cannot bind variables visible to tests)
    println("setting up")
  end

  setup_all do
    -- Runs once before all tests in this module
    println("one-time setup")
  end

  test "foo" do
    assert 1 == 1
  end
end
```

`setup` and `setup_all` are for side-effectful setup (e.g., starting a mock server).
They do not share state with test bodies (for v1). Each test runs in a clean
environment.

### Tags (v1: name-based filtering only)

For v1, tests are filtered by substring match on the test name. Tags can be
embedded in the name:

```march
test "[slow] computes fib(40)" do
  assert fib(40) == 102334155
end
```

Run with `march test --filter=slow` to run only tests whose name contains "slow".

---

## File Conventions

- Test files: `test/test_*.march` (prefix convention matching March's own test suite)
  OR `test/*_test.march` (suffix convention, for compatibility with forge)
- Each test file is a standard March module
- `forge test` discovers and runs all test files in `test/`

---

## Output Format

### Dot mode (default)

```
test/test_math.march ...F..
test/test_string.march .....

2 failures:

FAIL test/test_math.march: "division by zero"
  Assertion failed: div(10, 0) == :error
    left:  :ok(Inf)
    right: :error

Finished: 8 tests, 2 failures, 0 errors in 3ms
```

### Verbose mode (`--verbose` or `-v`)

```
test/test_math.march
  ✓ addition works (0ms)
  ✓ subtraction works (0ms)
  ✗ division by zero (1ms)
  ✓ multiplication works (0ms)

...
```

---

## CLI Interface

```
march test [options] [file...]
march test --verbose           # verbose output
march test --filter=pattern    # only run tests matching substring
march test test/test_math.march  # run specific file(s)
```

Also exposed via forge:

```
forge test [options]           # runs all test files in test/
```

---

## Implementation Phases

### Phase 1: Syntax (lexer + AST + parser)
- [ ] Add `TEST`, `ASSERT`, `SETUP`, `SETUP_ALL` keywords to lexer
- [ ] Add `DTest` declaration to AST
- [ ] Add `EAssert` expression to AST
- [ ] Add `DSetup` and `DSetupAll` declarations to AST
- [ ] Add parser rules for all of the above

### Phase 2: Desugar
- [ ] Pass `DTest` through unchanged
- [ ] Rewrite `EAssert (EApp (EVar "==", [lhs; rhs]))` → `EAssertEq(lhs, rhs)` or equivalent
- [ ] Handle `DSetup`, `DSetupAll` (pass through)

### Phase 3: Typecheck
- [ ] `DTest` body typechecks as `Unit`
- [ ] `EAssert` typechecks as `Unit` (assertion evaluates to unit)
- [ ] `DSetup`, `DSetupAll` bodies typecheck as `Unit`
- [ ] Emit warning if no assertions in a test body

### Phase 4: Eval + test runner
- [ ] `run_tests` function in `eval.ml`
- [ ] Collect all `DTest` nodes from the module
- [ ] Run setup_all once (if present), then for each test: run setup, run test body
- [ ] Catch assertion failures (new exception type)
- [ ] Dot output by default
- [ ] `--verbose` output on request
- [ ] Exit code 1 if any tests fail

### Phase 5: march test subcommand
- [ ] `march test [--verbose] [--filter=pat] [file...]` subcommand in `bin/main.ml`
- [ ] Auto-discover `test/test_*.march` if no files given
- [ ] Update `forge/lib/cmd_test.ml` to call `march test`

---

## Design Notes

### Why first-class syntax?

Alternatives considered:
1. **Library approach** (`Test.register("name", fn() -> ...)`) — no special syntax needed but verbose and no assertion rewriting
2. **Macro approach** — not available in March
3. **First-class syntax** (chosen) — enables assertion rewriting, IDE integration, and consistent tooling

### Why not share setup state with tests?

Sharing state between setup and test bodies would require a context object (like ExUnit's `context` map) which complicates the type system. For v1, setup is side-effects only. A context mechanism can be added in v2.

### Parallel execution

Per-file actor isolation: each test *file* could be run in a separate actor/process (v2). For v1, tests run sequentially within a file. The spec documents that parallel tests should not share external mutable state.

### Assertion rewriting without macros

The desugar pass inspects the expression inside `assert` and, if it's a binary
comparison, preserves both sides as separate expressions with their source locations.
The eval pass then evaluates each side independently when an assertion fails, giving
rich error messages.
