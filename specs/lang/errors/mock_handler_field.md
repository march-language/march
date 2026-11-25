---
layout: docs
title: "mock_handler_field"
permalink: /docs/errors/mock_handler_field/
---

# `mock_handler_field`: a `mock` handler names an operation its kind does not have

The handler of a `mock` block is a record with one field per operation of the
mocked capability kind; each field is an `Option`, and `None` (or leaving the
field out) keeps the real operation. This error reports a field the kind does
not have. `march --emit-io-ops` lists every kind's fields.

## A program that triggers it

```march
-- MARCH-MODE: test
mod ConsoleTest do
  needs IO.Console

  test "a field the kind does not have" do
    mock IO.Console with { println: Some(fn _ -> ()) } do
      println("hello")
    end
    ()
  end
end
```

## The fix

Name the operation the kind has. `println` is a stdlib function that prints
through the `print_line` operation:

```march
mod ConsoleTest do
  needs IO.Console

  test "print_line is the operation" do
    mock IO.Console with { print_line: Some(fn _ -> ()) } do
      println("hello")
    end
    ()
  end
end
```

## Why the rule exists

A misspelled field would otherwise be silently ignored, and the test would
run the real operation while looking mocked.

See also: [the language reference](../capabilities.md).
