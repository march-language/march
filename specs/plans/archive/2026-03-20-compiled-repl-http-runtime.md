# Compiled REPL + HTTP C Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the March REPL execute code via compile-and-dlopen (LLVM IR → clang → .so → dlopen) instead of the tree-walking interpreter, then implement HTTP/WS builtins as C runtime functions so the HTTP server works natively from day 1.

**Architecture:** Each REPL expression compiles to a shared library exporting a single entry function. The runtime (`march_runtime.c` + `march_http.c`) is pre-compiled to a shared library on first launch and cached. REPL bindings persist as LLVM globals with `RTLD_GLOBAL` visibility across dlopen'd fragments. HTTP builtins exist only in C (no eval.ml duplication) — the interpreter path remains for non-HTTP code, but HTTP servers require `--compile` or the compiled REPL.

**Tech Stack:** OCaml 5.3.0, LLVM IR (textual), clang, POSIX dlopen/dlsym, pthreads, POSIX sockets

---

## File Structure

| File | Role |
|------|------|
| **Create:** `lib/jit/jit.ml` | Compile-and-dlopen engine: compile .ll → .so, dlopen, dlsym, call, close |
| **Create:** `lib/jit/jit.mli` | Public interface for JIT module |
| **Create:** `lib/jit/dune` | Library definition with unix dependency |
| **Create:** `lib/jit/jit_stubs.c` | OCaml C stubs for dlopen/dlsym/dlclose (no ctypes dependency) |
| **Create:** `runtime/march_http.h` | HTTP/WS C function declarations |
| **Create:** `runtime/march_http.c` | HTTP/WS C implementations (server listen, parse, WS handshake, etc.) |
| **Create:** `runtime/sha1.c` | Vendored minimal SHA-1 (~80 lines) for WS handshake |
| **Create:** `runtime/base64.c` | Vendored minimal Base64 (~40 lines) for WS handshake |
| **Modify:** `lib/tir/llvm_emit.ml` | Add `emit_repl_expr`, `emit_repl_decl`, extend `mangle_extern` for HTTP builtins, add HTTP extern declarations |
| **Modify:** `lib/repl/repl.ml` | Replace `eval_expr`/`eval_decl` calls with JIT compile-and-run path |
| **Modify:** `lib/repl/dune` | Add `march_jit` and `march_tir` dependencies |
| **Modify:** `bin/main.ml` | Pre-compile runtime .so on REPL launch, pass to JIT; add `march_http.c` to `--compile` link step |
| **Modify:** `bin/dune` | Add `march_jit` dependency |
| **Modify:** `runtime/march_runtime.h` | Add `#include "march_http.h"` |
| **Modify:** `march.opam` | No new opam deps needed (dlopen is POSIX, SHA-1/Base64 are vendored) |
| **Create:** `test/test_jit.ml` | Tests for the JIT compile-and-dlopen path |

---

## Task 1: OCaml dlopen C Stubs

Minimal C stubs that expose POSIX `dlopen`/`dlsym`/`dlclose` to OCaml without requiring the `ctypes` opam package.

**Files:**
- Create: `lib/jit/jit_stubs.c`
- Create: `lib/jit/jit.ml`
- Create: `lib/jit/jit.mli`
- Create: `lib/jit/dune`

- [ ] **Step 1: Write the C stubs file**

```c
/* lib/jit/jit_stubs.c */
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <dlfcn.h>

/* dlopen(path, RTLD_NOW | RTLD_GLOBAL) → handle (nativeint)
   Empty string "" is treated as NULL (returns main program handle). */
CAMLprim value march_dlopen(value v_path) {
    CAMLparam1(v_path);
    const char *path = String_val(v_path);
    /* Treat empty string as NULL (main program handle) */
    if (path[0] == '\0') path = NULL;
    void *handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) caml_failwith(dlerror());
    CAMLreturn(caml_copy_nativeint((intnat)handle));
}

/* dlsym(handle, symbol) → function pointer (nativeint) */
CAMLprim value march_dlsym(value v_handle, value v_sym) {
    CAMLparam2(v_handle, v_sym);
    void *handle = (void *)Nativeint_val(v_handle);
    const char *sym = String_val(v_sym);
    void *ptr = dlsym(handle, sym);
    if (!ptr) caml_failwith(dlerror());
    CAMLreturn(caml_copy_nativeint((intnat)ptr));
}

/* dlclose(handle) → unit */
CAMLprim value march_dlclose(value v_handle) {
    CAMLparam1(v_handle);
    void *handle = (void *)Nativeint_val(v_handle);
    dlclose(handle);
    CAMLreturn(Val_unit);
}

/* Call a void→ptr function (for REPL expressions that return a March value).
   Takes a function pointer (nativeint), calls it, returns result as nativeint. */
CAMLprim value march_call_void_to_ptr(value v_fptr) {
    CAMLparam1(v_fptr);
    void *(*fn)(void) = (void *(*)(void))Nativeint_val(v_fptr);
    void *result = fn();
    CAMLreturn(caml_copy_nativeint((intnat)result));
}

/* Call a void→void function (for REPL declarations with side effects). */
CAMLprim value march_call_void_to_void(value v_fptr) {
    CAMLparam1(v_fptr);
    void (*fn)(void) = (void (*)(void))Nativeint_val(v_fptr);
    fn();
    CAMLreturn(Val_unit);
}

/* Call a void→i64 function (for REPL expressions returning Int/Bool). */
CAMLprim value march_call_void_to_int(value v_fptr) {
    CAMLparam1(v_fptr);
    int64_t (*fn)(void) = (int64_t (*)(void))Nativeint_val(v_fptr);
    int64_t result = fn();
    CAMLreturn(caml_copy_int64(result));
}

/* Call a void→double function (for REPL expressions returning Float). */
CAMLprim value march_call_void_to_float(value v_fptr) {
    CAMLparam1(v_fptr);
    double (*fn)(void) = (double (*)(void))Nativeint_val(v_fptr);
    double result = fn();
    CAMLreturn(caml_copy_double(result));
}
```

- [ ] **Step 2: Write the OCaml interface**

```ocaml
(* lib/jit/jit.mli *)

(** A handle to a loaded shared library. *)
type dl_handle

(** Open a shared library. Raises [Failure] on error.
    Symbols are loaded with RTLD_GLOBAL so later fragments see them. *)
val dlopen : string -> dl_handle

(** Look up a symbol in a shared library. Raises [Failure] if not found. *)
val dlsym : dl_handle -> string -> nativeint

(** Close a shared library handle. *)
val dlclose : dl_handle -> unit

(** Call a (void -> ptr) function pointer. Returns the result pointer as nativeint. *)
val call_void_to_ptr : nativeint -> nativeint

(** Call a (void -> void) function pointer. *)
val call_void_to_void : nativeint -> unit

(** Call a (void -> i64) function pointer. *)
val call_void_to_int : nativeint -> int64

(** Call a (void -> double) function pointer. *)
val call_void_to_float : nativeint -> float
```

