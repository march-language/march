# Object capabilities, phase 2: handles, stdlib-only raw builtins, checked name lookups

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every operation that opens a file, directory, connection, listener or child process returns an unforgeable handle that needs no capability to use. The raw integer builtins behind them become stdlib-only. Finding or registering a table or an actor by name becomes a checked operation.

**Architecture:** There is one new runtime cell, the *handle box*. It is reference-counted and holds the raw descriptor, a kind, and an atomic state word (a closed bit plus an in-flight count). The cell is the same in the C runtime and, as an OCaml record, in the interpreter. Five builtin type constructors (`File.Handle`, `File.Dir`, `Socket`, `Listener`, `Process`) name it to the type checker the way `Vault` and `IO.Console` do, so user code cannot build one. The stdlib wraps the existing raw `Int` builtins: each use enters the box (refused once closed), calls the raw builtin, and leaves. The raw builtins and the stdlib's own fd-taking plumbing then become stdlib-only. Handle *uses* leave `builtin_cap_table`, so they charge nothing; the opens stay charged. A new `IO.Registry` kind, and name scopes on `IO.Registry` and `IO.Mut`, make lookups by name checked.

**Tech Stack:** OCaml 5.5.1 (typecheck, TIR, interpreter), C runtime (`runtime/*.c`), March stdlib (`stdlib/*.march`), menhir grammar plus the tree-sitter grammar for the scope syntax.

**Spec:** `specs/2026-11-10-object-capability-design.md`: §6 (handles), §7 (pids), §15 (files), §17 (phase 2), §18 (Handles bullet), §20. Name scopes come from `specs/2026-11-09-narrow-capabilities-design.md` §8 (`IO.Mut("name")`).

## Global Constraints

- Handle types are exactly `File.Handle`, `File.Dir`, `Socket`, `Listener`, `Process` (spec §6). None may be spelled `Handle` alone: the stdlib's typestate `Handle(r, s)` (`stdlib/handle.march`) is registered under the bare name `"Handle"` and is `always_linear`. A nested `type Handle` inside `mod File` would inherit that linearity (`lib/typecheck/typecheck.ml:9288`, `resolves_always_linear` in `lib/typecheck/typecheck_env.ml:1358`).
- Representation: "a reference-counted box holding the descriptor and a closed flag. A use after close returns `Err`." (spec §6)
- "The raw integer builtins become stdlib-only (the existing `check_stdlib_only_refs` gate)." (spec §6). That gate is now inline at variable resolution, in `lib/typecheck/typecheck.ml:2787`, driven by `stdlib_only` in `lib/typecheck/typecheck_env.ml:2295`. The function name `check_stdlib_only_refs` survives only in stale comments.
- "Using the handle needs no `needs` line and no check against the current authority: the open was checked." (spec §6)
- "Path-based conveniences stay (`File.read(path)`, `File.write(path, s)`)." (spec §6)
- `File.open_in(dir, rel)` "opens beneath `dir` with no `needs`, refusing any path that leaves it" (spec §6). Linux: `openat2(RESOLVE_BENEATH)`. macOS: "`realpath` plus `O_NOFOLLOW` (best effort, documented)" (spec §15).
- "Handles are not sendable to another node. Within a node, sending a handle in a message shares it." (spec §6)
- "`Vault.whereis("sessions")` is checked against `IO.Mut("sessions")`". "`actor_whereis`, `actor_register` and `actor_registered` are checked against a new kind `IO.Registry("name", prefix("..."))`" (spec §6).
- Breaking changes ship with a `### Changed` CHANGELOG entry and, where the rewrite is mechanical, a machine fix that `forge fix` applies (spec §17).
- Repo rules (CLAUDE.md):
  - Run `dune build --root .` and `scripts/run-tests.sh` inside the worktree.
  - Stage files by explicit path. No `git add -A` or `git add .`, and no bare `git stash`.
  - Move `specs/todos/` → `specs/progress/` in the commit that closes an item.
  - Edit `specs/lang/`, then regenerate `docs/` with `scripts/gen-lang-docs.py`.
  - A new `test/native/*.march` fixture also updates `test/refine_audit/corpus.baseline`.
  - A grammar change also updates `tree-sitter-march/grammar.js`.
  - A new runtime `.c` file needs a line in `runtime/sources.list`.

## Decisions this plan makes (builder's, per spec §20)

1. **One runtime box, five type names.** The box kind is a small integer:

   | Kind | Constant |
   |---|---|
   | FILE | 1 |
   | DIR | 2 |
   | TCP | 3 |
   | TCP_BORROWED | 4 |
   | LISTENER | 5 |
   | UDP | 6 |
   | TLS | 7 |
   | TLS_CTX | 8 |
   | PROCESS | 9 |

   `Udp.UdpSocket`, `Tls.TlsConn`, `Tls.TlsCtx` and `WebSocket.WsSocket` become `opaque type`s over a `Socket` box of the matching kind. Today their constructors are public (`type UdpSocket = UdpSocket(Int)`), so they are forgeable.
2. **The stdlib wraps; the raw builtins stay.** No existing raw builtin changes type, ABI, borrow mode or C symbol. The new builtins are seven polymorphic, stdlib-only primitives: `handle_new`, `handle_enter`, `handle_leave`, `handle_close`, `handle_detach`, `handle_is_closed` and `handle_aux` (Task 2). This keeps the C HTTP event loop, the cluster stack and every backend's raw table as they are.
3. **Close and in-flight.** `handle_enter` atomically increments the in-flight count unless the closed bit is set. `handle_close` sets the bit. The raw descriptor is released either by the `handle_leave` that brings the count to zero, or by `handle_close` itself when the count is already zero. Sockets also get `shutdown(SHUT_RDWR)` at `handle_close`, so a reader parked in `recv` wakes. A box freed with the descriptor still open (never closed, or a panic stranded an in-flight count) releases it in its destructor. A descriptor is therefore never reused while a use is in flight, and is released exactly once.
4. **Stdlib plumbing that takes `fd : Int` gets a new attribute, `@[stdlib_internal]`.** This covers the cluster stack, `HttpServer.fd`, and `ClusterConn`. The attribute extends the stdlib-only gate from builtins to stdlib functions. The cluster stack keeps its raw fds: cluster peers are trusted (spec §2, non-goals), and converting it would touch about 40 functions for no authority gain.
5. **`File.open` is split by mode**, so the stdlib-mediated ceiling charges `IO.FileWrite` only to writers:
   - `File.open(path)` reads (`IO.FileRead`).
   - `File.open_write(path, mode)` with `WriteMode = Truncate | Append` writes (`IO.FileWrite`).

   The directory opens split the same way: `File.open_dir` (read-only) and `File.open_dir_write`.
