# `forge run FILE` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `forge run foo.march [-- args]` run one `.march` file, interpreted or compiled, with the project's module search path and FFI shims when a project is in scope.

**Architecture:** `Cmd_run` is restructured around one resolver that returns an *entry* plus a *context* (`lib_path_env` + `ffi_flags`); the entry comes either from `forge.toml` or from the command line, and everything downstream is identical. The compiled single-file path reuses `Cmd_build.compile_entry` into a temp output instead of `Cmd_build.build`, leaving the project's target-dir/CAS/workspace semantics untouched. A new `march --args` flag closes the one gap forge cannot paper over: the interpreter had no way to give a program its own argv.

**Tech Stack:** OCaml 5.3, dune, cmdliner (forge CLI), OCaml `Arg` (compiler CLI), Alcotest.

Source spec: `specs/todos/2026-09-01-forge-run-single-file.md`.

## Global Constraints

- Build and test from the worktree root with `dune build --root .` — this worktree sits *inside* the main checkout, so a bare `dune build` resolves to the outer repo root and fails with `Don't know how to build bin/main.exe`.
- Never regress the exact-string assertion in `forge/test/test_forge.ml`'s `test_interp_command_no_ffi_is_unchanged`: with no program args the interpreted command must stay byte-identical to `MARCH_LIB_PATH=/p/lib march '/p/lib/app.march'`.
- `process_argv` with no `--args` must keep returning the compiler process's `Sys.argv`. Verified current behaviour: `main.exe probe.march` prints `<path-to-main.exe>,<path-to-probe.march>`.
- Never `git stash` in this worktree (shared stash stack across worktrees).
- No `Co-Authored-By` lines in commits.
- Stage files explicitly by name; never `git add -A`/`.`/`-am`.

---

### Task 1: `march --args` seeds the interpreted program's argv

The interpreter's `process_argv` builtin returns the *compiler's* `Sys.argv`, and `march` rejects a second positional (`Usage: march [options] [file.march]`, exit 1 — verified). So without this task, `forge run f.march -- a b` could only work under `--compiled`, and would silently mean something else by default.

