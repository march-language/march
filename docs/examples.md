---
layout: page
title: Examples
nav_order: 16
---

# Examples

Runnable programs in `examples/` that showcase March language features and common patterns. Each example is a self-contained `.march` file.

To run any example:

```sh
dune exec march -- examples/<name>.march
```

---

## Fundamentals

### hello.march

Functions, let bindings, recursion, and `|>` pipes with the List stdlib. A good first program.

```elixir
fn greet(name : String) : String do
  "Hello, " ++ name ++ "!"
end

fn factorial(0) : Int do 1 end
fn factorial(n) : Int do n * factorial(n - 1) end

fn double_evens(xs : List(Int)) : List(Int) do
  xs
  |> List.filter(fn x -> x % 2 == 0)
  |> List.map(fn x -> x * 2)
end
```

---

### pattern_matching.march

Comprehensive pattern matching: literals, custom ADTs, `Option`/`Result`, nested patterns, and multi-head function definitions.

```elixir
type Shape = Circle(Int) | Rect(Int, Int) | Triangle(Int, Int)

fn area(s : Shape) : Int do
  match s do
    Circle(r)      -> r * r * 3
    Rect(w, h)     -> w * h
    Triangle(b, h) -> (b * h) / 2
  end
end

-- Nested Option patterns
fn unwrap_nested(v : Option(Option(Int))) : Int do
  match v do
    Some(Some(n)) -> n
    Some(None)    -> -1
    None          -> -2
  end
end
```

---

### list_lib.march

A custom integer list type built with recursive ADTs. Implements `length`, `sum`, `product`, `max`, `reverse`, `append`, and `range` from scratch — a clean exercise in pattern matching and recursion.

```elixir
type IntList = INil | ICons(Int, IntList)

fn sum(INil)         : Int do 0 end
fn sum(ICons(x, xs)) : Int do x + sum(xs) end

fn reverse(xs : IntList) : IntList do rev_acc(xs, INil) end
fn rev_acc(INil, acc)         do acc end
fn rev_acc(ICons(x, xs), acc) do rev_acc(xs, ICons(x, acc)) end
```

---

### modules.march

Module organisation in one file: qualified access, two-level nesting, and private functions (`pfn`).

```elixir
-- Qualified access
let a = MathUtils.square(4)

-- Two-level nesting
let area = Geometry.Rect.area(6, 7)

-- pfn is private — only callable within Crypto
mod Crypto do
  fn encode(x : Int) : Int do add_checksum(scramble(x)) end
  pfn scramble(x : Int) : Int do x * 31 + 7 end
end
```

---

## Actors & Concurrency

### actors.march

Spawning actors, sending messages, handling death gracefully, and observing state transitions.

```elixir
actor Counter do
  state { value : Int }
  init  { value = 0 }

  on Increment(n : Int) do { state with value = state.value + n } end
  on Reset()            do { state with value = 0 } end
  on Probe(label : String) do
    println("[Counter] " ++ label ++ " = " ++ int_to_string(state.value))
    state
  end
end

let c = spawn(Counter)
send(c, Increment(5))
send(c, Probe("after increment"))
```

---

### tasks_basic.march

Lightweight tasks: spawn, await, chained results, and fan-out patterns using the Collatz sequence as a stand-in for CPU-bound work.

```elixir
-- Two independent tasks, combined on await
fn two_tasks() : Int do
  let t1 = task_spawn(fn x -> collatz(27, 0))
  let t2 = task_spawn(fn x -> collatz(871, 0))
  task_await_unwrap(t1) + task_await_unwrap(t2)
end
```

---

### tasks_fork_join.march

Recursive divide-and-conquer parallelism. Forks at a midpoint, spawns tasks for each half, and joins results. Demonstrates the canonical pattern for tree-structured parallel work.

```elixir
fn par_sum(lo : Int, hi : Int, threshold : Int) : Int do
  if hi - lo <= threshold do sum_range(lo, hi)
  else do
    let mid   = lo + (hi - lo) / 2
    let left  = task_spawn(fn x -> par_sum(lo, mid, threshold))
    let right = task_spawn(fn x -> par_sum(mid + 1, hi, threshold))
    task_await_unwrap(left) + task_await_unwrap(right)
  end
end
```

