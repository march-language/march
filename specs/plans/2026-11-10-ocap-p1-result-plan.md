# Object capabilities, phase 1: every capability operation returns `Result` — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every capability operation a program can perform returns `Result(T, CapError)` (or a
`Result` whose error type carries a `CapError`), through one run-time check point that phase 4
fills in, with a `forge fix` rewrite that migrates call sites.

**Architecture:** One new raw builtin, `cap_check_raw(kind, target) : Int`, implemented once per
runtime (C, interpreter, JS; the JIT links the C runtime). It answers "allowed" in every normal
run; a test-only hook, `MARCH_TEST_REFUSE`, makes it refuse whole kinds so every `Err` path can be
tested on every backend now. A new stdlib module `Authority` turns its answer into
`Result((), CapError)`. Every stdlib public entry point that performs a checked operation calls
`Authority.check` first and returns a `Result`; the raw builtins beneath become stdlib-only, as the
design's §15 already prescribes for the network. Builtin types do not change, so the nine-table
builtin machinery is touched once (for `cap_check_raw`), not ~60 times. A new typechecker diagnostic
recognises "a `Result(T, CapError)` where a `T` was expected" and carries a machine fix that
`forge fix` applies.

**Tech Stack:** OCaml 5.5.1 (compiler, interpreter, forge), C (runtime), JavaScript
(`runtime/march_runtime.mjs`), March (stdlib).