**Files:**
- Modify: `lib/eval/eval_runtime.ml` (append the ref at end of file)
- Modify: `lib/eval/eval_builtins.ml:3196-3201` (the `process_argv` builtin)
- Modify: `bin/main.ml:4188` (`let files = ref []`) and `bin/main.ml:4207` (beside `--ffi-so` in `specs`) and `bin/main.ml:4300` (the `| [f] -> compile f` branch)
- Create: `test/test_prog_argv.ml`
- Modify: `test/dune:14` (add the module to `march_test_compiler`)
- Modify: `test/test_compiler.ml:14744` (register the suite)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `March_eval.Eval.program_argv : string list option ref` (re-exported from `Eval_runtime` via `eval.ml`'s `include Eval_runtime`), and the compiler flag `--args` whose contract is *"every remaining token is the program's argv, so it must come last"*. Task 2 relies on that flag's spelling and last-position rule.

- [ ] **Step 1: Write the failing test**

Create `test/test_prog_argv.ml`:

```ocaml
(* `march FILE --args a b` seeds the interpreted program's own argv.

   Without it, the process_argv builtin (lib/eval/eval_builtins.ml) returns the
   COMPILER process's Sys.argv, and march rejects a second positional outright
   ("Usage: march [options] [file.march]"), so an interpreted script has no way
   at all to see its own arguments.  `forge run f.march -- a b` depends on this.

   Exe-relative compiler path, for the same reason as test_cap_strip.ml: a
   CWD-relative path returns 127 under dune's test runner. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

(* Prints its argv, comma-joined.  The explicit caps are required: a `main` with
   no capability parameter is rejected outright ("performs IO but declares no
   grant"), and IO.Process is what System.argv() itself needs. *)
let probe_src = {|
mod ArgvProbe do
  needs IO.Console
  needs IO.Process
  fn main(_c : Cap(IO.Console), _p : Cap(IO.Process)) : () do
    println(String.join(System.argv(), ","))
  end
end
|}

(* Returns (exit_code, trimmed_stdout_and_stderr, path_of_the_probe_file). *)
let run_probe extra =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf
      "compiler not found at %s — test/dune must declare bin/main.exe as a dep \
       of run_compiler.exe" compiler_exe;
  let src = Filename.temp_file "prog_argv" ".march" in
  let oc = open_out src in
  output_string oc probe_src;
  close_out oc;
  let out = Filename.temp_file "prog_argv_out" ".txt" in
  let rc =
    Sys.command
      (Printf.sprintf "%s %s%s > %s 2>&1"
         (Filename.quote compiler_exe) (Filename.quote src) extra
         (Filename.quote out))
  in
  let ic = open_in out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  (try Sys.remove src with Sys_error _ -> ());
  (try Sys.remove out with Sys_error _ -> ());
  (rc, String.trim s, src)

let test_args_seeds_argv () =
  let (rc, out, src) = run_probe " --args alpha beta" in
  Alcotest.(check int) "exit 0" 0 rc;
  Alcotest.(check string) "argv is the script then its arguments"
    (src ^ ",alpha,beta") out

let test_args_with_nothing_after_is_script_only () =
  (* Arg.Rest_all fires with the empty list, which must still take precedence
     over Sys.argv — otherwise `--args` with no arguments would leak the
     compiler's own command line into the program. *)
  let (rc, out, src) = run_probe " --args" in
  Alcotest.(check int) "exit 0" 0 rc;
  Alcotest.(check string) "argv is just the script" src out

let test_without_args_flag_behaviour_is_unchanged () =
  let (rc, out, src) = run_probe "" in
  Alcotest.(check int) "exit 0" 0 rc;
  Alcotest.(check string) "still the compiler's own Sys.argv"
    (compiler_exe ^ "," ^ src) out

let test_bare_positional_still_rejected () =
  (* Program arguments must go through --args; a second positional stays an
     error, so nothing silently changes meaning for existing callers. *)
  let (rc, _out, _src) = run_probe " alpha" in
  Alcotest.(check bool) "second positional is still an error" true (rc <> 0)

let tests =
  [ Alcotest.test_case "--args becomes the program's argv" `Quick
      test_args_seeds_argv;
    Alcotest.test_case "--args with nothing after it is script-only" `Quick
      test_args_with_nothing_after_is_script_only;
    Alcotest.test_case "no --args keeps the old Sys.argv behaviour" `Quick
      test_without_args_flag_behaviour_is_unchanged;
    Alcotest.test_case "a bare second positional is still rejected" `Quick
      test_bare_positional_still_rejected ]
```

Register it. In `test/dune:14`, append `test_prog_argv` to the `march_test_compiler` `(modules ...)` list:

```
 (modules test_compiler test_repl_cache test_tcenv_cli_cache test_cap_strip test_cap_symbols test_cap_markers test_cap_package test_cap_scope test_cap_ceiling test_cap_unforgeable test_cap_dict test_cap_attrib_agreement test_cap_sandbox_profile test_cap_sandbox_runtime test_ctxesc test_prog_argv)
```

In `test/test_compiler.ml`, next to the `("cap_markers", Test_cap_markers.tests);` entry at line 14744, add:

```ocaml
      ("prog_argv", Test_prog_argv.tests);
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test prog_argv
```

Expected: FAIL. `--args` is not a known option, so `march` prints `unknown option '--args'` and exits non-zero; `test_args_seeds_argv` fails on the exit-code check. `test_without_args_flag_behaviour_is_unchanged` and `test_bare_positional_still_rejected` should already PASS — they pin existing behaviour.

- [ ] **Step 3: Add the ref**

Append to the end of `lib/eval/eval_runtime.ml`:

```ocaml
(** argv the running March program should see, when the driver supplies one.

    [None] — the default, and what a bare `march f.march` still does — means
    [process_argv] falls back to the compiler process's own [Sys.argv].
    `march f.march --args a b` sets [Some ["f.march"; "a"; "b"]] so a script run
    by `forge run f.march -- a b` sees its own arguments, matching what the same
    program sees compiled and executed directly.

    It lives here rather than in eval.ml beside [ffi_shim_so] because
    [Eval_builtins] must read it, and [Eval_builtins] only opens the modules
    earlier in the include chain.  eval.ml's [include Eval_runtime] re-exports
    it, so bin/main.ml still reaches it as [March_eval.Eval.program_argv]. *)
let program_argv : string list option ref = ref None
```

- [ ] **Step 4: Read it from the builtin**

In `lib/eval/eval_builtins.ml`, replace the `process_argv` entry:

```ocaml
  ; ("process_argv", VBuiltin ("process_argv", function
        | [] ->
          let args = match !program_argv with
            | Some argv -> argv
            | None -> Array.to_list Sys.argv
          in
          List.fold_right (fun s acc -> VCon ("Cons", [VString s; acc]))
            args (VCon ("Nil", []))
        | _ -> eval_error "process_argv: no arguments expected"))
```

(`program_argv` resolves through the existing `open Eval_runtime` at the top of the file. The builtin's closure body runs at call time, so reading the ref there picks up whatever the driver set.)

- [ ] **Step 5: Add the compiler flag and seed the ref**

In `bin/main.ml`, after `let files = ref [] in` (line 4188), add:

```ocaml
  let prog_args = ref None in
```

In the `specs` list, immediately after the `--ffi-so` entry (line 4207), add:

```ocaml
    ("--args",       Arg.Rest_all (fun l -> prog_args := Some l),
                     " Pass every remaining argument to the program as its argv; must come last");
```

`Arg.Rest_all` (not `Arg.Rest`) is required: it fires exactly once with all remaining tokens, *including* the empty list, so `--args` with nothing after it still overrides `Sys.argv` instead of silently falling through.

Then replace the single-file dispatch at line 4300:

```ocaml
  | [f] ->
    (* --args makes the program's argv explicit; leaving [program_argv] as None
       preserves the historical behaviour (the compiler's own Sys.argv) for
       every caller that does not pass it.  Inert under --compile/--check,
       where argv comes from the executed binary or is never read. *)
    (match !prog_args with
     | Some args -> March_eval.Eval.program_argv := Some (f :: args)
     | None -> ());
    compile f
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test prog_argv
```

Expected: PASS, 4 cases.

- [ ] **Step 7: Check nothing else regressed**

```bash
scripts/run-tests.sh -q compiler eval
```

Expected: no new failures versus the pre-change baseline.

- [ ] **Step 8: Commit**

```bash
git add lib/eval/eval_runtime.ml lib/eval/eval_builtins.ml bin/main.ml test/test_prog_argv.ml test/dune test/test_compiler.ml
git commit -m "feat(compiler): march --args seeds the interpreted program's argv"
```

---

### Task 2: `Cmd_run` resolves an entry plus a context

Restructures `forge/lib/cmd_run.ml` so the entry can come from either `forge.toml` or the command line, and threads program args into the interpreted command. No CLI change yet — `Cmd_run.run`'s new parameters are optional, so behaviour is identical until Task 4 wires them up.

**Files:**
- Modify: `forge/lib/cmd_run.ml` (whole file, 68 lines)
- Modify: `forge/test/test_forge.ml` (new cases near the existing `interp_command` ones at line 1535, registered in the `"interp_command"` group at line 1741)

**Interfaces:**
- Consumes: the `--args` contract from Task 1 (flag spelled `--args`, must come last on the `march` command line). `Cmd_build.lib_path_env : ?release:bool -> Project.project -> string` and `Cmd_build.ffi_flags_full : ?target_is_cross:bool -> Project.project -> (string, string) result`, both already public.
- Produces:
  - `Cmd_run.context = { lib_path_env : string; ffi_flags : string }`
  - `Cmd_run.resolve_entry : ?file:string -> unit -> (string * context, string) result`
  - `Cmd_run.interp_command : lib_path_env:string -> dump_flag:string -> ffi_flags:string -> ?args:string list -> entry:string -> string`
  - `Cmd_run.run : ?dump_phases:bool -> ?compiled:bool -> ?target:string -> ?file:string -> ?args:string list -> unit -> (unit, string) result`

  Task 3 extends `run`'s compiled branch; Task 4 calls `run` with `?file`/`~args`.

- [ ] **Step 1: Write the failing tests**

In `forge/test/test_forge.ml`, after `test_interp_command_no_ffi_is_unchanged` (line 1547-1555), add:

```ocaml
let test_interp_command_passes_program_args () =
  (* The program's own arguments ride behind --args, which must come LAST:
     the compiler collects every remaining token there (Arg.Rest_all), so a
     flag emitted after it would be swallowed as a program argument. *)
  let cmd =
    Cmd_run.interp_command ~lib_path_env:"MARCH_LIB_PATH=/p/lib "
      ~dump_flag:"" ~ffi_flags:"" ~args:["alpha"; "two words"]
      ~entry:"/p/lib/app.march"
  in
  Alcotest.(check string) "args follow the entry behind --args"
    "MARCH_LIB_PATH=/p/lib march '/p/lib/app.march' --args 'alpha' 'two words'"
    cmd

let test_interp_command_empty_args_adds_nothing () =
  (* An empty arg list must not grow a stray "--args": the no-args command is
     what every existing caller (and forge watch) emits. *)
  let cmd =
    Cmd_run.interp_command ~lib_path_env:"MARCH_LIB_PATH=/p/lib "
      ~dump_flag:"" ~ffi_flags:"" ~args:[] ~entry:"/p/lib/app.march"
  in
  Alcotest.(check string) "identical to the no-args command"
    "MARCH_LIB_PATH=/p/lib march '/p/lib/app.march'" cmd

let test_resolve_entry_missing_file () =
  match Cmd_run.resolve_entry ~file:"/definitely/not/here.march" () with
  | Ok _ -> Alcotest.fail "a missing file must not resolve"
  | Error msg ->
    Alcotest.(check bool) "error names the file" true
      (contains msg "/definitely/not/here.march")

let test_resolve_entry_directory_is_rejected () =
  match Cmd_run.resolve_entry ~file:(Filename.get_temp_dir_name ()) () with
  | Ok _ -> Alcotest.fail "a directory must not resolve as an entry"
  | Error msg ->
    Alcotest.(check bool) "error explains it is not a file" true
      (contains msg "not a file")

let test_resolve_entry_outside_a_project_runs_bare () =
  (* Outside a project there is no forge.toml to read, so the file runs with no
     MARCH_LIB_PATH and no FFI flags — the same fallback Cmd_test.run_files
     already uses for ad-hoc test files. *)
  let tmpdir = Filename.temp_dir "resolve_bare_" "" in
  let file = Filename.concat tmpdir "scratch.march" in
  let oc = open_out file in
  output_string oc "mod Scratch do\n  fn main() do\n    ()\n  end\nend\n";
  close_out oc;
  let old_cwd = Sys.getcwd () in
  Fun.protect
    ~finally:(fun () ->
        Unix.chdir old_cwd;
        let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       Unix.chdir tmpdir;
       match Cmd_run.resolve_entry ~file:"scratch.march" () with
       | Error msg -> Alcotest.failf "expected a bare resolution, got: %s" msg
       | Ok (entry, ctx) ->
         Alcotest.(check string) "entry is the file as given" "scratch.march" entry;
         Alcotest.(check string) "no lib path" "" ctx.Cmd_run.lib_path_env;
         Alcotest.(check string) "no ffi flags" "" ctx.Cmd_run.ffi_flags)
```

Register them in the `"interp_command"` group (line 1741):

```ocaml
      Alcotest.test_case "program args ride behind --args" `Quick
        test_interp_command_passes_program_args;
      Alcotest.test_case "no program args leaves the command unchanged" `Quick
        test_interp_command_empty_args_adds_nothing;
      Alcotest.test_case "a missing FILE is rejected" `Quick
        test_resolve_entry_missing_file;
      Alcotest.test_case "a directory FILE is rejected" `Quick
        test_resolve_entry_directory_is_rejected;
      Alcotest.test_case "a FILE outside a project runs bare" `Quick
        test_resolve_entry_outside_a_project_runs_bare;
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
dune build --root . test/run_compiler.exe 2>&1 | head -20
```

Expected: FAIL to compile — `Unbound value Cmd_run.resolve_entry`, and `interp_command` does not accept `~args`. (`test_forge.ml` rides in the compiler suite's dune libraries; if the build error names a different runner, run that runner's build instead.)

- [ ] **Step 3: Rewrite `cmd_run.ml`**

Replace the whole of `forge/lib/cmd_run.ml` with:

```ocaml
(** forge run — run a March program through the interpreter (fast for
    development) or, with --compiled, through the LLVM pipeline.

    The entry is either the project's (forge.toml [package] entrypoint, else
    lib/<name>.march) or a single file named on the command line.  Both resolve
    to the same pair — an entry path plus the context it runs in — so only
    [resolve_entry] knows the difference. *)

(** Where a run gets its module search path and native FFI shims. *)
type context = {
  lib_path_env : string;  (** MARCH_LIB_PATH=... prefix, incl. the toolchain PATH *)
  ffi_flags    : string;  (** --ffi-c/--ffi-link flags, each with a leading space *)
}

let empty_context = { lib_path_env = ""; ffi_flags = "" }

(** Install the resolved toolchain if absent (so the PATH prefix
    [Cmd_build.lib_path_env] builds actually points at something), then collect
    the project's search path and FFI shims. *)
let context_of_project proj =
  match Toolchain.ensure_installed () with
  | Error e -> Error e
  | Ok () ->
    match Cmd_build.ffi_flags_full proj with
    | Error msg -> Error msg
    | Ok ffi_flags -> Ok { lib_path_env = Cmd_build.lib_path_env proj; ffi_flags }

(** Resolve what to run and the context to run it in.

    [file] names a single .march file.  It still picks up the surrounding
    project's lib path and FFI shims when there is one, so a scratch file can
    import that project's own modules; with no project it runs bare, the same
    fallback [Cmd_test.run_files] uses for ad-hoc test files.

    Without [file], the project's entry is used and a project is required. *)
let resolve_entry ?file () =
  match file with
  | Some f ->
    if not (Sys.file_exists f) then
      Error (Printf.sprintf "file not found: %s" f)
    else if Sys.is_directory f then
      Error (Printf.sprintf "not a file: %s" f)
    else
      (match Project.load () with
       | Error _   -> Ok (f, empty_context)
       | Ok proj   -> Result.map (fun ctx -> (f, ctx)) (context_of_project proj))
  | None ->
    match Project.load () with
    | Error msg -> Error msg
    | Ok proj ->
      let entry = match proj.Project.entrypoint with
        | Some ep -> Filename.concat proj.Project.root ep
        | None    ->
          Filename.concat proj.Project.root
            (Filename.concat "lib" (proj.Project.name ^ ".march"))
      in
      if not (Sys.file_exists entry) then
        Error (Printf.sprintf "entry point not found: %s" entry)
      else Result.map (fun ctx -> (entry, ctx)) (context_of_project proj)

(** The shell command for an interpreted run.

    Split out of [run] so the FFI flags are pinned by a unit test
    (forge/test/test_forge.ml, "interp_command"): dropping them here is
    invisible to every project without [[ffi]] sources, and fatal — with an
    unhelpful "symbol not found for interpreter FFI" — to every project with
    them.  [ffi_flags] and [dump_flag] already carry their own leading space
    (see [Cmd_build.ffi_flags_of]).

    [args] goes last, behind --args: the compiler collects every remaining
    token there (Arg.Rest_all), so anything emitted after it would be swallowed
    as a program argument.  An empty [args] emits nothing at all, keeping the
    command byte-identical to what forge has always run. *)
let interp_command ~lib_path_env ~dump_flag ~ffi_flags ?(args = []) ~entry =
  let args_flag =
    if args = [] then ""
    else " --args " ^ String.concat " " (List.map Filename.quote args)
  in
  Printf.sprintf "%smarch%s%s %s%s"
    lib_path_env dump_flag ffi_flags (Filename.quote entry) args_flag

let run ?(dump_phases = false) ?(compiled = false) ?target ?file ?(args = []) () =
  if compiled then
    (* Task 3 replaces this branch. *)
    match Cmd_build.build ~release:false ~dump_phases ?target () with
    | Error msg -> Error msg
    | Ok output ->
      let cmd = match target with
        | Some ("js" | "javascript") -> "node " ^ Filename.quote output
        | _ -> Filename.quote output
      in
      let rc = Sys.command cmd in
      if rc = 0 then Ok ()
      else Error (Printf.sprintf "program exited with code %d" rc)
  else
    match resolve_entry ?file () with
    | Error msg -> Error msg
    | Ok (entry, ctx) ->
      let dump_flag = if dump_phases then " --dump-phases" else "" in
      let cmd =
        interp_command ~lib_path_env:ctx.lib_path_env ~dump_flag
          ~ffi_flags:ctx.ffi_flags ~args ~entry
      in
      let rc = Sys.command cmd in
      if rc = 0 then Ok ()
      else Error (Printf.sprintf "program exited with code %d" rc)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test interp_command
```

Expected: PASS, including the pre-existing `no [ffi] leaves the command unchanged` exact-string case.

- [ ] **Step 5: Confirm `forge watch` still compiles**

`Cmd_watch.run_action` calls `Cmd_run.run ~compiled:true ?target ()`; the new parameters are optional, so it must need no edit.

```bash
dune build --root . forge/bin/main.exe
```

Expected: builds clean, no warnings about `Cmd_watch`.

- [ ] **Step 6: Commit**

```bash
git add forge/lib/cmd_run.ml forge/test/test_forge.ml
git commit -m "refactor(forge): cmd_run resolves an entry plus its context"
```

---

### Task 3: compiled single-file runs

`Cmd_build.build` always builds the *project* entry into the project's target dir. A single file instead compiles through `Cmd_build.compile_entry` into a temp output. `compile_entry` already echoes the compiler's stderr (`run_capturing_stderr` writes it out at `cmd_build.ml:297`), so diagnostics stay visible.

**Files:**
- Modify: `forge/lib/cmd_build.ml` (lift `output_ext` to a top-level function; it is currently inline at lines 743-746)
- Modify: `forge/lib/cmd_run.ml` (the `compiled` branch from Task 2)
- Modify: `forge/test/test_forge.ml` (one case, registered in the `"interp_command"` group)

**Interfaces:**
- Consumes: `Cmd_run.resolve_entry` and `Cmd_run.context` from Task 2. `Cmd_build.compile_entry : lib_path_env:string -> ffi_flags:string -> output:string -> release:bool -> dump_phases:bool -> ?target:string -> string -> int * int * int` (returns `(exit_code, n_errors, n_warnings)`), already public.
- Produces: `Cmd_build.output_ext : string option -> string`, and a `Cmd_run.run` whose `compiled` branch honours `?file`. Task 4 needs no further changes here.

- [ ] **Step 1: Write the failing test**

In `forge/test/test_forge.ml`, next to the Task 2 cases, add:

```ocaml
let test_output_ext_by_target () =
  (* Pinned because the single-file compiled run names a temp output with this,
     and running a .mjs as if it were a native binary fails confusingly. *)
  Alcotest.(check string) "native has no extension" "" (Cmd_build.output_ext None);
  Alcotest.(check string) "js" ".mjs" (Cmd_build.output_ext (Some "js"));
  Alcotest.(check string) "javascript" ".mjs" (Cmd_build.output_ext (Some "javascript"));
  Alcotest.(check string) "wasm" ".wasm" (Cmd_build.output_ext (Some "wasm32"));
  Alcotest.(check string) "an unknown target is native" ""
    (Cmd_build.output_ext (Some "aarch64-linux"))
```

Register it in the same group:

```ocaml
      Alcotest.test_case "output extension follows the target" `Quick
        test_output_ext_by_target;
```

- [ ] **Step 2: Run it to verify it fails**

```bash
dune build --root . test/run_compiler.exe 2>&1 | head -20
```

Expected: FAIL to compile — `Unbound value Cmd_build.output_ext`.

- [ ] **Step 3: Lift `output_ext` in `cmd_build.ml`**

Add above `compile_entry` (before line 472):

```ocaml
(** Filename extension for a build's output, by target.  Shared by the project
    build and by the single-file [forge run FILE --compiled] path, which names
    a temp output the same way. *)
let output_ext = function
  | Some ("js" | "javascript") -> ".mjs"
  | Some t when String.length t >= 4 && String.sub t 0 4 = "wasm" -> ".wasm"
  | _ -> ""
```

Then delete the inline copy inside `build` (lines 743-746) and change the `output` binding at line 748 to use it:

```ocaml
          let output =
            Filename.concat build_dir (proj.Project.name ^ output_ext target) in
```

- [ ] **Step 4: Rewrite the `compiled` branch of `Cmd_run.run`**

In `forge/lib/cmd_run.ml`, add above `run`:

```ocaml
(** Execute a built artifact with the program's own arguments. *)
let exec_output ~target ~args output =
  let quoted = String.concat " " (List.map Filename.quote args) in
  let sep = if args = [] then "" else " " in
  let cmd = match target with
    | Some ("js" | "javascript") ->
      Printf.sprintf "node %s%s%s" (Filename.quote output) sep quoted
    | _ -> Printf.sprintf "%s%s%s" (Filename.quote output) sep quoted
  in
  let rc = Sys.command cmd in
  if rc = 0 then Ok ()
  else Error (Printf.sprintf "program exited with code %d" rc)
```

and replace `run` with:

```ocaml
let run ?(dump_phases = false) ?(compiled = false) ?target ?file ?(args = []) () =
  match resolve_entry ?file () with
  | Error msg -> Error msg
  | Ok (entry, ctx) ->
    if not compiled then begin
      let dump_flag = if dump_phases then " --dump-phases" else "" in
      let cmd =
        interp_command ~lib_path_env:ctx.lib_path_env ~dump_flag
          ~ffi_flags:ctx.ffi_flags ~args ~entry
      in
      let rc = Sys.command cmd in
      if rc = 0 then Ok ()
      else Error (Printf.sprintf "program exited with code %d" rc)
    end else
      match file with
      | None ->
        (* Project build: go through Cmd_build.build so the target dir, the CAS
           and workspace semantics stay exactly as they were. *)
        (match Cmd_build.build ~release:false ~dump_phases ?target () with
         | Error msg -> Error msg
         | Ok output -> exec_output ~target ~args output)
      | Some _ ->
        (* Single file: compile straight to a temp output.  The CAS caches the
           real work, so the artifact itself is disposable and is removed after
           the run rather than littering the cwd. *)
        let output =
          Filename.temp_file "forge-run-" (Cmd_build.output_ext target) in
        (* temp_file creates the file; the compiler wants to write it itself. *)
        (try Sys.remove output with Sys_error _ -> ());
        Fun.protect
          ~finally:(fun () ->
              try if Sys.file_exists output then Sys.remove output
              with Sys_error _ -> ())
          (fun () ->
             let (rc, _errors, _warnings) =
               Cmd_build.compile_entry ~lib_path_env:ctx.lib_path_env
                 ~ffi_flags:ctx.ffi_flags ~output ~release:false ~dump_phases
                 ?target entry
             in
             if rc <> 0 then
               Error (Printf.sprintf "march compiler exited with code %d" rc)
             else exec_output ~target ~args output)
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test interp_command
```

Expected: PASS, all cases in the group.

- [ ] **Step 6: Check the project build path is untouched**

```bash
scripts/run-tests.sh -q compiler
```

Expected: no new failures — in particular nothing in the forge build/test groups.

- [ ] **Step 7: Commit**

```bash
git add forge/lib/cmd_build.ml forge/lib/cmd_run.ml forge/test/test_forge.ml
git commit -m "feat(forge): compile and run a single file with --compiled"
```

---

### Task 4: wire up the CLI, verify end to end, document

**Files:**
- Modify: `forge/bin/main.ml:219-236` (`run_cmd`)
- Modify: `docs/tooling.md` (the `forge run` section)
- Modify: `CHANGELOG.md` (under `## [Unreleased]`, `### Added`)
- Move: `specs/todos/2026-09-01-forge-run-single-file.md` → `specs/progress/`

**Interfaces:**
- Consumes: `Cmd_run.run : ?dump_phases:bool -> ?compiled:bool -> ?target:string -> ?file:string -> ?args:string list -> unit -> (unit, string) result` from Tasks 2-3.
- Produces: the final CLI surface. Nothing depends on this task.

- [ ] **Step 1: Rewrite `run_cmd`**

In `forge/bin/main.ml`, replace the `run_cmd` definition (lines 219-236) with:

```ocaml
let run_cmd =
  let dump_phases =
    Arg.(value & flag & info ["dump-phases"]
           ~doc:"Serialize each compiler IR stage to march-phases/phases.json")
  in
  let compiled =
    Arg.(value & flag & info ["compiled"]
           ~doc:"Compile via the LLVM pipeline first, then execute the resulting binary")
  in
  let target =
    Arg.(value & opt (some string) None &
         info ["target"] ~docv:"TARGET"
           ~doc:"Compilation target when using $(b,--compiled): native (default) or js. \
                 With $(b,js), builds an .mjs module then runs it with node.")
  in
  let files =
    Arg.(value & pos_all string [] &
         info [] ~docv:"FILE"
           ~doc:"A single .march file to run, followed by any arguments for the \
                 program itself (separate them with $(b,--)). Omit FILE to run \
                 the project's entry point. A file named here still sees the \
                 surrounding project's modules and FFI shims when there is one.")
  in
  let run d c tgt fs =
    (* The first positional is always the FILE; everything after it belongs to
       the program.  There is deliberately no spelling that passes arguments to
       the PROJECT entry: cmdliner records the positionals but not where `--`
       sat, so `forge run -- a b` cannot be told apart from a file `a` with one
       argument, and guessing (e.g. "it's a file if it exists") is worse than
       not offering it. *)
    let (file, args) = match fs with
      | []          -> (None, [])
      | f :: rest   -> (Some f, rest)
    in
    handle (Cmd_run.run ~dump_phases:d ~compiled:c ?target:tgt ?file ~args ())
  in
  Cmd.v (Cmd.info "run" ~doc:"Build and run the current project, or a single file")
    Term.(const run $ dump_phases $ compiled $ target $ files)
```

- [ ] **Step 2: Build and check the help text**

```bash
dune build --root . forge/bin/main.exe && ./_build/default/forge/bin/main.exe run --help=plain | head -30
```

Expected: builds clean; the synopsis shows `[FILE]…` and the FILE paragraph appears under ARGUMENTS.

- [ ] **Step 3: Verify end to end, outside any project**

```bash
cd "$(mktemp -d)" && cat > scratch.march <<'EOF'
mod Scratch do
  needs IO.Console
  needs IO.Process
  fn main(_c : Cap(IO.Console), _p : Cap(IO.Process)) : () do
    println(String.join(System.argv(), ","))
  end
end
EOF
```

Then, with `FORGE=/Users/80197052/code/march/.claude/worktrees/ast-llvm-open-source-a73a89/_build/default/forge/bin/main.exe` and the matching `march` on PATH:

```bash
"$FORGE" run scratch.march -- alpha beta
```

Expected: `scratch.march,alpha,beta` — argv[0] is the script path.

```bash
"$FORGE" run --compiled scratch.march -- alpha beta
```

Expected: `<temp-binary-path>,alpha,beta` — argv[0] is the binary, the arguments match. The two runs must agree on everything after argv[0]; that agreement is the whole point of Task 1.

```bash
"$FORGE" run -- alpha beta
```

Expected: `error: file not found: alpha`, exit 1.

```bash
"$FORGE" run nope.march
```

Expected: `error: file not found: nope.march`, exit 1.

- [ ] **Step 4: Verify it picks up a project's modules**

```bash
cd "$(mktemp -d)" && "$FORGE" new demo && cd demo
cat > scratch.march <<'EOF'
mod Scratch do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) : () do
    println("scratch sees the project")
  end
end
EOF
"$FORGE" run scratch.march
```

Expected: `scratch sees the project`. Then confirm the project path is unregressed:

```bash
"$FORGE" run
```

Expected: the scaffolded project's own output, exactly as before this change.

- [ ] **Step 5: Run the full suite**

```bash
scripts/run-tests.sh
```

Expected: no new failures against the baseline recorded before Task 1.

- [ ] **Step 6: Update the docs**

In `docs/tooling.md`, extend the `forge run` entry with the single-file form:

```markdown
forge run                        # run the project entry (interpreted)
forge run --compiled             # compile via LLVM, then run the binary
forge run foo.march              # run a single file
forge run --compiled foo.march   # compile and run a single file
forge run foo.march -- a b       # pass a and b to the program as its argv
```

A file named on the command line still sees the surrounding project's modules
and FFI shims when it is inside a project, so a scratch file can import your own
code; outside a project it runs standalone. Arguments after `--` reach the
program as `System.argv()`, with `argv[0]` the script path when interpreted and
the binary path when compiled. Passing arguments requires naming a FILE.

In `CHANGELOG.md`, under `## [Unreleased]` / `### Added`:

```markdown
- `forge run FILE` runs a single `.march` file, interpreted or (with
  `--compiled`) through the LLVM pipeline. A file inside a project still
  resolves that project's modules and FFI shims. Arguments after `--` reach the
  program as `System.argv()`; the compiler gained `march --args` to make that
  work for interpreted runs too.
```

- [ ] **Step 7: Close the todo**

```bash
git mv specs/todos/2026-09-01-forge-run-single-file.md specs/progress/
```

Then edit the moved file's header line so it records the outcome rather than an open item: replace `Filed 2026-09-01. Design approved; not yet implemented.` with `Filed 2026-09-01, landed 2026-09-01.` and drop the `` `[P2]` `` tag from the title line.

- [ ] **Step 8: Commit**

```bash
git add forge/bin/main.ml docs/tooling.md CHANGELOG.md specs/progress/2026-09-01-forge-run-single-file.md
git commit -m "feat(forge): forge run FILE runs a single march file"
```
