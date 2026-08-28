---
layout: cookbook
title: "Cookbook: Linear Types"
permalink: /docs/cookbook/linear-types/
---

# Linear Types

A linear value must be used exactly once: the compiler rejects code that drops it without consuming it, or uses it twice. This makes resource leaks and double-frees impossible to write.

---

## Declaring a linear type

A plain `type` is unrestricted by default: any binding of it can be copied, dropped, or used any number of times. Linearity is requested at the *binding site*, with `linear let`, or on a function parameter with `linear`:

```march
type FileHandle = FileHandle(Int)

fn read_file(path : String) : String do
  linear let fh = open_file(path)
  -- fh must be used before the function returns — the compiler tracks this
  let content = read_all(fh)   -- consumes fh
  content
end
```

Forgetting to use `fh` is a compile error:

```march
fn bad(path : String) : String do
  linear let fh = open_file(path)
  "oops"    -- error: "The linear value `fh` was never used."
end
```

And using it twice is also a compile error:

```march
fn also_bad(path : String) : String do
  linear let fh = open_file(path)
  let a = read_all(fh)
  let b = read_all(fh)   -- error: "The linear value `fh` is used more than once here."
  a ++ b
end
```

---

## Always-linear types

`always_linear type` promotes every binding to linear without per-use-site annotations:

```march
always_linear type DbConn = DbConn(Int)
```

Useful when you want the linearity guarantee enforced everywhere in the codebase, not just where the author remembered to write `linear let`.

---

## Typestate: handles that track state

A typestate handle adds a phantom *state* parameter to an `always_linear type`, so the compiler can track not just "used exactly once" but *which state* the value is in at every point in the program:

```march
always_linear type FileHandle(s) = FileHandle(Int)

tag FileTag
tag Closed
tag Open
```

State transitions are declared with `transitions`. Each `via` function must take the handle in its `from` state and return the handle (and *only* the handle, with no `Result` wrapper and no tuple) in its `to` state:

```march
fn open_conn(h : FileHandle(Closed)) : FileHandle(Open) do
  ...
end

fn close_file(h : FileHandle(Open)) : FileHandle(Closed) do
  ...
end

transitions FileHandle do
  FileTag: Closed -> Open   via open_conn
  FileTag: Open   -> Closed via close_file
end
```

Calling `close_file` on a `FileHandle(Closed)`, or `open_conn` on a `FileHandle(Open)`, is a compile error: the compiler tracks exactly which state the handle is in and rejects the call before it runs at all.

Two things fall out of `via`'s "handle in, bare handle out" shape:

1. **Acquiring the first handle is not itself a transition.** `open_file` takes a `String`, not a `FileHandle`: the `transitions` block only covers moves between states of a value you already hold, not creating that value in the first place. It's an ordinary function, free to return `Result` for the acquisition to fail:

   ```march
   fn open_file(path : String) : Result(FileHandle(Closed), String) do
     ...
   end
   ```

2. **An operation that also returns data can't be declared as a `via` transition** (its return type would be a tuple, not a bare handle), but it's still typestate-checked, for free, by its argument type. `read_chunk` only accepts a `FileHandle(Open)`, so calling it before `open_conn` is exactly as much a compile error as calling `close_file` twice would be; it just isn't *listed* under `transitions`, since it can't be:

   ```march
   fn read_chunk(h : FileHandle(Open)) : (String, FileHandle(Open)) do
     ...
   end
   ```

Putting the pieces together:

```march
fn process(path : String) : Result(String, String) do
  let? h0        = open_file(path)          -- FileHandle(Closed)
  let h1         = open_conn(h0)             -- FileHandle(Open)      — declared transition
  let (data, h2) = read_chunk(h1)             -- FileHandle(Open)      — checked via argument type
  match close_file(h2) do                     -- FileHandle(Closed)    — declared transition
    FileHandle(_) -> Ok(data)                 -- consumes the final handle
  end
end
```

Skipping the `open_conn` step and calling `read_chunk(h0)` directly is rejected at compile time:

```
expected `Open` but got `Closed`.

    let (data, h2) = read_chunk(h0)
                                 ^^
    This is argument #1 of a function call.
```

---

## `with` for linear resource scopes

`with` pairs acquisition with guaranteed cleanup, useful when you want RAII-style deterministic release. It's an alternative to `let?` for the same kind of Result-returning acquisition; here it drives the same state machine as `process` above:

```march
fn process_with(path : String) : Result(String, String) do
  with Ok(h0) <- open_file(path) do
    let h1         = open_conn(h0)
    let (data, h2) = read_chunk(h1)
    match close_file(h2) do
      FileHandle(_) -> Ok(data)
    end
  else
    Err(e) -> Err(e)
  end
end
```

Just like any other linear binding, a handle acquired through `with` is tracked for double-use and drop: consuming `h0` twice, or leaving `h2` unconsumed, is a compile error the same way it would be with a plain `let`.

---

## Complete example: safe socket lifecycle

```march
mod Net do
  always_linear type Socket(s) = Socket(Int)

  tag SockTag
  tag Connected
  tag Disconnected

  fn connect(addr : String) : Result(Socket(Connected), String) do
    ...
  end

  fn disconnect(sock : Socket(Connected)) : Socket(Disconnected) do
    ...
  end

  -- `send_bytes`/`recv_bytes` take or return more than a bare handle (a
  -- payload alongside it), so — like `read_chunk` above — they can't be
  -- listed in `transitions`. Their `Socket(Connected)` argument type still
  -- makes calling them out of order (e.g. after `disconnect`) a compile
  -- error; `transitions` only needs to cover the pure handle-to-handle edges.
  fn send_bytes(sock : Socket(Connected), data : String) : Socket(Connected) do
    ...
  end

  fn recv_bytes(sock : Socket(Connected)) : (String, Socket(Connected)) do
    ...
  end

  transitions Socket do
    SockTag: Connected -> Disconnected via disconnect
  end

  fn echo_once(addr : String) : Result((), String) do
    let? sock0       = connect(addr)
    let (msg, sock1) = recv_bytes(sock0)
    let sock2        = send_bytes(sock1, msg)
    match disconnect(sock2) do
      Socket(_) -> Ok(())
    end
  end
end
```

`recv_bytes` consumes `sock0` and returns `(msg, Socket(Connected))`, a fresh handle. Using `sock0` again after that (say, passing it to a second `recv_bytes` call) is a compile error: `sock0` is linear, and it was already consumed. Forgetting to call `disconnect` at the end would also be a compile error: the final handle would be dropped without being consumed. And calling `send_bytes` or `recv_bytes` *after* `disconnect` fails too: their parameter type is `Socket(Connected)`, and by then all you have is a `Socket(Disconnected)`.
