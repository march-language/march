---
layout: docs
title: "mock_outside_test"
permalink: /docs/errors/mock_outside_test/
---

# `mock_outside_test`: a `mock` block outside a test build

`mock SCOPE with HANDLER do ... end` replaces real capability operations with
a handler, so a test can run code that reads the clock, prints or opens files
without touching the outside world. It exists only in test builds: `march
test`, `forge test`, and any build with `--test`. Anywhere else it is this
error.

## A program that triggers it

```march
mod Main do
  needs IO.Console
  needs IO.Clock

  fn main() do
    mock IO.Clock with { unix_time_ms: Some(fn _ -> 0) } do
      println(show(System.now_ms()))
    end
  end
end
```

## The fix

Move the `mock` into a test, and run it with `march test` (or `forge test`):

```march
mod ClockTest do
  needs IO.Clock

  test "the clock can be mocked" do
    let t = mock IO.Clock with { unix_time_ms: Some(fn _ -> 0) } do
      System.now_ms()
    end
    assert(t == Ok(0))
  end
end
```

## Why the rule exists

A mock decides what a capability operation does, and the block has the
mocked authority whether or not the program was launched with it. That is
what a test wants and what a shipped program must never do, so a release
build refuses it.

See also: [the language reference](../capabilities.md).
