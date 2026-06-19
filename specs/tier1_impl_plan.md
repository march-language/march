# Tier 1 Implementation Plan

Three items, ordered by dependency. Each is implementation-ready: all design
decisions have been made, file locations are pinned, and test lists are
complete.

**Total estimated LoE:** ~3.5–4 days for all three.

---

## Item 1 — Capability Body Enforcement: Phase 1 (stdlib annotation)

**LoE:** 0.5–1 day  
**Risk:** None — purely additive `needs` declarations, no type-checker changes  
**Full spec:** `specs/capability-body-enforcement.md §Phase 1`

### What to do

Add `needs` declarations to the top of eight stdlib modules. Each `needs` line
goes inside the `mod Name do` block, at the top before any `fn` declarations.

| File | Lines to add |
|------|-------------|
| `stdlib/io.march` | `needs IO.Console` |
| `stdlib/file.march` | `needs IO.FileRead`, `needs IO.FileWrite` |
| `stdlib/dir.march` | `needs IO.FileRead`, `needs IO.FileWrite` |
| `stdlib/system.march` | `needs IO.Process`, `needs IO.Clock` |
| `stdlib/csv.march` | `needs IO.FileRead` |
| `stdlib/uuid.march` | `needs IO.Random` |
| `stdlib/random.march` | `needs IO.Random` |
| `stdlib/crypto.march` | `needs IO.Random` |

**`IO.Random` and `IO.Clock` don't exist yet** — add them to `io_cap_hierarchy`
in `lib/typecheck/typecheck.ml` at line ~902 before touching any stdlib files:

```ocaml
(* lib/typecheck/typecheck.ml ~line 902 *)
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
  ("IO.Random",     Some "IO");     (* NEW *)
  ("IO.Database",   Some "IO.NetConnect"); (* NEW — declaration-only, no builtins *)
]
```

`IO.Database` has no entries in the `builtin_cap_table` (Phase 2). It is a
semantic marker: Depot's wire layer will declare `needs IO.Database`, which
then propagates transitively to any app that imports Depot via the existing
Check 4. An app that already declares `needs IO.NetConnect` automatically
satisfies it (parent subsumes child via `cap_subsumes`).

### Verification

Run `scripts/run-tests.sh` after each file. All 1535 tests must pass.
The new `needs` declarations only break compilation if a module imports the
annotated stdlib module AND the importing module is already missing a `needs`
declaration — which no existing test does.

---

## Item 2 — Capability Body Enforcement: Phase 2 (body-scanning pass)

**LoE:** 1.5 days  
**Risk:** Low — warning-first; existing tests unaffected until warnings→errors  
**Full spec:** `specs/capability-body-enforcement.md §Phase 2`  
**Prerequisite:** Item 1 done (hierarchy has `IO.Random`, `IO.Database`)

### Key reuse: `calls_in_expr` already exists

The `cap no_panic` implementation (Phase 3c, committed) added `calls_in_expr`
at `lib/typecheck/typecheck.ml:5434`. It collects `(string * Ast.span) list`
from any expression, walking lambdas, blocks, let-bindings, match arms, and
if-expressions. **Do not write a new traversal** — use this one directly.

The only difference from the no_panic use: instead of checking against
`panic_surface_*` sets, we look up each call name in `builtin_cap_table`.

### Step 1 — Add `builtin_cap_table`

Place this near `io_cap_hierarchy` (~line 902):

```ocaml
(* lib/typecheck/typecheck.ml — near io_cap_hierarchy *)
let builtin_cap_table : string StrMap.t = StrMap.of_list [
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
  (* IO.FileSystem — needs both read+write *)
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
  (* IO.Random *)
  ("random_bytes",          "IO.Random");
  ("stdlib_random_bytes",   "IO.Random");
  ("uuid_v4",               "IO.Random");
]
```

### Step 2 — Collect body cap uses in `check_module_needs`

`check_module_needs` lives at line ~4634. Currently it builds `used_caps` only
from function parameter and return type annotations (`cap_paths_in_surface_ty`).

Extend it to also collect from function bodies and `DLet` RHS expressions.
Insert the following immediately after the existing `used_caps` definition
(after the closing `) decls in` at line ~4661):

```ocaml
(* lib/typecheck/typecheck.ml — inside check_module_needs, after used_caps *)
let body_cap_uses : (string * Ast.span) list =
  List.concat_map (function
    | Ast.DFn (def, _) ->
      List.concat_map (fun clause ->
        List.filter_map (fun (call_name, call_span) ->
          StrMap.find_opt call_name builtin_cap_table
          |> Option.map (fun cap -> (cap, call_span))
        ) (calls_in_expr [] clause.Ast.fc_body)
      ) def.fn_clauses
    | Ast.DLet (_vis, b, _) ->
      List.filter_map (fun (call_name, call_span) ->
        StrMap.find_opt call_name builtin_cap_table
        |> Option.map (fun cap -> (cap, call_span))
      ) (calls_in_expr [] b.Ast.bind_expr)
    | _ -> []
  ) decls
in
let all_used_caps = used_caps @ body_cap_uses in
```