**Spec:** `specs/2026-11-10-object-capability-design.md` (§2, §3, §6, §15, §17, §20). Where it is
silent, `specs/2026-11-09-dependency-grants-and-restrict-design.md` §"Refusal is an error value"
(superseded design, still valid here) and `specs/2026-11-09-narrow-capabilities-design.md` §4
(environment reads: "a variable that is not set and one that is out of scope are different
results").

## Global Constraints

- Refusal is an error value: never a crash, never a silent no-op (§15, owner 2026-11-09).
- `CapError` names the refused scope and the limit that refused it (§15). Its variants are ours (§20).
- Every runtime the same: compiled (C), interpreter, JIT, JS produce identical results (§15).
- No threading capabilities through parameters; no parameterised modules (owner). Nothing in this
  phase adds a parameter to any function.
- A module's `needs` limits only its own operations; operations performed through the stdlib are
  charged to the calling module as now (§4, owner 2026-11-10). This phase changes no charging rule.
- Cost: a program with no scopes pays one cheap read per capability operation and nothing per call (§15).
- Uses of a handle need no authority (§6): `Vault.set`, socket send/receive, `file_read_line`,
  process pipes are **not** capability operations and are **not** re-typed here.
- Breaking change, pre-1.0: ships with a `forge fix` rewrite and a `### Changed` CHANGELOG entry (§17).
- Repo rules (CLAUDE.md): `dune build --root .` in a worktree; `scripts/run-tests.sh`; stage files
  by explicit path; never bare `git stash`; `specs/todos/` → `specs/progress/` in the landing commit;
  edit `specs/lang/`, then `scripts/gen-lang-docs.py`; new error-corpus cases via
  `scripts/seed-error-corpus.sh`.

## Inventory (grounded 2026-11-10 on `aeac8a566`)

`builtin_cap_table` (`lib/typecheck/typecheck_builtins.ml:225`) lists 135 builtins. Every one is
callable from user code today; the stdlib-only gate (`Typecheck_env.stdlib_only`,
`lib/typecheck/typecheck_env.ml:2295`) holds none of them. Classified against §6:

**C — checked in this phase** (the operation itself is the authority; no handle stands in for it).
Kind and target are what `Authority.check` receives.

| Builtins | Kind | Target | Type today | Public entry point(s) |
|---|---|---|---|---|
| `print`, `print_line`, `println`, `print_stderr` | `IO.Console` | `"stdout"` / `"stderr"` | `String -> ()` | `Prelude.println` (shadows the builtin), `IO.write/puts/warn/gets/inspect` |
| `io_read_line`, `io_read_byte` (**not in the cap table today**) | `IO.Console` | `"stdin"` | `String` / `Int` | `IO.read_line`, `IO.read_byte`, `IO.gets` |
| `unix_time`, `unix_time_ms`, `uuid_v7` | `IO.Clock` | `""` | `Float` / `Int` / `String` | `DateTime.now`, `UUID.v7`; new `System.unix_time`, `System.unix_time_ms` |
| `random_bytes`, `stdlib_random_bytes`, `uuid_v4` | `IO.Random` | `""` | `Bytes` / `String` | `Crypto.random_bytes/random_hex`, `UUID.v4`, `Random.int` |
| `process_env` | `IO.Process` | the name | `Option(String)` | `Process.env`, `System.env`, `Env.*`, `Config.*` |
| `process_set_env`, `process_cwd`, `process_argv`, `process_pid`, `process_exit` | `IO.Process` | name / `""` | `()` / `String` / `List(String)` / `Int` | `Process.*`, `System.*` |
| `process_spawn_sync`, `process_spawn_lines`, `process_spawn_async` | `IO.Process` | the program | `Result(_, String)` | `Process.run/run_stream/spawn_async`, `System.cmd` |
| `signal_watch`, `signal_raise_self` | `IO.Signal` | the signal name | `()` | `Signal.watch`, `Signal.raise` |
| `task_spawn`, `task_spawn_link`, `task_spawn_steal`, `task_spawn_with_cancel` | `IO.Spawn` | `""` | `Task(a)` | `Task.async`, `Task.async_stream*`; internal: `List.pmap*`, `Parallel.*` |
| `vault_new`, `vault_whereis` | `IO.Mut` | the table name | `Vault(v)` / `Option(Vault(v))` | `Vault.new/open/whereis`, `Config.new_store` |
| `vault_ns_set`, `vault_ns_get`, `vault_ns_drop` (take a name, not a handle) | `IO.Mut` | the namespace | `()` / `Option(v)` | `Vault.ns_*` |
| `file_read`, `file_write`, `file_append`, `file_delete`, `file_rename`, `file_copy`, `file_stat`, `file_exists`, `dir_list`, `dir_exists`, `dir_mkdir`, `dir_mkdir_p`, `dir_rmdir`, `dir_rm_rf` | `IO.FileRead` / `IO.FileWrite` / `IO.FileSystem` (as the cap table says) | the path (both, for rename/copy) | `Result(_, FileError)`; `file_exists`/`dir_exists` `Bool` | `File.*`, `Dir.*`, `Seq.from_file_*` |
| `file_open`, `csv_open` | as above | the path | `Result(Int, _)` | `File.with_lines/with_chunks/each_*`, `Csv.*` (phase 2 turns the `Int` into `File.Handle`) |
| `tcp_connect`, `tcp_connect_timeout` | `IO.NetConnect` | `host:port` | `Result(Int, String)` | `Socket.connect*`, `HttpTransport.*`, `HttpClient.*` |
| `tcp_listen`, `http_server_listen`, `http_server_spawn_n`, `http_server_plain_listener`, `http_server_bind_host` | `IO.NetListen` | `addr:port` | mixed | `HttpServer.listen/spawn_n/bind_host/plain_listener` |
| `udp_open`, `udp_connect`, `udp_resolve`, `udp_send_batch`, `udp_send_many` (each names a destination) | `IO.NetConnect` | `host:port` | `Result(_, String)` | `Udp.*` |
| `dns_resolve` | `IO.Network` | the host | `Result(List(String), String)` | `Dns.resolve` |
| `tls_client_ctx`, `tls_server_ctx` | `IO.NetConnect.TLS` | `""` | `Result(Int, String)` | `Tls.client_ctx/server_ctx`, `Tls.https_get` |

**U — uses of something already opened; unchanged** (§6 "uses that need no authority"):
`file_read_line`, `file_read_chunk`, `csv_next_row`, `tcp_send_all`, `tcp_recv_*` (8),
`tcp_set_recv_timeout`, `tcp_accept`, `tcp_accept_timeout`, `tcp_local_port`, `udp_close`,
`udp_local_addr`, `udp_stats`, `udp_recv_batch`, `ws_recv`, `ws_send`, `ws_select`, `tls_connect`,
`tls_accept`, `tls_read*`, `tls_write`, `tls_negotiated_*`, `tls_peer_cn`, `tls_ctx_set_groups`,
`process_read_line`, `process_write`, `process_kill_proc`, `process_wait_proc`, `vault_set`,
`vault_set_ttl`, `vault_drop`, `vault_update`, `vault_put_new`, `vault_incr`, `vault_push_capped`,
`vault_reap`, `vault_close`, `http_server_wait`, `http_server_set_timeouts`,
`http_server_tls_configure`, `http_server_reload_tls`, `signal_unwatch`, `get_work_pool`.

**I — runtime-internal; stdlib-only, unchecked:** `dist_monitor_register`, `dist_monitor_pending`,
`dist_monitor_ack`, `dist_monitor_forget_node` (called only from private `ClusterNode`/`DistLink`
functions; the cluster's authority is checked at `ClusterNode.start`, phase 7).

**Out of this phase, stated so nobody re-litigates it:** actor `spawn` (not a capability operation
today; phase 4 gives actors their authority), `extern` calls (authority is checked when the library
is opened, phase 2's `Foreign.open`), `actor_whereis`/`actor_register` (phase 2's `IO.Registry`).

**Already returning `Result` with another error type** (gain a `CapRefused(CapError)` variant):
`FileError` (`stdlib/file.march:13`, a `ptype`), `CsvError`, `SocketError`, `UdpError`, `TlsError`,
`DnsError`, `TransportError` (two copies: `http_transport.march:21`, `http_client.march:18`),
`HttpError`. `HttpError`'s `OutOfScope(String)`, `MethodRefused(String)` and `PathRefused(String)`
(host-scope guard, shipped 2026-11-09) are refusals and fold into `CapRefused`. `String`-errored
public functions (`Process.run/run_stream/spawn_async`, `System.cmd`) get a new `ProcessError`.

**Blast radius, measured.** A throwaway stdlib where `Prelude.println` returns `Result` (scratch
only) makes 366 of the 790 `.march` files under `test/`, `bench/`, `examples/` that mention `println`
fail to typecheck, with 532 new `type_mismatch` errors: 393 a block's last line (365 of them the
declared `: ()`/`: Unit` of `main`), 79 after `->` (match arm or lambda), 50 inline `do`/`else`, 10
other. A `println` used as a statement compiles unchanged (March has no unused-value warning).
Embedded March in `test/*.ml` (≈1,200 `println`) was not measured. Clock reads (~170 sites),
env reads (~200), task spawns (~500) add to this.

## Decisions (mine, inside §20's "left to the builder"; each is a line for the owner to veto)

1. **Where the check sits:** in the stdlib entry point, calling `cap_check_raw`, not inside each C
   builtin. Same choice §15 made for network connections. Keeps builtin ABIs unchanged.
2. **Existing error types gain `CapRefused(CapError)`** rather than nesting
   (`Result(Result(T, FileError), CapError)`) or replacing the error type. One level of `Result`,
   I/O errors keep their detail, and `CapError` is always one match arm away.
3. **`CapError` shape:**
   ```march
   type CapLimit = Launch | FnNeeds(String) | ModNeeds(String) | Restrict(String) | DepGrant(String)
   type CapError = CapError(String, String, CapLimit, String)
   --                      kind    target  limit     the limit's scope text
   ```
   `CapError`'s constructor is named after its type, not `Refused`/`CapRefused`, because
   `TransportError` already has `Refused(String)` and every error type below gains a
   `CapRefused(CapError)` variant (ambiguous short constructor names resolve to the current
   module, a known trap). Only `Launch` is produced in phase 1 (by the test hook). Phases 4–6 produce the rest; the variant
   list is final so they add no breaking change. `Authority.describe(e)` renders it as
   `IO.FileRead("/etc/passwd") refused by the launch grant (IO.Console)`.
4. **Migration semantics** (what `forge fix` writes):
   - `Result((), CapError)` where `()` is expected, on a block's last line: add a line `()` after it
     (the refusal is discarded, as it already is for every statement-position call).
   - the same anywhere else (arm, lambda, inline `if`): wrap as `Authority.ignore(e)`.
   - `Result(T, CapError)` where a non-unit `T` is expected: wrap as `Authority.must(e)`, which panics
     with `Authority.describe(err)`. Today's behaviour (the op never fails) is preserved; a refusal
     becomes the panic the narrow-capabilities design specified "until phase 2".
   - a call of a raw builtin made stdlib-only here: rename to its entry point (table in Task 5).
   - existing `match` on an error type that gained `CapRefused`: no machine fix (the arm's body is the
     programmer's call); the non-exhaustive diagnostic names `CapRefused` and suggests
     `CapRefused(e) -> ...` at `maybe-incorrect` tier, so `forge fix` does not apply it unasked.
5. **Spawns return `Result(Task(a), CapError)`**, as the superseded design listed. Stdlib helpers that
   spawn as an implementation detail (`List.pmap`, `pmap_n`, `pfilter`, `preduce`, `Parallel.*`) fall
   back to the sequential computation on refusal and keep their types.
6. **Test hook:** `MARCH_TEST_REFUSE="IO.Console,IO.FileRead"` (kind names; a kind refuses itself and
   its descendants in `Cap_lattice.hierarchy`). Read once per process. It can only narrow. Phase 4
   replaces it with `--grant`/`MARCH_GRANT` and deletes it.
7. **No "unused `Result`" warning** in this phase (it would fire on ~5,000 `println` statements).
   Filed as a todo for after phase 8.

## Review Focus

- A refused operation inside stdlib code the user did not call directly (a `Logger` timestamp, the
  clock read seeding `Random.int`, a `List.pmap` spawn) must not panic: the expected behaviour is
  the per-site policy in Task 7/9, pinned by a refusal test for each.
- `Process.env` on an unset variable vs a refused read: `Ok(None)` vs `Err(CapError(...))`, never
  the same value (narrow-capabilities §4). Pinned in Task 8.
- The REPL and doctests must not start echoing `Ok(())` after every `println`. Pinned in Task 12.
- Rewriting `file_read("/etc/x")` to `File.read("/etc/x")` must keep the compile-time literal
  path-scope check (`path_arg_builtins`, `lib/typecheck/typecheck_caps.ml:224`) firing. Pinned in
  Task 5.
- A stdlib wrapper whose body no longer typechecks is silent: `bin/main.ml` drops diagnostics spanned
  in stdlib files. Every stdlib task runs `march --check stdlib/<file>.march` (unfiltered when the
  file is the entry) and Task 0's per-file baseline must not grow.

---

### Task 0: Baselines

Nothing later can show "no regression" without these. No code changes.

**Files:**
- Create: `specs/progress/2026-11-10-ocap-p1-baselines.md` (numbers only; deleted by Task 15)

- [ ] **Step 1:** Record the stdlib self-check baseline: for every `stdlib/*.march`, `HOME=$(mktemp -d) ./_build/default/bin/main.exe --check stdlib/$f` and save the error count per file.
- [ ] **Step 2:** Record the corpus baseline: `--check-json` on every `.march` under `test/`, `bench/`, `examples/` (8-way `xargs -P`, private `HOME`), keeping one JSON file per input under `$SCRATCH/base/`.
- [ ] **Step 3:** Record timings, compiled `--opt 2`, 5 runs each, median: `bench/list_ops.march`, `bench/binary_trees.march`, and three new microbenches written now: `bench/println_loop.march` (1e6 `println` to a pipe), `bench/clock_loop.march` (1e7 `unix_time_ms`), `bench/spawn_loop.march` (1e5 `Task.async` + `await`). Register the three in `test/test_bench_gate.ml` with expected output.
- [ ] **Step 4:** `scripts/oracle-base.sh ir types` and keep the manifests; these oracles will go RED by design later (Task 15 reviews the diff instead of expecting green).
- [ ] **Step 5:** Commit the three benches, the gate registration and the baseline note.

### Task 1: `Authority` module and `CapError`

**Files:**
- Create: `stdlib/authority.march`
- Test: `test/stdlib/test_authority.march`

**Interfaces:**
- Produces: `type CapLimit`, `type CapError` (Decision 3, exactly); `Authority.describe(e : CapError) : String`; `impl Show(CapError)` via `describe`; `Authority.must(r : Result(a, CapError)) : a` (panics with `describe`; no refinement precondition, unlike `Result.unwrap`); `Authority.ignore(r : Result(a, CapError)) : ()`; `Authority.check(kind : String, target : String) : Result((), CapError)` (calls `cap_check_raw` from Task 2; until Task 2 lands, write it against a stub returning 0 in the same commit series).
- `CapError` and `CapLimit` must resolve by bare name from any module, as `FileError` does. Verify that before writing the rest.

- [ ] **Step 1: Write failing tests** in `test/stdlib/test_authority.march`:
  `describe(CapError("IO.FileRead", "/etc/passwd", Launch, "IO.Console")) == "IO.FileRead(\"/etc/passwd\") refused by the launch grant (IO.Console)"`;
  `describe(CapError("IO.Clock", "", ModNeeds("Report"), "IO.Console")) == "IO.Clock refused by module Report's needs (IO.Console)"`;
  `must(Ok(3)) == 3`; `ignore(Ok(1)) == ()`; `check("IO.Console", "stdout") == Ok(())`.
- [ ] **Step 2:** `scripts/run-tests.sh stdlib_march` → FAIL (module missing).
- [ ] **Step 3:** Implement. `Authority` has no `needs` line and performs no operation itself.
- [ ] **Step 4:** `march --check stdlib/authority.march` → no output; `scripts/run-tests.sh stdlib_march` → PASS. Check `lsp/test` prelude-collision and `scripts/check-docs.sh` (stdlib module count moves 139 → 140; update the counted docs it names).
- [ ] **Step 5:** Commit.

### Task 2: `cap_check_raw` in every runtime, with the test hook

The one new builtin. Load the `compiler-builtin` skill and the memory list of nine sites; the skill
alone lists four.

**Files:**
- Modify: `lib/typecheck/typecheck_builtins.ml` (`builtin_bindings`: `("cap_check_raw", Mono (TArrow (t_string, TArrow (t_string, t_int))))`; not in `builtin_cap_table`)
- Modify: `lib/typecheck/typecheck_env.ml:2295` (`stdlib_only`: `("cap_check_raw", "use `Authority.check(kind, target)`")`)
- Modify: `lib/eval/eval_builtins.ml` (+ a new `lib/eval/eval_cap.ml` holding the parsed hook)
- Create: `runtime/march_cap_check.c`, `runtime/march_cap_check.h`; Modify: `runtime/sources.list` (one line, role `core`)
- Modify: `lib/tir/llvm_builtins.ml` (entry **and** `PDeclare`: `declare i64 @march_cap_check_raw(ptr, ptr)`), `lib/tir/defun.ml` (`builtin_names`), `lib/tir/borrow.ml` (`extern_borrow_table`: both args borrowed), `lib/tir/purity.ml` (impure: two checks must never CSE, which matters from phase 4)
- Modify: `lib/tir/js_emit.ml` (call arm, `runtime_uses`, shim), `runtime/march_runtime.mjs`
- Modify: `lib/caps/emit_c_table.ml` to also write `runtime/march_cap_lattice.mjs` (the JS runtime has no lattice today), plus its freshness rule in `test/dune` next to the C one
- Modify: `test/test_codegen.ml` (`golden_preamble_core`, one new line)
- Test: `test/cap_conformance/refuse_console.march` and friends (Task 13 builds the runner; here, add a temporary case to `test/test_compiler.ml` group `cap_check`)

**Interfaces:**
- Produces: `cap_check_raw(kind : String, target : String) : Int` — `0` allowed; `1` refused by the launch (the only
  non-zero value in phase 1; phase 4 adds codes). And `cap_launch_text() : String`, the hook's value (`""` when unset),
  same nine sites, same commit, so `Authority.check` can fill the limit's scope text without a checked env read.
- C: `int64_t march_cap_check_raw(march_string *kind, march_string *target)`; the hook is parsed once (first call, `pthread_once`) into an array of kind strings; a refusal is `march_cap_subsumes(refused_kind, kind)` for any entry. The fast path with no hook set is one load of a static flag and a return.
- Interpreter and JS: the same semantics, hook from the OCaml process environment / `process.env` read once; the browser build (no `process`) always allows.

- [ ] **Step 1: Failing test** (`test_compiler.ml`, group `cap_check`): a program in `Authority` style calling `cap_check_raw("IO.FileRead", "/x")` from a stdlib-spanned fixture prints `0`; with `MARCH_TEST_REFUSE=IO.FileSystem` prints `1`; with `MARCH_TEST_REFUSE=IO.Console` prints `0`. Run under interpreter, `--compile`, `--jit`, `--target js` (node). And a user-file call is rejected by the stdlib-only gate with the suggestion text.
- [ ] **Step 2:** Run → FAIL (unknown builtin).
- [ ] **Step 3:** Implement all sites.
- [ ] **Step 4:** `dune build --root .` (restages the runtime: a targeted `bin/main.exe` build does not), clear `~/.march/cas/artifacts-v2/` in the private `HOME`, rerun → PASS on four backends. `scripts/run-tests.sh codegen compiler`, `scripts/check-runtime-sources.sh`, the lattice freshness rule.
- [ ] **Step 5:** Replace Task 1's stub with the real builtin; `Authority.check` returns `Err(CapError(kind, target, Launch, cap_launch_text()))` on `1`.
- [ ] **Step 6:** Commit.

### Task 3: The classification table and its freshness test

**Files:**
- Create: `lib/caps/cap_ops.ml`, `lib/caps/cap_ops.mli`
- Test: `test/test_cap_ops.ml` (registered in `test/run_compiler.ml`)

**Interfaces:**
- Produces: `type cls = Checked of { entry : string list } | Use | Internal`; `val table : (string * cls) list` keyed by builtin name, holding the Inventory's C/U/I rows, with `entry` the public entry points the gate's suggestion names; `val classify : string -> cls option`.

- [ ] **Step 1: Failing tests:** every name in `builtin_cap_table` has exactly one row; every row names a builtin that exists in `builtin_bindings`; `io_read_line`/`io_read_byte` are `Checked`; `vault_set` is `Use`; `dist_monitor_ack` is `Internal`.
- [ ] **Step 2:** FAIL → implement → PASS (`scripts/run-tests.sh -q compiler`).
- [ ] **Step 3:** Add `io_read_line`, `io_read_byte` to `builtin_cap_table` as `IO.Console` and to `lib/caps/cap_symbols.ml`; `test_cap_symbols` "no drift" stays green; fix every program that now lacks `needs IO.Console` (expected: none outside `stdlib/io.march`, which has it; check with Task 0's corpus run).
- [ ] **Step 4:** Commit, with a `specs/todos/` entry closed in the same commit noting stdin reads were uncharged.

### Task 4: The coverage test (§15's "a new one lacks a check")

**Files:**
- Create: `test/test_cap_check_coverage.ml` (registered in `run_compiler`)

**Interfaces:**
- Consumes: `Cap_ops.table`.
- Produces: a test that loads the whole stdlib (as `get_stdlib_tc_env` does; checking one file alone is vacuous), and for every function whose body calls a `Checked` builtin requires that the same function calls `Authority.check` on the path before it, or that the function is listed in the file's `coverage_allowlist : (string * string) list` (function, reason). Starts with an allowlist of every current offender; each later task deletes its lines; Task 15 asserts the list is empty except reasoned `Internal` rows.

- [ ] **Step 1:** Write the test with the allowlist generated from today's stdlib (it passes by construction); add a negative case: a fixture stdlib function calling `unix_time()` with no check is reported, naming the function and builtin.
- [ ] **Step 2:** PASS; commit.

### Task 5: Gate the checked builtins; the rename fix

**Files:**
- Modify: `lib/typecheck/typecheck_env.ml` (`stdlib_only` gains every `Checked` builtin; suggestion text from `Cap_ops`)
- Modify: `lib/typecheck/typecheck_caps.ml` (`check_stdlib_only_refs`: attach a machine-applicable `FReplace` renaming the callee when `Cap_ops` names exactly one entry point with the same arity; otherwise no fix)
- Modify: `stdlib/system.march` (add `unix_time() : Float`, `unix_time_ms() : Int`, still plain here; Task 7 re-types them)
- Test: `test/errors/stdlib_only_*` via `scripts/seed-error-corpus.sh`; `test/test_cap_net_scope.ml`-style case for path literals

Rename table (builtin → entry point): `print`→`IO.write`, `print_line`/`println`→`IO.puts`, `print_stderr`→`IO.warn`, `unix_time`→`System.unix_time`, `unix_time_ms`→`System.unix_time_ms`, `uuid_v4`→`UUID.v4`, `uuid_v7`→`UUID.v7`, `random_bytes`/`stdlib_random_bytes`→`Crypto.random_bytes`, `process_env`→`Process.env`, `process_set_env`→`Process.set_env`, `process_cwd`→`Process.cwd`, `process_argv`→`Process.argv`, `process_pid`→`Process.pid`, `process_exit`→`Process.exit`, `process_spawn_sync`→`Process.run`, `signal_watch`→`Signal.watch` (takes `Sig`, not `Int`: no fix), `task_spawn`→`Task.async` (arity/shape differ: no fix, suggestion only), `vault_new`→`Vault.new`, `vault_whereis`→`Vault.whereis`, `file_*`/`dir_*`→`File.*`/`Dir.*` same suffix, `dns_resolve`→`Dns.resolve`. Builtins phase 2 will wrap in handle types (`file_open`, `csv_open`, `tcp_*`, `udp_*`, `tls_*_ctx`, `http_server_*`, `process_spawn_async`) are gated **by phase 2**, not here: they stay callable, and Task 10 checks them inside their stdlib wrappers.

- [ ] **Step 1: Failing tests:** a user file calling `unix_time()` gets `stdlib_only` with the fix `System.unix_time()`; `forge fix` applies it; a user file calling `file_read("/etc/passwd")` under `needs IO.FileRead("./data/")` is rejected before and after the rename with the same path-scope diagnostic (if the wrapper hides the literal from `path_arg_builtins`, extend the check to the `File`/`Dir` entry points' first argument in this task).
- [ ] **Step 2:** FAIL → implement → PASS (`scripts/run-tests.sh errors compiler`).
- [ ] **Step 3:** Run `forge fix` path mode (Task 11; if not landed yet, land this task after it) over `test/`, `bench/`, `examples/`; Task 0's corpus run shows no file with a new error. The ~200 direct `task_spawn` calls get the suggestion only; rewrite them by hand to `Task.async` here.
- [ ] **Step 4:** Commit.

### Task 6: Console

**Files:**
- Modify: `stdlib/prelude.march:462` (`println`), `stdlib/io.march` (`write`, `puts`, `warn`, `gets`, `read_line`, `read_byte`, `inspect`), every stdlib caller of these (75 sites: `Actor`, `Recon`, `Trace`, `Dataframe`, …)
- Test: `test/stdlib/test_io_refusal.march`; `test/cap_conformance/console_*.march` (Task 13)

**Interfaces:**
- Produces: `println(x) : Result((), CapError)`; `IO.write/puts/warn(s : String) : Result((), CapError)`; `IO.read_line() : Result(String, CapError)`; `IO.read_byte() : Result(Int, CapError)`; `IO.gets(prompt) : Result(String, CapError)`; `IO.inspect(v : a) : a` **unchanged** (a debugging pass-through; on refusal it prints nothing and returns `v`).

- [ ] **Step 1: Failing tests:** `println("x") == Ok(())`; under `MARCH_TEST_REFUSE=IO.Console` it prints nothing and returns `Err(CapError("IO.Console", "stdout", Launch, "IO.Console"))`; `IO.warn` target is `"stderr"`; `IO.inspect(3) == 3` under refusal.
- [ ] **Step 2:** FAIL → implement (each body: `let? () = Authority.check("IO.Console", "stdout")`, then the raw call, then `Ok(...)`) → PASS.
- [ ] **Step 3:** Stdlib internal callers: a statement-position call needs nothing; a tail call gets `()` after it. `march --check` on every touched stdlib file shows no count above Task 0's baseline. Delete the console lines from Task 4's allowlist.
- [ ] **Step 4:** Do not migrate the corpus here (Task 14 does all of it once Task 10's diagnostic exists); land this task together with Task 14's console part if CI must stay green per commit, otherwise on the branch in order.
- [ ] **Step 5:** Commit.

### Task 7: Clock, random, UUID, and the stdlib's own reads

**Files:**
- Modify: `stdlib/system.march` (`unix_time`, `unix_time_ms`, `monotonic_time`), `stdlib/datetime.march:149`, `stdlib/uuid.march`, `stdlib/crypto.march:250`, `stdlib/random.march`, `stdlib/logger.march`, `stdlib/check.march`, cluster modules (`cluster_node`, `topology`, `net_kernel`, `swim_driver`, `cluster_load`: 32 sites)
- Test: `test/stdlib/test_clock_refusal.march`

**Interfaces:**
- Produces: `System.unix_time() : Result(Float, CapError)`, `System.unix_time_ms() : Result(Int, CapError)`, `System.monotonic_time() : Result(Int, CapError)`, `DateTime.now() : Result(DateTime, CapError)`, `UUID.v4() / v7() : Result(UUID, CapError)`, `Crypto.random_bytes(n) : Result(Bytes, CapError)`, `Crypto.random_hex(n) : Result(String, CapError)`, `Random.int(lo, hi) : Result(Int, CapError)`.
- Per-site policy for reads the caller did not ask for: `Logger` omits the timestamp field on refusal; `Crypto.hash_password` propagates (its salt is the point); `Check` (property tests) seeds from a fixed seed on refusal and says so in its report header; cluster modules propagate to their already-`Result` public entry points.

- [ ] **Step 1: Failing tests:** each producer returns `Ok` normally and `Err(CapError("IO.Clock"|"IO.Random", "", Launch, _))` under the hook; `Logger` under `IO.Clock` refusal logs a line without a timestamp; `UUID.v7` is refused by `IO.Clock`, `UUID.v4` by `IO.Random`.
- [ ] **Step 2:** FAIL → implement → PASS; `march --check` each file at or below baseline; Task 4 allowlist shrinks.
- [ ] **Step 3:** Add the missing `needs IO.Clock` to `UUID` and `Random` (they read the clock without declaring it; found by the inventory) and confirm the ceiling tests (`test_cap_ceiling`) stay green.
- [ ] **Step 4:** Commit.

### Task 8: Process, System, Env, Config

**Files:**
- Modify: `stdlib/process.march`, `stdlib/system.march`, `stdlib/env.march`, `stdlib/config.march`, callers in `stdlib/` (54 env sites)
- Test: `test/stdlib/test_process_refusal.march`

**Interfaces:**
- Produces: `type ProcessError = SpawnFailed(String) | CapRefused(CapError)` in `stdlib/process.march`;
  `Process.env(name) : Result(Option(String), CapError)`; `set_env : Result((), CapError)`; `cwd : Result(String, CapError)`; `argv : Result(List(String), CapError)`; `pid : Result(Int, CapError)`; `exit(code) : Result((), CapError)` (returns only on refusal);
  `Process.run/run_stream/spawn_async : Result(_, ProcessError)`; `System.*` mirror these; `System.cmd : Result(ProcessResult, ProcessError)`;
  `Env.get(name, default) : Result(String, CapError)`, `Env.require : Result(String, CapError)` (still panics on unset), `Env.get_int/get_bool/is_set` likewise `Result`; `Config.*` reads propagate.

- [ ] **Step 1: Failing tests:** unset variable → `Ok(None)`; refused → `Err(CapError("IO.Process", "HOME", Launch, _))`; the two are different values (narrow-capabilities §4); `Env.get("UNSET", "d") == Ok("d")`; refused `Env.get` is `Err`, not `Ok("d")`; `Process.run` refused → `Err(CapRefused(CapError(...)))` with target the program name; a non-existent program → `Err(SpawnFailed(_))`.
- [ ] **Step 2:** FAIL → implement → PASS; baseline check; allowlist shrinks.
- [ ] **Step 3:** Commit. Leave a note in the shared ocap notes folder: phase 2 reshapes `Process.spawn_async`'s handle and should keep `ProcessError`.

### Task 9: Signals, tasks, vault opens

**Files:**
- Modify: `stdlib/signal.march`, `stdlib/task.march`, `stdlib/list.march` (`pmap*`, `pfilter`, `preduce`), `stdlib/parallel.march`, `stdlib/vault.march`, `stdlib/config.march` (`new_store`), session/topology callers
- Test: `test/stdlib/test_spawn_refusal.march`, `test/stdlib/test_vault_refusal.march`

**Interfaces:**
- Produces: `Signal.watch(s, h) : Result((), CapError)`, `Signal.raise(s) : Result((), CapError)`, `Signal.unwatch` unchanged;
  `Task.async(f) : Result(Task(a), CapError)`; `Task.async_stream(xs, f)` / `async_stream_n` : `Result(_, CapError)` (refused before any spawn);
  `List.pmap/pmap_n/pfilter/preduce`, `Parallel.pmap_n/preduce_n`: types unchanged, sequential on refusal;
  `Vault.new(name) / open(name) : Result(Vault(v), CapError)`, `Vault.whereis(name) : Result(Option(Vault(v)), CapError)`, `Vault.ns_set/ns_drop : Result((), CapError)`, `Vault.ns_get : Result(Option(v), CapError)`; every other `Vault.*` unchanged (uses of a handle).

- [ ] **Step 1: Failing tests:** `Task.async` refused under `IO.Spawn` → `Err(CapError("IO.Spawn", "", Launch, _))`; `List.pmap([1,2,3], fn x -> x * 2)` under refusal `== [2,4,6]`; `Vault.new("t")` refused under `IO.Mut` with target `"t"`; `Vault.set` on a handle obtained before is unaffected by the hook (impossible within one process today, so assert it on the type: `Vault.set` still returns `()`); `Signal.watch` refused target is `"SIGUSR1"`.
- [ ] **Step 2:** FAIL → implement → PASS; baseline; allowlist shrinks.
- [ ] **Step 3:** Commit.

### Task 10: Files, directories, CSV, network: the `CapRefused` variants

**Files:**
- Modify: `stdlib/file.march:13` (`ptype FileError` gains `CapRefused(CapError)` **last**, so the runtime-built tags `0..4` do not move), `stdlib/dir.march`, `stdlib/csv.march:26`, `stdlib/seq.march`, `stdlib/socket.march`, `stdlib/udp.march`, `stdlib/tls.march`, `stdlib/dns.march`, `stdlib/http_transport.march`, `stdlib/http_client.march` (both `TransportError`s; `HttpError` loses `OutOfScope`, `MethodRefused`, `PathRefused` and gains `CapRefused(CapError)`; the scope guard at `http_client.march:477-510` builds `CapRefused(CapError(..., ModNeeds(<module>), <spec>))`), `stdlib/http.march:984` (`ScopeRefusal` stays internal), `stdlib/http_server.march`
- Test: `test/stdlib/test_file_refusal.march`, `test/stdlib/test_net_refusal.march`; existing host-scope tests (`test_cap_net_scope.ml`, path-scope suites) updated to the new variant

**Interfaces:**
- Produces: each listed error type gains `CapRefused(CapError)`; `File.exists(path) : Result(Bool, CapError)`, `Dir.exists : Result(Bool, CapError)`; `HttpServer.listen(server) : Result((), CapError)`, `HttpServer.spawn_n : Result(Int, CapError)`, `HttpServer.bind_host : Result((), CapError)`; every other public function keeps its `Result(T, E)` type and now returns `Err(CapRefused(...))` on refusal. Target strings: the path (`file_rename`/`file_copy` check both, source first), `host:port` for connects and UDP destinations, `addr:port` for listens.

- [ ] **Step 1: Failing tests:** `File.read("x")` under `IO.FileRead` refusal → `Err(CapRefused(CapError("IO.FileRead", "x", Launch, _)))` (outer: the `FileError` variant, inner: the `CapError` value); `File.copy("a","b")` under `IO.FileWrite` refusal names `"b"`; `Socket.connect("example.com", 80)` under `IO.NetConnect` → `Err(CapRefused(_))` without opening a socket (assert with a listener in the test that counts accepts: zero); a host-scoped `HttpClient.get` outside its scope → `Err(CapRefused(CapError("IO.NetConnect", "foo.com/", ModNeeds("M"), "example.com")))`; the existing `test_cap_net_scope` expectations move from `OutOfScope(h)` to that.
- [ ] **Step 2:** FAIL → implement → PASS (`scripts/run-tests.sh stdlib stdlib_march compiler`); baseline; allowlist shrinks to the reasoned `Internal` rows only.
- [ ] **Step 3:** Non-exhaustive matches on these types in `stdlib/` gain a `CapRefused(e)` arm that propagates; count corpus matches with Task 0's tooling and list them for Task 14.
- [ ] **Step 4:** Commit. Note for phase 2 in the shared folder: `file_open`, `csv_open`, `tcp_*`, `udp_*`, `tls_*_ctx`, `http_server_*`, `process_spawn_async` are checked in their wrappers but **not** gated; phase 2 gates them when it introduces the handle types, and its new opens must call `Authority.check`.

### Task 11: `cap_result_unhandled` diagnostic, its fixes, and `forge fix` on plain paths

**Files:**
- Modify: `lib/errors/code.ml` (new code `cap_result_unhandled`), `lib/errors/explain.ml` (page), `lib/typecheck/typecheck_unify.ml` (`report_mismatch`: when actual is `Result(t, CapError)` and `t` unifies with expected, emit this code instead of `type_mismatch`, with the fix of Decision 4), the block-tail detection where the checker knows the expression is a block's last element (`lib/typecheck/typecheck.ml`, the `EBlock` arm)
- Modify: `forge/lib/cmd_fix.ml` (`forge fix [--dry-run] PATH...`: with paths, skip `Project.load` and fix the given `.march` files or directories; repeat collect-and-apply until a pass applies zero fixes, at most 5 passes), `forge/bin/main.ml`
- Test: `test/errors/cap_result_unhandled_{1,2,3,4}.march` via `scripts/seed-error-corpus.sh`; `forge/test/test_fix_cap_result.ml` with `forge/test/fixtures/cap_result/{before,after}/`

**Interfaces:**
- Consumes: `CapError` (Task 1), the re-typed entry points (Tasks 6–10).
- Produces: fixes, all `machine-applicable`: `FInsert` of `<indent>()` after the line (block tail); `FReplace` to `Authority.ignore(<expr>)` (other unit positions); `FReplace` to `Authority.must(<expr>)` (value positions). The expression's source text comes from its span.

- [ ] **Step 1: Failing corpus cases:** (1) `fn main() : () do println("x") end` across lines → fix inserts `()`; (2) `match o do Some(v) -> println(v) None -> () end` → `Authority.ignore(println(v))`; (3) `let t = System.unix_time_ms() + 1` → `Authority.must(System.unix_time_ms()) + 1`; (4) `match Process.env("H") do Some(v) -> v None -> "" end` → scrutinee wrapped in `must`. Each `.expected` shows the fix diff.
- [ ] **Step 2:** `ERRORS_ONLY=cap_result_unhandled ./_build/default/test/run_errors.exe -e` → FAIL.
- [ ] **Step 3:** Implement; `UPDATE_ERRORS=1` for the four new cases only; review the diff; `git diff test/errors/` shows no other case changed.
- [ ] **Step 4: forge tests:** fixture `before/` (one file per shape above plus an unannotated helper whose `Result` reaches a `: ()` caller) → `forge fix before/` → equals `after/` byte for byte; a second run reports "no auto-fixable diagnostics found"; the result typechecks (`--check` empty). Run `forge/test/run_cases_parallel.sh` or the forge dune test.
- [ ] **Step 5:** Commit.

### Task 12: REPL echo and doctests

**Files:**
- Modify: the REPL's value echo (find where `lib/repl/repl.ml` suppresses `()`; the JIT REPL path in `lib/jit/` too) and `lib/doctest/doctest.ml` if it echoes separately
- Test: `test/test_jit.ml` / REPL tests; a doctest in `stdlib/authority.march`

**Interfaces:**
- Produces: an expression of type `Result((), CapError)` whose value is `Ok(())` echoes nothing, exactly as `()` does; `Err(e)` echoes `Err(<describe e>)`.

- [ ] **Step 1: Failing tests:** REPL input `println("hi")` prints `hi` and no `Ok(())`, interpreted and JIT; a doctest `march> println("x")` expecting `x` passes.
- [ ] **Step 2:** FAIL → implement → PASS (`scripts/run-tests.sh test_jit eval`, with `MARCH_BIN` set as the script does).
- [ ] **Step 3:** `node scripts/browser-repl-smoke.js` after `scripts/build-browser-repl.sh` into a scratch dir (do not commit the bot-owned output): the smoke's `println` cases echo no `Ok(())`.
- [ ] **Step 4:** Commit.

### Task 13: Refusal conformance on every backend

The seed of §15's conformance suite; phase 4 extends it rather than starting one.

**Files:**
- Create: `test/cap_conformance/<case>.march` + `<case>.expected` (one per kind: console, clock, random, env, process run, signal, spawn, vault open, file read, file write, net connect, net listen, dns, tls ctx), `test/run_cap_conformance.ml` (suite `cap_conformance` in `scripts/run-tests.sh` and `scripts/test-affected.sh`)

**Interfaces:**
- Each case's header line `-- REFUSE: IO.Clock` is the `MARCH_TEST_REFUSE` value. The runner executes it interpreted, `--compile`, `--jit` and `--target js` under node, and requires all four outputs equal `.expected` (pattern: `test/run_test_reports.ml`, including its `js_unsupported` list with reasons).

- [ ] **Step 1:** Write the cases (each prints `Authority.describe(e)` of the refusal it provokes, then one allowed operation of another kind to show it still works) and the runner → FAIL until the runner exists → PASS.
- [ ] **Step 2:** Prove the runner goes RED: flip one backend (make the JS shim always allow) and see the case fail naming the backend; revert.
- [ ] **Step 3:** Register in CI (`.github/workflows/README.md` names the job) and in `scripts/test-affected.sh` rules for `runtime/march_cap_check.*`, `lib/eval/eval_cap.ml`, `stdlib/authority.march`.
- [ ] **Step 4:** Commit.

### Task 14: Migrate the repository

Large and mostly mechanical. Split commits by tree so a reviewer can read each.

**Files:** `test/**/*.march`, `bench/*.march`, `examples/**`, `test/*.ml` and `lsp/test/*.ml` embedded sources, golden files (`test/snapshots/`, `test/errors/`, `test/test_reports/`, `test/test_codegen.ml` preambles), `specs/lang/*.md` code samples, `.claude/skills/march-lang/SKILL.md`

- [ ] **Step 1:** `forge fix test/ bench/ examples/` (Task 11's path mode). Then rerun Task 0's corpus check: no file has an error that the baseline did not. Expected order of magnitude: 366+ files.
- [ ] **Step 2:** Hand-fix what has no machine fix: non-exhaustive matches from Task 10 Step 3, direct `task_spawn` calls, programs whose `.expected` output now differs. Commit per tree.
- [ ] **Step 3:** Embedded sources in `.ml` tests: run each suite, fix by the same rules, commit per suite (`compiler`, `eval`, `codegen`, `stdlib`, `test_jit`, `lsp`). LSP hover/signature tests that pin `println`'s type move to the new type.
- [ ] **Step 4:** Goldens: `UPDATE_SNAPSHOTS=1`, `UPDATE_ERRORS=1`, `UPDATE_TEST_REPORTS=1` and review each `git diff`: every change must be a `println`/entry-point type or an added `()`/`Authority.*`; anything else is a bug to fix, not to accept.
- [ ] **Step 5:** Docs: `specs/lang/capabilities.md` and `capability-enforcement.md` gain a "Refusals" section (CapError, `Authority.must/ignore`, the error-type variants, the test hook as test-only); every sample that calls a re-typed function is updated; `scripts/gen-lang-docs.py`; `scripts/check-docs.sh`. Update the `march-lang` skill (println returns a `Result`; `Authority.must`).
- [ ] **Step 6:** Commit.

### Task 15: Verification, benchmarks, changelog, specs bookkeeping

- [ ] **Step 1:** `scripts/run-tests.sh` (full) green; `scripts/run-tests.sh refinecheck` with z3 on PATH; `cap_conformance` green.
- [ ] **Step 2:** Task 4's allowlist holds only `Internal` rows with reasons; the stdlib per-file `--check` counts are at or below Task 0's.
- [ ] **Step 3:** `scripts/oracle-base.sh ir types`: both RED by design. Review the IR diff on a sample of 20 programs: the only changes are a `march_cap_check_raw` call before each checked operation and the `Result` construction; review the types diff: only re-typed entry points. Write the summary into the PR description.
- [ ] **Step 4:** Benchmarks from Task 0, same machine, `scripts/` load check first (other sessions' load makes numbers lie): `list_ops`, `binary_trees` within noise; `println_loop`, `clock_loop`, `spawn_loop` within 5%. If `println_loop` is worse because `Ok(())` allocates, make `Ok(())` of `Result((), _)` a static constant in codegen (one task, its own commit) before accepting.
- [ ] **Step 5:** `CHANGELOG.md` `## [Unreleased]` `### Changed`: capability operations return `Result`; the list of re-typed entry points; `forge fix` migrates; `HttpError`'s three refusal variants became `CapRefused`. `specs/progress/2026-11-10-ocap-p1-result.md` (what landed, the decisions above, the measured blast radius); delete the baseline note; `specs/todos/2026-11-10-unused-cap-result-lint.md` (Decision 7); `specs/todos/2026-11-10-ocap-p2-gate-handle-builtins.md` (the builtins Task 5 left callable, for phase 2).
- [ ] **Step 6:** Commit.

---

## Execution order and parallelism

Tasks 0 → 1 → 2 → 3 → 4 are sequential. Tasks 6, 7, 8, 9, 10 each touch their own stdlib files and
can run in parallel after 4 (they share Task 4's allowlist file: each deletes only its own lines).
Task 11 depends on 1 and needs at least Task 6 to test against; Task 5 needs 11's path mode.
Tasks 12 and 13 need 2 and 6. Task 14 needs everything before it; Task 15 is last. The branch is red
between Task 6 and Task 14 unless each family's corpus migration is folded into its own task; if CI
must stay green per merged PR, ship Tasks 0–5 + 11 as one PR (no type changes yet), then one PR per
family (6–10) each carrying its share of Task 14, then 12, 13 and 15.

## Overlap with the other phase sessions

- **Phase 2 (handles)** edits the same stdlib files for `file_open`, `csv_open`, sockets, listeners,
  processes and vault opens. This plan only adds `Authority.check` calls and `CapRefused` variants
  there and leaves gating of handle builtins to phase 2. Whichever lands second rebases; the
  conflict is textual.
- **Phase 3 (compile-time checks under `--check`, interpreter, REPL)** changes when the existing
  ceiling diagnostics run; it does not touch run-time checks. The new `cap_result_unhandled`
  diagnostic is a type error and already runs everywhere types are checked.
- **Phase 4** replaces `MARCH_TEST_REFUSE` with launch narrowing, makes `cap_check_raw` consult the
  current authority, adds non-zero limit codes, and extends `test/cap_conformance/`.
