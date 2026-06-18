# Capability Body Enforcement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `needs` declarations in March a real static guarantee. Today any module can call `println`, `file_read`, `tcp_connect`, etc. without declaring any capability. This plan adds a `builtin_cap_table` and a body-scanning pass to `check_module_needs` so that every IO builtin call requires a matching `needs` declaration.

**Spec:** `specs/capability-body-enforcement.md`  
**Effort:** ~2.5 days total across 4 tasks  
**Risk:** Low — additive changes; warnings ship before errors

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/typecheck/typecheck.ml` | Modify | Cap hierarchy additions, `builtin_cap_table`, `calls_in_expr`, extend `check_module_needs` |
| `stdlib/io.march` | Modify | Add `needs IO.Console` |
| `stdlib/file.march` | Modify | Add `needs IO.FileRead`, `needs IO.FileWrite` |
| `stdlib/dir.march` | Modify | Add `needs IO.FileRead`, `needs IO.FileWrite` |
| `stdlib/system.march` | Modify | Add `needs IO.Process`, `needs IO.Clock` |
| `stdlib/uuid.march` | Modify | Add `needs IO.Random`, `needs IO.Clock` |
| `stdlib/crypto.march` | Modify | Add `needs IO.Random` |
| `depot/lib/wire/connection.march` | Modify | Add `needs IO.NetConnect`, `needs IO.Database` |
| `depot/lib/wire/pool.march` | Modify | Add `needs IO.NetConnect`, `needs IO.Database` |
| `test/test_march.ml` | Modify | Add `cap_body_enforce` test group (~15 tests) |

---

## Task 0: Cap Hierarchy Additions

**Scope:** `lib/typecheck/typecheck.ml`  
**LoE:** ~30 minutes

Add `IO.Random` (CSPRNG operations) and `IO.Database` (declaration-only; Depot declares it) to the hierarchy, and register them in the type builtins table.

---

- [ ] **Step 0a: Add to `io_cap_hierarchy`**

File: `lib/typecheck/typecheck.ml`, line 883–894.

Current:
```ocaml
let io_cap_hierarchy : (string * string option) list = [
  ("IO",            None);
  ("IO.Console",    Some "IO");
  ("IO.FileSystem", Some "IO");
  ("IO.FileRead",   Some "IO.FileSystem");
  ("IO.FileWrite",  Some "IO.FileSystem");
  ("IO.Network",    Some "IO");
  ("IO.NetConnect", Some "IO.Network");
  ("IO.NetListen",  Some "IO.Network");
  ("IO.Process",    Some "IO");
  ("IO.Clock",      Some "IO");
]
```

Change to:
```ocaml
let io_cap_hierarchy : (string * string option) list = [
  ("IO",            None);
  ("IO.Console",    Some "IO");
  ("IO.FileSystem", Some "IO");
  ("IO.FileRead",   Some "IO.FileSystem");
  ("IO.FileWrite",  Some "IO.FileSystem");
  ("IO.Network",    Some "IO");
  ("IO.NetConnect", Some "IO.Network");
  ("IO.NetListen",  Some "IO.Network");
  ("IO.Database",   Some "IO.NetConnect");
  ("IO.Process",    Some "IO");
  ("IO.Clock",      Some "IO");
  ("IO.Random",     Some "IO");
]
```

---

- [ ] **Step 0b: Add to type builtins table**

File: `lib/typecheck/typecheck.ml`, line 1591–1594.

Current:
```ocaml
    ("IO",            0); ("IO.Console",    0); ("IO.FileSystem", 0);
    ("IO.FileRead",   0); ("IO.FileWrite",  0); ("IO.Network",    0);
    ("IO.NetConnect", 0); ("IO.NetListen",  0); ("IO.Process",    0);
    ("IO.Clock",      0);
```

Change to:
```ocaml
    ("IO",            0); ("IO.Console",    0); ("IO.FileSystem", 0);
    ("IO.FileRead",   0); ("IO.FileWrite",  0); ("IO.Network",    0);
    ("IO.NetConnect", 0); ("IO.NetListen",  0); ("IO.Database",   0);
    ("IO.Process",    0); ("IO.Clock",      0); ("IO.Random",     0);