- [ ] **Step 3: Write the OCaml implementation**

```ocaml
(* lib/jit/jit.ml *)

type dl_handle = nativeint

external dlopen : string -> dl_handle = "march_dlopen"
external dlsym : dl_handle -> string -> nativeint = "march_dlsym"
external dlclose : dl_handle -> unit = "march_dlclose"
external call_void_to_ptr : nativeint -> nativeint = "march_call_void_to_ptr"
external call_void_to_void : nativeint -> unit = "march_call_void_to_void"
external call_void_to_int : nativeint -> int64 = "march_call_void_to_int"
external call_void_to_float : nativeint -> float = "march_call_void_to_float"
```

- [ ] **Step 4: Write the dune file**

```
; lib/jit/dune
; Note: -ldl is needed on Linux but not macOS (dlopen is in libSystem).
; This project targets macOS, so no -ldl needed. For Linux, add
; (c_library_flags (-ldl)) later.
(library
 (name march_jit)
 (libraries unix)
 (c_names jit_stubs))
```

- [ ] **Step 5: Build and verify it compiles**

Run: `/Users/80197052/.opam/march/bin/dune build lib/jit/march_jit.cma`
Expected: Clean build, no errors.

- [ ] **Step 6: Write a smoke test**

Create `test/test_jit.ml` with a basic dlopen test that opens libc and calls `getpid`:

```ocaml
(* Add to test/test_jit.ml *)
let test_dlopen_libc () =
  (* On macOS, dlopen(NULL) gives the main program handle which includes libc *)
  let handle = March_jit.Jit.dlopen "" in
  (* getpid is always available *)
  let _sym = March_jit.Jit.dlsym handle "getpid" in
  March_jit.Jit.dlclose handle;
  Alcotest.(check pass) "dlopen/dlsym/dlclose round-trip" () ()
```

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/jit/jit_stubs.c lib/jit/jit.ml lib/jit/jit.mli lib/jit/dune test/test_jit.ml
git commit -m "feat(jit): add OCaml dlopen/dlsym C stubs for compile-and-run REPL"
```

---

## Task 2: LLVM IR Emission for REPL Expressions

Extend `llvm_emit.ml` with functions that emit REPL expressions and declarations as standalone callable functions (not wrapped in `@main`). Each REPL input becomes a function `@repl_N` that can be dlsym'd and called.

**Files:**
- Modify: `lib/tir/llvm_emit.ml`

**Context:** The existing `emit_module` (line 1102) emits all functions from a `tir_module` and optionally appends a `@main` wrapper. For the REPL, we need:
- `emit_repl_expr` — wraps a TIR expression in a `@repl_N() -> result_type` function
- `emit_repl_decl` — wraps a TIR declaration (fn/let) and stores the result in a global symbol
- Both must emit `declare` directives for all previously-defined globals (from earlier REPL fragments)

- [ ] **Step 1: Add global symbol tracking type**

Add at the top of `llvm_emit.ml`, after the `ctx` type definition (line ~40):

```ocaml
(** Tracks REPL globals across fragments. Each entry:
    (llvm_name, llvm_type_string).  Example: ("repl_x", "ptr") *)
type repl_globals = (string * string) list ref
```

- [ ] **Step 2: Add `emit_repl_globals_decl` helper**

Emits `@repl_x = external global ptr` declarations for all previously defined REPL globals so the current fragment can reference them:

```ocaml
let emit_repl_globals_decl (buf : Buffer.t) (globals : (string * string) list) =
  List.iter (fun (name, ty) ->
    Printf.bprintf buf "@%s = external global %s\n" name ty
  ) globals
```

- [ ] **Step 3a: Expose `llvm_ty` from `llvm_emit.ml`**

`llvm_ty` is currently a private function in `llvm_emit.ml`. It's needed by `repl_jit.ml` to track REPL global types. Add a public wrapper:

```ocaml
(* At the end of llvm_emit.ml, add: *)
let llvm_ty_of_tir = llvm_ty
```

Since `march_tir` doesn't have a `.mli` for `llvm_emit`, this function is automatically public.

- [ ] **Step 3b: Add `emit_repl_expr` function**

Emits a REPL expression as a callable function `@repl_N` that returns the result. The expression is lowered through the full TIR pipeline first (by the caller), then this function emits it as LLVM IR:

```ocaml
(** Emit a REPL expression as a standalone .ll fragment.
    Returns textual LLVM IR with a function [@repl_<n>] that computes
    and returns the expression result.
    [prev_globals] are (name, llvm_ty) pairs from earlier REPL inputs.
    [fns] are any helper functions the expression depends on. *)
let emit_repl_expr ?(fast_math=false) ~(n : int) ~(ret_ty : Tir.ty)
    ~(prev_globals : (string * string) list)
    ~(fns : Tir.fn_def list)
    ~(types : Tir.type_def list)
    (body : Tir.expr) : string =
  let ctx = make_ctx ~fast_math () in
  (* Register type info *)
  build_ctor_info ctx { tm_types = types; tm_fns = fns };
  List.iter (fun fn -> Hashtbl.replace ctx.top_fns fn.Tir.fn_name true) fns;
  (* Emit helper functions *)
  List.iter (emit_fn ctx) fns;
  (* Emit the REPL entry function *)
  let ret_llty = llvm_ty ret_ty in
  let fname = Printf.sprintf "repl_%d" n in
  Printf.bprintf ctx.buf "\ndefine %s @%s() {\nentry:\n" ret_llty fname;
  let (_ty, result) = emit_expr ctx body in
  Printf.bprintf ctx.buf "  ret %s %s\n}\n" ret_llty result;
  (* Assemble the full .ll *)
  let out = Buffer.create 4096 in
  emit_preamble out;
  emit_repl_globals_decl out prev_globals;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.contents out
```

Note: `build_ctor_info`, `llvm_ty`, `emit_fn`, `emit_expr`, `emit_preamble` are all existing functions in `llvm_emit.ml`. `build_ctor_info` (line 1034) expects a `tir_module` — we pass a synthetic one with the types and functions. `llvm_ty` is currently private to `llvm_emit.ml` — you must expose it (add to `.mli` or create a public helper; see Step 3a below). The key design point is: one function `@repl_N`, no `@main` wrapper, globals declared as `external`.

- [ ] **Step 4: Add `emit_repl_decl` function**

For `let x = expr`, emits a global `@repl_x` and a `@repl_N_init` function that computes the value and stores it:

```ocaml
(** Emit a REPL let-binding as a .ll fragment.
    Creates a global [@repl_<name>] and an init function [@repl_<n>_init]
    that computes the value and stores it in the global. *)
