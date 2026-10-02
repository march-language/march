# forgepm Pooled DB (sub-project A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove, with a CI-wired native test, that a depot-shaped actor Pool works from compiled HTTP handlers under concurrency with flat RSS, then switch forgepm's two live DB sites to the depot Pool it already starts.

**Architecture:** Part 1 (this repo) adds `test/native/pooled_actor_http.march`, a server fixture mirroring `depot/lib/wire/pool.march` (actor Pool, `task_spawn(actor_call)` checkout from HTTP pthreads, heap-payload reply), driven by a new exercise in `test/test_http_native.ml` after factoring its compile/spawn/readiness machinery into a reusable `with_compiled_server`. Part 2 (`~/code/forgepm`) routes `Repo.with_conn` and `Packages.pkg_exec` through `Pool.with_conn` on the pool stored in Vault `forgepm:pool`, with fallback to connect-per-query, and adds an acceptance script.

**Tech Stack:** March (compiled, `--opt 2`), OCaml 5.3 Alcotest + `threads.posix` (already linked by `test/dune`), depot 0.3.3, bastion 0.3.1, bash + `wrk` + `psql` for acceptance.

**Spec:** `specs/2026-10-01-forgepm-pooled-db-design.md`.

## Global Constraints

- Worktree: `/Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd`, branch `claude/forgepm-http-bastion-perf-30174f`. Always pass `--root .` to dune. Preferred runner: `scripts/run-tests.sh`.
- `test_http_native` rides in `run_stdlib.exe` (`test/dune:37`, `test/run_stdlib.ml`). Run it with `./_build/default/test/run_stdlib.exe test 'http server' -e` after `dune build --root . bin/main.exe test/run_stdlib.exe`. Memory trap: there are two stdlib test exes; `test_stdlib_march.exe` does NOT run this suite.
- Compile fixtures at `--opt 2` (the shipped build). Both server modes must be exercised: `MARCH_HTTP_EVLOOP=0` (thread pool, forgepm's prod mode) and `MARCH_HTTP_EVLOOP=1`.
- Never pipe `march --compile`; redirect to a file. Never `git add -A`/`.`; stage by name. No `Co-Authored-By`.
- Scratch files go in `/private/tmp/claude-502/-Users-80197052-code-march--claude-worktrees-silly-blackwell-37c0cd/0e1b7f0c-ae69-409c-adbc-7baab209d08b/scratchpad` (call it `$SCRATCH` below).
- Lambda syntax: `fn _ -> …` is ONE-arg; `fn -> …` is zero-arg. `task_spawn` passes one arg, so its callback is `fn _ -> …`.
- `if … do … else … end`; one `end` per `if`. Match arms are `Pat -> body` with newline separators; multi-arm `match … do … end`.
- forgepm side: `forge build` must report 0 errors; `forge test` for pure tests. forgepm's `Repo.with_conn` return type is unchanged: the callback's `ConnResult` (`Result(QueryResult, String)`) or `Err(String)` on a connect/checkout failure.
- A runtime hang or corruption surfaced by Part 1 is in scope: stop, use superpowers:systematic-debugging, fix the runtime, keep the test.
- Specs discipline: `specs/todos/2026-10-01-forgepm-pooled-db.md` moves to `specs/progress/` in the commit that lands Task 4. CHANGELOG bullet only if a runtime fix ships.
- Decision graph: goal 2543, decision 2548. After each commit: `deciduous add action "<title>" -c 90 --commit HEAD` and `deciduous link 2548 <id> -r "<reason>"`.

---

## File map

| File | Responsibility |
|---|---|
| `test/native/pooled_actor_http.march` (create) | Server fixture: actor Pool + HTTP handler using `with_conn` per request |
| `test/native/foreign_actor_http.march`, `.expected` (delete) | Never-wired predecessor, superseded |
| `test/test_http_native.ml` (modify) | Factor `with_compiled_server`; add `run_pooled_e2e`; register two cases |
| `test/dune:96-102` (modify) | `run_stdlib` depends on the fixture file |
| `~/code/forgepm/lib/forgepm/repo.march` (modify) | `with_conn` via depot Pool with fallback |
| `~/code/forgepm/lib/forgepm/packages/packages.march:295-325` (modify) | `pkg_exec` delegates to `Repo.with_conn`; delete `pconn_cfg` |
| `~/code/forgepm/scripts/pool-acceptance.sh` (create) | Acceptance run: pg_stat_activity, RSS, non-2xx, CPU-µs/req A/B |
| `~/code/forgepm/docs/deploy.md` (modify) | Note the pool is live and how to size it |

---

### Task 1: The pooled-actor HTTP fixture

**Files:**
- Create: `test/native/pooled_actor_http.march`
- Delete: `test/native/foreign_actor_http.march`, `test/native/foreign_actor_http.expected`

**Interfaces:**
- Produces: a server binary reading `MARCH_TEST_HTTP_PORT`; `GET /` → `200` body `conn=<id>:<buflen>` with id in 1..4 and buflen `65536`; `GET /stats` → `200` body `out=<n>`; anything else → `404 Not Found`. Announces mode on stderr via the runtime banner (unchanged).

- [ ] **Step 1: Write the fixture**

```march
-- test/native/pooled_actor_http.march
--
-- A depot-shaped connection pool (depot/lib/wire/pool.march) driven from
-- compiled HTTP handlers. Handlers run on raw pthreads (thread pool) or
-- event-loop pthreads, never on a scheduler green thread; checkout goes
-- through task_spawn(actor_call) exactly as depot's Pool.checkout does, which
-- is the foreign-thread bridge path. The reply is a HEAP payload (a record
-- holding a 64 KiB Bytes) because an Int reply is an immediate whose decrc
-- is a no-op and hid the Perceus niche-reuse corruption depot hit in July.
-- Driven by test/test_http_native.ml (run_pooled_e2e); no .expected file.
mod PooledActorHttp do
  needs IO.Process
  needs IO.NetListen
  needs IO.Spawn

  type Conn = { id : Int, buf : Bytes }

  pfn mk_conn(i) do
    { id: i, buf: Bytes.from_string(String.repeat("x", 65536)) }
  end

  pfn mk_conns(i, n, acc) do
    if i > n do acc else mk_conns(i + 1, n, Cons(mk_conn(i), acc)) end
  end

  -- State field order matters: actor_get_int(pool, 0) reads `out`.
  actor Pool do
    state { out : Int, idle : List(Conn) }
    init { out: 0, idle: Nil }

    on PoolInit(n : Int) do
      { state with idle: mk_conns(1, n, Nil) }
    end

    -- actor_call target. reply_to is injected by the runtime as field[0].
    on Checkout(reply_to) do
      let result = match state.idle do
        Cons(c, rest) -> { conn: Some(c), new_state: { state with idle: rest, out: state.out + 1 } }
        Nil           -> { conn: None, new_state: state }
        end
      -- Bind before returning: a handler whose final expression is a field
      -- projection loses the state update compiled (depot's note).
      let new_state = result.new_state
      let _ = actor_reply(reply_to, result.conn)
      new_state
    end

    on Checkin(c : Conn) do
      { state with idle: Cons(c, state.idle), out: state.out - 1 }
    end
  end

  -- Mirrors depot Pool.checkout: actor_call on a fresh green thread, the
  -- caller (an HTTP pthread) only touches task_spawn/task_await.
  pfn checkout(pool) do
    let t = task_spawn(fn _ ->
      match actor_call(pool, Checkout(0), 5000) do
      Err(e) -> Err("pool actor: " ++ e)
      Ok(maybe) ->
        match maybe do
        None    -> Err("no connection available")
        Some(c) -> Ok(c)
        end
      end)
    task_await_unwrap(t)
  end

  pfn with_conn(pool, f) do
    match checkout(pool) do
    Err(e) -> Err(e)
    Ok(c)  ->
      let r = f(c)
      let _ = send(pool, Checkin(c))
      Ok(r)
    end
  end

  pfn router(pool, conn) do
    match (HttpServer.method(conn), HttpServer.path_info(conn)) do
    (:get, Nil) ->
      match with_conn(pool, fn c -> "conn=" ++ int_to_string(c.id) ++ ":" ++ int_to_string(Bytes.length(c.buf))) do
      Ok(body) -> conn |> HttpServer.text(200, body)
      Err(e)   -> conn |> HttpServer.text(503, e)
      end
    (:get, Cons("stats", Nil)) ->
      conn |> HttpServer.text(200, "out=" ++ int_to_string(actor_get_int(pool, 0)))
    _ -> conn |> HttpServer.text(404, "Not Found")
    end
  end

  pfn port_from_env() do
    match process_env("MARCH_TEST_HTTP_PORT") do
    Some(s) ->
      match string_to_int(s) do
      Some(n) -> n
      None -> 0
      end
    None -> 0
    end
  end

  fn main(_cap_netlisten : Cap(IO.NetListen), _cap_process : Cap(IO.Process), _cap_spawn : Cap(IO.Spawn)) do
    let port = port_from_env()
    if port == 0 do
      process_exit(2)
    else
      let pool = spawn(Pool)
      let _ = send(pool, PoolInit(4))
      HttpServer.new(port)
      |> HttpServer.plug(fn conn -> router(pool, conn))
      |> HttpServer.listen()
    end
  end
end
```

If the typechecker rejects a capability (`needs`) or a builtin name, read the error: `IO.Spawn` may be named differently on main (`grep -n "IO.Spawn" test/native/*.march stdlib/*.march`), and `actor_reply`/`actor_call`/`actor_get_int` are the builtins depot uses (`depot/lib/wire/pool.march:157,241,292`).

- [ ] **Step 2: Compile it and smoke-test by hand**

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && dune build --root . bin/main.exe 2>&1 | tail -3
```

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && ./_build/default/bin/main.exe --compile --opt 2 -o "$SCRATCH/pah" test/native/pooled_actor_http.march > "$SCRATCH/pah.compile.log" 2>&1; echo "exit=$?"; tail -5 "$SCRATCH/pah.compile.log"
```
Expected: `exit=0`.

```bash
cd "$SCRATCH" && (MARCH_TEST_HTTP_PORT=29941 MARCH_HTTP_EVLOOP=0 ./pah > pah.log 2>&1 &) ; sleep 1; curl -s http://127.0.0.1:29941/; echo; curl -s http://127.0.0.1:29941/stats; echo; for i in 1 2 3 4 5 6; do curl -s http://127.0.0.1:29941/ & done; wait; echo; curl -s http://127.0.0.1:29941/stats; echo; pkill -f "^./pah$" ; pgrep -f "^./pah$" || echo stopped; head -3 pah.log
```
Expected: `conn=4:65536` (or any id 1..4), `out=0`, six `conn=<1..4>:65536` bodies (ids may repeat across the burst since conns return to the pool between requests; none may be `503`), `out=0`, and the banner `HTTP thread pool started`. If the sandbox blocks loopback, note it and rely on Task 3's harness instead (it runs the same exchange from OCaml).

If `/` returns `503 no connection available` under the six-way burst, that is expected only if more than 4 are in flight at once; with 4 conns and 6 clients a `503` is possible. Change the burst to 4 (`for i in 1 2 3 4`) before concluding anything.

- [ ] **Step 3: Delete the superseded fixture**

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && git rm -q test/native/foreign_actor_http.march test/native/foreign_actor_http.expected && git status --short
```

- [ ] **Step 4: Commit**

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && git add test/native/pooled_actor_http.march && git commit -q -m "test(native): depot-shaped actor Pool HTTP fixture, replacing never-wired foreign_actor_http" && git log --oneline -1
```

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && id=$(deciduous add action "Task 1: pooled_actor_http fixture written and smoke-tested" -c 90 --commit HEAD | grep -o 'node [0-9]*' | awk '{print $2}') && deciduous link 2548 $id -r "Part 1 fixture"
```

---

### Task 2: Factor `with_compiled_server` out of `run_http_e2e`

Pure refactor: the two existing cases must pass unchanged before and after.

**Files:**
- Modify: `test/test_http_native.ml:138-581`

**Interfaces:**
- Produces:
  ```ocaml
  type child_status = [ `Alive | `Exited of int | `Signaled of int | `Stopped of int ]
  type server_ctx = {
    port            : int;
    bail            : 'a. string -> 'a;
    child_pid       : unit -> int option;
    child_status    : unit -> child_status;
    describe_status : child_status -> string;
    connect_or_bail : string -> Unix.file_descr;
    send            : Unix.file_descr -> string -> unit;
    request_bytes   : meth:string -> path:string -> body:string -> keep_alive:bool -> string;
    read_response   : Unix.file_descr -> string ref -> deadline:float -> int * string * string;
    check_response  : string -> exp_status:int -> exp_body:string -> int * string * string -> unit;
  }
  val with_compiled_server :
    variant:string -> slug:string -> evloop:bool -> server_src:string ->
    (server_ctx -> unit) -> unit
  ```
  `with_compiled_server` compiles `server_src` at `--opt 2`, starts it with `MARCH_TEST_HTTP_PORT` and `MARCH_HTTP_EVLOOP=0|1`, waits for readiness and the mode banner, runs the callback, then kills the child. It returns without calling the callback on a legitimate clang-absent skip (`compile_march_or_skip` → `None`).

- [ ] **Step 1: Record the baseline**

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && dune build --root . bin/main.exe test/run_stdlib.exe 2>&1 | tail -3 && ./_build/default/test/run_stdlib.exe test 'http server' -e > "$SCRATCH/http_e2e_before.log" 2>&1; echo "exit=$?"; grep -E "OK|FAIL|SKIP" "$SCRATCH/http_e2e_before.log" | head
```
Expected: `exit=0`, two `[OK]` lines. If a line says `[SKIP]`, clang is missing and nothing in this plan can be verified; stop and report.

- [ ] **Step 2: Introduce the types and move the lifecycle code**

In `test/test_http_native.ml`, directly above `let run_http_e2e` (line 138), add the two type definitions from Interfaces. Then rename the existing `let run_http_e2e ~variant ~slug ~evloop () =` to `let with_compiled_server ~variant ~slug ~evloop ~server_src (k : server_ctx -> unit) =`, and inside it:

1. Replace `output_string oc server_src;` (line 156) with the same line (it now refers to the labelled argument; the top-level `server_src` string stays and is passed explicitly by the caller).
2. Immediately before the comment `(* ── Phase A: ~45 requests, each on its own connection ───────────────── *)` (line 466), replace everything from that comment through the end of the `Fun.protect ~finally:cleanup (fun () -> … )` body (line 581, the `(describe_status st))))` line) with:

```ocaml
  k { port = !port;
      bail;
      child_pid = (fun () -> !child);
      child_status;
      describe_status;
      connect_or_bail;
      send;
      request_bytes;
      read_response;
      check_response })
```

The `bail` field is polymorphic; OCaml accepts the local `bail` (type `string -> 'a` from `Alcotest.failf`) for an `'a. string -> 'a` field only if `bail` is itself generalized. It is defined with `let bail (msg : string) = Alcotest.failf …`, which generalizes; if the compiler complains ("this field value has type string -> unit…"), wrap as `bail = (fun msg -> bail msg)` will NOT help; instead annotate the definition: `let bail : 'a. string -> 'a = fun msg -> Alcotest.failf … in`.

- [ ] **Step 3: Re-create `run_http_e2e` as the moved phases**

After `with_compiled_server`, add:

```ocaml
(* ── The original exercise: 65 requests, bodies, keep-alive, pipelining ── *)
let run_http_e2e ~variant ~slug ~evloop () =
  with_compiled_server ~variant ~slug ~evloop ~server_src (fun ctx ->
    let { bail; connect_or_bail; send; request_bytes; read_response;
          check_response; child_status; describe_status; _ } = ctx in
    let req_timeout = 30.0 in
    <PASTE the Phase A … Phase D code removed in Step 2, verbatim, here>
  )
```

The pasted code referenced `variant` (Phase C2's label) and `req_timeout`; both are in scope. It referenced `bail`, `connect_or_bail`, `send`, `request_bytes`, `read_response`, `check_response`, `child_status`, `describe_status`, all destructured above. Nothing else.

- [ ] **Step 4: Build and run the two existing cases**

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && dune build --root . test/run_stdlib.exe 2>&1 | head -30
```
Expected: no output (clean build). Fix any type error before continuing; the common one is an unused-variable warning-as-error for a destructured field, which you fix by dropping that field from the pattern.

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && ./_build/default/test/run_stdlib.exe test 'http server' -e > "$SCRATCH/http_e2e_after.log" 2>&1; echo "exit=$?"; grep -E "OK|FAIL|SKIP" "$SCRATCH/http_e2e_after.log" | head
```
Expected: `exit=0`, the same two `[OK]` lines as Step 1.

- [ ] **Step 5: Prove the refactor is not vacuous**

Temporarily change `~exp_body:"pong"` in Phase D to `~exp_body:"pongX"`, rebuild, rerun the same command. Expected: `exit=1` and a `FAIL` naming `final GET /ping`. Revert the change (`git checkout -- test/test_http_native.ml` would lose the refactor; instead edit `pongX` back to `pong`), rebuild, rerun: `exit=0`.

- [ ] **Step 6: Commit**

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && git add test/test_http_native.ml && git commit -q -m "test(http-native): factor server lifecycle into with_compiled_server; no behaviour change" && git log --oneline -1
```

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && id=$(deciduous add action "Task 2: with_compiled_server factored out; e2e cases green and proven non-vacuous" -c 90 --commit HEAD | grep -o 'node [0-9]*' | awk '{print $2}') && deciduous link 2548 $id -r "Part 1 harness refactor"
```

---

### Task 3: `run_pooled_e2e`: concurrency, leaked checkouts, RSS, liveness

**Files:**
- Modify: `test/test_http_native.ml` (append after `run_http_e2e`; extend `suites`)
- Modify: `test/dune:96-102` (`run_stdlib` deps)

**Interfaces:**
- Consumes: `with_compiled_server`, `server_ctx` from Task 2; the fixture from Task 1 (`GET /` → `conn=<1..4>:65536`, `GET /stats` → `out=<n>`).
- Produces: two Alcotest cases in `Test_http_native.suites`, one per server mode.

- [ ] **Step 1: Write the exercise**

Append to `test/test_http_native.ml`, before `let suites`:

```ocaml
(* ── Pooled actor exercise ──────────────────────────────────────────────── *)
(* A depot-shaped actor Pool driven from HTTP handler pthreads through
   task_spawn(actor_call): the path forgepm's Repo would take with depot's
   Pool. Four assertions a connect-per-query server cannot fake:
     1. sequential correctness (body names a pooled conn + intact 64 KiB buf)
     2. 32-way concurrent burst: every response 200, none hung
     3. /stats out=0 afterwards: every checkout was checked back in
     4. server RSS grew < 8 MiB across the burst (a per-request conn leak
        would be 1600 x 64 KiB ~ 100 MiB)
   plus the process is still alive. *)

let pooled_server_src () =
  let path =
    Filename.concat (march_project_root ()) "test/native/pooled_actor_http.march" in
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic; s

(* Resident set size of [pid] in KiB via ps(1); identical flag on macOS and
   Linux. -1 if ps cannot answer (the assertion then fails loudly). *)
let rss_kib pid =
  let cmd = Printf.sprintf "ps -o rss= -p %d" pid in
  let ic = Unix.open_process_in cmd in
  let line = try input_line ic with End_of_file -> "" in
  ignore (Unix.close_process_in ic);
  match int_of_string_opt (String.trim line) with Some n -> n | None -> -1

let conn_body_ok body =
  (* conn=<1..4>:65536 *)
  String.length body = String.length "conn=N:65536"
  && String.sub body 0 5 = "conn="
  && (let c = body.[5] in c >= '1' && c <= '4')
  && String.sub body 6 6 = ":65536"

let run_pooled_e2e ~variant ~slug ~evloop () =
  with_compiled_server ~variant ~slug ~evloop ~server_src:(pooled_server_src ())
    (fun ctx ->
    let { bail; connect_or_bail; send; request_bytes; read_response;
          child_status; describe_status; child_pid; _ } = ctx in
    let req_timeout = 30.0 in
    let get path =
      let fd = connect_or_bail ("GET " ^ path) in
      Fun.protect ~finally:(fun () -> try Unix.close fd with _ -> ()) (fun () ->
        let pending = ref "" in
        let deadline = Unix.gettimeofday () +. req_timeout in
        send fd (request_bytes ~meth:"GET" ~path ~body:"" ~keep_alive:false);
        let (status, body, _) = read_response fd pending ~deadline in
        (status, body))
    in
    let pid () = match child_pid () with Some p -> p | None -> bail "server pid unknown" in

    (* 1. sequential *)
    for i = 1 to 200 do
      let (st, body) = get "/" in
      if st <> 200 || not (conn_body_ok body) then
        bail (Printf.sprintf "sequential request %d/200: expected 200 conn=<1..4>:65536, got %d %S" i st body)
    done;
    let rss_before = rss_kib (pid ()) in

    (* 2. concurrent burst: 32 threads x 50 requests. Threads record their
       first failure instead of calling bail (Alcotest.fail from a non-main
       thread is not reliable). *)
    let failures = Mutex.create () in
    let first_failure = ref None in
    let note_failure msg =
      Mutex.lock failures;
      (if !first_failure = None then first_failure := Some msg);
      Mutex.unlock failures
    in
    let worker t () =
      try
        for i = 1 to 50 do
          let (st, body) = get "/" in
          if st <> 200 || not (conn_body_ok body) then
            note_failure (Printf.sprintf "thread %d request %d/50: got %d %S" t i st body)
        done
      with e -> note_failure (Printf.sprintf "thread %d raised %s" t (Printexc.to_string e))
    in
    let threads = List.init 32 (fun t -> Thread.create (worker t) ()) in
    List.iter Thread.join threads;
    (match !first_failure with
     | Some msg -> bail ("concurrent burst: " ^ msg)
     | None -> ());

    (* 3. no leaked checkouts. Checkin is an async send; allow it to land. *)
    let rec stats_zero tries =
      let (st, body) = get "/stats" in
      if st = 200 && body = "out=0" then ()
      else if tries = 0 then
        bail (Printf.sprintf "/stats after burst: expected 200 out=0, got %d %S (checkouts never checked back in)" st body)
      else (Unix.sleepf 0.1; stats_zero (tries - 1))
    in
    stats_zero 20;

    (* 4. RSS flat *)
    let rss_after = rss_kib (pid ()) in
    if rss_before < 0 || rss_after < 0 then
      bail (Printf.sprintf "could not read server RSS (before=%d after=%d KiB)" rss_before rss_after);
    let growth_kib = rss_after - rss_before in
    if growth_kib > 8 * 1024 then
      bail (Printf.sprintf "server RSS grew %d KiB across 1600 pooled requests (before %d, after %d): a per-request leak of the pooled conn or its reply" growth_kib rss_before rss_after);

    (* alive *)
    (match child_status () with
     | `Alive -> ()
     | st -> bail (Printf.sprintf "server process is NOT alive after the pooled exercise: it %s" (describe_status st))))