6. **Errors.** `FileError` gains `Closed`, `SocketError` gains `Closed`, and `Process` operations return `Result(_, ProcessError)` with `Closed | ProcessFailed(String)`. A use after close is `Err(Closed)` on every backend.
7. **Out of scope** (not in this phase's row of spec §17):
   - `Actor.pid_from_int` as an `Actor.Introspect`-kind operation is phase 7. `pid_of_int` is already stdlib-only.
   - Retiring `Cap(Actor.Introspect)` parameters is phase 7. `Actor.whereis(c, name)` keeps its parameter here and additionally becomes charged `IO.Registry`.
   - There is no `Library` handle (owner, 2026-11-10; question 1 below). A foreign call is checked per call against `IO.Foreign` and its symbol scopes, the same way console and environment access are. The check is compile-time today and also run-time from phase 4. Narrowed access is handed out as closures (spec §5). This phase builds nothing for foreign libraries.
   - The listen-address parameter is narrow-capabilities §6.
   - Vault *write* scopes are narrow-capabilities §8. This phase checks only the by-name lookups.

## Landing order with phase 1 (Result everywhere) and phase 3 (compile-time checks)

- **Phase 1 first.** Phase 1 changes the types of the operations that return a plain value today: console, clock, random, spawn, the `IO.Mut` table operations and signal registration (superseded design, "Every capability operation returns a `Result`"). Phase 2 changes no such type. The overlaps:
  - The `IO.Mut` lookups (`Vault.new`, `Vault.whereis`): phase 2 only adds a name-scope check, so it rebases onto whatever result type phase 1 gave them.
  - `FileError`, `SocketError`: if phase 1 adds a refusal variant (for example `Refused(CapError)`), phase 2's `Closed` variant sits beside it. The two are independent, so a rebase is a one-line merge in each `ptype`.
- **Phase 2 first.** Nothing in phase 2 depends on phase 1. Phase 1 then has fewer operations to convert: handle uses carry no capability after Task 10, so they are not "capability operations", and phase 1 must not wrap them in `Result(_, CapError)`.
  - **Handover note for phase 1:** leave in `specs/todos/` the list of builtins Task 10 removes from `builtin_cap_table`.
- **Phase 3.** Phase 3 edits the cap-checking code (`lib/typecheck/typecheck_caps.ml`, `check_stdlib_mediated_ceiling`). Phase 2 edits mostly data:
  - `builtin_cap_table`, `Cap_symbols.table`, `cap_infer`;
  - `path_arg_builtins` (Task 10), and the new `name_arg_fns` table from Task 12.

  The one shared seam is the literal-argument scan (`literal_path_uses`, `typecheck_caps.ml:243`), which Task 12 generalises. Whichever phase lands second takes the other's table rows.
- **Shared grammar.** Task 11 changes `scoped_cap_path` in `lib/parser/parser.mly` so a scope accepts several strings and string-valued options. The narrow-capabilities forms (`IO.Exec("rg", "fd")`, `IO.Env(prefix("WEATHER_"))`) need the same change. If someone lands it first, Task 11 shrinks to its name-scope semantics.

## Review Focus

1. **Close racing a parked reader.** One green thread is parked in `Socket.recv(s, …)` while another calls `Socket.close(s)`, on a different scheduler thread. The reader returns `Err(Closed)` promptly, and the descriptor number is not reused by a later open while the reader's in-flight count holds it. *(Task 1 C test `close_wakes_and_defers_release`; Task 6 native fixture `socket_close_while_recv`.)*
2. **Drop without close, and close then drop.** 10 000 open/drop and open/close/drop iterations keep the process's open-descriptor count flat, and no descriptor is closed twice. Today's leak probe, `test/native/file_handle_leak_probe.march`, is the model. *(Task 1 C test `release_exactly_once`; Task 5 fixture `file_handle_box_leak_probe`.)*
3. **Generic code meeting a handle.** Each of these must not crash:
   - `to_string`, `println(inspect(h))` or string interpolation of a handle;
   - storing it in a `List`, a `Map` value or a record;
   - sending it to a local actor and using it there;
   - comparing two handles with `==`.

   `==` is a type error with a clear message, or identity; this plan picks the type error. *(Task 2 tests `handle_in_generic_containers` and `handle_eq_is_type_error`; Task 6 fixture `socket_sent_to_local_actor`.)*
4. **Escaping a directory.** `File.open_in(dir, rel)` must refuse each of these rather than escape:
   - `rel` of `""`, `"."`, `"a/../.."`, `"/etc/passwd"`, `"a//b"`, or one containing a NUL byte;
   - a symlink chain whose second link leaves the directory;
   - the directory renamed or removed after `open_dir`.

   A symlink that stays inside is allowed on Linux. *(Task 7 tests.)*
5. **Interpreter and compiled binary disagree on an error.** The same program prints the same text in both for each of: use after close, double close, close of a never-opened (detached) handle, and `open_in` refusal. *(Task 15 parity sweep; each fixture runs under both, as `test/test_oracle.ml` does.)*

---

## File structure

| File | Responsibility |
|---|---|
| `runtime/march_handle.c` (new), `runtime/march_runtime.h` | Box layout, `MARCH_HANDLE_TAG`, kinds, enter/leave/close/detach, destructor by kind |
| `runtime/march_runtime.c` | Free path calls the handle destructor; `march_value_to_string` renders a box |
| `runtime/march_file_beneath.c` (new) | `march_file_open_at` / `march_dir_list_at`: beneath-only resolution for Linux and macOS |
| `lib/eval/eval_handle.ml` (new), `lib/eval/eval_types.ml` | Interpreter `VHandle` record and the same seven primitives |
| `lib/eval/eval_beneath_stubs.c` (new) | OCaml C stub over `march_file_beneath.c` for the interpreter |
| `lib/typecheck/typecheck_builtins.ml` | Handle type constructors, primitive types, cap-table edits, `IO.Registry` |
| `lib/typecheck/typecheck_env.ml`, `typecheck.ml` | `stdlib_only` rows; the `@[stdlib_internal]` gate |
| `lib/tir/llvm_builtins.ml`, `lib/tir/borrow.ml`, `lib/tir/kind.ml` | Codegen rows, borrow modes, boxed representation |
| `lib/caps/cap_lattice.ml`, `lib/caps/name_scope.ml` (new), `lib/caps/cap_scope.ml` | `IO.Registry`; name-scope algebra; scopability |
| `lib/parser/parser.mly`, `tree-sitter-march/grammar.js` | Multi-string scopes and string-valued scope options |
| `stdlib/file.march`, `socket.march`, `process.march`, `udp.march`, `tls.march`, `websocket.march`, `http_transport.march`, `http_client.march`, `http_server.march`, `actor.march`, `vault.march`, and the cluster modules | Public handle API; internal marking |

---

### Task 1: The handle box in the C runtime

**Files:**
- Create: `runtime/march_handle.c`
- Modify: `runtime/march_runtime.h`
  - after `MARCH_CLOSURE_TAG` (line ~365): `#define MARCH_HANDLE_TAG ((int32_t)-10)`, the kind constants, and the prototypes.
- Modify: `runtime/march_runtime.c`
  - `march_run_resource_dtor_slow` (line ~618): add a `MARCH_HANDLE_TAG` arm that calls `march_handle_dtor(p)`.
  - `march_value_to_string`: render `#<File.Handle>` and similar by kind, with `closed` appended when the closed bit is set.
- Modify: `runtime/march_message.c` `copy_value`: a handle cell is shared (rc+1, same pointer), never byte-copied. `march_msg_copy` has no caller today; this only closes the latent hole.
- Modify: `runtime/sources.list` (one line: `march_handle.c` with the role the other core files use), and every link list `scripts/check-runtime-sources.sh` names.
- Create: `test/test_handle.c`, plus a runner rule in `test/dune` modelled on `test_free_dtor` (`test/dune:530-557`).

**Interfaces:**
- Produces, in C:
  - `void *march_handle_new(int64_t kind, int64_t raw, int64_t aux)`: a 48-byte cell, rc 1. Layout: `[rc][tag=MARCH_HANDLE_TAG][pad=kind][raw@16][aux@24][state@32 (_Atomic int64)][pad@40]`.
  - `int64_t march_handle_enter(void *h, int64_t kind)`:
    - returns `raw`, with the in-flight count incremented;
    - returns `-1` when the closed bit is set;
    - calls `march_fatal` when `h` is not a handle cell or its kind differs. TCP and TCP_BORROWED both satisfy an expected TCP.
  - `void march_handle_leave(void *h)`: decrements; if that reaches 0 with the closed bit set and the descriptor not yet released, releases it.
  - `int64_t march_handle_close(void *h)`: returns 1 if this call set the closed bit, 0 if it was already set. Releases now if in-flight is 0, else defers to the last leave. For TCP, LISTENER and UDP it calls `shutdown(raw, SHUT_RDWR)` first.
  - `int64_t march_handle_detach(void *h)`: sets the closed bit *and* the released bit without releasing, and returns `raw` (−1 if already closed). Used when ownership moves (TCP → TLS, server conn → WebSocket).
  - `int64_t march_handle_is_closed(void *h)`, `int64_t march_handle_aux(void *h)`.
  - `void march_handle_dtor(void *h)`: releases if not yet released.
- Release by kind:

  | Kind | Release |
  |---|---|
  | FILE | `march_file_close((void*)raw)` |
  | DIR | `close(raw)` |
  | TCP, LISTENER | `march_tcp_close(raw)` |
  | UDP | `march_udp_close(raw)` |
  | TLS | `march_tls_close(raw)`, then `march_tcp_close(aux)` |
  | TLS_CTX | `march_tls_ctx_free(raw)` |
  | PROCESS | release the child's stream slot `raw` the way `march_process_wait_proc` does after reaping. Check the slot lifecycle at `runtime/march_runtime.c:12752-12860`. Do not kill the child. |
  | TCP_BORROWED | nothing (the HTTP event loop owns the descriptor) |

- The state word: bit 0 is closed, bit 1 is released, and bits 2 and up hold the in-flight count. Every transition is a CAS loop. "Released" is set by exactly one thread, through a CAS from (closed, in-flight 0, not released), so the descriptor is closed exactly once.

- [ ] **Step 1: Write the failing C tests** in `test/test_handle.c`. Use real descriptors from `pipe()` and `socketpair()`; check "released" with `fcntl(fd, F_GETFD) == -1 && errno == EBADF`.
  - `enter_after_close_refused`: `march_handle_enter` returns `-1` after `march_handle_close`.
  - `close_twice`: the first close returns 1, the second 0; the fd is released once.
  - `close_wakes_and_defers_release`: a pthread does `enter`, then a blocking `recv` on one end of a `socketpair`. The main thread closes the handle. The recv returns ≤ 0 within 1 s; the fd is still valid until that thread calls `leave`, and invalid after.
  - `release_exactly_once`: 8 threads each run 100 000 enter/leave cycles while a ninth closes. The count of release calls is 1. Route release through a test hook `march_handle_test_release_hook`.
  - `dtor_releases_unclosed`: dropping the last reference (`march_decrc`) to an unclosed box releases its fd.
  - `detach_does_not_release`: detach returns `raw`, the fd stays open, and the destructor does not close it.
  - `kind_mismatch_is_fatal`: install the fatal hook as `test/test_fatal_hook.c` does, and assert it fires.
- [ ] **Step 2: Run them; they fail to link**
  Run: `dune build --root . @test/test_handle 2>&1 | tail -5` (or the alias name the rule declares).
  Expected: undefined `march_handle_new`.
- [ ] **Step 3: Implement `runtime/march_handle.c`, the header additions and the three hook-ins above.**
- [ ] **Step 4: Run the C tests and the runtime checks**
  Run: `dune build --root . @test/test_handle && scripts/check-runtime-sources.sh && scripts/check-actor-rc-stores.sh`
  Expected: all pass.
- [ ] **Step 5: Commit**
  ```bash
  git add runtime/march_handle.c runtime/march_runtime.h runtime/march_runtime.c runtime/march_message.c runtime/sources.list test/test_handle.c test/dune
  git commit -m "runtime: reference-counted handle box with closed flag and in-flight count"
  ```

### Task 2: Handle types and primitives in the type checker, the backends and the interpreter

**Files:**
- Modify: `lib/typecheck/typecheck_builtins.ml`
  - `builtin_types` (line ~2062): add `("File.Handle", 0); ("File.Dir", 0); ("Socket", 0); ("Listener", 0); ("Process", 0)`.
  - Add the seven primitive types to `builtin_bindings` (line ~1170).
  - `qualified_type_builtins` (line ~2006): add `File.Handle` and `File.Dir` if the `Csv.CsvRow` precedent requires it. Step 1's first test decides.
- Modify: `lib/typecheck/typecheck_env.ml` `stdlib_only` (line 2295): add the seven primitives, with the hint "handles are made by their module's open functions".
- Modify: `lib/tir/llvm_builtins.ml`: seven rows (`march_name`, `c_name`, `ret_ty`, `declare_sig`). `handle_new` returns `ptr`; enter, close, detach, is_closed and aux return `i64`; leave returns `void`.
- Modify: `lib/tir/borrow.ml` `extern_borrow_table`: every primitive borrows its handle argument (`[true; false]` and so on). Argument 0 of `handle_new` is an Int, so `false`.
- Modify: `lib/tir/kind.ml` `c_boxed_types` (line 76): add the five type names, so the TIR treats them as boxed pointers with RC.
- Modify: `lib/caps/cap_symbols.ml`: no rows. The primitives carry no capability. Confirm the freshness test `test/test_cap_symbols.ml` agrees.
- Create: `lib/eval/eval_handle.ml`. Modify `lib/eval/eval_types.ml`, adding `VHandle of handle_cell`:
  ```ocaml
  type handle_cell = {
    h_kind : int;
    h_raw : value;
    h_aux : value;
    mutable h_closed : bool;
    mutable h_released : bool;
    h_release : unit -> unit;
  }
  ```
  Register the primitives in `lib/eval/eval_builtins.ml`, and give the printer a `VHandle` arm.
  - The interpreter's `handle_new` takes its `h_release` closure from a per-kind table in `eval_handle.ml`. That table calls the interpreter's existing implementations of `file_close`, `tcp_close`, `udp_close`, `tls_close` and `tls_ctx_free`.
  - Use `Gc.finalise` to release an unclosed handle. Release timing therefore differs from the compiled binary; no parity test may depend on when a dropped handle is released.
- Test: `test/test_stdlib_only.ml` (gate), `test/test_compiler.ml` (types), `test/test_eval.ml` (interpreter primitives), `test/test_codegen.ml` (compiled primitives).

**Interfaces:**
- Consumes: Task 1's C symbols.
- Produces, in the type checker:
  ```
  handle_new       : Int -> Int -> Int -> a        -- kind, raw, aux; the stdlib annotates the result
  handle_enter     : a -> Int -> Int               -- handle, expected kind; -1 when closed
  handle_leave     : a -> ()
  handle_close     : a -> Bool                     -- true when this call closed it
  handle_detach    : a -> Int                      -- raw, or -1 when already closed
  handle_is_closed : a -> Bool
  handle_aux       : a -> Int
  ```
- Produces, in the stdlib: `pfn`-level kind constants are not expressible as named constants, so the stdlib passes these literals: 1 FILE, 2 DIR, 3 TCP, 4 TCP_BORROWED, 5 LISTENER, 6 UDP, 7 TLS, 8 TLS_CTX, 9 PROCESS. Every stdlib call site carries a `-- kind TCP` comment.

- [ ] **Step 1: Write the failing tests**
  - `test_compiler.ml` `handle_type_names_resolve`: `fn f(h : File.Handle) : File.Dir do f(h) end` resolves both names, and `Int` does not unify with `Socket`. Expect the error to contain "Socket" and "Int".
  - `test_compiler.ml` `file_handle_is_not_linear`: a user module using a `File.Handle` value twice typechecks with no linearity error. This is the typestate-`Handle` collision guard.
  - `test_compiler.ml` `handle_eq_is_type_error`: `h1 == h2` for two `Socket` values is a type error.
  - `test_stdlib_only.ml` `handle_primitives_gated`: user code calling `handle_new(3, 0, 0)` gets `stdlib_internal`, and its message names "handles are made by".
  - `test_eval.ml` and `test_codegen.ml` `handle_primitive_roundtrip`: run with the fixture registered as stdlib (as `test_stdlib_only.ml:26` does). Make a TCP_BORROWED box (kind 4, so release is a no-op) over raw `7`, enter, leave, close, then enter again. Expected output: `[7, true, -1, false]` (raw, first close, enter after close, second close). Identical on both. A raw descriptor is never `-1`, so `-1` is free to mean "closed".
  - `test_eval.ml` and `test_codegen.ml` `handle_in_generic_containers`: a `List(Socket)`, a `Map(String, Socket)` value and a record field holding a box are printed with `inspect`. The output contains `#<Socket>` and does not crash.
- [ ] **Step 2: Run them; they fail**
  Run: `scripts/run-tests.sh -q compiler eval codegen`
  Expected: the new cases FAIL (unknown type `File.Handle`, unbound `handle_new`).
- [ ] **Step 3: Implement the rows and the interpreter module listed above.**
- [ ] **Step 4: Run them; they pass, and the table-agreement suites stay green**
  Run: `scripts/run-tests.sh -q compiler eval codegen stdlib && scripts/run-tests.sh test_jit`
  Expected: PASS. `test_builtin_borrow_classification` and `test_builtin_compiled_lowering` include the new rows.
- [ ] **Step 5: Commit** the files above, with message `typecheck,tir,eval: handle types and stdlib-only handle primitives`.

### Task 3: `@[stdlib_internal]`: the stdlib-only gate for stdlib functions

**Files:**
- Modify: `lib/typecheck/typecheck.ml`, at the stdlib-only check (line ~2787). After it, if the resolved name is a stdlib function whose `fn_attrs` contain `"stdlib_internal"`, and the reference's span is not `span_is_stdlib`, raise `Err.Code.stdlib_internal`. The message reads "`M.f` is internal to the standard library; use the handle API in `M`" (the hint comes from an optional attribute argument, below).
  - Record the attribute per qualified function name in a new `env.stdlib_internal_fns : (string, string) Hashtbl.t` (qualified name → hint), filled when the stdlib's `DFn`s are checked.
  - The gate fires on value references too (`let f = NetKernel.send_frame`), as the builtin gate does.
- Modify: `lib/typecheck/typecheck_env.ml` / `typecheck_env.mli`: the new table field.
- Modify: `lib/parser/parser.mly`, only if `@[stdlib_internal("hint")]` with a string argument does not already parse. Check with an existing attribute that takes arguments (`@[trusted_linear(v)]` takes an identifier). If a string is needed, take the argument-free form and look the hint up from a table keyed by module instead.
  - Any grammar change here also goes into `tree-sitter-march/grammar.js`.
- Modify: every stale comment that names `check_stdlib_only_refs` (`typecheck_builtins.ml:88,157`, `bin/toolchain.ml:705`) to name the resolution-time gate. These are current-truth code comments that doc-lint does not check, but they mislead.
- Test: `test/test_stdlib_only.ml`.

**Interfaces:**
- Produces: the attribute `@[stdlib_internal]` on a stdlib `fn`. A reference from user code is a type error with code `stdlib_internal`.

- [ ] **Step 1: Write the failing tests** in `test/test_stdlib_only.ml`. Use a stdlib-registered fixture module `mod Inner do @[stdlib_internal] fn raw(fd : Int) : Int do fd end end`.
  - `internal_fn_call_refused`: a user `Inner.raw(3)` is an error with code `stdlib_internal`.
  - `internal_fn_value_refused`: a user `let f = Inner.raw` is also an error.
  - `internal_fn_stdlib_ok`: a second stdlib-registered module calling `Inner.raw(3)` gets no error.
  - `internal_fn_user_shadow_ok`: a user module that defines its own `raw` and calls it gets no error.
- [ ] **Step 2: Run them; they fail**
  Run: `scripts/run-tests.sh -q compiler` (the stdlib-only cases are in `run_compiler`; if not, the suite `test_stdlib_only.ml` registers in).
  Expected: the first two FAIL (no error raised).
- [ ] **Step 3: Implement the gate.**
- [ ] **Step 4: Run them; they pass**
  Run: same command. Expected: PASS.
- [ ] **Step 5: Seed the golden diagnostic.** Run `scripts/seed-error-corpus.sh` (or add `test/errors/stdlib_internal_2.march` by hand, in the shape of `stdlib_internal_1.march`). Then run `UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e` and review `git diff test/errors/`.
- [ ] **Step 6: Commit** with message `typecheck: @[stdlib_internal] extends the stdlib-only gate to stdlib functions`.

### Task 4: `File.Handle`: opening, reading, writing, seeking and closing a file

**Files:**
- Modify: `stdlib/file.march`:
  - `ptype FileError` gains `Closed`;
  - `type WriteMode = Truncate | Append`;
  - new functions below. `with_lines`, `with_chunks`, `each_line` and `each_chunk` keep their signatures and use the handle internally.
- New raw builtins, each at every site in the `compiler-builtin` skill's list. There are nine (memory: `project_new_builtin_nine_sites`); follow `test_builtin_*`'s agreement tests to find them all:

  | Builtin | Type | Capability | C |
  |---|---|---|---|
  | `file_open_write` | `String -> Int -> Result(Int, FileError)` (mode 0 truncate, 1 append; creates the file, 0644) | `IO.FileWrite` | `fopen` with `"wb"` / `"ab"` into the existing `fh_open` table |
  | `file_write_handle` | `Int -> String -> Result((), FileError)` | none | — |
  | `file_seek` | `Int -> Int -> Result(Int, FileError)` (absolute offset; returns the new offset) | none | — |

  `file_open_write` also goes in `path_arg_builtins` at index 0. Interpreter: `Unix.openfile` with `O_WRONLY; O_CREAT; O_TRUNC/O_APPEND`, then `out_channel_of_descr`. The interpreter's file handles are channels behind `Obj.magic`; keep that representation, now wrapped in a box.
- Modify: `lib/tir/borrow.ml`: the two use builtins take the Int handle owned, as the existing file use builtins do (Int, no RC); no entry needed. Confirm with the agreement test.
- Test: `test/stdlib/test_file_handle.march` (new; registered with `stdlib_march`); `test/native/file_handle_box_leak_probe.march` plus `.expected`.

**Interfaces:**
- Consumes: Task 2's primitives.
- Produces (public, in `mod File`):
  ```
  fn open(path : String) : Result(File.Handle, FileError)                       -- IO.FileRead
  fn open_write(path : String, mode : WriteMode) : Result(File.Handle, FileError) -- IO.FileWrite
  fn read_line(h : File.Handle) : Result(Option(String), FileError)
  fn read_chunk(h : File.Handle, size : Int) : Result(Option(String), FileError)
  fn write_to(h : File.Handle, data : String) : Result((), FileError)
  fn seek(h : File.Handle, offset : Int) : Result(Int, FileError)
  fn close(h : File.Handle) : Result((), FileError)        -- Err(Closed) on a second close
  fn with_open(path : String, f : File.Handle -> a) : Result(a, FileError)
  fn with_open_write(path : String, mode : WriteMode, f : File.Handle -> a) : Result(a, FileError)
  ```
  `write_to` is not named `write` because `File.write(path, data)`, the path convenience, keeps its name (spec §6).
- Each use function has the same shape, written once as a private helper the others call:
  ```march
  pfn with_raw(h : File.Handle, f : Int -> Result(b, FileError)) : Result(b, FileError) do
    let fd = handle_enter(h, 1)     -- kind FILE
    if fd == -1 do Err(Closed) else
      let r = f(fd)
      handle_leave(h)
      r
    end
  end
  ```
  The helper costs one closure per use. If the Task 15 benchmark shows it, inline the enter/leave pair in each function instead. This is the one place the plan prescribes a body, because the leave-after-use order is the invariant Task 1 depends on.
- `with_open` and `with_open_write` close through `try_finally` (the existing `with_lines` pattern), so a panicking callback still closes.

- [ ] **Step 1: Write the failing tests**, `test/stdlib/test_file_handle.march`. Use a scratch directory made by `Dir.mkdir_p` under the test's temp path.
  - `test "write then read back"`: `open_write(p, Truncate)`, `write_to(h, "a\nb\n")`, `close(h)`; then `open(p)`, `read_line` twice. Expect `Ok(Some("a"))`, `Ok(Some("b"))`, then `Ok(None)`.
  - `test "append"`: after the above, `open_write(p, Append)` plus `write_to(h, "c\n")`. `File.read(p) == Ok("a\nb\nc\n")`.
  - `test "seek"`: `seek(h, 2)` returns `Ok(2)`, and the next `read_line` is `Ok(Some("b"))`.
  - `test "use after close"`: after `close(h)`, `read_line(h) == Err(Closed)`, `write_to(h, "x") == Err(Closed)`, and `close(h) == Err(Closed)`.
  - `test "with_open closes"`: keep the handle the callback received, by returning it. After `with_open` returns, `read_line(kept) == Err(Closed)`.
  - `test "handle needs no capability"`: a nested module `mod Reader do needs () fn first(h : File.Handle) do File.read_line(h) end end`, called with a handle opened in the test module, typechecks and returns `Ok(Some("a"))`. A `needs ()` module is the spec §18 "a handle works in a module with `needs ()`" case. If the ceiling still charges `IO.FileRead` here, the test fails, and that is fixed in Task 10. Mark the test `-- passes after Task 10` and register it then.
- [ ] **Step 2: Write `test/native/file_handle_box_leak_probe.march`.**
  - 10 000 iterations of `open`/drop and of `open`/`close`/drop.
  - Then read the process's open-descriptor count, the way `file_handle_leak_probe.march` does, and print `fds stable`.
  - `.expected`: `fds stable`.
- [ ] **Step 3: Run them; they fail**
  Run: `scripts/run-tests.sh -q stdlib_march`, then `./_build/default/test/run_codegen.exe -e` for the native fixture (or the suite `test/native` registers in; `scripts/affected.sh` prints it).
  Expected: FAIL (`File.open_write` unbound).
- [ ] **Step 4: Implement the builtins and the stdlib functions.**
- [ ] **Step 5: Run them; they pass.** Also run `scripts/run-tests.sh -q stdlib` (the existing `File`/`Seq`/`Csv` tests stay green) and `dune build --root . test/test_refinecheck.exe && UPDATE_SNAPSHOTS=1 ./_build/default/test/test_refinecheck.exe -e 'audit-baseline'` (new native fixture).
- [ ] **Step 6: Commit** the stdlib file, the builtin sites, the tests, and `test/refine_audit/corpus.baseline`. Add a CHANGELOG `### Added` bullet for the `File.Handle` API. Message: `stdlib: File.Handle (open, open_write, read_line, write_to, seek, close, with_open)`.

### Task 5: `Socket` and `Listener`: connections and listening

**Files:**
- Modify `stdlib/socket.march`:
  - `SocketError` gains `Closed`.
  - Every function that took `fd : Int` takes `s : Socket`.
  - `connect` and `connect_timeout` return `Result(Socket, SocketError)`.
  - New listener functions, below.
  - `with_connection` passes a `Socket`.
- Modify `stdlib/udp.march`: `type UdpSocket = UdpSocket(Int)` becomes `opaque type UdpSocket = UdpSocket(Socket)` over kind UDP. The public signatures keep `UdpSocket`, and every use goes through enter/leave.
- Modify `stdlib/tls.march`:
  - `TlsCtx` and `TlsConn` become `opaque` over kinds TLS_CTX and TLS.
  - `connect(s : Socket, ctx, host)` and `accept(s : Socket, ctx)`: on success they `handle_detach(s)` and store the tcp fd as the TLS box's `aux`, so closing the `TlsConn` closes both. On failure `s` stays open and owned by the caller.
- Modify `stdlib/websocket.march`: `WsSocket` becomes opaque over kind TCP_BORROWED. The HTTP event loop owns the fd, so check `march_http.c:1983` and `:2357`, where the handshake runs.
- Test: `test/stdlib/test_socket.march` (existing, migrated); new native fixtures `test/native/socket_close_while_recv.march` and `test/native/socket_sent_to_local_actor.march`.

**Interfaces:**
- Consumes: Task 2's primitives.
- Produces (in `mod Socket`):
  ```
  fn connect(host : String, port : Int) : Result(Socket, SocketError)                       -- IO.NetConnect
  fn connect_timeout(host : String, port : Int, timeout_ms : Int) : Result(Socket, SocketError)
  fn write(s : Socket, data : String) : Result((), SocketError)
  fn recv(s : Socket, max_bytes : Int) : Result(String, SocketError)
  fn recv_timeout(s : Socket, max_bytes : Int, timeout_ms : Int) : Result(String, SocketError)
  fn set_recv_timeout(s : Socket, timeout_ms : Int) : Result((), SocketError)
  fn recv_deadline(s : Socket, max_bytes : Int, timeout_ms : Int) : Result(Option(String), SocketError)
  fn peer_addr(s : Socket) : Result(String, SocketError)
  fn close(s : Socket) : Result((), SocketError)
  fn listen(port : Int) : Result(Listener, SocketError)                                     -- IO.NetListen
  fn accept(l : Listener) : Result(Socket, SocketError)
  fn accept_timeout(l : Listener, timeout_ms : Int) : Result(Socket, SocketError)
  fn local_port(l : Listener) : Result(Int, SocketError)
  fn close_listener(l : Listener) : Result((), SocketError)
  ```
- `accept` is charged nothing after Task 10: holding the `Listener` is the authority (spec §6 table: "accept (yields a `Socket`)").
- Produces, stdlib-internal (`@[stdlib_internal]`):
  - `fn Socket.raw_fd(s : Socket) : Int` (enter, then leave immediately; for stdlib code that hands an fd to C);
  - `fn Socket.adopt(fd : Int) : Socket` (kind TCP);
  - `fn Socket.borrow(fd : Int) : Socket` (kind TCP_BORROWED).

- [ ] **Step 1: Write the failing tests.**
  - Migrate `test/stdlib/test_socket.march` to the new types.
  - Add `test "listen accept roundtrip"`: listen on port 0; `local_port`; connect to it from a spawned task; accept; write and recv `"ping"`; close both. Expect `Ok("ping")`.
  - Add `test "use after close"`: `write(s, "x") == Err(Closed)` after `close(s)`; `accept(l) == Err(Closed)` after `close_listener(l)`.
  - Add `test "udp socket is opaque"` as a reject program. Put `Udp.UdpSocket(5)` in `test/errors/handle_forge_1.march`; the expected error names the hidden constructor.
  - `test/native/socket_close_while_recv.march`: a task blocks in `Socket.recv(s, 16)` on an accepted connection whose peer sends nothing. After 100 ms the main thread calls `Socket.close(s)`. The task's result is `Err(Closed)`, it finishes within 1 s, and the program prints `woke closed`. Run it under 4 scheduler threads (the env var the existing scheduler fixtures use).
  - `test/native/socket_sent_to_local_actor.march`: send an accepted `Socket` in a message to a local actor, which writes `"hi"` to it; the main thread's client reads `"hi"`. Prints `shared`.
- [ ] **Step 2: Run them; they fail**
  Run: `scripts/run-tests.sh -q stdlib_march errors`, plus the native fixtures.
  Expected: FAIL (type errors on `Socket`).
- [ ] **Step 3: Implement the four stdlib modules.**
- [ ] **Step 4: Run them; they pass.** Also run `scripts/run-tests.sh -q stdlib` and `scripts/run-tests.sh test_jit`. Regenerate the refine audit baseline for the new fixtures, and the error goldens (`UPDATE_ERRORS=1 …`).
- [ ] **Step 5: Commit** with message `stdlib: Socket and Listener handles; Udp, Tls, WebSocket handles opaque`, plus a CHANGELOG `### Changed` bullet: "`Socket.connect` returns a `Socket`, not an `Int`; `Udp.UdpSocket`, `Tls.TlsConn`, `Tls.TlsCtx` and `WebSocket.WsSocket` can no longer be built from an integer."

### Task 6: The HTTP client and server on handles

**Files:**
- Modify `stdlib/http_transport.march`:
  - `connect(req)` returns `Ok(Socket)`;
  - `request_on`, `stream_request_on`, `stream_chunked_body` and `stream_fixed_body` take `Socket`.
- Modify `stdlib/http_client.march`: `transport_keepalive` and `run_on_fd` take `Socket`. Rename `run_on_fd` to `run_on`, keeping `run_on_fd` as a deprecated alias for one release if it has callers outside the stdlib.
- Modify `stdlib/http_server.march`:
  - `Conn`'s first field becomes `Socket` (kind TCP_BORROWED, made with `Socket.borrow(fd)` where the server builds a `Conn` from the C event loop's fd). Find every construction site with `forge search --callers Conn`.
  - `HttpServer.fd(conn)` becomes `@[stdlib_internal]`.
  - Add `fn HttpServer.test_conn(method : Atom, path : String, headers : List(Header), body : String) : Conn`, whose socket is a detached box (closed, released), so handler unit tests stop building `Conn` positionally with an Int.
