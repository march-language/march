---
layout: cookbook
title: "Cookbook: Concurrency"
permalink: /docs/cookbook/concurrency/
scrollmd: true
---

# Concurrency

March has two concurrency primitives: **Tasks** for async work and **Actors** for stateful, isolated processes.

---

## Tasks

`Task.async` starts a concurrent computation. `Task.await` blocks until it finishes:

<!-- scroll:skip -->
```march
let t = Task.async(fn () -> expensive_computation())
let result = Task.await(t)
```

Run multiple tasks in parallel and collect all results:

<!-- scroll:skip -->
```march
let tasks = List.map(urls, fn url -> Task.async(fn () -> fetch(url)))
let results = Task.await_many(tasks)
```

Race: first to finish wins, others are cancelled:

<!-- scroll:skip -->
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

An actor has isolated state and processes messages one at a time. No shared memory means data races are impossible by construction:

<!-- scroll:skip -->
```march
actor Counter do
  state { value : Int }
  init { value: 0 }

  on Increment(n : Int) do
    { value: state.value + n }
  end

  on Report() do
    println(int_to_string(state.value))
    state
  end
end
```

Spawn an actor and send messages:

<!-- scroll:skip -->
```march
let pid = spawn(Counter)
send(pid, Increment(5))
send(pid, Increment(3))
let _ = send(pid, Report())
```

---

## Fan-out and collect

A common pattern: fan out N tasks, collect when all complete. `Task.async_stream` maps a list to concurrent tasks and returns results as they finish:

```march
let client = HttpClient.new_client()
let urls = ["https://api.example.com/a", "https://api.example.com/b"]

let results = Task.async_stream(urls, fn url ->
  HttpClient.get(client, url)
)
```

For structured coordination, use an actor as a mailbox: tasks send to it, it accumulates results:

<!-- scroll:skip -->
```march
actor Collector do
  state { items : List(String), done : Int, total : Int }
  init { items: Nil, done: 0, total: 0 }

  on Start(n : Int) do
    { state with total: n }
  end

  on Item(s : String) do
    { state with items: Cons(s, state.items), done: state.done + 1 }
  end

  on Results() do
    println(int_to_string(state.done) ++ " items collected")
    state
  end
end
```

---

## Complete example: parallel computation with timeout

```march
mod Parallel do
  needs IO.Spawn
  needs IO.Console

  fn sum_to(n : Int) : Int do
    List.fold_left(List.range(1, n + 1), 0, fn (acc, x) -> acc + x)
  end

  fn main(_cap_console : Cap(IO.Console), _cap_spawn : Cap(IO.Spawn)) do
    let inputs = [10, 20, 30, 40, 50]
    let tasks = List.map(inputs, fn n ->
      Task.async(fn () -> sum_to(n))
    )
    let results = Task.await_many_ms(tasks, 5000)
    List.each(results, fn r ->
      match r do
        Ok(v)  -> println("sum: " ++ int_to_string(v))
        Err(e) -> println("error: " ++ e)
      end
    )
  end
end
```