```

Note: `get` is called from worker threads and uses `connect_or_bail`, which can call `bail` → `Alcotest.failf` from a non-main thread; that raises inside the thread and is caught by the `with e ->` and reported through `note_failure`. That is the intended path.

- [ ] **Step 2: Register the two cases**

Replace the `let suites = …` block at the end of the file with:

```ocaml
let suites =
  [ ("http server (compiled, end-to-end)",
     [ Alcotest.test_case
         "thread-pool server: 65 requests, bodies, keep-alive, pipelining, \
          process alive (compiled --opt 2)" `Quick
         (run_http_e2e ~variant:"thread pool (default)" ~slug:"threadpool"
            ~evloop:false);
       Alcotest.test_case
         "event-loop server (MARCH_HTTP_EVLOOP=1): 65 requests, bodies, \
          keep-alive, pipelining, process alive (compiled --opt 2)" `Quick
         (run_http_e2e ~variant:"event loop (MARCH_HTTP_EVLOOP=1)"
            ~slug:"evloop" ~evloop:true);
       Alcotest.test_case
         "thread-pool server: depot-shaped actor Pool from handler pthreads, \
          32-way burst, no leaked checkouts, flat RSS (compiled --opt 2)" `Quick
         (run_pooled_e2e ~variant:"pooled actor, thread pool" ~slug:"pooledpool"
            ~evloop:false);
       Alcotest.test_case
         "event-loop server: depot-shaped actor Pool from evloop pthreads, \
          32-way burst, no leaked checkouts, flat RSS (compiled --opt 2)" `Quick
         (run_pooled_e2e ~variant:"pooled actor, event loop" ~slug:"pooledevloop"
            ~evloop:true);
     ]);
  ]