- Modify every positional `Conn(` construction outside the stdlib (the inventory found `examples/bastion_tests/*.march`, `test/test_eval.ml` and `test/test_https_native.ml`) to `HttpServer.test_conn`.
- Modify `forge/tasks/forge_registry.march`, which calls `tcp_connect` / `tcp_send_all` / `tcp_recv_http` / `tcp_close` directly, to `HttpTransport` or `Socket`.
- Test: the existing HTTP suites (`test/test_http_native.ml`, `test/test_https_native.ml`, the `stdlib` HTTP cases) are the regression net. Add `test "handler unit test with test_conn"` to the HttpServer stdlib tests.

**Interfaces:**
- Consumes: Task 5's `Socket`, `Socket.borrow`, `Socket.raw_fd`.
- Produces: `HttpServer.test_conn`, as above; `HttpTransport.connect : Request -> Result(Socket, _)` (its error type is unchanged).

- [ ] **Step 1:** Write `test "handler unit test with test_conn"`: a router handler called on `test_conn(:get, "/x", [], "")` returns status 200.
- [ ] **Step 2:** Run it; it fails (`test_conn` unbound).
- [ ] **Step 3:** Implement the changes above.
- [ ] **Step 4:** Run `scripts/run-tests.sh stdlib codegen eval` (the full suite, including the Slow HTTP cases) and `dune build --root . lsp/bin/main.exe && scripts/run-tests.sh lsp`. Expected: green.
- [ ] **Step 5: Benchmark the hot path.** The server now allocates one box per connection. Run: `march --compile --opt 2 bench/<the HTTP benchmark specs/benchmarks.md names> …` before and after, on a quiet machine. A load average of 229 from other sessions makes benchmarks lie (memory `feedback_loadavg_makes_suites_and_benchmarks_lie`). Expected: within noise; record both numbers in the commit message.
- [ ] **Step 6: Commit**, with a CHANGELOG `### Changed` bullet for `HttpTransport.connect` and `HttpServer.Conn`.

