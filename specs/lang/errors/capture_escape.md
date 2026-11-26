---
layout: docs
title: "capture_escape"
permalink: /docs/errors/capture_escape/
---

# `capture_escape`: a scoped handle leaves its callback

Some functions open a resource, hand it to a callback, and close it when the
callback returns: `File.with_open`, `File.with_open_write`,
`Socket.with_connection`. The handle the callback receives is a *scoped
handle*. It is only good until the callback returns, so it may not leave the
callback, on its own or inside anything that holds it. Before this check, a
handle that got out failed later, at run time, with `Err(Closed)`.

The handle leaves when the callback:

- returns it, or returns a function, record, tuple, list or task that holds it;
- stores it in a `Vault` table;
- sends it to an actor, or gives it to a spawned actor;
- hands a function that captured it to something that runs it later (a signal
  watcher, a logger field);
- passes it to code the compiler cannot follow, such as a function value read
  from a table that was opened by name.

Everything else is allowed inside the callback: passing the handle to
functions that read or write, building local values around it, starting a task
that uses it and awaiting that task before returning.

## A program that triggers it

```march
mod Main do
  needs IO.FileRead

  fn main() do
    let reader = File.with_open("notes.txt", fn h -> fn () -> File.read_line(h))
    ()
  end
end
```

The callback returns a function that still holds `h`. By the time anyone calls
it, `with_open` has closed the file.

## The fix

Read what you need inside the callback, and return the data:

```march
mod Main do
  needs IO.FileRead

  fn main() do
    let first = File.with_open("notes.txt", fn h -> File.read_line(h))
    ()
  end
end
```

If the handle really has to outlive one call, open it with `File.open` and
close it yourself with `File.close`. An ordinary handle is not scoped and can
go anywhere.

## Writing a function with a scoped callback

Mark the callback's parameter `scoped` in the signature of the function that
owns the resource:

```text
fn with_log(path : String, body : scoped File.Handle -> r) : Result(Result(r, FileError), CapError) do
  File.with_open_write(path, File.Append, body)
end
```

Every caller of `with_log` then gets this check for the handle its callback
receives.