let emit_repl_decl ?(fast_math=false) ~(n : int) ~(name : string)
    ~(val_ty : Tir.ty)
    ~(prev_globals : (string * string) list)
    ~(fns : Tir.fn_def list)
    ~(types : Tir.type_def list)
    (body : Tir.expr) : string =
  let ctx = make_ctx ~fast_math () in
  build_ctor_info ctx { tm_types = types; tm_fns = fns };
  List.iter (fun fn -> Hashtbl.replace ctx.top_fns fn.Tir.fn_name true) fns;
  List.iter (emit_fn ctx) fns;
  let llty = llvm_ty val_ty in
  let global_name = "repl_" ^ name in
  let init_name = Printf.sprintf "repl_%d_init" n in
  (* Define the global *)
  Printf.bprintf ctx.preamble "@%s = global %s zeroinitializer\n" global_name llty;
  (* Emit init function: compute value, store to global *)
  Printf.bprintf ctx.buf "\ndefine void @%s() {\nentry:\n" init_name;
  let (_ty, result) = emit_expr ctx body in
  Printf.bprintf ctx.buf "  store %s %s, ptr @%s\n" llty result global_name;
  Printf.bprintf ctx.buf "  ret void\n}\n";
  (* Assemble *)
  let out = Buffer.create 4096 in
  emit_preamble out;
  emit_repl_globals_decl out prev_globals;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.contents out
```

- [ ] **Step 5: Add `emit_repl_fn` for function declarations**

For `fn foo(x) do ... end`, emits the function itself plus a dummy init so the REPL runner has a consistent interface:

```ocaml
(** Emit a REPL function declaration as a .ll fragment.
    The function is emitted at top level (callable by later fragments).
    A no-op [@repl_<n>_init] is emitted so the REPL runner can call it uniformly. *)
let emit_repl_fn ?(fast_math=false) ~(n : int)
    ~(prev_globals : (string * string) list)
    ~(types : Tir.type_def list)
    (fn : Tir.fn_def) : string =
  let ctx = make_ctx ~fast_math () in
  build_ctor_info ctx { tm_types = types; tm_fns = [fn] };
  Hashtbl.replace ctx.top_fns fn.Tir.fn_name true;
  emit_fn ctx fn;
  let init_name = Printf.sprintf "repl_%d_init" n in
  Printf.bprintf ctx.buf "\ndefine void @%s() {\nentry:\n  ret void\n}\n" init_name;
  let out = Buffer.create 4096 in
  emit_preamble out;
  emit_repl_globals_decl out prev_globals;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.contents out
```

- [ ] **Step 6: Build and verify**

Run: `/Users/80197052/.opam/march/bin/dune build`
Expected: Clean build.

- [ ] **Step 7: Commit**

```bash
git add lib/tir/llvm_emit.ml
git commit -m "feat(llvm): add REPL emission functions for compile-and-dlopen"
```

---

## Task 3: REPL JIT Compilation Pipeline

Build the orchestrator that connects emission → clang → dlopen → call. This is a new module `lib/jit/repl_jit.ml` that the REPL calls instead of `eval_expr`/`eval_decl`.

**Files:**
- Create: `lib/jit/repl_jit.ml`
- Create: `lib/jit/repl_jit.mli`
- Modify: `lib/jit/dune` (add `march_tir`, `march_ast`, `march_typecheck` deps)

- [ ] **Step 1: Write the interface**

```ocaml
(* lib/jit/repl_jit.mli *)

(** Persistent state for the compiled REPL. *)
type t

(** Create a JIT context.
    [runtime_so] is the path to the pre-compiled march_runtime.so.
    [clang] is the clang binary path (default "clang"). *)
val create : runtime_so:string -> ?clang:string -> unit -> t

(** Compile and execute a REPL expression.
    Returns the LLVM IR return type and a string representation of the result.
    Raises [Failure] on compile or link error. *)