### Task 7: `File.Dir`: authority over a subtree

**Files:**
- Create `runtime/march_file_beneath.c` and add it to `runtime/sources.list`. It provides:
  - `int march_beneath_open(int dirfd, const char *rel, int flags, int mode)` (fd, or −errno);
  - `void *march_file_open_at(int64_t dirfd, void *rel, int64_t flags)` (registers the `FILE*` in the existing `fh_open` table);
  - `void *march_dir_list_at(int64_t dirfd, void *rel)`;
  - `void *march_dir_open(void *path)`, which returns `Result(Int, FileError)` over `open(path, O_DIRECTORY|O_RDONLY|O_CLOEXEC)`.
- Linux: `openat2` with `RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS`. On `ENOSYS` (kernel < 5.6), fall back to the macOS algorithm.
- macOS and the fallback algorithm:
  1. Refuse before any syscall:
     - `rel` empty, absolute, or containing a NUL byte;
     - a `..` component after lexical normalisation (reuse the rule in `lib/caps/cap_scope.ml` `normalize`, reimplemented in C);
     - a normalised result equal to `.`.
  2. Open each intermediate component with `openat(cur, comp, O_DIRECTORY|O_NOFOLLOW)`, and the last with `O_NOFOLLOW`. A symlink anywhere is refused with `ELOOP`.
  3. Document it as best effort: macOS refuses every symlink, even one that stays inside. That is stricter than Linux and is the documented difference.