```

---

- [ ] **Step 0c: Build and verify hierarchy is intact**

```bash
dune build 2>&1 | head -20
```

Expected: clean build. The new caps appear in the hierarchy and type table but nothing uses them yet.

---

## Task 1: Builtin→Cap Table and `calls_in_expr`

**Scope:** `lib/typecheck/typecheck.ml` (new definitions near `io_cap_hierarchy`)  
**LoE:** ~0.5 days

---

- [ ] **Step 1a: Add `builtin_cap_table` after `cap_subsumes`**

Insert after the `cap_subsumes` definition (currently ends at line ~911). This table is the authoritative mapping from builtin name to required capability.

```ocaml
(** Mapping from builtin function name to the minimum capability it requires.
    Builtins not in this table are pure and require no capability. *)
let builtin_cap_table : string StringMap.t = StringMap.of_list [
  (* IO.Console *)
  ("println",               "IO.Console");
  ("print",                 "IO.Console");
  (* IO.FileRead *)
  ("file_exists",           "IO.FileRead");
  ("file_read",             "IO.FileRead");
  ("file_open",             "IO.FileRead");
  ("file_read_line",        "IO.FileRead");
  ("file_read_chunk",       "IO.FileRead");
  ("file_stat",             "IO.FileRead");
  ("dir_exists",            "IO.FileRead");
  ("dir_list",              "IO.FileRead");
  ("csv_open",              "IO.FileRead");
  ("csv_next_row",          "IO.FileRead");
  (* IO.FileWrite *)
  ("file_write",            "IO.FileWrite");
  ("file_append",           "IO.FileWrite");
  ("file_delete",           "IO.FileWrite");
  ("file_rename",           "IO.FileWrite");
  ("dir_mkdir",             "IO.FileWrite");
  ("dir_mkdir_p",           "IO.FileWrite");
  ("dir_rmdir",             "IO.FileWrite");
  ("dir_rm_rf",             "IO.FileWrite");
  (* IO.FileSystem (covers both read + write) *)
  ("file_copy",             "IO.FileSystem");
  (* IO.NetConnect *)
  ("tcp_connect",           "IO.NetConnect");
  ("tcp_send_all",          "IO.NetConnect");
  ("tcp_recv_all",          "IO.NetConnect");
  ("tcp_recv_exact",        "IO.NetConnect");
  ("tcp_recv_http",         "IO.NetConnect");
  ("tcp_recv_http_headers", "IO.NetConnect");
  ("tcp_recv_chunk",        "IO.NetConnect");
  ("tcp_recv_chunked_frame","IO.NetConnect");
  ("ws_recv",               "IO.NetConnect");
  ("ws_send",               "IO.NetConnect");
  ("ws_select",             "IO.NetConnect");
  (* IO.Network *)
  ("dns_resolve",           "IO.Network");
  (* IO.NetListen *)
  ("http_server_listen",    "IO.NetListen");
  ("http_server_spawn_n",   "IO.NetListen");
  ("http_server_wait",      "IO.NetListen");
  (* IO.Process *)
  ("process_env",           "IO.Process");
  ("process_set_env",       "IO.Process");
  ("process_cwd",           "IO.Process");
  ("process_argv",          "IO.Process");
  ("process_pid",           "IO.Process");
  ("process_exit",          "IO.Process");
  ("process_spawn_sync",    "IO.Process");
  ("process_spawn_lines",   "IO.Process");
  ("process_spawn_async",   "IO.Process");
  ("process_read_line",     "IO.Process");
  ("process_write",         "IO.Process");
  ("process_kill_proc",     "IO.Process");
  ("process_wait_proc",     "IO.Process");
  (* IO.Clock *)
  ("unix_time",             "IO.Clock");
  ("unix_time_ms",          "IO.Clock");
  ("uuid_v7",               "IO.Clock");
  ("sys_uptime_ms",         "IO.Clock");
  (* IO.Random *)
  ("random_bytes",          "IO.Random");
  ("stdlib_random_bytes",   "IO.Random");
  ("uuid_v4",               "IO.Random");
]
```

Note: `StringMap` is already in scope in `typecheck.ml` (it's `StrMap` — check which alias is used and match the existing style).

---

- [ ] **Step 1b: Check the correct map module name**

```bash
grep -n "StringMap\|StrMap\|String_map" lib/typecheck/typecheck.ml | head -5
```

Use whichever alias is already in scope. If it's `StrMap`, change `StringMap.of_list` to `StrMap.of_list`. If neither has `of_list`, use a list fold:

```ocaml
let builtin_cap_table : string StrMap.t =
  List.fold_left (fun m (k, v) -> StrMap.add k v m) StrMap.empty [
    ...
  ]
