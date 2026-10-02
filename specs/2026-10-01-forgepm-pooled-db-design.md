# forgepm: a real DB pool from compiled HTTP handlers (sub-project A)

**Status:** Part 1 landed 2026-10-01; Part 2 in forgepm.
**Driver:** deployed forgepm opens one Postgres connection per query (two
`Connection.connect` sites in the web binary: `lib/forgepm/repo.march:35`,
`lib/forgepm/packages/packages.march:316`), plus one more per request for the
metrics upsert. The comment justifying it ("the depot actor Pool hangs on the
HTTP worker pthreads") dates from July 2026 and has not been re-tested since the
foreign-thread actor bridge and the Perceus erased-niche fix landed on main.
**Siblings (own specs later):** B = HTTP handlers as green threads
(`specs/2026-07-09-http-handlers-as-green-threads.md`); C = root-cause the
reverted Vault-slot pool's ~1.6 MB/request leak.

## What is known

- Compiled HTTP handlers run on raw pthreads (`connection_thread`,
  `runtime/march_http.c`, default mode) or inline on evloop pthreads
  (`MARCH_HTTP_EVLOOP=1`). Neither is a green thread. forgepm prod uses the
  default mode.
- `Actor.call` directly from a foreign thread still returns
  `"actor_call: not in scheduler context"` (`runtime/march_runtime.c`). depot's
  `Pool.checkout` (`depot/lib/wire/pool.march:239`) wraps it in
  `task_spawn … |> task_await_unwrap`, and `task_await` from a foreign thread
  waits on a condvar (the bridge). That is the path under test.
- `runtime/march_extras.c`'s Vault `set`/`get`/`drop` balance refcounts, so the
  old leak was not in Vault itself. Out of scope here (sub-project C).
- `test/native/foreign_actor_http.march` exercises this shape but is wired into
  no dune rule or driver: it has never run in CI. It replies an `Int`
  (an immediate), which hid the heap-payload corruption depot hit.
- `Forgepm.Application.start` already calls `Pool.start` and stores the ref in
  Vault `forgepm:pool`; nothing reads it.

## Acceptance criteria

Against the compiled forgepm (`forge build --release`) with the docker-compose
Postgres, under `wrk -t4 -c32 -d60s` on a page that bypasses `PageCache`:

1. `pg_stat_activity` count for the forgepm database stays ≤ `DB_POOL_MAX` + 1
   for the whole run.
2. Server RSS is flat after a 10 s warm-up.
3. Zero non-2xx responses and no handler hang.
4. CPU-µs/request is not worse than the connect-per-query binary, measured as
   an order-swapped A/B on the same box (loopback req/s is not a server metric;
   see `specs/benchmarks.md`).

A latency improvement is expected but not a gate.

## Approach chosen

Use depot's actor Pool as-is, behind a fallback to the current direct path.
Rejected: a C-level pool primitive (new builtins, duplicates depot, no evidence
the actor hop is the bottleneck) and rebuilding forgepm's Vault-slot pool (the
design that leaked; diagnosing it is C).

## Part 1: March native fixture (this repo)

### `test/native/pooled_actor_http.march` (server role only)

- `type Conn = { id : Int, buf : Bytes }`, `buf` 64 KiB, so a leaked conn per
  request is visible in RSS within a few hundred requests.
- `actor Pool`, state `{ idle : List(Conn), out : Int }`, four conns in `init`.
  `Checkout(reply_to)` pops and replies `Some(conn)` or `None`; `Checkin(conn)`
  pushes back. Binds the new state to a local before returning it, as depot does.
- `with_conn(pool, f)`: `task_spawn(fn _ -> Actor.call(pool, Checkout(0), 5000))`,
  `task_await_unwrap`, call `f`, `send(pool, Checkin(conn))`.
- Handler: `GET /` → `with_conn`, body `conn=<id>`; `GET /stats` → `out=<n>`
  via `actor_get_int`. Listen port from `MARCH_TEST_HTTP_PORT`.
- Replaces `foreign_actor_http.march`/`.expected`, which are deleted.

### Harness: `test/test_http_native.ml`

Factor `run_http_e2e`'s compile (`--opt 2`), free-port pick, spawn, readiness
wait, port-collision retry and liveness check into a shared helper; add
`run_pooled_e2e ~evloop`. Assertions, in order:

1. 200 sequential `GET /` all return 200 with body `conn=<1..4>`.
2. 32 client threads × 50 `GET /` concurrently: every response 200 with a
   valid body, none times out.
3. `GET /stats` → `out=0` after the burst.
4. Server RSS (`ps -o rss= -p <pid>`) sampled after step 1 and after step 2:
   growth < 8 MiB (a per-request leak would be ≈ 100 MiB).
5. Server process alive at the end.

Run twice: default thread pool and `MARCH_HTTP_EVLOOP=1`.

If the thread-pool run hangs or corrupts, that is a runtime bug inside A's
scope; debug it (systematic-debugging), do not route around it.

## Part 2: forgepm (`~/code/forgepm`)

- `Forgepm.Repo.with_conn(f)`: `Vault.get(Vault.open("forgepm:pool"), "db")`.
  `Some(pool)` → `Pool.with_conn(pool, f)`; `Ok(r)` → `r`; `Err(reason)` →
  log a warning once per reason and fall back to `Connection.connect`.
  `None` (a forge task that never ran `Application.start`) → direct path,
  silently; that is today's behaviour for tasks.
- `Forgepm.Packages.pkg_exec` delegates to `Repo.with_conn`; delete `pconn_cfg`.
- `Repo.transaction` keeps `BEGIN`/`COMMIT`/`ROLLBACK` over the pooled conn.
  Check depot's `Checkin` for whether it pings or trusts the returned conn; if
  it trusts, `with_conn` closes instead of checking in after a protocol error,
  so a broken socket is never reused.
- `migrate` and `seed` tasks keep their direct connections.
- Rewrite the stale comments in `repo.march` and `packages.march` to state why
  the pool is now safe and point at the March fixture.
- No config change: `DB_POOL_MIN`/`DB_POOL_MAX` are already wired.

### Acceptance script: forgepm `scripts/pool-acceptance.sh`

Runs the four criteria above: starts the binary, samples `pg_stat_activity`
and RSS every 5 s during `wrk`, prints wrk's non-2xx count, and computes
CPU-µs/request for an A/B pair of binaries given on the command line
(order-swapped: A, B, B, A). Network-facing steps may need to run outside the
agent sandbox.

## Records

- `specs/todos/2026-10-01-forgepm-pooled-db.md` filed with this spec; moved to
  `specs/progress/` in the commit that lands Part 1 (Part 2 lives in forgepm).
- CHANGELOG bullet only if Part 1 uncovers and fixes a runtime bug.
- Decision graph: goal 2543; options/decision/actions linked as work lands.