- Create `lib/eval/eval_beneath_stubs.c`, the interpreter's binding to the same C file (compiled into the eval library in `lib/eval/dune`; the runtime-sources check must list it).
- New raw builtins, all stdlib-only, at every builtin site:

  | Builtin | Type | Capability |
  |---|---|---|
  | `dir_open` | `String -> Result(Int, FileError)` | `IO.FileRead`; `path_arg_builtins` index 0 |
  | `file_open_at` | `Int -> String -> Int -> Result(Int, FileError)` (flags 0 read, 1 truncate, 2 append) | none |
  | `dir_list_at` | `Int -> String -> Result(List(String), FileError)` | none |

- Modify `stdlib/file.march`: the functions below. A write-capable directory records `aux = 1`.
- Test: `test/stdlib/test_file_dir.march` (new); `test/test_codegen.ml` case `dir_beneath_symlink_linux`, skipped on macOS with the reason printed.

**Interfaces:**
- Consumes: Task 2 and Task 4.
- Produces (in `mod File`):
  ```
  fn open_dir(path : String) : Result(File.Dir, FileError)          -- IO.FileRead; read-only beneath
  fn open_dir_write(path : String) : Result(File.Dir, FileError)    -- IO.FileRead and IO.FileWrite
  fn open_in(d : File.Dir, rel : String) : Result(File.Handle, FileError)
  fn open_write_in(d : File.Dir, rel : String, mode : WriteMode) : Result(File.Handle, FileError)  -- Err(Permission(rel)) on a read-only dir
  fn list_in(d : File.Dir, rel : String) : Result(List(String), FileError)   -- rel "" lists d itself
  fn close_dir(d : File.Dir) : Result((), FileError)
  ```
- `list_in(d, "")` is the one place an empty `rel` is accepted.
- Refusals are `Err(Permission(rel))`, a new `FileError` variant `Escapes(rel)`, or `Err(Closed)`. This plan picks `Escapes(String)` for leaving the directory, so callers can tell it from an OS permission error.

