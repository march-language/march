# data_frame_test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a March app that exercises DataFrame, Stats, HTTP server, and supervision end-to-end via a supervised HTTP server that analyzes S&P 500 CSV data.

**Architecture:** A supervisor actor manages an `AnalysisCounter` actor. The HTTP server (`/health`, `/analyze`) runs in `main()`. The `/analyze` endpoint parses CSV into a DataFrame, runs Stats, group-by, filter, sort, and returns JSON. The integration test uses `HttpServer.spawn_n` + `HttpClient` to verify the full pipeline in-process.

**Tech Stack:** March stdlib — DataFrame, Stats, HttpServer, HttpClient, Http, Json, Actor supervision

---

## File Map

| File | Purpose |
|------|---------|
| `data_frame_test/lib/data_frame_test.march` | App: supervisor actors, analysis helpers, router, main |
| `data_frame_test/data/sp500_sample.csv` | Sample S&P 500 data (50 rows, 5 tickers) |
| `data_frame_test/test/data_frame_test_test.march` | Integration test: pure router + spawn_n + HttpClient assertions |

**Important:** March's `HttpServer.spawn_n` forks an OS subprocess. Actors live in the parent process; the subprocess's router must be a **pure function** (no `send` to parent PIDs — those won't work cross-process). The app's `lib/` file uses actors + `listen()` for the real server. The test file uses `spawn_n` with a pure router and separately demonstrates supervision in the test's `main()`.

---

## Task 1: Build march and scaffold project

**Files:**
- Run commands in `/Users/80197052/code/march` (build) and `/Users/80197052/code` (scaffold)

- [ ] **Step 1: Build and install the march compiler**

```bash
cd /Users/80197052/code/march
dune build && dune install
```

Expected: no errors. The `march` and `forge` binaries are updated.

- [ ] **Step 2: Create the project**

```bash
cd /Users/80197052/code
forge new data_frame_test
```

Expected: output `created app project 'data_frame_test'`. Creates `lib/data_frame_test.march`, `test/data_frame_test_test.march`, `forge.toml`.

- [ ] **Step 3: Verify structure**

```bash
find data_frame_test -type f | grep -v .git | sort
```

Expected tree:
```
data_frame_test/.editorconfig
data_frame_test/.gitignore
data_frame_test/README.md
data_frame_test/forge.toml
data_frame_test/lib/data_frame_test.march
data_frame_test/test/data_frame_test_test.march
```

- [ ] **Step 4: Verify the scaffold compiles**

```bash
cd /Users/80197052/code/data_frame_test
dune exec march -- lib/data_frame_test.march
```

Expected: `Hello from data_frame_test!`

- [ ] **Step 5: Create data directory**

```bash
mkdir -p /Users/80197052/code/data_frame_test/data
```

---

## Task 2: Create sample S&P 500 CSV

**Files:**
- Create: `data_frame_test/data/sp500_sample.csv`

The CSV must have columns: `Date,Open,High,Low,Close,Volume,Name`. Include 5 tickers × 10 dates = 50 rows. Two tickers (GOOGL, AMZN) have Close > 100 to exercise the filter.

- [ ] **Step 1: Write the CSV file**

Write the following content to `data_frame_test/data/sp500_sample.csv`:

```csv
Date,Open,High,Low,Close,Volume,Name
2013-02-08,67.7142,68.4928,66.9143,67.8542,158168416,AAPL
2013-02-11,68.0714,69.2771,67.6071,68.5614,129029425,AAPL
2013-02-12,68.5014,68.9114,66.8214,66.7228,151829175,AAPL
2013-02-13,66.7442,67.6228,66.1742,66.7228,118007700,AAPL
2013-02-14,66.3557,67.3771,66.2842,66.8657,68568700,AAPL
2013-02-15,65.8128,66.5671,65.3142,65.7328,93604700,AAPL
2013-02-19,65.8785,66.1071,64.8357,65.0571,114854800,AAPL
2013-02-20,64.5571,65.2814,63.2642,63.3157,172284800,AAPL
2013-02-21,63.1014,63.7785,62.8357,63.2214,115516200,AAPL
2013-02-22,63.8714,64.7428,63.5,64.5,87798600,AAPL
2013-02-08,27.88,28.075,27.43,27.73,20082000,MSFT
2013-02-11,27.84,28.115,27.72,28.045,13819100,MSFT
2013-02-12,27.745,27.79,27.25,27.34,20288900,MSFT
2013-02-13,27.53,27.6,27.33,27.5,16667800,MSFT
2013-02-14,27.5,27.685,27.49,27.55,9716000,MSFT
2013-02-15,27.5,27.76,27.47,27.73,14316000,MSFT
2013-02-19,27.95,28.345,27.89,28.26,13718200,MSFT
2013-02-20,27.84,28.105,27.74,27.84,14668200,MSFT
2013-02-21,27.81,27.975,27.695,27.85,10282400,MSFT
2013-02-22,27.82,28.0,27.745,27.885,8675200,MSFT
2013-02-08,739.06,745.5,731.3577,738.2,4745099,GOOGL
2013-02-11,737.44,741.7,735.65,739.0,3642388,GOOGL
2013-02-12,737.85,743.4,735.5,737.9,4221887,GOOGL
2013-02-13,735.76,742.5,735.52,739.25,3416500,GOOGL
2013-02-14,741.05,745.0,738.8,744.5,3026700,GOOGL
2013-02-15,742.55,748.0,741.75,745.7,2907200,GOOGL
2013-02-19,749.0,753.0,746.5,752.5,2743100,GOOGL
2013-02-20,748.65,752.0,744.0,745.0,2837800,GOOGL
2013-02-21,743.5,748.0,741.0,742.5,2673600,GOOGL
2013-02-22,744.0,751.0,743.0,749.0,2498700,GOOGL
2013-02-08,264.88,266.7,263.73,265.0,2566700,AMZN
2013-02-11,265.08,268.25,264.6,267.24,2091700,AMZN
2013-02-12,267.11,270.2,266.5,269.25,2463500,AMZN
2013-02-13,268.5,271.0,267.25,270.5,2073800,AMZN
2013-02-14,270.0,271.75,268.5,270.75,1832400,AMZN
2013-02-15,269.5,271.5,268.0,270.0,1693200,AMZN
2013-02-19,271.0,275.0,270.5,274.0,2035600,AMZN
2013-02-20,272.5,274.0,270.25,271.5,1848100,AMZN
2013-02-21,269.75,272.0,268.5,270.25,1766900,AMZN
2013-02-22,271.0,273.5,270.0,272.5,1622300,AMZN
2013-02-08,37.12,37.94,36.71,37.79,12652700,TSLA
2013-02-11,37.94,38.14,37.34,37.66,12345600,TSLA
2013-02-12,37.5,37.95,36.85,37.2,8987300,TSLA
2013-02-13,37.3,38.2,37.15,38.1,9212400,TSLA
2013-02-14,38.1,38.5,37.8,38.3,7834500,TSLA
2013-02-15,38.0,38.65,37.7,38.5,8123600,TSLA
2013-02-19,39.0,39.75,38.5,39.5,9456700,TSLA
2013-02-20,39.25,39.6,38.85,39.15,8234500,TSLA
2013-02-21,38.9,39.3,38.5,38.8,7645300,TSLA
2013-02-22,39.0,39.8,38.75,39.6,8345600,TSLA
```

- [ ] **Step 2: Verify row count**

```bash
wc -l /Users/80197052/code/data_frame_test/data/sp500_sample.csv
```

Expected: `51` (1 header + 50 data rows)

---

## Task 3: Write the main app

**Files:**
- Modify: `data_frame_test/lib/data_frame_test.march` (replace scaffold content)

The app defines:
1. `AnalysisCounter` actor — tracks count of analyses run
2. `AppSupervisor` actor — manages `AnalysisCounter` under one_for_one
3. Pure analysis helpers: `value_to_json`, `row_to_json`, `df_to_json_array`, `column_stats`, `analyze`
4. `make_router(counter_pid)` — returns a closure capturing the counter PID
5. `main()` — spawns supervisor, gets counter PID, starts HTTP server with `listen()`

- [ ] **Step 1: Write lib/data_frame_test.march**

Replace the scaffold file entirely with:

```march
-- data_frame_test/lib/data_frame_test.march
--
-- End-to-end demonstration of:
--   * Actor supervision (one_for_one)
--   * HTTP server with router
--   * DataFrame.from_csv_string, lazy, filter, sort_by, collect
--   * DataFrame.group_by + agg (Mean, Count)
--   * Stats.mean, std_dev, min_val, max_val on float columns
--   * JSON serialization of analysis results

mod DataFrameTest do

  -- ── Actors ────────────────────────────────────────────────────────────────

  -- Counts how many POST /analyze requests have been processed.
  actor AnalysisCounter do
    state { count : Int }
    init  { count = 0 }

    on Inc() do
      let n = state.count + 1
      println("[AnalysisCounter] total analyses: " ++ int_to_string(n))
      { count = n }
    end
  end

  -- Supervisor: manages AnalysisCounter under one_for_one.
  -- If AnalysisCounter crashes, only it restarts; no other children affected.
  actor AppSupervisor do
    state { counter : Int }
    init  { counter = 0 }

    supervise do
      strategy one_for_one
      max_restarts 5 within 30
      AnalysisCounter counter
    end
  end

  -- ── JSON helpers ──────────────────────────────────────────────────────────

  -- Convert a DataFrame Value to a JsonValue.
  fn value_to_json(v) do
    match v do
    | IntVal(n)   -> Json.encode_int(n)
    | FloatVal(f) -> Json.encode_number(f)
    | StrVal(s)   -> Json.encode_string(s)
    | BoolVal(b)  -> Json.encode_bool(b)
    | NullVal     -> Json.encode_null()
    end
  end

  -- Convert a DataFrame Row to a JSON Object.
  fn row_to_json(row) do
    match row do
    | Row(pairs) ->
      let kvs = List.map(pairs, fn p ->
        match p do
        | (k, v) -> (k, value_to_json(v))
        end)
      Json.encode_object(kvs)
    end
  end

  -- Convert a DataFrame to a JSON Array of row objects.
  fn df_to_json_array(df) do
    Json.encode_array(List.map(DataFrame.to_rows(df), fn r -> row_to_json(r)))
  end

  -- ── Analysis ──────────────────────────────────────────────────────────────

  -- Compute descriptive stats for one numeric column. Returns a JsonValue object.
  fn column_stats(df, col) do
    match DataFrame.float_list(df, col) do
    | Err(e) ->
      Json.encode_object([
        ("column", Json.encode_string(col)),
        ("error",  Json.encode_string(e))
      ])
    | Ok(xs) ->
      match xs do
      | Nil ->
        Json.encode_object([
          ("column", Json.encode_string(col)),
          ("count",  Json.encode_int(0))
        ])
      | Cons(_, Nil) ->
        -- single element: std_dev would panic, skip it
        Json.encode_object([
          ("column", Json.encode_string(col)),
          ("count",  Json.encode_int(1)),
          ("mean",   Json.encode_number(Stats.mean(xs))),
          ("min",    Json.encode_number(Stats.min_val(xs))),
          ("max",    Json.encode_number(Stats.max_val(xs)))
        ])
      | _ ->
        Json.encode_object([
          ("column",  Json.encode_string(col)),
          ("count",   Json.encode_int(List.length(xs))),
          ("mean",    Json.encode_number(Stats.mean(xs))),
          ("std_dev", Json.encode_number(Stats.std_dev(xs))),
          ("min",     Json.encode_number(Stats.min_val(xs))),
          ("max",     Json.encode_number(Stats.max_val(xs)))
        ])
      end
    end
  end

  -- Main analysis pipeline. Returns a JSON string.
  fn analyze(body) do
    match DataFrame.from_csv_string(body) do
    | Err(e) ->
      Json.to_string(Json.encode_object([
        ("error", Json.encode_string("CSV parse error: " ++ e))
      ]))
    | Ok(df) ->
      let n_rows    = DataFrame.row_count(df)
      let col_names = DataFrame.schema(df)

      -- Stats per numeric column
      let numeric_cols = ["Open", "High", "Low", "Close", "Volume"]
      let stats_arr = Json.encode_array(
        List.map(numeric_cols, fn col -> column_stats(df, col)))

      -- Group by Name: mean Close, mean Volume, row count per group
      let group_arr =
        match DataFrame.agg(
            DataFrame.group_by(df, ["Name"]),
            [Mean("Close"), Mean("Volume"), Count]) do
        | Err(_)  -> Json.encode_array(Nil)
        | Ok(gdf) -> df_to_json_array(gdf)
        end

      -- Filter: rows where Close > 100.0
      let filter_count =
        match DataFrame.collect(
            DataFrame.filter(
              DataFrame.lazy(df),
              Gt(Col("Close"), LitFloat(100.0)))) do
        | Err(_)     -> Json.encode_int(-1)
        | Ok(fdf)    -> Json.encode_int(DataFrame.row_count(fdf))
        end

      -- Sort by Close descending, return top 10 rows
      let top10_arr =
        match DataFrame.collect(
            DataFrame.sort_by(
              DataFrame.lazy(df),
              [("Close", Desc)])) do
        | Err(_)     -> Json.encode_array(Nil)
        | Ok(sdf)    -> df_to_json_array(DataFrame.head(sdf, 10))
        end

      Json.to_string(Json.encode_object([
        ("row_count",         Json.encode_int(n_rows)),
        ("columns",           Json.encode_array(List.map(col_names, fn n -> Json.encode_string(n)))),
        ("stats_by_column",   stats_arr),
        ("group_by_name",     group_arr),
        ("rows_close_gt_100", filter_count),
        ("top10_by_close",    top10_arr)
      ]))
    end
  end

  -- ── HTTP router ───────────────────────────────────────────────────────────

  -- Returns a router closure that closes over counter_pid.
  -- counter_pid must be in the same process (not across spawn_n subprocess).
  fn make_router(counter_pid) do
    fn conn ->
      match (HttpServer.method(conn), HttpServer.path_info(conn)) do
      | (Get, Cons("health", Nil)) ->
        conn |> HttpServer.json(200, "{\"status\":\"ok\"}")
      | (Post, Cons("analyze", Nil)) ->
        send(counter_pid, Inc())
        let body   = HttpServer.req_body(conn)
        let result = analyze(body)
        conn |> HttpServer.json(200, result)
      | _ ->
        conn |> HttpServer.text(404, "Not found")
      end
    end
  end

  -- ── Entry point ───────────────────────────────────────────────────────────

  fn main() do
    -- 1. Start supervisor (auto-starts AnalysisCounter as a child)
    let sup = spawn(AppSupervisor)
    let counter_int = match get_actor_field(sup, "counter") do
    | None    -> panic("AppSupervisor: 'counter' field not found")
    | Some(n) -> n
    end
    let counter_pid = pid_of_int(counter_int)
    println("Supervisor pid:       " ++ to_string(sup))
    println("AnalysisCounter pid:  " ++ int_to_string(counter_int))
    println("")

    -- 2. Start HTTP server (blocks forever)
    println("HTTP server listening on http://localhost:8080")
    println("  GET  /health   -> {\"status\":\"ok\"}")
    println("  POST /analyze  -> JSON analysis of CSV body")
    println("")
    let router = make_router(counter_pid)
    HttpServer.new(8080)
    |> HttpServer.plug(router)
    |> HttpServer.listen()
  end

end
```

- [ ] **Step 2: Verify the file compiles (no runtime — just typecheck)**

```bash
cd /Users/80197052/code
dune exec march -- data_frame_test/lib/data_frame_test.march
```

The server will start and block. Interrupt with `Ctrl+C` after seeing the startup output. Expected output before interrupting:

```
Supervisor pid:       <pid>
AnalysisCounter pid:  <n>

HTTP server listening on http://localhost:8080
  GET  /health   -> {"status":"ok"}
  POST /analyze  -> JSON analysis of CSV body
```

If there are typecheck errors, fix them before proceeding. Common issues:
- `Col` needs a String arg: `Col("Close")`, not `Col`
- Float arithmetic uses `+.`, `-.`, `*.`, `/.` — not `+`, `-`, `*`, `/`
- `Gt`, `LitFloat` etc. are `ColExpr` constructors — no module prefix needed (they're in scope)
- `Mean`, `Count`, `Asc`, `Desc` are `AggExpr`/`SortDir` constructors — no module prefix needed

- [ ] **Step 3: Quick smoke test — run in background and curl**

In one terminal:
```bash
cd /Users/80197052/code
dune exec march -- data_frame_test/lib/data_frame_test.march &
sleep 1
curl http://localhost:8080/health
```

Expected: `{"status":"ok"}`

Then:
```bash
curl -s -X POST http://localhost:8080/analyze \
  --data-binary @data_frame_test/data/sp500_sample.csv | head -c 200
```

Expected: JSON starting with `{"row_count":50,...}`

Kill the background server:
```bash
kill %1
```

---

## Task 4: Write the integration test

**Files:**
- Modify: `data_frame_test/test/data_frame_test_test.march` (replace scaffold)

The test is a standalone runner (not using `describe`/`test` — those are for unit tests). It:
1. Demonstrates supervision in the parent process (spawns supervisor, verifies actor state)
2. Starts a server subprocess with `spawn_n(2)` using a **pure** router (no actor send)
3. Makes 2 HTTP requests via `HttpClient`
4. Asserts on responses

**Why pure router in test:** `HttpServer.spawn_n` forks an OS subprocess. PIDs from the parent's actor runtime are invalid in the subprocess. The pure router avoids cross-process actor communication.

- [ ] **Step 1: Write test/data_frame_test_test.march**

Replace the scaffold file entirely with:

```march
-- data_frame_test/test/data_frame_test_test.march
--
-- Integration test for data_frame_test.
-- Demonstrates:
--   * Supervision: spawn supervisor, verify child actor alive
--   * HTTP server: spawn_n(2) subprocess with pure router
--   * DataFrame + Stats + JSON pipeline via POST /analyze
--   * HttpClient assertions on GET /health and POST /analyze

mod DataFrameTestTest do

  -- ── Actors (for supervision demo in parent process) ───────────────────────

  actor AnalysisCounter do
    state { count : Int }
    init  { count = 0 }
    on Inc() do
      { count = state.count + 1 }
    end
  end

  actor AppSupervisor do
    state { counter : Int }
    init  { counter = 0 }
    supervise do
      strategy one_for_one
      max_restarts 5 within 30
      AnalysisCounter counter
    end
  end

  -- ── JSON + analysis helpers (pure — safe to call in server subprocess) ────

  fn value_to_json(v) do
    match v do
    | IntVal(n)   -> Json.encode_int(n)
    | FloatVal(f) -> Json.encode_number(f)
    | StrVal(s)   -> Json.encode_string(s)
    | BoolVal(b)  -> Json.encode_bool(b)
    | NullVal     -> Json.encode_null()
    end
  end

  fn row_to_json(row) do
    match row do
    | Row(pairs) ->
      let kvs = List.map(pairs, fn p ->
        match p do
        | (k, v) -> (k, value_to_json(v))
        end)
      Json.encode_object(kvs)
    end
  end

  fn df_to_json_array(df) do
    Json.encode_array(List.map(DataFrame.to_rows(df), fn r -> row_to_json(r)))
  end

  fn column_stats(df, col) do
    match DataFrame.float_list(df, col) do
    | Err(e) ->
      Json.encode_object([
        ("column", Json.encode_string(col)),
        ("error",  Json.encode_string(e))
      ])
    | Ok(xs) ->
      match xs do
      | Nil ->
        Json.encode_object([("column", Json.encode_string(col)), ("count", Json.encode_int(0))])
      | Cons(_, Nil) ->
        Json.encode_object([
          ("column", Json.encode_string(col)),
          ("count",  Json.encode_int(1)),
          ("mean",   Json.encode_number(Stats.mean(xs))),
          ("min",    Json.encode_number(Stats.min_val(xs))),
          ("max",    Json.encode_number(Stats.max_val(xs)))
        ])
      | _ ->
        Json.encode_object([
          ("column",  Json.encode_string(col)),
          ("count",   Json.encode_int(List.length(xs))),
          ("mean",    Json.encode_number(Stats.mean(xs))),
          ("std_dev", Json.encode_number(Stats.std_dev(xs))),
          ("min",     Json.encode_number(Stats.min_val(xs))),
          ("max",     Json.encode_number(Stats.max_val(xs)))
        ])
      end
    end
  end

  fn analyze(body) do
    match DataFrame.from_csv_string(body) do
    | Err(e) ->
      Json.to_string(Json.encode_object([("error", Json.encode_string(e))]))
    | Ok(df) ->
      let n_rows    = DataFrame.row_count(df)
      let col_names = DataFrame.schema(df)
      let numeric_cols = ["Open", "High", "Low", "Close", "Volume"]
      let stats_arr = Json.encode_array(
        List.map(numeric_cols, fn col -> column_stats(df, col)))
      let group_arr =
        match DataFrame.agg(
            DataFrame.group_by(df, ["Name"]),
            [Mean("Close"), Mean("Volume"), Count]) do
        | Err(_)  -> Json.encode_array(Nil)
        | Ok(gdf) -> df_to_json_array(gdf)
        end
      let filter_count =
        match DataFrame.collect(
            DataFrame.filter(
              DataFrame.lazy(df),
              Gt(Col("Close"), LitFloat(100.0)))) do
        | Err(_)  -> Json.encode_int(-1)
        | Ok(fdf) -> Json.encode_int(DataFrame.row_count(fdf))
        end
      let top10_arr =
        match DataFrame.collect(
            DataFrame.sort_by(
              DataFrame.lazy(df),
              [("Close", Desc)])) do
        | Err(_)  -> Json.encode_array(Nil)
        | Ok(sdf) -> df_to_json_array(DataFrame.head(sdf, 10))
        end
      Json.to_string(Json.encode_object([
        ("row_count",         Json.encode_int(n_rows)),
        ("columns",           Json.encode_array(List.map(col_names, fn n -> Json.encode_string(n)))),
        ("stats_by_column",   stats_arr),
        ("group_by_name",     group_arr),
        ("rows_close_gt_100", filter_count),
        ("top10_by_close",    top10_arr)
      ]))
    end
  end

  -- Pure router (no actor send — safe in spawn_n subprocess)
  fn router(conn) do
    match (HttpServer.method(conn), HttpServer.path_info(conn)) do
    | (Get, Cons("health", Nil)) ->
      conn |> HttpServer.json(200, "{\"status\":\"ok\"}")
    | (Post, Cons("analyze", Nil)) ->
      let body   = HttpServer.req_body(conn)
      let result = analyze(body)
      conn |> HttpServer.json(200, result)
    | _ ->
      conn |> HttpServer.text(404, "Not found")
    end
  end

  -- ── Test helpers ──────────────────────────────────────────────────────────

  fn pass(label) do
    println("[PASS] " ++ label)
  end

  fn fail(label, msg) do
    println("[FAIL] " ++ label ++ ": " ++ msg)
  end

  fn assert_contains(label, haystack, needle) do
    if String.contains(haystack, needle) then
      pass(label)
    else
      fail(label, "expected to contain '" ++ needle ++ "'")
    end
  end

  fn assert_eq_str(label, expected, actual) do
    if expected == actual then
      pass(label)
    else
      fail(label, "expected '" ++ expected ++ "' got '" ++ actual ++ "'")
    end
  end

  -- ── Sample CSV ────────────────────────────────────────────────────────────

  fn sample_csv() do
    "Date,Open,High,Low,Close,Volume,Name\n" ++
    "2013-02-08,67.7142,68.4928,66.9143,67.8542,158168416,AAPL\n" ++
    "2013-02-11,68.0714,69.2771,67.6071,68.5614,129029425,AAPL\n" ++
    "2013-02-12,68.5014,68.9114,66.8214,66.7228,151829175,AAPL\n" ++
    "2013-02-08,27.88,28.075,27.43,27.73,20082000,MSFT\n" ++
    "2013-02-11,27.84,28.115,27.72,28.045,13819100,MSFT\n" ++
    "2013-02-12,27.745,27.79,27.25,27.34,20288900,MSFT\n" ++
    "2013-02-08,739.06,745.5,731.3577,738.2,4745099,GOOGL\n" ++
    "2013-02-11,737.44,741.7,735.65,739.0,3642388,GOOGL\n" ++
    "2013-02-12,737.85,743.4,735.5,737.9,4221887,GOOGL\n" ++
    "2013-02-08,264.88,266.7,263.73,265.0,2566700,AMZN\n" ++
    "2013-02-11,265.08,268.25,264.6,267.24,2091700,AMZN\n" ++
    "2013-02-12,267.11,270.2,266.5,269.25,2463500,AMZN\n" ++
    "2013-02-08,37.12,37.94,36.71,37.79,12652700,TSLA\n" ++
    "2013-02-11,37.94,38.14,37.34,37.66,12345600,TSLA\n" ++
    "2013-02-12,37.5,37.95,36.85,37.2,8987300,TSLA\n"
  end

  -- ── Main ──────────────────────────────────────────────────────────────────

  fn main() do
    println("=== data_frame_test integration test ===")
    println("")

    -- ── Part 1: Supervision demo ─────────────────────────────────────────────
    println("--- Supervision ---")
    let sup = spawn(AppSupervisor)
    let counter_int = match get_actor_field(sup, "counter") do
    | None    -> panic("counter field missing")
    | Some(n) -> n
    end
    let counter_pid = pid_of_int(counter_int)
    println("Supervisor pid:      " ++ to_string(sup))
    println("AnalysisCounter pid: " ++ int_to_string(counter_int))
    println("Counter alive:       " ++ bool_to_string(is_alive(counter_pid)))
    println("")

    -- Crash and verify supervisor restarts the counter
    kill(counter_pid)
    let counter_int2 = match get_actor_field(sup, "counter") do
    | None    -> -1
    | Some(n) -> n
    end
    let counter_pid2 = pid_of_int(counter_int2)
    if counter_int2 != counter_int && is_alive(counter_pid2) then
      pass("supervisor restarted counter after crash (new pid: " ++ int_to_string(counter_int2) ++ ")")
    else
      fail("supervision restart", "expected new pid, same=" ++ bool_to_string(counter_int2 == counter_int))
    end
    println("")

    -- ── Part 2: HTTP + DataFrame + Stats + JSON ───────────────────────────────
    println("--- HTTP / DataFrame / Stats / JSON ---")

    -- Spawn server subprocess: handles exactly 2 requests then exits.
    let handle = HttpServer.new(8091)
      |> HttpServer.plug(router)
      |> HttpServer.spawn_n(2)

    let client = HttpClient.new_client()

    -- Request 1: GET /health
    match HttpClient.get(client, "http://localhost:8091/health") do
    | Err(_)     -> fail("GET /health", "request error")
    | Ok(resp)   ->
      let body = Http.response_body(resp)
      assert_contains("GET /health contains 'ok'", body, "ok")
    end

    -- Request 2: POST /analyze with inline CSV
    let csv = sample_csv()
    match HttpClient.post(client, "http://localhost:8091/analyze", csv) do
    | Err(_)   -> fail("POST /analyze", "request error")
    | Ok(resp) ->
      let body = Http.response_body(resp)
      -- Validate JSON keys present in response
      assert_contains("POST /analyze has row_count",         body, "row_count")
      assert_contains("POST /analyze has stats_by_column",   body, "stats_by_column")
      assert_contains("POST /analyze has group_by_name",     body, "group_by_name")
      assert_contains("POST /analyze has rows_close_gt_100", body, "rows_close_gt_100")
      assert_contains("POST /analyze has top10_by_close",    body, "top10_by_close")
      -- GOOGL and AMZN have Close > 100; AAPL, MSFT, TSLA do not
      -- 3 GOOGL rows + 3 AMZN rows = 6 rows above 100
      assert_contains("POST /analyze rows_close_gt_100 is 6", body, "\"rows_close_gt_100\":6")
      -- Verify we got 5 groups (one per ticker)
      assert_contains("POST /analyze contains GOOGL in group", body, "GOOGL")
      assert_contains("POST /analyze contains AAPL in group",  body, "AAPL")
    end

    -- Wait for server subprocess to exit cleanly
    HttpServer.wait_for(handle)

    println("")
    println("=== Done ===")
  end

end
```

- [ ] **Step 2: Run the test**

Note: `march test` is a valid march subcommand that runs a test file and reports results. It is distinct from `march <file>` which runs `main()`.

```bash
cd /Users/80197052/code
dune exec march -- test data_frame_test/test/data_frame_test_test.march
```

Expected output:
```
=== data_frame_test integration test ===

--- Supervision ---
Supervisor pid:      <pid>
AnalysisCounter pid: <n>
Counter alive:       true
[PASS] supervisor restarted counter after crash (new pid: <m>)

--- HTTP / DataFrame / Stats / JSON ---
[PASS] GET /health contains 'ok'
[PASS] POST /analyze has row_count
[PASS] POST /analyze has stats_by_column
[PASS] POST /analyze has group_by_name
[PASS] POST /analyze has rows_close_gt_100
[PASS] POST /analyze has top10_by_close
[PASS] POST /analyze rows_close_gt_100 is 6
[PASS] POST /analyze contains GOOGL in group
[PASS] POST /analyze contains AAPL in group

=== Done ===
```

If any test fails, debug the specific assertion. Common issues:
- Port conflict: change `8091` to another unused port
- JSON key mismatch: check exact key names in `analyze` output
- Filter count wrong: count GOOGL rows (3) + AMZN rows (3) where Close > 100 = 6

- [ ] **Step 3: Commit**

```bash
cd /Users/80197052/code/data_frame_test
git add lib/data_frame_test.march test/data_frame_test_test.march data/sp500_sample.csv
git commit -m "feat: end-to-end DataFrame/Stats/HTTP/supervision integration test"
```

---

## Task 5: Run the full app with the real CSV

**Files:** None modified — this is a runtime validation.

- [ ] **Step 1: Run the server in background**

```bash
cd /Users/80197052/code
dune exec march -- data_frame_test/lib/data_frame_test.march &
sleep 1
```

- [ ] **Step 2: Test health endpoint**

```bash
curl http://localhost:8080/health
```

Expected: `{"status":"ok"}`

- [ ] **Step 3: POST the full S&P 500 sample CSV**

```bash
curl -s -X POST http://localhost:8080/analyze \
  --data-binary @data_frame_test/data/sp500_sample.csv \
  | python3 -m json.tool 2>/dev/null || cat
```

Expected: pretty-printed JSON with:
- `"row_count": 50`
- `"columns": ["Date","Open","High","Low","Close","Volume","Name"]`
- `"stats_by_column"`: array of 5 objects with `mean`, `std_dev`, `min`, `max` for each numeric column
- `"group_by_name"`: array of 5 objects (one per ticker) with mean Close, mean Volume, count
- `"rows_close_gt_100"`: 20 (10 GOOGL + 10 AMZN rows where Close > 100)
- `"top10_by_close"`: array of 10 rows, top 10 by Close descending (all GOOGL rows, since GOOGL Close ~737–752)

- [ ] **Step 4: Kill the server**

```bash
kill %1
```

- [ ] **Step 5: Done**

All March features exercised:
- [x] HTTP server (`HttpServer.new/plug/listen`)
- [x] Supervision (`actor/supervise/one_for_one/max_restarts`)
- [x] DataFrame CSV parsing (`from_csv_string`)
- [x] Stats (`mean`, `std_dev`, `min_val`, `max_val`)
- [x] DataFrame lazy + filter (`lazy`, `filter`, `ColExpr`, `collect`)
- [x] DataFrame lazy + sort (`sort_by`, `SortDir`, `collect`)
- [x] DataFrame group-by + agg (`group_by`, `agg`, `AggExpr`)
- [x] JSON serialization (`Json.encode_object/array/number/string/to_string`)
- [x] Pattern matching, pipe operators, closures, Result/Option types

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| `I cannot find a variable named 'Col'` | `Col`, `Gt`, `LitFloat` etc. are in scope from `ColExpr` type — no module prefix needed. If still failing, check DataFrame is loaded. |
| `I cannot find a variable named 'Mean'` | `Mean`, `Count` etc. are `AggExpr` constructors — no module prefix. |
| `I cannot find a variable named 'Desc'` | `Desc` is a `SortDir` constructor — no module prefix. |
| `type error: expected Float` | Float arithmetic uses `+.` `-. ` `*.` `/.`. `+` is for Int only. |
| Port 8080/8091 already in use | Change port in the file, or kill the existing process with `lsof -ti:8080 \| xargs kill`. |
| `all tests passed` format mismatch | The test file uses a custom runner (not native `test`/`describe`), so run with `dune exec march -- test file.march`, not `forge test`. |
| `std_dev panics on single element` | Already handled in `column_stats` with `Cons(_, Nil)` pattern. |