```

- [ ] **Step 3: Make dune re-run the suite when the fixture changes**

In `test/dune`, the `run_stdlib` stanza's deps line (line 102) becomes:

```
 (deps %{exe:../bin/main.exe} (source_tree ../runtime) (source_tree ../stdlib)
       (file native/pooled_actor_http.march))
```

- [ ] **Step 4: Build and run**

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && dune build --root . bin/main.exe test/run_stdlib.exe 2>&1 | head -30
```
Expected: clean.

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && ./_build/default/test/run_stdlib.exe test 'http server' -e > "$SCRATCH/pooled_e2e.log" 2>&1; echo "exit=$?"; grep -E "\[(OK|FAIL|SKIP)\]" "$SCRATCH/pooled_e2e.log"
```
Expected: `exit=0`, four `[OK]`.

If the thread-pool pooled case FAILS with a hang ("no response bytes within the 30s deadline"), a 503 body (`no connection available` or `pool actor: …`), a wrong body, RSS growth, or a dead server: this is the runtime bug the spec anticipates. Do NOT weaken the assertion. Capture `$SCRATCH/pooled_e2e.log` (it embeds the server's stderr), file the finding as a `deciduous add observation`, and switch to superpowers:systematic-debugging with the fixture as the repro (`$SCRATCH/pah` from Task 1 plus `curl` bursts). Likely suspects, in order: the foreign `task_await` condvar path (`runtime/march_runtime.c` around `task_wait_done`), `Checkin` sends from a foreign thread (`march_sched_wake` external stack), and RC of the `Conn` record crossing the mailbox. A fix goes in its own commit with its own `specs/progress/` entry and CHANGELOG bullet.

- [ ] **Step 5: Prove the new assertions bite**

Temporarily edit the fixture's `Checkin` handler to drop the conn (`{ state with out: state.out - 1 }`, not pushing to idle); rebuild nothing (the harness reads the source file at test time) and rerun. Expected: FAIL at either the burst (503s once the four conns are gone) or `/stats`. Revert with `git checkout -- test/native/pooled_actor_http.march`. Rerun: `exit=0`.

- [ ] **Step 6: Commit**

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && git add test/test_http_native.ml test/dune && git commit -q -m "test(http-native): pooled actor exercise: 32-way burst from handler pthreads, no leaked checkouts, flat RSS" && git log --oneline -1
```

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && id=$(deciduous add action "Task 3: run_pooled_e2e wired in both server modes" -c 90 --commit HEAD | grep -o 'node [0-9]*' | awk '{print $2}') && deciduous link 2548 $id -r "Part 1 exercise" && oid=$(deciduous add outcome "Native pooled-actor exercise GREEN in thread-pool and evloop modes (or: red, see observation)" -c 85 | grep -o 'node [0-9]*' | awk '{print $2}') && deciduous link $id $oid -r "result"
```
Edit the outcome title to match what happened.

---

### Task 4: Full suite, specs bookkeeping, PR for Part 1

**Files:**
- Move: `specs/todos/2026-10-01-forgepm-pooled-db.md` → `specs/progress/2026-10-01-forgepm-pooled-db.md`
- Modify: `specs/2026-10-01-forgepm-pooled-db-design.md` (Status line)

- [ ] **Step 1: Run the suites that touch this**

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && scripts/run-tests.sh stdlib codegen > "$SCRATCH/suite.log" 2>&1; echo "exit=$?"; grep -E "Test Successful|tests run|FAIL" "$SCRATCH/suite.log" | head
```
Expected: `exit=0`. Per memory, judge by `$?`, not tail output. `stdlib` here is the alcotest `run_stdlib.exe` group that carries `test_http_native`; `codegen` because the fixture dir is referenced by codegen's native rules' sibling list only if you added one (you did not, but it is cheap).