```

---

- [ ] **Step 1c: Add `calls_in_expr` after `builtin_cap_table`**

This walker collects `(cap_required, span)` pairs for every builtin call in an expression tree.

```ocaml
(** [calls_in_expr e] walks [e] and returns [(cap, span)] for every call to a
    builtin in [builtin_cap_table].  Descends into lambdas, let-bindings,
    match arms, if branches, records, tuples, and pipes. *)
let rec calls_in_expr (e : Ast.expr) : (string * Ast.span) list =
  match e with
  | Ast.EApp (Ast.EVar name, args, sp) ->
    let head = match StrMap.find_opt name.txt builtin_cap_table with
      | Some cap -> [(cap, sp)]
      | None -> []
    in
    head @ List.concat_map calls_in_expr args
  | Ast.EApp (f, args, _) ->
    calls_in_expr f @ List.concat_map calls_in_expr args
  | Ast.ELam (_, body, _) -> calls_in_expr body
  | Ast.ELet (_, rhs, body, _) -> calls_in_expr rhs @ calls_in_expr body
  | Ast.ELetFn (_, _, _, body, _) -> calls_in_expr body
  | Ast.EBlock (exprs, _) -> List.concat_map calls_in_expr exprs
  | Ast.EIf (cond, t, f_opt, _) ->
    calls_in_expr cond @ calls_in_expr t @
    Option.fold ~none:[] ~some:calls_in_expr f_opt
  | Ast.EMatch (scrut, arms, _) ->
    calls_in_expr scrut @
    List.concat_map (fun arm -> calls_in_expr arm.Ast.arm_body) arms
  | Ast.ERecord (fields, _) ->
    List.concat_map (fun (_, e) -> calls_in_expr e) fields
  | Ast.ERecordUpdate (base, fields, _) ->
    calls_in_expr base @
    List.concat_map (fun (_, e) -> calls_in_expr e) fields
  | Ast.ETuple (es, _) -> List.concat_map calls_in_expr es
  | Ast.EPipe (lhs, rhs, _) -> calls_in_expr lhs @ calls_in_expr rhs
  | _ -> []
```

Check the exact AST constructors against `lib/ast/ast.ml` — names like `EBlock`, `ELetFn`, `ERecordUpdate` may differ slightly. The key cases are `EApp`, `ELam`, `ELet`, `EBlock`, `EIf`, `EMatch`.

---

- [ ] **Step 1d: Build and verify no regressions**

```bash
dune build 2>&1 | head -20
scripts/run-tests.sh -q 2>&1 | tail -5
```

Expected: clean build, all tests pass. No new warnings yet — the new definitions are not wired into `check_module_needs`.

---

## Task 2: Extend `check_module_needs`

**Scope:** `lib/typecheck/typecheck.ml`, `check_module_needs` function (line ~4626)  
**LoE:** ~0.5 days

The existing `used_caps` collects `Cap(X)` occurrences from function **signatures**. This task adds `body_cap_uses` that collects required caps from function **bodies** via `calls_in_expr`.

---

- [ ] **Step 2a: Add body scanning to `check_module_needs`**

The `used_caps` binding (currently at line ~4631) and the `declared_needs` binding (line ~4627) are already in scope. After the closing `)` of the `used_caps` let-binding (currently at line ~4653), add:

```ocaml
  (* Body-level cap uses: walk every DFn body and DLet RHS for builtin calls. *)
  let body_cap_uses : (string * Ast.span) list =
    List.concat_map (function
      | Ast.DFn (def, _) ->
        List.concat_map (fun clause ->
          calls_in_expr clause.Ast.fc_body
        ) def.fn_clauses
      | Ast.DLet (_, rhs, _) ->
        calls_in_expr rhs
      | _ -> []
    ) decls
  in
  let all_used_caps = used_caps @ body_cap_uses in
```

Then replace every reference to `used_caps` in Checks 1, 2, 3, and the `used` predicate in Check 2 with `all_used_caps`:

- Check 1 iterates `used_caps` → change to `all_used_caps`
- Check 2's `used` predicate: `List.exists (fun (cap_path, _) -> ...) used_caps` → `all_used_caps`
- Check 3 iterates `used_caps` → change to `all_used_caps`

Check 4 (transitive import check) and Checks 5/6 do NOT use `used_caps` — leave those unchanged.

---

- [ ] **Step 2b: Improve Check 1 error message for body-call violations**

When Check 1 fires for a cap that came from `body_cap_uses` (not from a signature), the error message should say "body call" rather than the generic form. Track the source in the cap tuple:

Add a type alias for clarity:
```ocaml
type cap_source = SigCap | BodyCap of string (* builtin name *)
```

Then thread `cap_source` through `used_caps` and `body_cap_uses`. In Check 1, when `src = BodyCap builtin_name`, emit:

```
error[E0431]: `file_read` requires capability `IO.FileRead`
  --> src/loader.march:14:20
   |