---

## Supervision

### supervision_strategies.march

All three restart strategies in one file: `one_for_one`, `one_for_all`, and `rest_for_one`. Each is demonstrated with a concrete crash scenario so you can observe which siblings are restarted.

```elixir
-- one_for_one: only the crashed child restarts
actor OneForOneSup do
  state { wa : Int, wb : Int }
  init  { wa = 0, wb = 0 }
  supervise do
    strategy one_for_one
    max_restarts 5 within 60
    Worker wa
    Worker wb
  end
end

-- rest_for_one: crash parser → restarts parser + writer, not reader
actor PipelineSup do
  state { reader : Int, parser : Int, writer : Int }
  init  { reader = 0, parser = 0, writer = 0 }
  supervise do
    strategy rest_for_one
    max_restarts 5 within 60
    Worker reader
    Worker parser
    Worker writer
  end
end
```

---

### supervision_monitor.march

Actor monitoring and `Down` messages. Shows how to watch for actor death, handle the `Down` delivery in a mailbox, and demonitor cleanly.

---

### supervision_linear_drop.march

Resource cleanup with user-defined `Drop` implementations. Resources registered via `own()` are released in reverse acquisition order when their actor crashes — the RAII pattern for actors.

```elixir
impl Drop(DbConnection) do
  fn drop(conn) do
    match conn do
    DbConnection(id) -> println("[Drop] Closing db connection " ++ to_string(id))
    end
  end
end

-- Register with an actor — dropped automatically on crash
own(pid, DbConnection(100))
own(pid, FileHandle("/var/log/worker.log"))
-- On crash: FileHandle dropped first, then DbConnection
```

---

## HTTP & Web

### http_hello.march

The smallest possible HTTP server: 18 lines, one route, plain text response.

```elixir
fn router(conn) do
  match (HttpServer.method(conn), HttpServer.path_info(conn)) do
  (:get, Nil) -> conn |> HttpServer.text(200, "Hello from compiled March!")
  _ -> conn |> HttpServer.text(404, "Not Found")
  end
end

fn main() do
  HttpServer.new(8080)
  |> HttpServer.plug(router)
  |> HttpServer.listen()
end
```

---

### http_streaming.march

Three streaming patterns: print chunks as they arrive, byte counting without buffering, and large chunked transfer encoding. Uses `HttpClient.stream_get` with an `on_chunk` callback.

```elixir
fn print_chunk(chunk) do
  print("[chunk " ++ int_to_string(string_length(chunk)) ++ " bytes]")
  print(chunk)
end

match HttpClient.stream_get(client, "http://httpbin.org/stream/5", print_chunk) do
Ok((status, _, _)) -> print("Status: " ++ int_to_string(status))
Err(_)             -> print("Error!")
end
```

---

### http_requests.march

Full HTTP client stack: `GET` and `POST` requests, request pipeline steps, default headers, and `Result`-based error handling.

---

### http_test.march

Integration test pattern: spawn a server subprocess, make real HTTP requests (`GET /`, `GET /ping`, `POST /echo`), assert on responses.

---

### counter_server.march

An actor-backed HTTP API. A `Counter` actor holds state; HTTP routes `GET /count`, `POST /increment`, `POST /decrement` message it directly. Shows the standard actor+HTTP integration pattern.

---

### ws_echo.march

WebSocket server on port 9877. Handles `TextFrame`, `BinaryFrame`, `Ping`/`Pong`, and `Close` in a recursive loop.

```elixir
fn handle_frame(conn, frame) do
  match frame do
  TextFrame(msg)   -> WsServer.send_text(conn, "echo: " ++ msg)
  BinaryFrame(b)   -> WsServer.send_binary(conn, b)
  Ping(data)       -> WsServer.send_pong(conn, data)
  Close            -> WsServer.close(conn)
  end
end
```

---

## Data & Statistics

### stats_basic.march

Descriptive and bivariate statistics using the `Stats` module on plain `List(Float)` values.