- [ ] **Step 1: Write the failing tests**, `test/stdlib/test_file_dir.march`, in a scratch tree `root/{a.txt, sub/b.txt}` with a symlink `root/out -> /etc`.
  - `open_in(d, "a.txt")` reads; `open_in(d, "sub/b.txt")` reads.
  - `open_in(d, "../x")`, `"/etc/passwd"`, `"sub/../../x"`, `""` and `"."` each give `Err(Escapes(_))`.
  - `open_in(d, "out/passwd")` gives `Err(Escapes(_))` on both platforms.
  - On a read-only dir: `open_write_in(d, "new.txt", Truncate) == Err(Permission("new.txt"))`.
  - On `open_dir_write`: the same call succeeds and `File.read(root ++ "/new.txt") == Ok("")`.
  - `list_in(d, "")` sorted is `["a.txt", "out", "sub"]`.
  - After `close_dir(d)`: `open_in(d, "a.txt") == Err(Closed)`.
  - A handle opened through `d` stays usable after `close_dir(d)` (it holds its own fd).
  - `test "dir works in a needs () module"`: a nested `needs ()` module given `d` reads `a.txt`. Registered after Task 10, like Task 4's.
  - `dir_beneath_symlink_linux` (`test_codegen.ml`, Linux only): a symlink `root/in -> sub` opens on Linux through `openat2`.
  - Renamed-directory case: rename `root` after `open_dir`; `open_in(d, "a.txt")` still opens the file in the moved directory (the fd follows the inode). Assert that, and document it.
- [ ] **Step 2:** Run them; they fail. `scripts/run-tests.sh -q stdlib_march`.
- [ ] **Step 3:** Implement the C file, the stub, the builtins and the stdlib functions.
- [ ] **Step 4:** Run them; they pass on macOS locally. Run the Linux leg in the local aarch64 Docker recipe (memory `project_aarch64_ci_leg_local_docker_repro`) or leave it to CI, and say which in the commit message.
- [ ] **Step 5:** Commit, with a CHANGELOG `### Added` bullet that states the macOS limit: every symlink is refused beneath a directory handle.

### Task 8: `Process` handles

**Files:**
- Modify `stdlib/process.march`:
  - `type LiveProcess` becomes `opaque type LiveProcess = LiveProcess(Int, Int)` (stdlib-internal use only).
  - `spawn_async` returns `Result(Process, ProcessError)`, a box of kind PROCESS with `raw` = stream slot and `aux` = pid.
  - `read_line`, `write`, `kill` and `wait_proc` take `Process`. Each rebuilds `LiveProcess(handle_aux(p), slot)` inside enter/leave and calls the existing raw builtin.
  - `ptype ProcessError = Closed | ProcessFailed(String)`.
  - `wait_proc` closes the handle after reaping, so a second `wait_proc` is `Err(Closed)`.
- Test: `test/stdlib/test_process.march` (existing or new), and the `test_codegen.ml` cases that call `process_spawn_async` / `process_kill_proc` (inventory: `test_codegen.ml` is the only caller), migrated.

**Interfaces:**
- Produces:
  ```
  fn spawn_async(command : String, args : List(String)) : Result(Process, ProcessError)   -- IO.Process
  fn read_line(p : Process) : Result(Option(String), ProcessError)
  fn write(p : Process, data : String) : Result((), ProcessError)
  fn kill(p : Process) : Result((), ProcessError)
  fn wait_proc(p : Process) : Result(Int, ProcessError)
  ```

- [ ] **Step 1: Write the failing tests.**
  - `spawn_async("cat", [])`, `write(p, "x\n")`, `read_line(p) == Ok(Some("x"))`, `kill(p)`, then `wait_proc(p)` returns `Ok(_)`.
  - A second `wait_proc(p) == Err(Closed)`; `write(p, "y") == Err(Closed)`.
  - `spawn_async("/nonexistent", [])` gives `Err(ProcessFailed(_))`.
- [ ] **Step 2:** Run them; they fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run them; they pass, under `scripts/run-tests.sh -q stdlib_march codegen`.
- [ ] **Step 5:** Commit, with a CHANGELOG `### Changed` bullet.

### Task 9: Mark the stdlib's fd plumbing internal

**Files:** add `@[stdlib_internal]` to each public function that takes or returns a raw `fd : Int`, or a record holding one, outside the handle modules. The inventory found these; re-derive with `grep -n "fd : Int\|_fd : Int" stdlib/*.march` and `forge search` before starting:
- `stdlib/net_kernel.march`: `send_frame`, `write_framed`, `recv_frame`, `recv_frame_exact`, `handshake`, `handshake_role`, `recv_frame_until`, `handshake_addr`, `raw_allowed`, `link_binding`, `forget`, `sealed`, `handshake_auth`.
- `stdlib/node_send.march`: `cast`, `cast_schema`, `recv_failure`, `cast_from`, `serve_one`, `serve_one_reply`, `handle_frame`.
- `stdlib/node_call.march`: `call`, `serve_one`, `serve_loop`.
- `stdlib/node_queue.march`: `start`, `close_fd`, `consumed`.
- `stdlib/peer_reader.march`: `serve`.
- `stdlib/peer_registry.march`: `no_fd`, `add_data`.
- `stdlib/cluster_conn.march`: `listen`, `accept_split*`, `accept_one`.
- `stdlib/cluster_node.march`: `handshake`.
- `stdlib/session_node.march`: any public function over `Link`'s fds.
- `stdlib/http_server.march`: `fd` (done in Task 6).

Public *record* types with `fd : Int` fields (`CnLink`, `CnHalf`, `Peer`, `WriterState`, `Link`) stay as they are. A user who builds one gains nothing unless a function that does I/O on it is reachable, and every such function is now internal. Step 1's test checks exactly that.

- Test: `test/test_stdlib_only.ml`.

- [ ] **Step 1: Write the failing test** `cluster_plumbing_internal`: user code calling `NetKernel.send_frame(5, "x")` and `ClusterConn.listen(0)` each gets `stdlib_internal`.
- [ ] **Step 2:** Run it; it fails.
- [ ] **Step 3:** Add the attributes. Do not change any signature.
- [ ] **Step 4:** Run `scripts/run-tests.sh -q compiler stdlib`, and the two-node suite the `steward` skill names, in the background, since it is long.
  - Expected: green, apart from fixtures that call these functions directly. Those are migrated in Task 10, or, where the fixture is a cluster test that must use the plumbing, it gets compiled with the fixture's span registered as stdlib, the way `test_stdlib_only.ml` does. Prefer migration.
- [ ] **Step 5:** Commit.

### Task 10: The raw builtins become stdlib-only, and handle uses charge nothing

**Files:**
- Modify `lib/typecheck/typecheck_env.ml` `stdlib_only`. Add each builtin below with a hint naming its wrapper (for example `("tcp_send_all", "use `Socket.write`")`):
  - files: `file_open`, `file_open_write`, `file_read_line`, `file_read_chunk`, `file_write_handle`, `file_seek`, `file_close`, `dir_open`, `file_open_at`, `dir_list_at`;
  - CSV: `csv_open`, `csv_next_row`, `csv_close`;
  - TCP: every `tcp_*`;
  - UDP: every `udp_*`;
  - TLS: every `tls_*`;
  - WebSocket: `ws_recv`, `ws_send`, `ws_select`;
  - HTTP server: `http_server_spawn_n`, `http_server_wait`, `http_server_plain_listener`, `http_conn_is_tls`;
  - process: `process_spawn_async`, `process_read_line`, `process_write`, `process_kill_proc`, `process_wait_proc`.
- Modify `lib/typecheck/typecheck_builtins.ml` `builtin_cap_table`. Remove every *use* builtin and keep every *open*:
  - **Removed:**
    - files: `file_read_line`, `file_read_chunk`, `csv_next_row`;
    - TCP: `tcp_send_all`, `tcp_recv_all`, `tcp_recv_exact`, `tcp_recv_http`, `tcp_recv_http_headers`, `tcp_recv_chunk`, `tcp_recv_chunk_timeout`, `tcp_set_recv_timeout`, `tcp_recv_chunked_frame`, `tcp_recv_timeout`, `tcp_accept`, `tcp_accept_timeout`, `tcp_local_port`;
    - UDP: `udp_connect`, `udp_close`, `udp_local_addr`, `udp_stats`, `udp_send_batch`, `udp_send_many`, `udp_recv_batch`;
    - TLS: `tls_read`, `tls_read_timeout`, `tls_write`, `tls_negotiated_alpn`, `tls_peer_cn`, `tls_negotiated_group`, `tls_accept`, `tls_connect`, `tls_ctx_set_groups`;
    - WebSocket: `ws_recv`, `ws_send`, `ws_select`;
    - process: `process_read_line`, `process_write`, `process_kill_proc`, `process_wait_proc`.
  - **Kept** (opens): `file_open`, `csv_open`, `file_open_write`, `dir_open`, `tcp_connect`, `tcp_connect_timeout`, `tcp_listen`, `udp_open`, `udp_resolve`, `tls_client_ctx`, `tls_server_ctx`, `process_spawn_async`, the `http_server_*` listeners, and the dist-monitor rows.