14 |   let content = file_read(path)
   |                 ^^^^^^^^^ requires IO.FileRead
   |
   = this module calls `file_read` but does not declare `needs IO.FileRead`
   = help: add `needs IO.FileRead` to mod Loader
   = note: `IO.FileRead` is a child of `IO.FileSystem`; `needs IO.FileSystem`
           would also satisfy this requirement
```

The "also satisfies" note is generated by filtering `cap_ancestors(req_cap)` to drop the cap itself.

**Note:** This step adds some type-annotation plumbing. If it delays shipping, skip it — the existing Check 1 message format is acceptable for initial rollout.

---

- [ ] **Step 2c: Build and run full test suite**

```bash
dune build 2>&1 | head -20
scripts/run-tests.sh 2>&1 | tail -20
```

At this point, if any stdlib module calls an IO builtin without a `needs` declaration, the typechecker will emit a **warning** (since we start in warning mode). Verify the warnings appear and point to the right modules.

**Expected warnings before Task 3:**
- `stdlib/io.march` — `println`/`print` without `needs IO.Console`
- `stdlib/file.march` — `file_read`/`file_write` etc. without `needs IO.FileRead`/`IO.FileWrite`
- `stdlib/dir.march` — `dir_list` etc. without `needs IO.FileRead`/`IO.FileWrite`
- `stdlib/system.march` — `process_env` etc. without `needs IO.Process`
- `stdlib/uuid.march` — `uuid_v4`/`uuid_v7` without `needs IO.Random`/`IO.Clock`
- `stdlib/crypto.march` — `stdlib_random_bytes` without `needs IO.Random`

These warnings confirm the scanner is working before Task 3 silences them.

---

## Task 3: Stdlib and Depot Annotation

**Scope:** Stdlib `.march` files + Depot wire layer  
**LoE:** ~1 day

For each file: add `needs X` line(s) immediately after the `mod Name do` opening line. The declaration goes before any `type`, `pfn`, or `fn` definitions.

---

### stdlib/io.march

- [ ] **Step 3a: Add `needs IO.Console`**

File: `stdlib/io.march`, line 15–16. Add after `mod IO do`:
```march
mod IO do
  needs IO.Console
```

Verify: `stdlib/io.march` calls `println` (line ~23), `print` (line ~18). Both covered by `IO.Console`.

---

### stdlib/file.march

- [ ] **Step 3b: Add `needs IO.FileRead`, `needs IO.FileWrite`**

File: `stdlib/file.march`, line 8–9. Add after `mod File do`:
```march
mod File do
  needs IO.FileRead
  needs IO.FileWrite
```

Check: `file_copy` → `IO.FileSystem` in the builtin table. `IO.FileSystem` is the parent of both `IO.FileRead` and `IO.FileWrite`; declaring the two children also satisfies `file_copy`'s `IO.FileSystem` requirement because `cap_subsumes "IO.FileRead" "IO.FileSystem"` and `cap_subsumes "IO.FileWrite" "IO.FileSystem"` — wait, that's backwards. `cap_subsumes parent child` means parent is an ancestor of child. `IO.FileSystem` is the *parent* of both.

So `needs IO.FileSystem` would cover `file_copy`. But `needs IO.FileRead` alone does NOT cover `file_copy` (IO.FileSystem ≠ IO.FileRead). Options:
- Declare `needs IO.FileSystem` instead of the two children (covers both + file_copy)
- Or declare `needs IO.FileRead`, `needs IO.FileWrite`, `needs IO.FileSystem` (redundant but explicit)
- Or remap `file_copy` → `IO.FileWrite` in the table (copy writes the destination; reading is incidental)

**Recommended:** Remap `file_copy` to `IO.FileWrite` in `builtin_cap_table`. Rationale: a function that can write files can certainly copy them. The file_copy operation is destructive (creates or overwrites the destination) so the write cap is the more meaningful gate.

Update `builtin_cap_table`:
```ocaml
  ("file_copy",             "IO.FileWrite");  (* was IO.FileSystem *)
```

Then `stdlib/file.march` only needs:
```march
mod File do
  needs IO.FileRead
  needs IO.FileWrite