Then replace every subsequent reference to `used_caps` in `check_module_needs`
with `all_used_caps`. There are three sites:
- Check 1 (`List.iter (fun (cap_path, sp) -> ...`) at line ~4666
- Check 2 (`let used = List.exists ...`) at line ~4704
- Check 3 (IO root hint) at line ~4714

### Step 3 — Warning vs error mode

Phase 2 ships as a **warning** initially. In the Check 1 error path, replace
`Err.error` with `Err.warning` for errors that originate from `body_cap_uses`
(not from signature uses). The cleanest way: tag each `(cap, span)` in
`body_cap_uses` with a `Body` provenance marker, and use `Err.warning` for
those:

```ocaml
(* Tag provenance *)
type cap_source = Sig | Body

let body_cap_uses : (string * Ast.span * cap_source) list = ...
let sig_cap_uses  : (string * Ast.span * cap_source) list =
  List.map (fun (c, s) -> (c, s, Sig)) used_caps in
let all_used_caps = sig_cap_uses @ body_cap_uses in

(* In Check 1: *)
List.iter (fun (cap_path, sp, source) ->
  ...
  if not covered && not self_declared then
    (match source with
     | Body -> Err.warning env.errors ~span:sp (...)
     | Sig  -> Err.error   env.errors ~span:sp (...))
) all_used_caps;
```

For Check 2 and Check 3, use `all_used_caps` without the provenance tag (just
strip it: `List.map (fun (c, s, _) -> (c, s)) all_used_caps`).

### Tests

New group `cap_body_enforce` in `test/test_compiler.ml` (model after
`opts_no_panic` suite — use the `typecheck` helper):

1. `println` without `needs IO.Console` → warning (has_errors = true, or
   check for warning specifically using `Errors.warnings`)
2. `file_read` without `needs IO.FileRead` → warning
3. `file_read` with `needs IO.FileRead` → ok
4. `file_read` with `needs IO.FileSystem` (parent cap) → ok
5. `file_read` with `needs IO` (root) → ok
6. `file_copy` requires `needs IO.FileSystem` (not FileRead or FileWrite alone)
7. Lambda inside HOF calling `file_read` → flags the enclosing module
8. `DLet` body calling `tcp_connect` → warning on module missing `needs IO.NetConnect`
9. Pure fn, no builtins, no `needs` → ok
10. `uuid_v4` without `needs IO.Random` → warning
11. `uuid_v7` without `needs IO.Clock` → warning
12. `random_bytes` with `needs IO.Random` → ok
13. `process_argv` without `needs IO.Process` → warning
14. Existing signature-based Cap check (Check 1) still fires as error, not warning
15. Check 2: unused `needs IO.Console` when no IO builtins called → warning

---

## Item 3 — Record Field Auto-Satisfy (Feature 2)

**LoE:** 0.5–1 day (~35 lines)  
**Risk:** Very low — purely additive, only fires for anonymous TRecord types  
**Full spec:** `specs/structural-interface-satisfaction.md §Feature 2`

### What it does

When the compiler needs to discharge `CInterface("Named", TRecord[("name",
TString); ...])` and no explicit `impl Named(TRecord...)` exists, it checks
whether the anonymous record has a field whose name and type match the
interface's single accessor method. If so, the constraint is silently
satisfied — no error, no `impl` block required.

```march
interface Named(a) do
  fn name(a) -> String
end

-- No impl needed; anonymous records with a `name: String` field auto-satisfy:
fn greet(x) when Named(x) do "Hello, " ++ name(x) end
fn main() do greet({ name = "Alice", age = 30 }) end  -- ok
```

### Eligibility rules (all must hold)

1. Target type is anonymous `TRecord` (not a `TCon` named alias).
2. Interface has exactly **one** method.
3. Method shape is `a -> T` — unary accessor, where `a` is the interface
   type parameter. Binary or multi-arg methods are excluded.
4. Record has a field whose name equals the method name and whose type unifies
   with `T`.

### Exact change location

`lib/typecheck/typecheck.ml` — `discharge_constraints` at line ~4482, inside
the `CInterface` match arm. Currently:

```ocaml
| CInterface (iface_name, t) ->
  let ty = repr t in
  (match ty with
   | TVar _ -> ()
   | _ ->
     let satisfied = match StrMap.find_opt iface_name env.impls with
       | None -> false
       | Some impl_tys -> List.exists (fun impl_ty ->
           impl_matches_ty (repr impl_ty) ty) impl_tys
     in
     if not satisfied then
       Err.error env.errors ~span
         (Printf.sprintf
            "`%s` does not implement interface `%s`.\n\
             Add `impl %s(%s) do ... end` to provide an implementation."
            (pp_ty ty) iface_name iface_name (pp_ty ty)))
```