- [ ] **Step 2: Tree-sitter / doc-lint are untouched**

No parser/lexer or `docs/` change in this plan; nothing to run.

- [ ] **Step 3: Move the todo to progress and update the spec status**

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && git mv specs/todos/2026-10-01-forgepm-pooled-db.md specs/progress/2026-10-01-forgepm-pooled-db.md
```

Edit `specs/progress/2026-10-01-forgepm-pooled-db.md`: change the first line to `# forgepm: real DB pool from compiled HTTP handlers (sub-project A, March side)` and append:

```
Landed 2026-10-01 (March side): `test/native/pooled_actor_http.march` +
`run_pooled_e2e` in `test/test_http_native.ml`, both server modes, in
`run_stdlib.exe`. forgepm side tracked in the forgepm repo (Part 2 of the
plan `specs/plans/2026-10-01-forgepm-pooled-db.md`).
```

Edit `specs/2026-10-01-forgepm-pooled-db-design.md` line 3 to `**Status:** Part 1 landed 2026-10-01; Part 2 in forgepm.`

- [ ] **Step 4: Commit and open the PR**

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && git add specs/progress/2026-10-01-forgepm-pooled-db.md specs/2026-10-01-forgepm-pooled-db-design.md && git commit -q -m "specs: close sub-project A (March side); forgepm part tracked downstream" && git push -u origin claude/forgepm-http-bastion-perf-30174f 2>&1 | tail -2
```

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && gh pr create --title "test(http-native): depot-shaped actor Pool from compiled handler pthreads, both server modes" --body "$(cat <<'EOF'
## Why
forgepm opens a Postgres connection per query because a July-2026 comment says depot's actor Pool hangs from HTTP worker pthreads. The foreign-thread bridge and the Perceus erased-niche fix have since landed, but the only fixture covering that shape (`test/native/foreign_actor_http.march`) was wired into nothing and replied an immediate `Int`, which hides heap-payload RC bugs.

## What
- `test/native/pooled_actor_http.march`: actor Pool mirroring `depot/lib/wire/pool.march` (task_spawn(actor_call) checkout, heap `Conn` with a 64 KiB `Bytes` reply), served over HTTP.
- `test/test_http_native.ml`: `with_compiled_server` factored out of `run_http_e2e` (no behaviour change); new `run_pooled_e2e`: 200 sequential, 32×50 concurrent, `/stats out=0`, RSS growth < 8 MiB, process alive. Runs under `MARCH_HTTP_EVLOOP=0` and `=1`.
- Deletes the never-wired fixture.

Design: `specs/2026-10-01-forgepm-pooled-db-design.md`. forgepm's Repo switch follows in the forgepm repo.

## Verification
`./_build/default/test/run_stdlib.exe test 'http server' -e`: 4/4 OK locally (macOS). Assertions proven non-vacuous by perturbing `Checkin` (fails) and the e2e body (fails).
EOF
)" 2>&1 | tail -1
```

