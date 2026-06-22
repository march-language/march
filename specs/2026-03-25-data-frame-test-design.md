# Design: data_frame_test — March End-to-End Integration App

**Date:** 2026-03-25
**Status:** Approved

## Overview

A self-contained March application that exercises DataFrame, Stats, HTTP server, and supervision end-to-end. The app is a supervised HTTP server that accepts a CSV file via POST request and returns a JSON analysis report.

## Architecture

```
main()
  ├── spawn(AppSupervisor)          -- supervision tree (one_for_one)
  │     └── AnalysisCounter actor   -- tracks analysis count
  └── HttpServer.listen(8080)       -- blocking HTTP server
        └── router
              ├── GET  /health      -- returns {"status":"ok"}
              └── POST /analyze     -- full DataFrame analysis pipeline
```

## Files

| File | Purpose |
|------|---------|
| `data_frame_test/bin/main.march` | All app code: supervisor actor, HTTP server, analysis logic |
| `data_frame_test/data/sp500_sample.csv` | Generated S&P 500-schema sample data (Date, Open, High, Low, Close, Volume, Name) |
| `data_frame_test/test/test_server.march` | Integration test using `HttpServer.spawn_n` + `HttpClient` |

## POST /analyze Pipeline

1. `HttpServer.req_body(conn)` — read raw CSV string
2. `DataFrame.from_csv_string(body)` — parse into typed DataFrame (auto-infers Float/String columns)
3. **Stats per numeric column** — `DataFrame.float_list(df, col)` → `Stats.mean/std_dev/min_val/max_val` for Close, Open, High, Low, Volume
4. **Group-by** — `DataFrame.group_by(df, ["Name"]) |> DataFrame.agg([Mean("Close"), Mean("Volume"), Count])`
5. **Filter** — `DataFrame.lazy(df) |> DataFrame.filter(Gt(Col("Close"), LitFloat(100.0))) |> DataFrame.collect()`
6. **Sort** — `DataFrame.lazy(df) |> DataFrame.sort_by([("Close", Desc)]) |> DataFrame.collect()`
7. Serialize results to JSON with `Json.encode_object` + `Json.to_string`
8. `HttpServer.json(conn, 200, json_str)` — respond

## Supervision

`AppSupervisor` actor manages `AnalysisCounter` actor under `one_for_one` strategy with `max_restarts 5 within 30`. The counter actor's state tracks how many analyses have run. Both the supervisor and the HTTP server start from `main()`.

## Test

Uses `HttpServer.spawn_n(server, 2)` to fork the server for exactly 2 requests, then:
1. `HttpClient.get(.../health)` — validates `{"status":"ok"}` in response body
2. `HttpClient.post(.../analyze, csv_content)` — validates JSON keys present in response

## Sample Data

A generated S&P 500-schema CSV (~50 rows, 5 tickers: AAPL, MSFT, GOOGL, AMZN, TSLA) with realistic prices and volumes. Schema: `Date,Open,High,Low,Close,Volume,Name`.

## Actor PID Wiring

The router closure captures the `AnalysisCounter` PID via closure. In `main()`:
1. `spawn(AppSupervisor)` → `sup`
2. `get_actor_field(sup, "counter")` → `Some(counter_int)` → `pid_of_int(counter_int)` → `counter_pid`
3. Define `let router = fn conn -> handle(conn, counter_pid)` — the router is a closure that closes over `counter_pid`
4. Inside `handle`, `send(counter_pid, Increment())` increments the counter on each analysis

## Key March APIs

- `DataFrame.from_csv_string(s)` → `Result(DataFrame, String)`
- `DataFrame.float_list(df, name)` → `Result(List(Float), String)`
- `DataFrame.lazy(df)` → `LazyFrame`
- `DataFrame.filter(lf, ColExpr)`, `DataFrame.sort_by(lf, keys)`, `DataFrame.collect(lf)`
- `DataFrame.group_by(df, cols)` → `GroupedFrame`; pipe to `DataFrame.agg(gf, exprs)` via `|>` — NOT a nested call
- `ColExpr` variants: `Col(String)`, `LitFloat(Float)`, `LitInt(Int)`, `Gt(ColExpr, ColExpr)`, `Gte`, `Lt`, `And`
- `AggExpr` variants: `Mean(String)`, `Sum(String)`, `Count`, `Std(String)`, `Min(String)`, `Max(String)`
- `SortDir`: `Asc | Desc`
- `Stats.mean/std_dev/min_val/max_val` on `List(Float)`
- `Json.encode_object/encode_string/encode_number/encode_array/to_string`
- `HttpServer.new/plug/listen/spawn_n/wait_for/req_body/json`
- `HttpClient.new_client/get/post`; `Http.response_body`
- Note: `HttpServer.spawn_n(server, n)` handles exactly `n` requests then exits — match test request count precisely