Replace the `if not satisfied then Err.error ...` block with:

```ocaml
     if not satisfied then begin
       (* Try record auto-satisfy before emitting an error.
          Applies only to anonymous TRecord types with a single-method
          accessor-shaped interface. *)
       let auto_satisfied =
         match ty with
         | TRecord flds ->
           (match StrMap.find_opt iface_name env.interfaces with
            | Some iface when List.length iface.iface_methods = 1 ->
              let m = List.hd iface.iface_methods in
              (* Check accessor shape: the method must be `a -> T` where
                 `a` is the interface's own type parameter. *)
              (match m.md_ty with
               | Ast.TyArrow (Ast.TyVar param, ret_surface)
                 when param.txt = iface.iface_param.txt ->
                 let ret_ty = surface_ty env ret_surface in
                 (match List.assoc_opt m.md_name.txt flds with
                  | Some fld_ty ->
                    (try unify env ~span ~reason:None fld_ty ret_ty; true
                     with _ -> false)
                  | None -> false)
               | _ -> false)
            | _ -> false)
         | _ -> false
       in
       if not auto_satisfied then
         Err.error env.errors ~span
           (Printf.sprintf
              "`%s` does not implement interface `%s`.\n\
               Add `impl %s(%s) do ... end` to provide an implementation."
              (pp_ty ty) iface_name iface_name (pp_ty ty))
     end
```

**Note on `surface_ty`:** Check how existing code converts `Ast.ty` to `ty` in
`discharge_constraints` — look for `infer_surface_ty` or `instantiate_surface`
calls nearby to use the right helper. The `surface_ty env` call here must match
whatever the rest of the function uses to resolve surface annotations.

**Note on `unify`:** Use `unify env ~span ~reason:None` (which may mutate
unification variables if the field type is polymorphic). Wrap in a `try/with`
to suppress the unification error if the types don't match — we just return
`false` and fall through to the standard error.

**Note on `TyArrow` shape:** March's surface AST uses `Ast.TyArrow` for
function types. An accessor-shaped method declaration in the interface is:
```march
fn name(a) -> String
```
which parses to `md_ty = TyArrow(TyVar "a", TyCon("String", []))`. The check
`param.txt = iface.iface_param.txt` confirms the argument type variable is the
interface's own parameter (not some other type variable).

### Tests

New group `record_auto_satisfy` in `test/test_compiler.ml`:

1. Single-method interface + anonymous record with matching field → no error
2. Single-method interface + anonymous record with wrong field type → error
3. Single-method interface + anonymous record missing field → error
4. Multi-method interface + anonymous record → error (auto-satisfy not applicable)
5. Non-accessor-shaped method (binary `fn eq(a, a) -> Bool`) → error
6. Named type alias `TCon("User", [])` does not auto-satisfy → error
7. Named type with explicit `impl` still satisfies → ok
8. Auto-satisfy fires inside `when Named(x)` constraint on function → ok
9. Generic function called with two different anonymous record shapes, both
   satisfying → ok (each monomorphized site discharges independently)

---

## Ordering and dependencies

```
Item 1  →  Item 2  →  (Item 3 is independent)
```

Item 3 has no dependency on Items 1 or 2. It can be done in parallel or first.
Items 1 and 2 must be done in order (hierarchy additions in Item 1 are required
before the body-scan in Item 2 can look up `IO.Random` and `IO.Database`).

Recommended sequence if working alone: **3 → 1 → 2**. Item 3 is the smallest
and most self-contained; do it first to build momentum. Items 1–2 then flow
naturally as a continuous session.

---

## Files changed summary

| File | Item 1 | Item 2 | Item 3 |
|------|--------|--------|--------|
| `lib/typecheck/typecheck.ml` | Add `IO.Random`, `IO.Database` to hierarchy | Add `builtin_cap_table`; extend `check_module_needs` | Extend `discharge_constraints` `CInterface` arm |
| `stdlib/io.march` | `needs IO.Console` | — | — |
| `stdlib/file.march` | `needs IO.FileRead`, `IO.FileWrite` | — | — |
| `stdlib/dir.march` | `needs IO.FileRead`, `IO.FileWrite` | — | — |
| `stdlib/system.march` | `needs IO.Process`, `IO.Clock` | — | — |
| `stdlib/csv.march` | `needs IO.FileRead` | — | — |
| `stdlib/uuid.march` | `needs IO.Random` | — | — |
| `stdlib/random.march` | `needs IO.Random` | — | — |
| `stdlib/crypto.march` | `needs IO.Random` | — | — |
| `test/test_compiler.ml` | — | 15 new tests (`cap_body_enforce`) | 9 new tests (`record_auto_satisfy`) |

No new AST nodes, no new keywords, no parser changes for any of the three items.