- `tls_connect` and `tls_accept` count as uses: they run over a `Socket` the caller already holds, and that open was checked. Making a TLS context stays checked.
- Regenerate `lib/caps/cap_symbols.ml` to match; its freshness test re-derives the join.
- Make the same removals in `lib/refinecheck/cap_infer.ml` (the third name→cap table) and check `lib/caps/net_dest.ml` `builtin_dest`. Handle operations there map to `Handle`; leave them.
- `lib/typecheck/typecheck_caps.ml` `path_arg_builtins`: add `file_open_write` and `dir_open` if Tasks 4 and 7 did not. Rewrite the comment at `:218-223` to say *why* handle uses need no path check: handles are unforgeable since this phase.
- Migrate every non-stdlib direct caller, as listed by the inventory, to the handle API:
  - `lib/desugar/control_wiring.march`: 58 `tcp_*` calls. It is spliced into a user entry module with span file `"<control>"`, so the gate applies to it.
  - `test/native/*.march`: 23 files with real `tcp_*`/`file_*`/`csv_*` calls. `close_returns_ok_atom`, `file_handle_leak_probe` and `csv_niche_row` pin raw-builtin behaviour; keep them by registering their span as stdlib in their driver, and say so in a comment.
  - `test/two_node/**`: 14 files.
  - `bench/cluster_frames.march`, `bench/actors/crash_loop.march`.
  - OCaml tests with embedded March: `test_compiler.ml`, `test_cap_sandbox_runtime.ml`, `test_cap_net_scope.ml`, `test_jit.ml`, `test_codegen.ml`, `test_cap_scope.ml`, `test_stdlib_suite.ml`, `test_host_scope.ml`, and the 1–2-hit files. For each case, decide whether it tests the raw builtin itself (then register the source as stdlib) or uses it incidentally (then migrate it).
- `forge/tasks/forge_registry.march` was done in Task 6.
- Test: `test/test_stdlib_only.ml`; `test/test_cap_symbols.ml`; `test/test_cap_attrib_agreement.ml`.

- [ ] **Step 1: Write the failing tests.**
  - `test_stdlib_only.ml` `raw_handle_builtins_gated`: user calls to `tcp_send_all(3, "x")`, `file_read_line(3)` and `process_wait_proc(p)` each get `stdlib_internal`, with the hint naming the wrapper.
  - `test_compiler.ml` `handle_use_charges_nothing`, three cases:
    - a module with `needs ()` whose function takes a `Socket` and calls `Socket.write` typechecks under `--check` (`cap_strict_ceiling` on), and its `--compile` TIR ceiling reports no violation;
    - the same module calling `Socket.connect` is refused;
    - one calling `Socket.accept(l)` is accepted.
  - Register the two `-- passes after Task 10` tests from Tasks 4 and 7.
- [ ] **Step 2:** Run them; they fail.
- [ ] **Step 3:** Make the table edits, regenerate `cap_symbols.ml`, and migrate the callers.
- [ ] **Step 4:** Run the full suite: `scripts/run-tests.sh` (not `-q`), then `scripts/run-tests.sh refinecheck` in the background, then `scripts/check-docs.sh`. Expected: green. Run `scripts/oracle-base.sh types`: the types oracle shows changes only in fixtures this branch edited. List any other change in the commit message and justify it.
- [ ] **Step 5:** Leave the handover note for phase 1 at `specs/todos/2026-11-10-ocap-p1-handle-uses-not-capability-ops.md`: the list of builtins removed from `builtin_cap_table` above, with one line of context.
- [ ] **Step 6:** Commit, with a CHANGELOG `### Changed` bullet: "the raw integer file, socket, TLS, UDP, WebSocket and process builtins are internal to the standard library; use `File`, `Socket`, `Udp`, `Tls`, `WebSocket`, `Process`."

### Task 11: Scope syntax: several names and string-valued options

**Files:**
- Modify: `lib/parser/parser.mly` `scoped_cap_path` (line ~1457) and `scope_option` (line ~1467). Accept:
  - `IO.Mut("sessions", "rate_limits")`, several leading strings;
  - `IO.Registry(prefix("worker."))`, an option with a string argument;
  - `IO.Registry("logger", prefix("worker."))`, both.
- The encoding stays a single string, so `DNeeds`'s AST type does not change:
  - extra leading strings become options `name=<s>`;
  - a string-argument option becomes `<o>=<s>`.

  So `IO.Mut("a", "b")` is `"a;name=b"`, and `IO.Registry(prefix("w."))` is `";prefix=w."`.

  A string containing `;`, `=` or `,` is refused by Task 12's validation with `invalid_cap_scope`, so the encoding cannot be confused.
- Modify: `tree-sitter-march/grammar.js`, the same productions; add fixtures under its test corpus. Run `scripts/check-tree-sitter.sh`.
- Test: `test/test_compiler.ml` parser cases (or wherever the host-scope parse tests live: `test_host_scope.ml`).

- [ ] **Step 1: Write the failing parse tests.** `parse_multi_name_scope` checks that `needs IO.Mut("a", "b")` yields scope `Some "a;name=b"`. `parse_string_option_scope` checks that `needs IO.Registry(prefix("w."))` yields `Some ";prefix=w."`. A third case checks that `needs IO.NetConnect("h", methods(get))` is unchanged.
- [ ] **Step 2:** Run them; they fail.
- [ ] **Step 3:** Implement. Check that menhir's conflict count does not rise. The count is recorded in the `proof_cap_dict` comment.
- [ ] **Step 4:** Run the tests and `scripts/check-tree-sitter.sh`; both pass.
- [ ] **Step 5:** Commit the parser and the tree-sitter grammar together.

### Task 12: `IO.Registry`, and name-checked lookups

**Files:**
- Modify `lib/caps/cap_lattice.ml`:
  - `hierarchy`: `("IO.Registry", Some "IO")`;
  - `words`: `("IO.Registry", ("registry", "names an actor"))`.

  Then regenerate `runtime/march_cap_lattice.c` with `lib/caps/emit_c_table.exe runtime` and update the index table in `test/test_cap_lattice.c:49`.
- Modify `lib/typecheck/typecheck_builtins.ml`:
  - `builtin_types` token: `("IO.Registry", 0)`; fix the stale "18-entry" comment.
  - `builtin_cap_table`: `actor_register`, `actor_unregister`, `actor_whereis` and `actor_registered` map to `IO.Registry`.

  Regenerate `cap_symbols.ml` and update `cap_infer.ml`.