```

---

### stdlib/dir.march

- [ ] **Step 3c: Add `needs IO.FileRead`, `needs IO.FileWrite`**

File: `stdlib/dir.march`, line 6–7. Add after `mod Dir do`:
```march
mod Dir do
  needs IO.FileRead
  needs IO.FileWrite
```

Verify: `dir_list` → `IO.FileRead`; `dir_mkdir`, `dir_rmdir`, `dir_rm_rf` → `IO.FileWrite`. All covered.

---

### stdlib/system.march

- [ ] **Step 3d: Add `needs IO.Process`**

File: `stdlib/system.march`, line 20–21. Add after `mod System do`:
```march
mod System do
  needs IO.Process
```

`monotonic_time` calls `sys_uptime_ms` → `IO.Clock`. Add `needs IO.Clock` too:
```march
mod System do
  needs IO.Process
  needs IO.Clock
```

Verify: `process_env`, `process_argv`, `process_cwd`, `process_pid`, `process_exit`, `process_spawn_sync` → `IO.Process`. `sys_uptime_ms` → `IO.Clock`. All covered.

---

### stdlib/uuid.march

- [ ] **Step 3e: Add `needs IO.Random`, `needs IO.Clock`**

File: `stdlib/uuid.march`, line 16–17. Add after `mod UUID do`:
```march
mod UUID do
  needs IO.Random
  needs IO.Clock
```

Verify: `uuid_v4` → `IO.Random`; `uuid_v7` → `IO.Clock`. Both covered.

---

### stdlib/crypto.march

- [ ] **Step 3f: Add `needs IO.Random`**

File: `stdlib/crypto.march`, line 18–19. Add after `mod Crypto do`:
```march
mod Crypto do
  needs IO.Random
```

Verify: `stdlib_random_bytes` → `IO.Random`; `random_bytes` (the private wrapper) also calls `stdlib_random_bytes`. Both covered. Hash functions (`sha256`, `hmac_sha256`, `pbkdf2_sha256`) are **pure** and not in the table — no additional caps needed.

---

### Note: stdlib/random.march

`stdlib/random.march` (mod Random) is a **pure** functional PRNG (xoshiro256**). It calls no IO builtins. Do NOT add any `needs` declaration here.

---

### Depot: wire/connection.march and wire/pool.march

The Depot library is in a separate repo at `/Users/80197052/code/depot`. These changes are outside the March stdlib but required before body-scanning is promoted to an error.

- [ ] **Step 3g: Annotate `depot/lib/wire/connection.march`**

File: `/Users/80197052/code/depot/lib/wire/connection.march`, line 3 (after `mod Connection do`):
```march
mod Connection do
  needs IO.NetConnect
  needs IO.Database
```

Verify: calls `tcp_connect` (→ IO.NetConnect), `tcp_send_all` (→ IO.NetConnect), `tcp_close` (no cap), `tcp_recv_exact` (→ IO.NetConnect). All IO.NetConnect. `IO.Database` is declaration-only (no builtin enforces it), but it propagates transitively.

- [ ] **Step 3h: Annotate `depot/lib/wire/pool.march`**

File: `/Users/80197052/code/depot/lib/wire/pool.march`, line 3 (after `mod Pool do`):
```march
mod Pool do
  needs IO.NetConnect
  needs IO.Database
