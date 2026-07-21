---
layout: cookbook
title: "Cookbook: Linear Types"
permalink: /docs/cookbook/linear-types/
---

# Linear Types

A linear value must be used exactly once — the compiler rejects code that drops it without consuming it, or uses it twice. This makes resource leaks and double-frees impossible to write.

---

## Declaring a linear type

```march
type FileHandle = FileHandle(Int)
```

A `linear let` at the binding site makes that particular binding linear. Dropping it without calling a consuming function is a compile error:

```march
fn main() do
  linear let fh = open_file("data.txt")
  -- returning here without using fh would be a compile error:
  -- "The linear value `fh` was never used."
  let content = read_all(fh)   -- consumes fh
  println(content)
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

`Handle(Resource, State)` is a built-in always-linear typestate handle. State transitions are declared with `transitions`:

```march
tag Open
tag Closed

transitions FileHandle do
  Closed: Closed -> Open   via open_file
  Open:   Open   -> Closed via close_file
  Open:   Open   -> Open   via read_chunk
end
```

Calling `read_chunk` on a `FileHandle(Closed)` is a compile error. The type system tracks exactly which state the handle is in at every point:

```march
fn process(path : String) : Result(String, String) do
  let? fh      = open_file(path)          -- FileHandle(Open)
  let? content = read_chunk(fh)           -- FileHandle(Open), returns (data, FileHandle(Open))
  close_file(content.handle)              -- FileHandle(Open) -> Closed
  Ok(content.data)
end
```

---

## `with` for linear resource scopes

`with` pairs acquisition with guaranteed cleanup — useful when you want RAII-style deterministic release:

```march
fn read_file(path : String) : Result(String, String) do
  with Ok(fh) <- open_file(path) do
    let content = read_all(fh)
    close_file(fh)
    Ok(content)
  else
    Err(e) -> Err(e)
  end
end
```

---

## Complete example: safe socket lifecycle

```march
mod Net do
  always_linear type Socket = Socket(Int)

  tag Connected
  tag Disconnected

  transitions Socket do
    Disconnected: Disconnected -> Connected    via connect
    Connected:    Connected    -> Disconnected via disconnect
    Connected:    Connected    -> Connected    via send_bytes
    Connected:    Connected    -> Connected    via recv_bytes
  end

  fn echo_once(addr : String) : Result((), String) do
    let? sock         = connect(addr)
    let? (msg, sock2) = recv_bytes(sock)
    let? sock3        = send_bytes(sock2, msg)
    disconnect(sock3)
    Ok(())
  end
end
```

`recv_bytes` consumes `sock` and returns `(data, Socket(Connected))` — a fresh handle. Using the original `sock` after that would be a compile error (linear value used twice). Forgetting to call `disconnect` at the end would also be a compile error — `sock3` would be dropped without being consumed.