- Create `lib/caps/name_scope.ml` / `.mli`:
  - `type t = { names : string list; prefixes : string list }`;
  - `val parse : string -> (t, string) result` (decodes Task 11's encoding; rejects an empty name, or `;`, `=` or `,` in a name);
  - `val admits : t -> string -> bool` (an exact name, or a name that starts with a prefix);
  - `val subsumes : t option -> t option -> bool` (`None` is unscoped; the semantics follow `Cap_scope.scope_subsumes`).
- Modify `lib/caps/cap_scope.ml` `is_scopable`: also true for `IO.Mut` and `IO.Registry`. Add `is_name_scopable`.
- Modify `lib/typecheck/typecheck_caps.ml`. Generalise the literal-argument scan, next to `path_arg_builtins`, with a table `name_arg_fns : (string * int) list`:
  - `("Vault.new", 0); ("Vault.open", 0); ("Vault.whereis", 0)` under `IO.Mut`;
  - `("Actor.register", 1); ("Actor.unregister", 0); ("Actor.whereis", 1)` under `IO.Registry`.

  These are stdlib *wrapper* names, because user code can no longer reach the builtins.

  For each call with a literal name in a module whose `needs` scopes that kind:
  - a name outside the scope is an error, `cap_scope_exceeded` or the code path scopes use for the same violation;
  - a computed name in a scoped module is an error, "cannot prove `<expr>` is within `IO.Registry(...)`; the check at run time arrives with phase 4" (fail closed, as host scopes do today);
  - `Actor.registered()` in a module with a *scoped* `IO.Registry` is refused: listing every name exceeds any name scope.
- Modify `stdlib/actor.march`: add `needs IO.Registry` to `mod Actor`. Keep the `Cap(Actor.Introspect)` parameters (phase 7 retires them).
- Migrate the callers. `Actor.register` has 84 lines in 42 files, `Actor.whereis` 67 lines in 39 files, `Actor.registered` 30 lines in 19 files, counting docs. Each calling module gains `needs IO.Registry`, applied by the machine fix below.
- Machine fix: make the missing-capability diagnostic for `IO.Registry` carry an insert fix adding `needs IO.Registry` after the module's last `needs` line. Most missing-`needs` diagnostics already carry one; confirm, and add it if not. `forge fix` then migrates downstream code.
- Docs: `specs/lang/capabilities.md` (the kind table at :60 and :194) and `specs/lang/core-march-types.md`; then `scripts/gen-lang-docs.py`. Also `specs/lang/types/accept/t57_cap_all_hierarchy_args.march`, and the `spec-search` skill's bundled copy if `scripts/check-docs.sh` checks it.
- Test: `test/test_cap_lattice.c`; `test/test_compiler.ml`; `test/errors/` goldens.

**Interfaces:**
- Produces: the kind `IO.Registry`; `Name_scope.{parse, admits, subsumes}`; scoped `needs IO.Mut("…")` and `needs IO.Registry("…", prefix("…"))` judged at compile time for literal names.

- [ ] **Step 1: Write the failing tests** (`test_compiler.ml` unless noted).
  - `registry_kind_required`: a module without `needs IO.Registry` calling `Actor.register(pid, "x")` is refused, and the diagnostic's machine fix inserts `needs IO.Registry`.
  - `registry_scope_literal`: under `needs IO.Registry("logger", prefix("worker."))`, these names are accepted for `Actor.register`: `"logger"`, `"worker.1"`. These are refused, each naming the scope: `"other"`, `"worker"` (no dot), `"workers.1"`.
  - `registry_scope_computed_fails_closed`: under the same scope, `Actor.whereis(c, "worker." ++ id)` is refused with the "cannot prove" message.
  - `registry_listing_needs_unscoped`: `Actor.registered(c)` under a scoped `IO.Registry` is refused; under bare `IO.Registry` it is accepted.
  - `mut_lookup_scope`: under `needs IO.Mut("sessions")`, `Vault.whereis("sessions")` is accepted and `Vault.whereis("tokens")` is refused (spec §18, "a lookup by name outside the scope is refused").
  - `name_scope_invalid`: `needs IO.Mut("a;b")` gives `invalid_cap_scope`.
  - `test_cap_lattice.c`: the new index row.
- [ ] **Step 2:** Run them; they fail. `scripts/run-tests.sh -q compiler`.
- [ ] **Step 3:** Implement. Run `forge fix` over the repo's own callers, or apply the inserted line by hand where `forge fix` refuses because the project has other errors (memory `project_vault_typed_handles_282_migration`).
- [ ] **Step 4:** Run `scripts/run-tests.sh` (full), `scripts/check-docs.sh`, `scripts/oracle-base.sh refine types`, and `UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e` with the diff reviewed. Expected: green; oracle changes only where this branch edited fixtures.
- [ ] **Step 5:** Commit, with a CHANGELOG `### Changed` bullet: "registering and finding actors by name needs the new `IO.Registry` capability; `forge fix` adds the line". Add an `### Added` bullet for name scopes on `IO.Mut` and `IO.Registry`.

### Task 13: Handles do not cross nodes

**Files:**
- Modify the typed remote-send check, `lib/typecheck/typecheck_caps.ml` `check_node_send_sites` (line 2174), and the `derive Json` expansion (`lib/desugar/desugar_derive.ml`). A message type that contains one of the five handle types, or `UdpSocket`/`TlsConn`/`TlsCtx`/`WsSocket`, at any depth is an error: "`File.Handle` cannot be sent to another node: a handle names a resource on this node". Today such a type already fails for lack of a `JsonTo` impl; the new message replaces that confusing one.
- Modify the untyped remote path, if one exists: check whether `send` to a `Pid` known to be remote serialises an arbitrary value, starting from `stdlib/node_send.march` and `runtime/march_remote_registry.c`. If it does, the serialiser refuses a `MARCH_HANDLE_TAG` cell at run time with an error value, not a crash.
- Test: `test/errors/handle_not_sendable_1.march` (golden); `test/test_compiler.ml`.

- [ ] **Step 1:** Write the failing golden: a `derive Json` record with a `Socket` field, sent with `Node.send`. The expected output carries the message above.
- [ ] **Step 2:** Run it; it fails (the old message differs).
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run it; it passes. Run `scripts/run-tests.sh -q errors compiler`.
- [ ] **Step 5:** Commit.

### Task 14: Documentation and records

**Files:**
- `specs/lang/`: the stdlib and capability chapters that describe files, sockets, processes and actor names, edited to the handle API. The inventory found raw builtin names in `actors.md`, `capabilities.md`, `core-march.md`, `core-march-types.md` and `refinement-types.md`. Then run `scripts/gen-lang-docs.py` and commit the regenerated `docs/` chapters.
- `docs/` pages not generated from `specs/lang` (`docs/stdlib.md`, `docs/hot-code-reload.md`, and the `docs/assets/explainer/authority/**` programs): edit them directly.
- `.claude/skills/march-lang/SKILL.md`: the raw-builtin mentions, and a short "Handles" paragraph.
- `specs/progress/2026-11-10-ocap-p2-handles.md`: what shipped, the decisions above, and the test names.
- `specs/todos/` follow-ups, one file each:
  - `…-listen-address-parameter.md`;
  - `…-http-server-spawn-n-handle-int.md` (`spawn_n` still returns an Int server handle; forging one lets a program wait on another server, which grants nothing, but it is the last integer handle);
  - `…-macos-dir-symlinks-refused.md` (documented behaviour; reopen if `openat2`-equivalent APIs appear);
  - `…-cluster-record-types-hold-raw-fds.md` (Task 9's records).
- `CHANGELOG.md`: confirm one bullet per user-visible change from Tasks 4–13, under `## [Unreleased]`.
- Downstream sweep. The repos at `~/code/conduit`, `~/code/test_conduit_app`, forgepm and depot use `Socket` / `HttpServer.Conn`, so `MARCH_LIB_PATH=… march --check` each with this branch's compiler. Do not judge by `forge build`'s cache hit (memory `project_vault_typed_handles_282_migration`). Record what breaks in the progress file. Do not edit those repos in this plan.

- [ ] **Step 1:** Write the docs, the records and the sweep.
- [ ] **Step 2:** Run `scripts/check-docs.sh` and `CHECK_STDLIB_HTML=1 scripts/check-docs.sh` where the generated pages are fresh. Expected: green.
- [ ] **Step 3:** Commit.

### Task 15: Whole-branch verification

- [ ] **Step 1:** Run `scripts/run-tests.sh` (full, including Slow), `scripts/run-tests.sh refinecheck` and `scripts/run-tests.sh test_jit`, all in the background. Expected: green.
- [ ] **Step 2: Interpreter/compiled parity.** For each handle fixture added in Tasks 4–8, run it interpreted (`dune exec --root . march -- FILE`) and compiled, and diff the output. Use a private `HOME`, as `scripts/triage.sh` does. Expected: identical, apart from release timing, which no fixture prints.
- [ ] **Step 3: ASAN.** Run the Task 1 C tests and the native fixtures `file_handle_box_leak_probe`, `socket_close_while_recv` and `socket_sent_to_local_actor` under `MARCH_SANITIZE=1`. ASAN needs Docker locally (memory `project_asan_local_requires_docker`). Expected: no reports.
- [ ] **Step 4: Leaks.** Build `socket_sent_to_local_actor` with `--rc-trace`, run it with `MARCH_TRACE_GC=1`, then run `scripts/gc-trace-report.py trace/gc`. Expected: exit 0, nothing live at exit.
- [ ] **Step 5: Oracles.**
  - `scripts/oracle-base.sh ir`: the IR changes only in programs that use the changed stdlib modules. Name each other changed program and explain it.
  - `scripts/determinism-oracle.sh --corpus small`: green.
- [ ] **Step 6: Benchmarks**, compiled at `--opt 2` on a quiet machine: the HTTP and file benchmarks `specs/benchmarks.md` lists, and `bench/list_ops.march` (closures; Task 4's helper takes one). Expected: within noise of the merge-base numbers.
- [ ] **Step 7:** Run `scripts/affected.sh --run` as a last cross-check. Every result goes in the PR description.

---

## Questions only the owner can answer

1. **`Library`: what is it a handle to?** Today a foreign library is not a value:
   - `extern "lib" : Cap(X) do … end` declares functions that are bound statically;
   - the compiled build links the shim at build time;
   - the interpreter `dlopen`s one global runtime `.so`, and an optional shim, lazily (`lib/eval/eval.ml:1435`).

   A `Library` handle that admits "the symbols the scope admitted" (spec §6) means one of two things:
   - (a) extern functions become callable only through the handle, which changes the meaning of `extern` and every call site;
   - (b) `Foreign.open(lib)` returns a record of function values captured at the open, which needs run-time `dlopen` in compiled builds too.

   This plan builds neither and files a todo. Which do you want, or should `Library` wait for the `IO.Foreign` symbol scopes in narrow-capabilities §7?
   **Decided by the owner, 2026-11-10: checked calls, no handle.** `extern` keeps its meaning. Each foreign call is checked against the current authority (`IO.Foreign("lib", symbols(...))`), at compile time now and also at run time from phase 4. Narrowed access is a closure over the admitted calls. The design doc's §6 table and §21 record the change in the same commit.
2. **`File.open` split by mode** (decision 5). **Decided by the owner, 2026-11-10: yes.** The API is `File.open(path)` and `File.open_write(path, mode)`.
3. **macOS refuses every symlink beneath a directory handle** (Task 7). **Decided by the owner, 2026-11-10: best effort is fine on macOS.**