Then bind it: `mcp__ccd_pr__get_status`; if it does not report this PR, `bind_pr`. Read CI; do not poll it yourself.

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && id=$(deciduous add action "Task 4: Part 1 PR opened" -c 90 --commit HEAD | grep -o 'node [0-9]*' | awk '{print $2}') && deciduous link 2548 $id -r "Part 1 shipped for review"
```

---

### Task 5: forgepm `Repo.with_conn` via the depot Pool, with fallback

Work in `/Users/80197052/code/forgepm` (its own git repo; check `git status` is clean and note the branch; create `claude/pooled-repo` from its default branch).

**Files:**
- Modify: `lib/forgepm/repo.march`
- Modify: `lib/forgepm/packages/packages.march:295-325`

**Interfaces:**
- Consumes: `Pool.with_conn(pool, callback) : Result(r, String)` where `callback : DbConn -> r` (`depot/lib/wire/pool.march:263`); `Vault.get(Vault.open("forgepm:pool"), "db") : Option(Pid)` set by `Forgepm.Application.start` (`lib/forgepm/application.march:34`); `Bastion.Logger.warn(msg, meta)`.
- Produces: `Forgepm.Repo.with_conn(f)` unchanged signature: returns `f(db)`'s `ConnResult`, or `Err(String)`. `Forgepm.Repo.exec_one`, `transaction` unchanged. `Forgepm.Packages.pkg_exec(f)` now equals `Forgepm.Repo.with_conn(f)`.

- [ ] **Step 1: Write a pure test for the fallback decision**

The decision "pool present and healthy → pooled; otherwise direct" is pulled into a pure helper so it can be unit-tested without Postgres. Create `test/repo_route_test.march`:

```march
-- test/repo_route_test.march
-- Pure tests for Forgepm.Repo's pool-or-direct routing. The DB-touching
-- paths are exercised by scripts/pool-acceptance.sh against a live Postgres.
mod Forgepm.Test.RepoRoute do

  needs IO.Console
  needs IO.NetConnect
  needs IO.Random
  needs IO.Mut

  import Test
  import Forgepm.Repo