val run_expr :
  t ->
  type_map:(March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t ->
  March_ast.Ast.module_ ->
  March_tir.Tir.ty * string

(** Compile and execute a REPL declaration (let binding or function def).
    [is_fn_decl]: true if the original input was a DFn, false for DLet.
    [bind_name]: the variable/function name being bound.
    Updates the JIT state with the new binding.
    Raises [Failure] on compile or link error. *)
val run_decl :
  t ->
  type_map:(March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t ->
  is_fn_decl:bool ->
  bind_name:string ->
  March_ast.Ast.module_ ->
  unit

(** Clean up: close all open dl handles, remove temp files. *)
val cleanup : t -> unit
```

- [ ] **Step 2: Write the implementation**

```ocaml
(* lib/jit/repl_jit.ml *)

type t = {
  runtime_so   : string;
  clang        : string;
  tmp_dir      : string;
  mutable counter  : int;
  mutable globals  : (string * string) list;  (* (llvm_name, llvm_ty) *)
  mutable handles  : Jit.dl_handle list;       (* open dl handles *)
}

let create ~runtime_so ?(clang="clang") () =
  let tmp_dir = Filename.concat
    (Filename.get_temp_dir_name ()) "march_jit" in
  (try Unix.mkdir tmp_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  (* Load the runtime .so first so its symbols are globally available *)
  let rt_handle = Jit.dlopen runtime_so in
  { runtime_so; clang; tmp_dir;
    counter = 0; globals = []; handles = [rt_handle] }

let next_id ctx =
  let n = ctx.counter in
  ctx.counter <- n + 1;
  n

let compile_fragment ctx (ir : string) : Jit.dl_handle =
  let n = ctx.counter - 1 in
  let ll_path = Filename.concat ctx.tmp_dir
    (Printf.sprintf "repl_%d.ll" n) in
  let so_path = Filename.concat ctx.tmp_dir
    (Printf.sprintf "repl_%d.so" n) in
  (* Write .ll *)
  let oc = open_out ll_path in
  output_string oc ir;
  close_out oc;
  (* Compile to .so *)
  let cmd = Printf.sprintf "%s -shared -fPIC -O0 -o %s %s 2>&1"
    ctx.clang so_path ll_path in
  let ic = Unix.open_process_in cmd in
  let output = Buffer.create 256 in
  (try while true do Buffer.add_char output (input_char ic) done
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  (match status with
   | Unix.WEXITED 0 -> ()
   | _ -> failwith (Printf.sprintf "clang failed: %s"
            (Buffer.contents output)));
  (* dlopen the .so *)
  let handle = Jit.dlopen so_path in
  ctx.handles <- handle :: ctx.handles;
  handle

(** Lower a single-expression module through the TIR pipeline. *)
let lower_module ~type_map (m : March_ast.Ast.module_) =
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  let tir = March_tir.Escape.escape_analysis tir in
  tir

let run_expr ctx ~type_map m =
  let n = next_id ctx in
  let tir = lower_module ~type_map m in
  (* The last function in the module is the expression wrapper.
     Extract its body and return type. *)
  let main_fn = List.find (fun (f : March_tir.Tir.fn_def) ->
    f.fn_name = "main") tir.March_tir.Tir.tm_fns in
  let ret_ty = main_fn.fn_ret_ty in
  let ir = March_tir.Llvm_emit.emit_repl_expr
    ~n ~ret_ty
    ~prev_globals:ctx.globals
    ~fns:(List.filter (fun (f : March_tir.Tir.fn_def) ->
      f.fn_name <> "main") tir.tm_fns)
    ~types:tir.tm_types
    main_fn.fn_body in
  let handle = compile_fragment ctx ir in
  let sym_name = Printf.sprintf "repl_%d" n in
  let fptr = Jit.dlsym handle sym_name in
  (* Call based on return type *)
  let result_str = match ret_ty with
    | March_tir.Tir.TInt ->
      let v = Jit.call_void_to_int fptr in
      Int64.to_string v
    | March_tir.Tir.TFloat ->
      let v = Jit.call_void_to_float fptr in
      Printf.sprintf "%g" v
    | March_tir.Tir.TBool ->
      let v = Jit.call_void_to_int fptr in
      if v = 0L then "false" else "true"
    | March_tir.Tir.TUnit ->
      Jit.call_void_to_void fptr;
      "()"
    | _ ->
      (* Heap-allocated value: call, get pointer, format via march_value_to_string *)
      let _ptr = Jit.call_void_to_ptr fptr in
      (* TODO: implement value pretty-printing from native pointer *)
      "<value>"
  in
  (ret_ty, result_str)

(** Distinguish fn vs let at the AST level, not TIR.
    [is_fn_decl] is true when the original REPL input was a DFn. *)
let run_decl ctx ~type_map ~is_fn_decl ~bind_name m =
  let n = next_id ctx in
  let tir = lower_module ~type_map m in
  let user_fns = List.filter (fun (f : March_tir.Tir.fn_def) ->
    f.fn_name <> "main") tir.March_tir.Tir.tm_fns in
  if is_fn_decl then begin
    (* Function declaration: emit the function at top level *)
    match user_fns with
    | [fn] ->
      let ir = March_tir.Llvm_emit.emit_repl_fn
        ~n ~prev_globals:ctx.globals ~types:tir.tm_types fn in
      let _handle = compile_fragment ctx ir in
      ()
    | _ -> failwith "expected exactly one user function in fn decl"
  end else begin
    (* Let binding: find main, extract body, store in global *)
    let main_fn = List.find (fun (f : March_tir.Tir.fn_def) ->
      f.fn_name = "main") tir.tm_fns in
    let ir = March_tir.Llvm_emit.emit_repl_decl
      ~n ~name:bind_name
      ~val_ty:main_fn.fn_ret_ty
      ~prev_globals:ctx.globals
      ~fns:user_fns
      ~types:tir.tm_types
      main_fn.fn_body in
    let handle = compile_fragment ctx ir in
    let init_name = Printf.sprintf "repl_%d_init" n in
    let fptr = Jit.dlsym handle init_name in
    Jit.call_void_to_void fptr;
    let global_name = "repl_" ^ bind_name in
    let llty = March_tir.Llvm_emit.llvm_ty_of_tir main_fn.fn_ret_ty in
    ctx.globals <- (global_name, llty) :: ctx.globals
  end

let cleanup ctx =
  List.iter (fun h -> try Jit.dlclose h with _ -> ()) ctx.handles;
  (* Optionally remove tmp_dir contents *)
  let entries = Sys.readdir ctx.tmp_dir in
  Array.iter (fun f ->
    try Sys.remove (Filename.concat ctx.tmp_dir f) with _ -> ()
  ) entries;
  (try Unix.rmdir ctx.tmp_dir with _ -> ())
```

**Important implementation notes for the engineer:**
- The `lower_module` helper wraps the expression in a synthetic module with a `main` function so the existing TIR pipeline works. The REPL already does this for typecheck — check how `repl.ml` wraps `ReplExpr` into a module.
- `llvm_ty` is currently not exposed from `llvm_emit.ml`. You'll need to add it to the `.mli` or create a helper.
- The value pretty-printing for heap objects (`<value>`) is a known TODO — Task 5 handles it.

- [ ] **Step 3: Update the dune file**

```
; lib/jit/dune (updated from Task 1 — now includes TIR pipeline deps)
(library
 (name march_jit)
 (libraries unix march_tir march_ast march_typecheck march_desugar)
 (c_names jit_stubs))
```

- [ ] **Step 4: Build**

Run: `/Users/80197052/.opam/march/bin/dune build`
Expected: Clean build.

- [ ] **Step 5: Commit**

```bash
git add lib/jit/repl_jit.ml lib/jit/repl_jit.mli lib/jit/dune
git commit -m "feat(jit): add REPL JIT compilation pipeline (compile → clang → dlopen → call)"
```

---

## Task 4: Pre-compile Runtime Shared Library

On first REPL launch (or `march --compile`), compile `march_runtime.c` to a cached `.so` that gets dlopen'd as the base for all REPL fragments.

**Files:**
- Modify: `bin/main.ml`

- [ ] **Step 1: Add runtime .so compilation function**

Add to `bin/main.ml` before the `compile` function:

```ocaml
(** Pre-compile the C runtime to a shared library.
    Cached at ~/.cache/march/libmarch_runtime.so.
    Returns the path to the .so. *)
let ensure_runtime_so () =
  let home = Sys.getenv "HOME" in
  let dot_cache = Filename.concat home ".cache" in
  let cache_dir = Filename.concat dot_cache "march" in
  (* Create parent directories recursively *)
  List.iter (fun d ->
    try Unix.mkdir d 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  ) [dot_cache; cache_dir];
  let so_path = Filename.concat cache_dir "libmarch_runtime.so" in
  (* Find runtime source *)
  let candidates = [
    "runtime/march_runtime.c";
    Filename.concat (Filename.dirname Sys.executable_name) "../runtime/march_runtime.c";
    Filename.concat (Filename.dirname Sys.executable_name) "../../runtime/march_runtime.c";
  ] in
  let runtime_c = match List.find_opt Sys.file_exists candidates with
    | Some p -> p
    | None -> failwith "march: cannot find runtime/march_runtime.c"
  in
  let runtime_dir = Filename.dirname runtime_c in
  (* Recompile if .so is missing or older than .c *)
  let needs_compile =
    not (Sys.file_exists so_path) ||
    (Unix.stat runtime_c).st_mtime > (Unix.stat so_path).st_mtime
  in
  if needs_compile then begin
    (* Note: -lpthread not needed on macOS (pthreads in libSystem).
       Add for Linux later. *)
    let cmd = Printf.sprintf
      "clang -shared -O2 -fPIC -I%s %s -o %s 2>&1"
      runtime_dir runtime_c so_path in
    let rc = Sys.command cmd in
    if rc <> 0 then
      failwith (Printf.sprintf "march: failed to compile runtime .so (clang exit %d)" rc)
  end;
  so_path
```

- [ ] **Step 2: Wire into REPL launch**

In `main.ml`, the REPL is launched at line ~262 with:
```ocaml
| []  -> March_repl.Repl.run ~stdlib_decls:(load_stdlib ()) ()
```

Change to pass the JIT context:
```ocaml
| []  ->
  let runtime_so = ensure_runtime_so () in
  let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
  Fun.protect
    ~finally:(fun () -> March_jit.Repl_jit.cleanup jit_ctx)
    (fun () ->
      March_repl.Repl.run ~stdlib_decls:(load_stdlib ()) ~jit_ctx:(Some jit_ctx) ())
```

- [ ] **Step 3: Update REPL.run signature to accept optional JIT context**

In `lib/repl/repl.ml`, update the `run` function signature and thread `jit_ctx` through to both `run_simple` and `run_tui`:

```ocaml
(* Update run to accept and forward jit_ctx *)
let run ~stdlib_decls ?(jit_ctx : March_jit.Repl_jit.t option) () =
  ...
  (* run delegates to run_tui or run_simple based on isatty.
     Both must accept ~jit_ctx. Update their signatures: *)

(* run_simple: add ~jit_ctx parameter *)
let run_simple ~stdlib_decls ~jit_ctx ... =
  ...

(* run_tui: add ~jit_ctx parameter *)
let run_tui ~stdlib_decls ~jit_ctx ... =
  ...
```

The `jit_ctx` parameter must flow from `run` into whichever sub-function is called. Search for the dispatch point (around line 1100-1103 where `run` decides between `run_tui` and `run_simple`) and pass `~jit_ctx` through. The actual eval replacement happens in Task 5.

- [ ] **Step 4: Update lib/repl/dune to add march_jit dependency**

```
(library
 (name march_repl)
 (libraries
   str
   unix
   notty
   notty.unix
   march_ast
   march_lexer
   march_parser
   march_desugar
   march_typecheck
   march_errors
   march_eval
   march_jit
   march_tir))
```

- [ ] **Step 5: Update bin/dune to add march_jit dependency**

Add `march_jit` to the libraries list in `bin/dune`.

- [ ] **Step 6: Build and verify**

Run: `/Users/80197052/.opam/march/bin/dune build`
Expected: Clean build.

- [ ] **Step 7: Commit**

```bash
git add bin/main.ml lib/repl/repl.ml lib/repl/dune bin/dune
git commit -m "feat(jit): pre-compile runtime .so on REPL launch, thread JIT context"
```

---

## Task 5: Wire JIT into REPL Evaluation

Replace the interpreter calls in `repl.ml` with the JIT compile-and-run path. The interpreter remains as a fallback (env variable `MARCH_REPL_INTERP=1`).

**Files:**
- Modify: `lib/repl/repl.ml`

**Context:** The REPL currently calls `March_eval.Eval.eval_expr !env e'` (line 415) and `March_eval.Eval.eval_decl !env d'` (line 357). These need to be replaced with JIT equivalents. The REPL has two modes: `run_simple` (plain text) and `run_tui` (notty). Both need updating, but they share the same eval pattern.

- [ ] **Step 1: Add a helper that wraps a REPL expression into a module for the TIR pipeline**

The TIR pipeline expects a `module_`. Create a helper that wraps a desugared expression into a synthetic module with stdlib + a `main` function:

```ocaml
(** Wrap a REPL expression in a synthetic module for TIR lowering.
    The expression becomes the body of fn main() do expr end.
    Note: fn_def has fields {fn_name; fn_vis; fn_doc; fn_ret_ty; fn_clauses}
    and fn_clause has {fc_params; fc_guard; fc_body; fc_span}. *)
let wrap_expr_as_module ~(stdlib_decls : March_ast.Ast.decl list)
    (e : March_ast.Ast.expr) : March_ast.Ast.module_ =
  let s = March_ast.Ast.dummy_span in
  let main_clause = {
    March_ast.Ast.fc_params = [];
    fc_guard = None;
    fc_body = e;
    fc_span = s;
  } in
  let main_def = {
    March_ast.Ast.fn_name = { txt = "main"; span = s };
    fn_vis = March_ast.Ast.Public;
    fn_doc = None;
    fn_ret_ty = None;
    fn_clauses = [main_clause];
  } in
  let main_decl = March_ast.Ast.DFn (main_def, s) in
  { mod_name = { txt = "Repl"; span = s };
    mod_decls = stdlib_decls @ [main_decl] }
```

A similar `wrap_decl_as_module` includes the declaration + a dummy `main` that references the bound name. For function declarations, include the `DFn` directly.

- [ ] **Step 2: Replace eval_expr in run_simple**

In the `run_simple` function, find the expression evaluation block (around line 414-418):

```ocaml
(* OLD: *)
let v = March_eval.Eval.eval_expr !env e' in
let vs = March_eval.Eval.value_to_string_pretty v in
Printf.printf "= %s\n%!" vs;

(* NEW: *)
match jit_ctx with
| Some jit ->
  let m = wrap_expr_as_module ~stdlib_decls e' in
  let (_ty, result_str) =
    March_jit.Repl_jit.run_expr jit ~type_map m in
  Printf.printf "= %s\n%!" result_str
| None ->
  let v = March_eval.Eval.eval_expr !env e' in
  let vs = March_eval.Eval.value_to_string_pretty v in
  Printf.printf "= %s\n%!" vs;
```

- [ ] **Step 3: Replace eval_decl in run_simple**

Similar pattern for declarations (around line 357):

```ocaml
match jit_ctx with
| Some jit ->
  (* Extract fn vs let and binding name from the AST declaration *)
  let (is_fn_decl, bind_name) = match d' with
    | March_ast.Ast.DFn (def, _) -> (true, def.fn_name.txt)
    | March_ast.Ast.DLet (b, _) ->
      let name = match b.bind_pat with
        | March_ast.Ast.PatVar n -> n.txt
        | _ -> Printf.sprintf "_v%d" !repl_counter
      in
      (false, name)
    | _ -> (false, Printf.sprintf "_v%d" !repl_counter)
  in
  let m = wrap_decl_as_module ~stdlib_decls d' in
  March_jit.Repl_jit.run_decl jit ~type_map ~is_fn_decl ~bind_name m;
  (* Print confirmation *)
  (match d' with
   | March_ast.Ast.DFn (def, _) ->
     Printf.printf "val %s = <fn>\n%!" def.fn_name.txt
   | March_ast.Ast.DLet (b, _) ->
     (match b.bind_pat with
      | March_ast.Ast.PatVar n ->
        Printf.printf "val %s = <bound>\n%!" n.txt
      | _ -> Printf.printf "val _ = ...\n%!")
   | _ -> ())
| None ->
  env := March_eval.Eval.eval_decl !env d';
```

- [ ] **Step 4: Apply the same changes to run_tui**

The TUI REPL has the same eval_expr (line ~662) and eval_decl (line ~594) calls. Apply the same JIT/fallback pattern.

- [ ] **Step 5: Test the compiled REPL end-to-end**

Run the REPL and test basic expressions:

```
$ dune exec march
march> 1 + 2
= 3
march> let x = 42
val x = 42
march> x * 2
= 84
march> fn double(n) do n * 2 end
val double = <fn>
march> double(21)
= 42
```

Expected: All expressions compile via JIT and produce correct results. Latency per expression should be <100ms.

- [ ] **Step 6: Add MARCH_REPL_INTERP fallback**

At the top of `run`, check for the env variable:

```ocaml
let use_jit = jit_ctx <> None &&
  Sys.getenv_opt "MARCH_REPL_INTERP" = None in
let jit_ctx = if use_jit then jit_ctx else None in
```

- [ ] **Step 7: Commit**

```bash
git add lib/repl/repl.ml
git commit -m "feat(repl): wire JIT compile-and-dlopen into REPL evaluation loop"
```

---

## Task 6: Native Value Pretty-Printing

When the REPL evaluates an expression that returns a heap-allocated value (ADT, string, list, record), we need to print it. Currently `repl_jit.ml` returns `"<value>"` for non-scalar types. This task adds a C function `march_value_to_string` in the runtime that formats any March value.

**Files:**
- Modify: `runtime/march_runtime.c`
- Modify: `runtime/march_runtime.h`
- Modify: `lib/jit/repl_jit.ml`
- Modify: `lib/tir/llvm_emit.ml` (add declare for the new function)

- [ ] **Step 1: Add `march_value_to_string` to the C runtime**

```c
/* runtime/march_runtime.c — append: */

/* Format a March value as a human-readable string.
   Uses the tag field to determine constructor name (requires a tag→name table
   registered at module init time, or falls back to numeric tags).
   For v1: print scalars inline, heap objects as #<tag:N fields:M>. */
void *march_value_to_string(void *v) {
    if (!v) return march_string_lit("(nil)", 5);
    march_hdr *h = (march_hdr *)v;
    int32_t tag = h->tag;
    /* String: tag doesn't matter, use march_string layout */
    /* For now, fall back to a generic representation */
    char buf[128];
    int n = snprintf(buf, sizeof(buf), "#<tag:%d>", tag);
    return march_string_lit(buf, n);
}
```

This is a minimal v1 — it prints `#<tag:0>` for ADTs. A follow-up can register constructor name tables at compile time for better output (e.g., `Some(42)` instead of `#<tag:1>`).

- [ ] **Step 2: Wire into repl_jit.ml**

In the `run_expr` function's catch-all branch, replace the `<value>` placeholder:

```ocaml
| _ ->
  let ptr = Jit.call_void_to_ptr fptr in
  (* Call march_value_to_string via dlsym *)
  let to_string_sym = Jit.dlsym (List.hd ctx.handles) "march_value_to_string" in
  (* We need a call_ptr_to_ptr stub — or just use the string for now *)
  (* For v1: format as opaque *)
  Printf.sprintf "#<native:%Ld>" (Int64.of_nativeint ptr)
```

Note: calling a `ptr -> ptr` C function from OCaml requires one more C stub (`march_call_ptr_to_ptr`). Add it to `jit_stubs.c`:

```c
CAMLprim value march_call_ptr_to_ptr(value v_fptr, value v_arg) {
    CAMLparam2(v_fptr, v_arg);
    void *(*fn)(void *) = (void *(*)(void *))Nativeint_val(v_fptr);
    void *arg = (void *)Nativeint_val(v_arg);
    void *result = fn(arg);
    CAMLreturn(caml_copy_nativeint((intnat)result));
}
```

And the OCaml binding:
```ocaml
external call_ptr_to_ptr : nativeint -> nativeint -> nativeint = "march_call_ptr_to_ptr"
```

Then the heap object branch becomes:
```ocaml
| _ ->
  let ptr = Jit.call_void_to_ptr fptr in
  let vts = Jit.dlsym (List.hd (List.rev ctx.handles))
    "march_value_to_string" in
  let str_ptr = Jit.call_ptr_to_ptr vts ptr in
  (* Read the march_string: len at offset 8, data at offset 16 *)
  (* This requires another C stub to extract — or just use generic format for v1 *)
  Printf.sprintf "#<value at 0x%Lx>" (Int64.of_nativeint ptr)
```

The full pretty-printing (reading the march_string bytes from OCaml) is fiddly. For v1, the generic format is fine. Mark the TODO clearly.

- [ ] **Step 3: Commit**

```bash
git add runtime/march_runtime.c runtime/march_runtime.h lib/jit/jit_stubs.c lib/jit/jit.ml lib/jit/jit.mli lib/jit/repl_jit.ml
git commit -m "feat(jit): add native value pretty-printing (v1: generic format)"
```

---

## Task 7: HTTP/WS C Runtime Functions

Implement the HTTP and WebSocket builtins in C. These are the same functions listed in the HTTP server spec, implemented as C runtime functions callable from compiled March code.

**Files:**
- Create: `runtime/march_http.h`
- Create: `runtime/march_http.c`
- Create: `runtime/sha1.c`
- Create: `runtime/base64.c`
- Modify: `runtime/march_runtime.h` (include march_http.h)

**Context:** All March values are passed as `void *` pointers to heap objects with the `march_hdr` layout (16-byte header, fields at offset 16+). Strings use `march_string` layout (rc + len + data). The object layout details are in `runtime/march_runtime.h`. Constructors are identified by the `tag` field in the header.

- [ ] **Step 1: Write SHA-1 and Base64 helpers**

`runtime/sha1.c` — minimal SHA-1 implementation (RFC 3174). ~80 lines. Used only for WebSocket handshake (`Sec-WebSocket-Accept`). Header: `void sha1(const uint8_t *msg, size_t len, uint8_t out[20]);`

`runtime/base64.c` — minimal Base64 encode. ~40 lines. Header: `int base64_encode(const uint8_t *in, size_t len, char *out, size_t out_sz);`

These are well-documented algorithms — the implementer can find reference implementations easily. Keep them minimal, no dynamic allocation.

- [ ] **Step 2: Write the HTTP runtime header**

```c
/* runtime/march_http.h */
#pragma once
#include "march_runtime.h"

/* TCP builtins */
int64_t march_tcp_listen(int64_t port);
int64_t march_tcp_accept(int64_t listen_fd);
void   *march_tcp_recv_http(int64_t fd, int64_t max_bytes);
void    march_tcp_send_all(int64_t fd, void *data);
void    march_tcp_close(int64_t fd);

/* HTTP builtins */
void *march_http_parse_request(void *raw_string);
void *march_http_serialize_response(int64_t status, void *headers, void *body);

/* Server builtin */
void march_http_server_listen(void *server_config, void *pipeline);

/* WebSocket builtins */
void    march_ws_handshake(int64_t fd, void *key_string);
void   *march_ws_recv(int64_t fd);
void    march_ws_send(int64_t fd, void *frame);
void   *march_ws_select(int64_t socket_fd, void *pipe_rd, int64_t timeout_ms);
```

- [ ] **Step 3: Implement TCP builtins**

```c
/* runtime/march_http.c */
#include "march_http.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>

int64_t march_tcp_listen(int64_t port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = INADDR_ANY,
        .sin_port = htons((uint16_t)port)
    };
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd); return -1;
    }
    if (listen(fd, 128) < 0) {
        close(fd); return -1;
    }
    return (int64_t)fd;
}

int64_t march_tcp_accept(int64_t listen_fd) {
    struct sockaddr_in client_addr;
    socklen_t len = sizeof(client_addr);
    int fd = accept((int)listen_fd, (struct sockaddr *)&client_addr, &len);
    return (int64_t)fd;
}

void march_tcp_send_all(int64_t fd, void *data) {
    march_string *s = (march_string *)data;
    const char *buf = s->data;
    int64_t remaining = s->len;
    while (remaining > 0) {
        ssize_t sent = send((int)fd, buf, (size_t)remaining, 0);
        if (sent <= 0) break;
        buf += sent;
        remaining -= sent;
    }
}

void march_tcp_close(int64_t fd) {
    close((int)fd);
}
```

`march_tcp_recv_http` is more involved — it reads until `\r\n\r\n` (end of headers), then reads `Content-Length` bytes for the body. The implementer should follow the logic in the existing `eval.ml` `tcp_recv_http` builtin.

- [ ] **Step 4: Implement HTTP parse/serialize**

`march_http_parse_request` takes a `march_string` (raw HTTP request) and returns a March tuple/record (depending on how Conn construction is done). The key insight: this function allocates March heap objects using `march_alloc` and returns a pointer.

`march_http_serialize_response` takes status (int64), headers (March list of string pairs), body (march_string), and returns a march_string containing the HTTP response.

The implementer should look at the existing eval.ml implementations of these builtins and port them to C, using `march_alloc` for heap allocations and the `march_hdr` layout for constructing values.

- [ ] **Step 5: Implement WebSocket handshake**

```c
void march_ws_handshake(int64_t fd, void *key_string) {
    march_string *key = (march_string *)key_string;
    /* Concatenate key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11" */
    const char *magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    size_t magic_len = 36;
    size_t total = (size_t)key->len + magic_len;
    char *concat = alloca(total);
    memcpy(concat, key->data, (size_t)key->len);
    memcpy(concat + key->len, magic, magic_len);
    /* SHA-1 hash */
    uint8_t hash[20];
    sha1((const uint8_t *)concat, total, hash);
    /* Base64 encode */
    char b64[32];
    base64_encode(hash, 20, b64, sizeof(b64));
    /* Send 101 response */
    char resp[256];
    int n = snprintf(resp, sizeof(resp),
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Accept: %s\r\n\r\n", b64);
    send((int)fd, resp, (size_t)n, 0);
}
```

- [ ] **Step 6: Implement WebSocket frame recv/send**

`march_ws_recv` — reads a WebSocket frame (RFC 6455 §5.2): 2-byte header, optional extended payload length, 4-byte mask (client→server), masked payload. Unmasks and returns a March `WsFrame` value (tagged union: TextFrame=0, BinaryFrame=1, Ping=2, Pong=3, Close=4).

`march_ws_send` — encodes a `WsFrame` value into a WebSocket frame and sends it. Server→client frames are NOT masked.

- [ ] **Step 7: Implement the server accept loop**

`march_http_server_listen` — the core accept loop. This is the C equivalent of the OCaml implementation described in the spec:

```c
void march_http_server_listen(void *server_config, void *pipeline) {
    /* Extract fields from Server(port, plugs, max_conns, idle_timeout) */
    int64_t *fields = (int64_t *)((char *)server_config + 16);
    int64_t port      = fields[0];
    void   *plugs     = (void *)fields[1];
    int64_t max_conns  = fields[2];
    int64_t idle_secs  = fields[3];

    int listen_fd = (int)march_tcp_listen(port);
    if (listen_fd < 0) { /* error handling */ return; }

    atomic_int active = 0;
    atomic_bool shutdown_flag = false;

    /* SIGTERM handler */
    /* ... install signal handler setting shutdown_flag ... */

    while (!atomic_load(&shutdown_flag)) {
        /* select with 1s timeout for shutdown check */
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(listen_fd, &readfds);
        struct timeval tv = { .tv_sec = 1, .tv_usec = 0 };
        int ready = select(listen_fd + 1, &readfds, NULL, NULL, &tv);
        if (ready <= 0) continue;

        int client_fd = accept(listen_fd, NULL, NULL);
        if (client_fd < 0) continue;

        if (atomic_load(&active) >= max_conns) {
            /* Send 503, close */
            const char *resp = "HTTP/1.1 503 Service Unavailable\r\n\r\n";
            send(client_fd, resp, strlen(resp), 0);
            close(client_fd);
            continue;
        }

        /* Set timeouts */
        struct timeval timeout = { .tv_sec = idle_secs, .tv_usec = 0 };
        setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(client_fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

        atomic_fetch_add(&active, 1);

        /* Spawn connection thread */
        /* ... pthread_create with args struct containing
           client_fd, pipeline, &active ... */
    }

    close(listen_fd);
}
```

The connection thread function calls the compiled March pipeline (defunctionalized dispatch) and handles WebSocket upgrades.

- [ ] **Step 8: Commit**

```bash
git add runtime/march_http.h runtime/march_http.c runtime/sha1.c runtime/base64.c
git commit -m "feat(runtime): add HTTP/WS C runtime builtins for native server"
```

---

## Task 8: Extend LLVM Emitter for HTTP Builtins

Register the HTTP/WS builtins in `llvm_emit.ml` so compiled March code can call them.

**Files:**
- Modify: `lib/tir/llvm_emit.ml`

- [ ] **Step 1: Extend `mangle_extern` with HTTP/WS builtins**

In `llvm_emit.ml`, find the `mangle_extern` function (around line 167) and add:

```ocaml
| "tcp_listen"              -> "march_tcp_listen"
| "tcp_accept"              -> "march_tcp_accept"
| "tcp_recv_http"           -> "march_tcp_recv_http"
| "tcp_send_all"            -> "march_tcp_send_all"
| "tcp_close"               -> "march_tcp_close"
| "http_parse_request"      -> "march_http_parse_request"
| "http_serialize_response" -> "march_http_serialize_response"
| "http_server_listen"      -> "march_http_server_listen"
| "ws_handshake"            -> "march_ws_handshake"
| "ws_recv"                 -> "march_ws_recv"
| "ws_send"                 -> "march_ws_send"
| "ws_select"               -> "march_ws_select"
```

- [ ] **Step 2: Add extern declarations in `emit_preamble`**

Find `emit_preamble` (around line 1075) and add the HTTP/WS function declarations after the existing ones:

```llvm
declare i64  @march_tcp_listen(i64 %port)
declare i64  @march_tcp_accept(i64 %fd)
declare ptr  @march_tcp_recv_http(i64 %fd, i64 %max)
declare void @march_tcp_send_all(i64 %fd, ptr %data)
declare void @march_tcp_close(i64 %fd)
declare ptr  @march_http_parse_request(ptr %raw)
declare ptr  @march_http_serialize_response(i64 %status, ptr %headers, ptr %body)
declare void @march_http_server_listen(ptr %config, ptr %pipeline)
declare void @march_ws_handshake(i64 %fd, ptr %key)
declare ptr  @march_ws_recv(i64 %fd)
declare void @march_ws_send(i64 %fd, ptr %frame)
declare ptr  @march_ws_select(i64 %fd, ptr %pipe, i64 %timeout)
```

- [ ] **Step 3: Update the `--compile` link command to include march_http.c**

In `bin/main.ml`, find the clang invocation (line ~217) and update:

```ocaml
(* Conditionally include march_http.c if it exists alongside march_runtime.c *)
let runtime_dir = Filename.dirname runtime in
let http_files =
  let http_c = Filename.concat runtime_dir "march_http.c" in
  if Sys.file_exists http_c then
    let sha1_c = Filename.concat runtime_dir "sha1.c" in
    let base64_c = Filename.concat runtime_dir "base64.c" in
    Printf.sprintf "%s %s %s" http_c sha1_c base64_c
  else ""
in
let cmd = Printf.sprintf "clang%s %s %s %s -o %s"
  opt_flag runtime http_files ll_file out_bin in
```

Note: `-lpthread` is not needed on macOS (pthreads are in libSystem). On Linux, add it conditionally. For now, macOS-only is fine.

- [ ] **Step 4: Update `ensure_runtime_so` to include march_http.c**

In `bin/main.ml`, update the runtime .so compilation to include all C files:

```ocaml
let http_c = Filename.concat runtime_dir "march_http.c" in
let extra_files =
  if Sys.file_exists http_c then
    let sha1_c = Filename.concat runtime_dir "sha1.c" in
    let base64_c = Filename.concat runtime_dir "base64.c" in
    Printf.sprintf "%s %s %s" http_c sha1_c base64_c
  else "" in
let cmd = Printf.sprintf
  "clang -shared -O2 -fPIC -I%s %s %s -o %s 2>&1"
  runtime_dir runtime_c extra_files so_path in
```

- [ ] **Step 5: Build and verify**

Run: `/Users/80197052/.opam/march/bin/dune build`
Expected: Clean build.

- [ ] **Step 6: Commit**

```bash
git add lib/tir/llvm_emit.ml bin/main.ml
git commit -m "feat(llvm): register HTTP/WS builtins in LLVM emitter and link step"
```

---

## Task 9: End-to-End Integration Test

Verify the full flow: March HTTP server source → `march --compile` → native binary → serves HTTP requests.

**Files:**
- Create: `test/test_http_native.sh`
- Create: `examples/http_hello.march`

- [ ] **Step 1: Write a minimal HTTP server example**

```march
-- examples/http_hello.march
mod HttpHello do

  fn router(conn) do
    match (Conn.method(conn), Conn.path_info(conn)) with
    | (Get, Nil) -> conn |> Conn.text(200, "Hello from compiled March!")
    | _ -> conn |> Conn.text(404, "Not Found")
    end
  end

  fn main() do
    HttpServer.new(8080)
    |> HttpServer.plug(router)
    |> HttpServer.listen()
  end

end
```

- [ ] **Step 2: Write the integration test script**

```bash
#!/bin/bash
# test/test_http_native.sh
set -e

echo "=== Compiling HTTP server ==="
dune exec march -- --compile examples/http_hello.march -o /tmp/march_http_test

echo "=== Starting server ==="
/tmp/march_http_test &
SERVER_PID=$!
sleep 1  # Wait for bind

echo "=== Testing GET / ==="
RESPONSE=$(curl -s http://localhost:8080/)
if [ "$RESPONSE" = "Hello from compiled March!" ]; then
    echo "PASS: GET / returned correct response"
else
    echo "FAIL: expected 'Hello from compiled March!', got '$RESPONSE'"
    kill $SERVER_PID 2>/dev/null
    exit 1
fi

echo "=== Testing 404 ==="
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/nonexistent)
if [ "$STATUS" = "404" ]; then
    echo "PASS: GET /nonexistent returned 404"
else
    echo "FAIL: expected 404, got $STATUS"
    kill $SERVER_PID 2>/dev/null
    exit 1
fi

echo "=== Stopping server ==="
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

echo "=== All tests passed ==="
rm -f /tmp/march_http_test
```

- [ ] **Step 3: Run the integration test**

Run: `bash test/test_http_native.sh`
Expected: All tests pass. The compiled March server handles HTTP requests natively.

- [ ] **Step 4: Test the REPL compiled path**

Start the REPL and verify basic compilation works:

```
$ dune exec march
march> 1 + 2
= 3
march> "hello"
= "hello"
```

Expected: Expressions compile and execute via the JIT path.

- [ ] **Step 5: Commit**

```bash
git add examples/http_hello.march test/test_http_native.sh
git commit -m "test: add end-to-end integration test for compiled HTTP server"
```

---

## Task 10: Update HTTP Server Spec

Update `specs/2026-03-20-http-server-design.md` to reflect the compiled-first approach. The spec currently treats compilation as a separate future concern — it should now document that v1 ships with both interpreter and compiled paths, and the compiled REPL uses dlopen.

**Files:**
- Modify: `specs/2026-03-20-http-server-design.md`

- [ ] **Step 1: Update the Goals section**

Add a bullet: "**Compiled from day 1** — the HTTP server compiles to native code via `march --compile`. The REPL uses compile-and-dlopen (LLVM IR → clang → .so) so HTTP builtins work everywhere. No dual implementation — builtins exist only as C runtime functions."

- [ ] **Step 2: Update the Architecture diagram**

Add the compiled path alongside the interpreter path:

```
Interpreter path:  dune exec march -- app.march  (eval.ml, OCaml builtins)
Compiled path:     march --compile app.march     (LLVM IR → clang → native binary, C builtins)
REPL path:         dune exec march               (compile-and-dlopen, same C builtins)
```

Note: HTTP builtins (http_server_listen, ws_recv, etc.) only exist in the C runtime. Non-HTTP code works on both paths.

- [ ] **Step 3: Update the File Layout table**

Add the new files:
| `runtime/march_http.c` | C implementations of HTTP/WS builtins for compiled mode |
| `runtime/march_http.h` | HTTP/WS C function declarations |
| `runtime/sha1.c` | Vendored SHA-1 for WebSocket handshake |
| `runtime/base64.c` | Vendored Base64 for WebSocket handshake |
| `lib/jit/jit.ml` | OCaml dlopen/dlsym stubs for compiled REPL |
| `lib/jit/repl_jit.ml` | REPL compile-and-dlopen orchestrator |

- [ ] **Step 4: Move "Compiled Mode" from aspirational to v1 scope**

The existing "Compiled Mode: LLVM IR" section (lines 556-663) should be reframed as part of v1, not a future concern. Update the opening sentence from "The interpreter (eval.ml) is the development path. For production, March compiles to native code" to "March compiles to native code for both development (REPL via compile-and-dlopen) and production (`march --compile`)."

- [ ] **Step 5: Commit**

```bash
git add specs/2026-03-20-http-server-design.md
git commit -m "docs: update HTTP server spec to reflect compiled-first v1 approach"
```