```elixir
-- Weekly temperatures
let temps = [18.5, 21.0, 19.8, 23.4, 22.1, 17.6, 20.3]

println("mean:    " ++ float_to_string(Stats.mean(temps)))
println("median:  " ++ float_to_string(Stats.median(temps)))
println("std_dev: " ++ float_to_string(Stats.std_dev(temps)))
println("p25:     " ++ float_to_string(Stats.percentile(temps, 25.0)))
println("p75:     " ++ float_to_string(Stats.percentile(temps, 75.0)))

-- Linear regression: hours studied → exam score
let (slope, intercept) = Stats.linear_regression(hours, scores)
let predicted = slope *. 9.0 +. intercept
```

Also shows `covariance`, `correlation`, `mode`, and the safe `Result`-returning variants (`mean_safe`, `std_dev_safe`).

---

### dataframe_basic.march

Tabular data pipelines with the `DataFrame` module. Uses an employee dataset throughout.

```elixir
-- Construct from typed columns
let df = DataFrame.from_columns([
  StrCol("name",   typed_array_from_list(["Alice", "Bob", "Charlie"])),
  StrCol("dept",   typed_array_from_list(["Eng", "Eng", "Sales"])),
  IntCol("salary", typed_array_from_list([95000, 88000, 72000])),
  FloatCol("rating", typed_array_from_list([4.5, 3.9, 4.2]))
])

-- LazyFrame: filter, sort, derived column, collect
let result =
  DataFrame.lazy(df)
  |> DataFrame.filter(Gt(Col("salary"), LitInt(80000)))
  |> DataFrame.sort_by([("salary", Desc)])
  |> DataFrame.with_column("bonus", fn row ->
      match DataFrame.row_get_int(row, "salary") do
      Some(s) -> IntVal(s / 10)
      None    -> IntVal(0)
      end)
  |> DataFrame.collect()

-- GroupBy: mean salary and headcount per department
let by_dept = DataFrame.group_by(df, ["dept"])
let agg_df  = DataFrame.agg(by_dept, [Mean("salary"), Count])

-- Stats integration
let summary          = DataFrame.summarize(df)       -- per-column stats as a DataFrame
let (train, holdout) = DataFrame.train_test_split(df, 0.8)
```

Also shows `inner_join`, `col_z_score` normalization, and bridging a column to `Stats` via `DataFrame.float_list`.

---

### csv_example.march

Four CSV parsing patterns from the stdlib: streaming rows, eager read, header-based field access, and TSV mode. Includes finding the oldest person in a dataset and filtering by column value.

---

### read_file.march

Three file reading patterns: full file into a string, lines into a list, and lazy line streaming with `File.with_lines` and `Seq.take`.

```elixir
-- Lazy: only reads lines as needed
File.with_lines("data.txt", fn lines ->
  let first10 = Seq.take(lines, 10) |> Seq.to_list()
  List.each(first10, println)
)
```

---

## Advanced

### capabilities.march

The capability security model. Shows `needs IO` declarations, `Cap(IO.Console)` and `Cap(IO.Network)` in function signatures, capability narrowing with `cap_narrow`, and higher-order capability passing.

```elixir
needs IO

-- Pure functions need no capability
fn format_greeting(name : String) : String do "Hello, " ++ name ++ "!" end

-- IO functions take an explicit capability token
fn greet(cap : Cap(IO.Console), name : String) : Unit do
  println(format_greeting(name))
end

-- Narrow the root cap to least-privilege sub-capabilities
fn main() : Unit do
  let cap         = root_cap
  let console_cap = cap_narrow(cap)
  let net_cap     = cap_narrow(cap)
  greet(console_cap, "Alice")
end
```

---

### templates.march

HTML templating with `~H` sigils and `IOList` composition. Covers layout wrapping, nested partials, ETag generation, and HTML-safe interpolation.

---

### debugger.march

Seven debugging workflows in one file: `dbg(expr)` logging, conditional breakpoints, `:find` search, `:watch` expressions, time-travel with `:tsave`/`:tload`, and actor message history replay.