describe "Repo.route_result" do

  test "a pooled Ok unwraps to the callback's result" do
    let r = Forgepm.Repo.route_result(Ok(Ok(42)), fn -> Err("direct should not run"))
    match r do
    Ok(v)  -> Test.assert_eq_int(v, 42, "pooled result passes through")
    Err(e) -> Test.fail("expected Ok(42), got Err(" ++ e ++ ")")
    end
  end

  test "a pooled Err falls back to the direct path" do
    let r = Forgepm.Repo.route_result(Err("pool actor: timeout"), fn -> Ok(7))
    match r do
    Ok(v)  -> Test.assert_eq_int(v, 7, "fallback ran")
    Err(e) -> Test.fail("expected fallback Ok(7), got Err(" ++ e ++ ")")
    end
  end

end

end
```

If `Test.fail` does not exist in forgepm's Test module, use `Test.assert(false, "…")`; check `grep -n "fn fail\|fn assert" ~/code/forgepm/.march/deps/*/lib/test*.march` or the bastion/stdlib Test module used by `test/metrics_test.march`.

- [ ] **Step 2: Run it to see it fail**

```bash
cd /Users/80197052/code/forgepm && forge test test/repo_route_test.march > /tmp/forgepm_repo_route.log 2>&1; echo "exit=$?"; grep -n -i "route_result\|error\|unknown" /tmp/forgepm_repo_route.log | head -5
```
Expected: non-zero exit, an error naming `route_result` as unknown.

- [ ] **Step 3: Implement**

Replace the body of `lib/forgepm/repo.march` with:

```march
mod Forgepm.Repo do

  needs IO.NetConnect
  needs IO.Random
  needs IO.Mut

  import Connection
  import Db
  import Pool
  import Vault

  -- Pooled by default, connect-per-query as the fallback.
  --
  -- Forgepm.Application.start creates depot's actor Pool and stores its pid in
  -- Vault "forgepm:pool". Checkout goes through Pool.with_conn, i.e.
  -- task_spawn(actor_call) from the HTTP worker pthread: the foreign-thread
  -- bridge path, proven under 32-way concurrency in both compiled server
  -- modes by march's test/native/pooled_actor_http.march + run_pooled_e2e.
  -- (The July-2026 note that the Pool "hangs on the HTTP worker threads"
  -- predates that bridge and the Perceus erased-niche fix that corrupted
  -- Some(DbConn) replies.)
  --
  -- Fallback: no pool in Vault (a forge task that never ran Application.start)
  -- or a checkout Err (pool exhausted / actor down / timeout) opens a
  -- short-lived connection as before, so a pool fault degrades to the old
  -- cost, never to a 503. The old Vault-slot reuse pool that leaked
  -- ~1.6MB/request is unrelated to depot's Pool and is being root-caused
  -- separately.

  pfn rconn_cfg() do
    {
      host:     Config.db_host(),
      port:     Config.db_port(),
      user:     Config.db_user(),
      database: Config.db_name(),
      password: Some(Config.db_password())
    }
  end

  pfn direct(f) do
    match Connection.connect(rconn_cfg()) do
    Err(e)  -> Err(e)
    Ok(raw) -> do
      let db = Db.from_postgres(raw)
      let r  = f(db)
      let _  = Db.close(db)
      r
    end
    end
  end

  doc "Pooled-vs-direct routing, pure: `pooled` is Pool.with_conn's result (Ok(callback result) or Err(reason)); `fallback` runs the direct path. Exposed for unit tests."
  fn route_result(pooled, fallback) do
    match pooled do
    Ok(r)  -> r
    Err(reason) -> do
      let _ = Bastion.Logger.warn("db pool checkout failed; using a direct connection", [("reason", reason)])
      fallback()
    end
    end
  end

  doc "Run f(db) on a pooled connection (falling back to a short-lived direct connection). Returns f's result (a ConnResult) or the connect error."
  fn with_conn(f) do
    match Vault.get(Vault.open("forgepm:pool"), "db") do
    None       -> direct(f)
    Some(pool) -> route_result(Pool.with_conn(pool, f), fn -> direct(f))
    end
  end

  doc "Execute a parameterized SQL statement (INSERT/UPDATE/DELETE) and return the ConnResult."
  fn exec_one(sql, params) do
    with_conn(fn db -> Db.exec(db, sql, params))
  end

  doc "Run f(conn) inside a transaction. Rolls back on Err."
  fn transaction(f) do
    with_conn(fn db ->
      let _ = Db.exec(db, "BEGIN", Nil)
      match f(db) do
      Err(e) -> do
        let _ = Db.exec(db, "ROLLBACK", Nil)
        Err(e)
      end
      Ok(v) -> do
        let _ = Db.exec(db, "COMMIT", Nil)
        Ok(v)
      end
      end
    )
  end

end
```

`needs IO.Mut` is for Vault. If `forge build` reports a missing capability, add exactly the one it names. If `Bastion.Logger` needs an `import`, add `import Bastion.Logger` (see `lib/forgepm/application.march:4`).

A conn after a protocol error: depot's `Checkin` trusts the returned conn (no ping, `pool.march:157-163`). `Db.exec` returning `Err` for a SQL error leaves the connection usable (Postgres stays in a clean state after an error response outside a transaction; inside `transaction` we `ROLLBACK`). A socket-level failure is also `Err(String)` from `Db.exec`; to avoid re-pooling a dead socket, `with_conn` cannot tell the two apart today. Record this as a follow-up in forgepm's specs (Step 5) rather than guessing a heuristic.

- [ ] **Step 4: `pkg_exec` delegates**

In `lib/forgepm/packages/packages.march`, delete `pconn_cfg` (lines ~305-313) and replace `pkg_exec`'s body:

```march
-- All package queries use Forgepm.Repo's connection policy (pooled, with a
-- direct-connection fallback); see lib/forgepm/repo.march for why the pool
-- is safe from HTTP worker threads now.
pfn pkg_exec(f) do
  Forgepm.Repo.with_conn(f)
end
```

Delete the comment block above it (lines ~295-304) that says the Pool hangs on HTTP worker threads; keep the sentence about conduit enqueues using direct SQL if it is still true (it is; conduit's embedded Pool is a separate matter).

- [ ] **Step 5: Build, test, record the follow-up**

```bash
cd /Users/80197052/code/forgepm && forge build > /tmp/forgepm_build.log 2>&1; echo "exit=$?"; grep -c -i "error" /tmp/forgepm_build.log; tail -3 /tmp/forgepm_build.log
```
Expected: `exit=0`, `0` errors. Memory: a `forge build` finishing in ~0.03s with "checked N file(s)" is a vacuous cache hit; confirm it actually compiled (the log shows a compile step).

```bash
cd /Users/80197052/code/forgepm && forge test test/repo_route_test.march > /tmp/forgepm_repo_route.log 2>&1; echo "exit=$?"; tail -5 /tmp/forgepm_repo_route.log
```
Expected: `exit=0`, 2 tests passed.

Append to `~/code/forgepm/specs/operations.md` under its perf/operations section:

```
- DB pool (2026-10-01): `Forgepm.Repo.with_conn` uses depot's actor Pool
  (`DB_POOL_MIN`/`DB_POOL_MAX`), falling back to a direct connection on a
  checkout error (logged at WARN with the reason). Follow-up: `Db.exec`'s
  `Err(String)` does not distinguish a SQL error (conn reusable) from a dead
  socket (conn must not be re-pooled); depot `Checkin` trusts the conn. If
  WARN logs show repeated failures on one conn, add a ping-on-checkin to
  depot's Pool.
```

- [ ] **Step 6: Commit (forgepm)**

```bash
cd /Users/80197052/code/forgepm && git add lib/forgepm/repo.march lib/forgepm/packages/packages.march test/repo_route_test.march specs/operations.md && git commit -q -m "feat(repo): pooled connections via depot Pool with direct-connection fallback" && git log --oneline -1
```

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && id=$(deciduous add action "Task 5: forgepm Repo.with_conn routes through depot Pool (forgepm commit $(cd /Users/80197052/code/forgepm && git rev-parse --short HEAD))" -c 85 | grep -o 'node [0-9]*' | awk '{print $2}') && deciduous link 2548 $id -r "Part 2 code"
```

---

### Task 6: Acceptance script and run

**Files:**
- Create: `~/code/forgepm/scripts/pool-acceptance.sh`
- Modify: `~/code/forgepm/docs/deploy.md` §2 table and §8

**Interfaces:**
- Consumes: a running Postgres reachable with forgepm's `DB_*` env (docker-compose's), `wrk` and `psql` on PATH, two forgepm binaries (before/after) for the A/B.
- Produces: a report on stdout with the four criteria and a PASS/FAIL per criterion.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# scripts/pool-acceptance.sh — acceptance run for the pooled Repo
# (march specs/2026-10-01-forgepm-pooled-db-design.md).
#
# usage: scripts/pool-acceptance.sh <binary-after> [<binary-before>]
#   Needs: a Postgres matching DB_* env (docker compose up -d db), wrk, psql.
#   Target: GET /health — goes through Repo.exec_one("SELECT 1") with no
#   rendering, no page cache and no metrics write, so it isolates the
#   connection policy.
# Criteria (spec): (1) pg_stat_activity <= DB_POOL_MAX+1 throughout,
#   (2) RSS flat after 10s warm-up, (3) zero non-2xx, (4) CPU-us/req not
#   worse than <binary-before> (order-swapped A,B,B,A).
set -euo pipefail
AFTER=${1:?usage: $0 <binary-after> [<binary-before>]}
BEFORE=${2:-}
PORT=${PORT:-4100}
DB_POOL_MAX=${DB_POOL_MAX:-20}
DB_NAME=${DB_NAME:-forgepm}
DUR=${DUR:-60}
export PORT DB_POOL_MAX MARCH_ENV=prod SECRET_KEY_BASE=${SECRET_KEY_BASE:-acceptance-run-not-a-real-secret-0123456789}

pgcount() { psql -At -c "select count(*) from pg_stat_activity where datname='${DB_NAME}'" "${DATABASE_URL:-postgres://${DB_USER:-postgres}:${DB_PASSWORD:-}@${DB_HOST:-localhost}:${DB_PORT:-5432}/${DB_NAME}}"; }
rss()     { ps -o rss= -p "$1" | tr -d ' '; }
cputime() { ps -o time= -p "$1" | tr -d ' ' | awk -F: '{if(NF==3)print $1*3600+$2*60+$3; else if(NF==2)print $1*60+$2; else print $1}'; }

start() { "$1" > "/tmp/forgepm-acc-$$.log" 2>&1 & echo $!; }
wait_ready() { for _ in $(seq 1 100); do curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1 && return 0; sleep 0.1; done; echo "server never became ready"; cat "/tmp/forgepm-acc-$$.log"; return 1; }

run_one() {  # $1 binary  $2 label  -> prints "label cpu_us_per_req non2xx max_pg rss_delta"
  local pid; pid=$(start "$1"); wait_ready
  wrk -t2 -c16 -d3s "http://127.0.0.1:${PORT}/health" >/dev/null   # warm-up
  local rss0 cpu0 maxpg=0; rss0=$(rss "$pid"); cpu0=$(cputime "$pid")
  ( for _ in $(seq 1 $((DUR/5))); do sleep 5; echo "$(pgcount)"; done ) > "/tmp/forgepm-acc-pg-$$.txt" &
  local sampler=$!
  local out; out=$(wrk -t4 -c32 -d"${DUR}s" --latency "http://127.0.0.1:${PORT}/health")
  wait "$sampler" || true
  local rss1 cpu1; rss1=$(rss "$pid"); cpu1=$(cputime "$pid")
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  local reqs non2xx; reqs=$(echo "$out" | awk '/requests in/{print $1}')
  non2xx=$(echo "$out" | awk '/Non-2xx/{print $NF}'); non2xx=${non2xx:-0}
  maxpg=$(sort -n "/tmp/forgepm-acc-pg-$$.txt" | tail -1)
  local cpuus; cpuus=$(awk -v a="$cpu0" -v b="$cpu1" -v n="$reqs" 'BEGIN{ if(n>0) printf "%.1f", (b-a)*1e6/n; else print "nan" }')
  echo "$2 cpu_us_per_req=$cpuus non2xx=$non2xx max_pg_conns=$maxpg rss_delta_kib=$((rss1-rss0)) reqs=$reqs"
  echo "$out" | grep -E "Latency|Requests/sec" | sed 's/^/    /'
}

echo "== pooled binary: $AFTER (DB_POOL_MAX=$DB_POOL_MAX, ${DUR}s) =="
A=$(run_one "$AFTER" after); echo "$A"
maxpg=$(echo "$A" | sed -n 's/.*max_pg_conns=\([0-9]*\).*/\1/p'); non2xx=$(echo "$A" | sed -n 's/.*non2xx=\([0-9]*\).*/\1/p'); rssd=$(echo "$A" | sed -n 's/.*rss_delta_kib=\(-\{0,1\}[0-9]*\).*/\1/p')
[ "$maxpg" -le $((DB_POOL_MAX+1)) ] && echo "(1) pg connections <= $((DB_POOL_MAX+1)): PASS ($maxpg)" || echo "(1) pg connections: FAIL ($maxpg > $((DB_POOL_MAX+1)))"
[ "$rssd" -le 16384 ] && echo "(2) RSS flat (<16 MiB growth): PASS (${rssd} KiB)" || echo "(2) RSS flat: FAIL (${rssd} KiB growth)"
[ "$non2xx" -eq 0 ] && echo "(3) zero non-2xx: PASS" || echo "(3) zero non-2xx: FAIL ($non2xx)"
if [ -n "$BEFORE" ]; then
  echo "== A/B CPU-us/req, order-swapped (A=before B=after): A B B A =="
  run_one "$BEFORE" before; run_one "$AFTER" after; run_one "$AFTER" after; run_one "$BEFORE" before
  echo "(4) judge by the four cpu_us_per_req numbers above; after must not exceed before"