```

- [ ] **Step 3i: Run full test suite, confirm zero new warnings**

```bash
scripts/run-tests.sh 2>&1 | tail -20
```

Expected: all existing tests pass, zero new capability warnings. The annotations silence the warnings introduced in Task 2.

---

## Task 4: Tests

**Scope:** `test/test_march.ml`  
**LoE:** ~0.5 days

Add a new test group `cap_body_enforce` with 15 cases. Find the existing `capabilities` group and add the new group immediately after it.

---

- [ ] **Step 4a: Add test group `cap_body_enforce`**

Each test is a `check_error` or `check_ok` call (follow the pattern used in the existing `capabilities` group).

```ocaml
let cap_body_enforce_tests = [

  (* 1. Direct builtin call without needs → error *)
  check_error "println without needs IO.Console" {|
    mod M do
      fn f() do println("hi") end
    end
  |} "IO.Console";

  (* 2. file_read without needs IO.FileRead → error *)
  check_error "file_read without needs" {|
    mod M do
      fn f(p) do file_read(p) end
    end
  |} "IO.FileRead";

  (* 3. file_read with needs IO.FileRead → ok *)
  check_ok "file_read with exact needs" {|
    mod M do
      needs IO.FileRead
      fn f(p) do file_read(p) end
    end
  |};

  (* 4. file_read with parent cap IO.FileSystem → ok *)
  check_ok "file_read with parent needs IO.FileSystem" {|
    mod M do
      needs IO.FileSystem
      fn f(p) do file_read(p) end
    end
  |};

  (* 5. file_read with root cap IO → ok *)
  check_ok "file_read with root needs IO" {|
    mod M do
      needs IO
      fn f(p) do file_read(p) end
    end
  |};

  (* 6. Lambda body scanned — module flagged *)
  check_error "lambda calling file_read flagged on enclosing module" {|
    mod M do
      fn f(xs) do List.map(fn p -> file_read(p) end, xs) end
    end
  |} "IO.FileRead";

  (* 7. DLet body calling tcp_connect → error *)
  check_error "DLet body calling tcp_connect without needs" {|
    mod M do
      let conn = tcp_connect("localhost", 5432)
    end
  |} "IO.NetConnect";

  (* 8. Pure module with no needs and no IO calls → ok *)
  check_ok "pure module no needs required" {|
    mod M do
      fn add(a, b) do a + b end
    end
  |};

  (* 9. uuid_v4 requires IO.Random → error without needs *)
  check_error "uuid_v4 without needs IO.Random" {|
    mod M do
      fn f() do uuid_v4() end
    end
  |} "IO.Random";

  (* 10. uuid_v7 requires IO.Clock → error without needs *)
  check_error "uuid_v7 without needs IO.Clock" {|
    mod M do
      fn f() do uuid_v7() end
    end
  |} "IO.Clock";

  (* 11. needs IO.Random satisfies random_bytes → ok *)
  check_ok "random_bytes with needs IO.Random" {|
    mod M do
      needs IO.Random
      fn f(n) do random_bytes(n) end
    end
  |};

  (* 12. process_argv without needs IO.Process → error *)
  check_error "process_argv without needs IO.Process" {|
    mod M do
      fn f() do process_argv() end
    end
  |} "IO.Process";

  (* 13. Existing Cap-param check still passes (regression) *)
  check_ok "Cap param signature check still works" {|
    mod M do
      needs IO.FileRead
      fn f(cap : Cap(IO.FileRead), p) do file_read(p) end
    end
  |};

  (* 14. tcp_connect with needs IO.Database (child of IO.NetConnect) → ok
         IO.Database < IO.NetConnect, so needs IO.NetConnect satisfies
         the IO.NetConnect requirement from tcp_connect *)
  check_ok "tcp_connect with needs IO.NetConnect covers IO.Database child" {|
    mod M do
      needs IO.NetConnect
      needs IO.Database
      fn connect(host, port) do tcp_connect(host, port) end
    end
  |};

  (* 15. unused needs still warns (Check 2 regression) *)
  check_warning "unused needs IO.Process warns" {|
    mod M do
      needs IO.Process
      fn f(x) do x + 1 end
    end
  |} "unused capability";

]
```

Wire into the test suite by adding `cap_body_enforce_tests` to the existing list of test groups in `let () = Alcotest.run "march" [...]`.

---

- [ ] **Step 4b: Run the new test group in isolation**

```bash
dune build test/run_compiler.exe
./_build/default/test/run_compiler.exe -e 2>&1 | grep "cap_body"
```

Expected: all 15 cases pass.

---

- [ ] **Step 4c: Run the full suite**

```bash
scripts/run-tests.sh 2>&1 | tail -5
```

Expected: all existing tests still pass, new group adds 15 green cases.

---

## Promotion to Error (follow-up)

After one release cycle with warnings:

- [ ] In `check_module_needs`, change `Err.warning` for body-cap violations to `Err.error`.
- [ ] Remove `--no-strict-caps` flag if it was added.
- [ ] Update `specs/todos.md` — mark both P2 items done.
- [ ] Update `specs/progress.md` — add to feature list, update test count.

---

## Summary

| Task | What | LoE |
|---|---|---|
| 0 — Hierarchy | Add `IO.Random`, `IO.Database` to hierarchy + type table | 0.5h |
| 1 — Scanner | `builtin_cap_table` + `calls_in_expr` walker | 0.5d |
| 2 — Enforcement | Extend `check_module_needs` with body scan | 0.5d |
| 3 — Annotation | Stdlib needs declarations + Depot wire layer | 1d |
| 4 — Tests | 15 new `cap_body_enforce` test cases | 0.5d |
| **Total** | | **~2.5d** |
