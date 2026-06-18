---
layout: cookbook
title: "Cookbook: Concurrency"
permalink: /docs/cookbook/concurrency/
---

# Concurrency

March has two concurrency primitives: **Tasks** for async work and **Actors** for stateful, isolated processes.

---

## Tasks

`Task.async` starts a concurrent computation. `Task.await` blocks until it finishes:

```march
let t = Task.async(fn () -> expensive_computation())
let result = Task.await(t)
```

Run multiple tasks in parallel and collect all results:

```march
let tasks = List.map(urls, fn url -> Task.async(fn () -> fetch(url)))
let results = Task.await_many(tasks)
```

Race — first to finish wins, others are cancelled:

```march
match Task.race([
  Task.async(fn () -> primary_source()),
  Task.async(fn () -> fallback_source())
]) do
  Ok(v)  -> v
  Err(e) -> handle_error(e)
end
```

---

## Actors

An actor has isolated state and processes messages one at a time. No shared memory — data races are impossible by construction:

```march
actor Counter do
  state { value : Int }
  init { value = 0 }

  on Increment(n : Int) do
    { value = state.value + n }
  end

  on Get() do
    println(int_to_string(state.value))
    state
  end
end
```

Spawn an actor and send messages:

```march
let pid = spawn(Counter)
send(pid, Increment(5))
send(pid, Increment(3))
send(pid, Get())
```

---

## Channels

Channels are typed conduits between tasks:

```march
let ch = Channel.new("work-queue")

Task.async(fn () -> do
  Channel.push(ch, "hello")
  Channel.push(ch, "world")
end)

let msg = Channel.receive(ch)
```

---

## Complete example: parallel fetch with timeout

```march
mod Fetch do
  fn fetch_all(urls : List(String)) : List(Result(String, String)) do
    let tasks = List.map(urls, fn url ->
      Task.async(fn () -> HttpClient.get(url))
    )
    Task.await_many_ms(tasks, 5000)
  end

  fn main() do
    let urls = [
      "https://httpbin.org/get",
      "https://httpbin.org/delay/1",
      "https://httpbin.org/status/500"
    ]
    let results = fetch_all(urls)
    List.each(results, fn r ->
      match r do
        Ok(resp) -> println("ok: " ++ String.slice_bytes(resp.body, 0, 40))
        Err(e)   -> println("err: " ++ e)
      end
    )
  end
end
```