fi
rm -f "/tmp/forgepm-acc-$$.log" "/tmp/forgepm-acc-pg-$$.txt"
```

`chmod +x scripts/pool-acceptance.sh`.

- [ ] **Step 2: Build both binaries**

```bash
cd /Users/80197052/code/forgepm && forge build --release > /tmp/forgepm_rel.log 2>&1; echo "exit=$?"; ls -la .march/build/release/forgepm 2>/dev/null || ls -la .march/build/*/forgepm
```
Copy the result to `/tmp/forgepm-after`. Then `git stash` is forbidden by project rules; instead build "before" from a worktree: `git worktree add /tmp/forgepm-before-wt HEAD~1 && (cd /tmp/forgepm-before-wt && forge build --release)` and copy its binary to `/tmp/forgepm-before`; `git worktree remove /tmp/forgepm-before-wt` afterwards.

- [ ] **Step 3: Run it**

```bash
cd /Users/80197052/code/forgepm && docker compose up -d db 2>&1 | tail -1 && DB_PASSWORD=$(grep -m1 DB_PASSWORD docker-compose.yml | sed 's/.*: *//; s/"//g') scripts/pool-acceptance.sh /tmp/forgepm-after /tmp/forgepm-before 2>&1 | tee /tmp/forgepm-acceptance.txt
```
Expected: (1) (2) (3) PASS; (4) after ≤ before in both orderings. Loopback networking may be blocked for the agent; if `wait_ready` fails with the server log showing it is listening, hand the exact command to the user to run and paste back.

If (2) fails: that is the leak class the spec worried about; capture RSS over time (`while sleep 5; do rss $pid; done`) and stop; this feeds sub-project C.
If (3) shows 503s: read the WARN lines in `/tmp/forgepm-acc-*.log`; a `pool actor: timeout` under 32 concurrency with `DB_POOL_MAX=20` means checkouts queue behind the actor; rerun with `DB_POOL_MAX=32` to confirm, then record the sizing guidance in deploy.md.

- [ ] **Step 4: Document and commit (forgepm)**

In `docs/deploy.md` §2, change the `DB_POOL_MIN / DB_POOL_MAX` row's Notes cell to: `pool sizing; the web binary checks out one connection per query. Size MAX at or above the expected concurrent in-flight requests (see scripts/pool-acceptance.sh).` In §8 add: `- DB connections are pooled since <commit>; a checkout failure falls back to a direct connection and logs a WARN with the reason.`

```bash
cd /Users/80197052/code/forgepm && git add scripts/pool-acceptance.sh docs/deploy.md && git commit -q -m "ops: pool acceptance script; deploy notes for the pooled Repo" && git log --oneline -1
```

Attach the acceptance output to the graph:

```bash
cd /Users/80197052/code/march/.claude/worktrees/silly-blackwell-37c0cd && id=$(deciduous add outcome "forgepm pool acceptance: <fill in PASS/FAIL per criterion and the four cpu_us/req numbers>" -c 85 | grep -o 'node [0-9]*' | awk '{print $2}') && deciduous link 2548 $id -r "acceptance result" && deciduous doc attach $id /tmp/forgepm-acceptance.txt -d "pool-acceptance.sh output"
```

Open the forgepm PR with `gh pr create` from `/Users/80197052/code/forgepm` (repo `ForgePM/forgepm`), body: what changed, the acceptance numbers, link to the march PR. Report the numbers verbatim to the user; if any criterion failed, say so with the output.

---

## Self-review

**Spec coverage.** Fixture shape (Task 1), harness factoring + five assertions + both modes (Tasks 2–3), runtime-bug-in-scope rule (Task 3 Step 4), `Repo`/`pkg_exec` switch with fallback and None/Err split (Task 5), transaction over pooled conn + checkin-trust note (Task 5 Steps 3/5), comment rewrite (Task 5), acceptance script with four criteria and A/B (Task 6), todo→progress + CHANGELOG rule + decision graph (Task 4, Global Constraints). `migrate`/`seed` untouched (Task 5 does not edit them). ✔

**Placeholders.** Task 2 Step 3 says "PASTE … verbatim" for ~115 lines that already exist in the file at known line numbers; that is a move, not an omission. Task 6 Step 4's outcome title has a `<fill in>` that is explicitly the measured result. ✔

**Type consistency.** `server_ctx` fields used in Task 3 (`bail`, `connect_or_bail`, `send`, `request_bytes`, `read_response`, `child_status`, `describe_status`, `child_pid`) all exist in Task 2's record. Fixture body `conn=<id>:65536` matches `conn_body_ok`. `/stats` → `out=<n>` matches `stats_zero`. `route_result(pooled, fallback)` matches the test (`fallback` is zero-arg, called as `fallback()`). ✔
