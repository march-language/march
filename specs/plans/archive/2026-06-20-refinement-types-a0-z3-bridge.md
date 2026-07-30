# Refinement Types A0 — Standalone Z3 Bridge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `lib/refine/` — a self-contained library that renders verification conditions (VCs) to SMT-LIB2, drives a long-lived `z3 -in` subprocess, parses `unsat`/`sat`(+model)/`unknown`, and caches results in the content-addressed store — proven by a unit test suite with **zero coupling to the typechecker**.

**Architecture:** Four small OCaml modules. `Smt` is a pure Int/Bool term AST + SMT-LIB2 renderer. `Model` is a pure s-expression parser for `(get-model)` output. `Solver` spawns and talks to `z3 -in` over Unix pipes, using `(push)`/`(pop)` per VC. `Vc_cache` hashes the rendered VC with BLAKE3 and stores the verdict under `.march/cas/vc/`. `Refine` orchestrates cache→solver→cache and maps the raw verdict to a caller-facing `outcome`. This is Phase A0 of the refinement-types spec (`specs/2026-06-20-dependent-types-refinements-design.md`); A1 wires it into `typecheck.ml`.

**Tech Stack:** OCaml 5.3, dune 3.7, alcotest, `unix` (subprocess/pipes), `march_cas` (for `Blake3.hash_string`), Z3 ≥ 4.x via `z3 -in` subprocess (no opam bindings).

---

## Reference facts (verified against the codebase)

- **dune library shape** (from `lib/errors/dune`): `(library (name march_xxx) (libraries ...))`. The wrapped module is referenced as `March_xxx.Mod` elsewhere.
- **BLAKE3**: `March_cas.Blake3.hash_string : string -> string` returns a 64-char lowercase hex digest (`lib/cas/blake3.ml:11`).
- **Subprocess pattern** (from `lib/eval/eval.ml`): `Unix.pipe ()` ×2 + `Unix.create_process` + `Unix.in_channel_of_descr` / `Unix.out_channel_of_descr`.
- **Test stanza shape** (from `test/dune:214-217`, the `test_cas` target): `(test (name test_X) (modules test_X) (libraries ... alcotest unix))`. The runner file contains `let () = Alcotest.run "name" suites`.
- **Z3 present locally** at `/opt/homebrew/bin/z3` (v4.15.4). It is **not** assumed present in CI — solver-integration tests skip cleanly when `z3` is absent.
- **Temp-file collision guard** (project memory): suffix temp paths with the pid to avoid clashes between concurrent sessions.

File layout created by this plan:

```
lib/refine/dune          (library march_refine)
lib/refine/smt.ml        pure term AST + SMT-LIB2 renderer
lib/refine/model.ml      pure s-expr parser for (get-model)
lib/refine/solver.ml     z3 -in driver (Unix pipes, push/pop)
lib/refine/vc_cache.ml   BLAKE3-keyed verdict cache under .march/cas/vc/
lib/refine/refine.ml     cache→solver orchestration + caller-facing outcome
test/test_refine.ml      alcotest suite (pure tests always; solver tests gated on z3)
```

---

## Task 1: Scaffold the library and prove the build/test loop

**Files:**
- Create: `lib/refine/dune`
- Create: `lib/refine/smt.ml`
- Create: `test/test_refine.ml`
- Modify: `test/dune` (add a `(test ...)` stanza)

- [ ] **Step 1: Create the library dune file**

Create `lib/refine/dune`:

```
(library
 (name march_refine)
 (libraries march_cas unix))
```

- [ ] **Step 2: Create a minimal module so the library is non-empty**

Create `lib/refine/smt.ml`:

```ocaml
(* SMT-LIB2 term AST and renderer for the refinement Z3 bridge.
   v1 supports the Int/Bool linear-arithmetic + EUF fragment. *)

(* Placeholder so the library builds; replaced in Task 2. *)
let version = "a0"
```

- [ ] **Step 3: Create the test runner**

Create `test/test_refine.ml`:

```ocaml
let smoke_suite =
  [ Alcotest.test_case "library links" `Quick (fun () ->
        Alcotest.(check string) "version" "a0" March_refine.Smt.version) ]

let () = Alcotest.run "march-refine" [ ("smoke", smoke_suite) ]
```

- [ ] **Step 4: Register the test in `test/dune`**

Add this stanza to `test/dune` immediately after the `test_cas` stanza (around line 217):

```
(test
 (name test_refine)
 (modules test_refine)
 (libraries march_refine alcotest unix))
```

- [ ] **Step 5: Build and run the smoke test**

Run: `dune build test/test_refine.exe && ./_build/default/test/test_refine.exe`
Expected: PASS — `Test Successful in ...` with one passing `smoke` case.

- [ ] **Step 6: Commit**

```bash
git add lib/refine/dune lib/refine/smt.ml test/test_refine.ml test/dune
git commit -m "feat(refine): scaffold march_refine library + test harness"
```

---

## Task 2: Pure SMT-LIB2 term AST and renderer

**Files:**
- Modify: `lib/refine/smt.ml` (replace placeholder)
- Modify: `test/test_refine.ml` (add `smt` suite)

- [ ] **Step 1: Write the failing test**

Replace the contents of `test/test_refine.ml` with:

```ocaml
open March_refine

let smoke_suite =
  [ Alcotest.test_case "library links" `Quick (fun () ->
        Alcotest.(check string) "version" "a0" Smt.version) ]

(* A VC asserting: (d > 0) ==> (d != 0).  We check validity by asserting the
   hypotheses and the NEGATED goal, then check-sat; unsat means valid. *)
let sample_vc : Smt.vc =
  { decls = [ ("d", Smt.SInt) ];
    assumptions = [ Smt.Gt (Smt.Const "d", Smt.IntLit 0) ];
    goal = Smt.Ne (Smt.Const "d", Smt.IntLit 0) }

let smt_suite =
  [ Alcotest.test_case "renders a term" `Quick (fun () ->
        Alcotest.(check string) "ge"
          "(>= _ 0)"
          (Smt.render (Smt.Ge (Smt.Const "_", Smt.IntLit 0))));

    Alcotest.test_case "renders negative int literal" `Quick (fun () ->
        Alcotest.(check string) "neg" "(- 3)" (Smt.render (Smt.IntLit (-3))));

    Alcotest.test_case "assertion_block negates the goal" `Quick (fun () ->
        Alcotest.(check string) "block"
          "(declare-const d Int)\n\
           (assert (> d 0))\n\
           (assert (not (not (= d 0))))\n"
          (Smt.assertion_block sample_vc)) ]

let () =
  Alcotest.run "march-refine"
    [ ("smoke", smoke_suite); ("smt", smt_suite) ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dune build test/test_refine.exe 2>&1 | head -20`
Expected: FAIL — compile error, `Smt.vc`, `Smt.SInt`, `Smt.render`, `Smt.assertion_block` undefined.

- [ ] **Step 3: Implement the term AST and renderer**

Replace the contents of `lib/refine/smt.ml` with:

```ocaml
(* SMT-LIB2 term AST and renderer for the refinement Z3 bridge.
   v1 supports the Int/Bool linear-arithmetic + EUF fragment. *)

let version = "a0"

type sort = SInt | SBool

type term =
  | Const of string          (* a declared symbol: "_", "i", or a measure-applied const *)
  | IntLit of int
  | BoolLit of bool
  | Add of term * term
  | Sub of term * term
  | MulLit of int * term     (* literal coefficient * term — keeps us in linear arithmetic *)
  | Neg of term
  | Not of term
  | And of term * term
  | Or of term * term
  | Implies of term * term
  | Eq of term * term
  | Ne of term * term
  | Lt of term * term
  | Le of term * term
  | Gt of term * term
  | Ge of term * term

type vc = {
  decls : (string * sort) list;   (* free symbols to declare *)
  assumptions : term list;        (* hypotheses (path context + known refinements) *)
  goal : term;                    (* the predicate we want to hold *)
}

let string_of_sort = function SInt -> "Int" | SBool -> "Bool"

let rec render = function
  | Const s -> s
  | IntLit n -> if n < 0 then Printf.sprintf "(- %d)" (- n) else string_of_int n
  | BoolLit b -> if b then "true" else "false"
  | Add (a, b) -> Printf.sprintf "(+ %s %s)" (render a) (render b)
  | Sub (a, b) -> Printf.sprintf "(- %s %s)" (render a) (render b)
  | MulLit (k, a) -> Printf.sprintf "(* %d %s)" k (render a)
  | Neg a -> Printf.sprintf "(- %s)" (render a)
  | Not a -> Printf.sprintf "(not %s)" (render a)
  | And (a, b) -> Printf.sprintf "(and %s %s)" (render a) (render b)
  | Or (a, b) -> Printf.sprintf "(or %s %s)" (render a) (render b)
  | Implies (a, b) -> Printf.sprintf "(=> %s %s)" (render a) (render b)
  | Eq (a, b) -> Printf.sprintf "(= %s %s)" (render a) (render b)
  | Ne (a, b) -> Printf.sprintf "(not (= %s %s))" (render a) (render b)
  | Lt (a, b) -> Printf.sprintf "(< %s %s)" (render a) (render b)
  | Le (a, b) -> Printf.sprintf "(<= %s %s)" (render a) (render b)
  | Gt (a, b) -> Printf.sprintf "(> %s %s)" (render a) (render b)
  | Ge (a, b) -> Printf.sprintf "(>= %s %s)" (render a) (render b)

(* The canonical assertion block for a VC: declare every free symbol, assert the
   hypotheses, and assert the NEGATED goal.  Sent to z3 between push/pop and also
   used (verbatim) as the BLAKE3 cache key.  `(check-sat)` is appended by the
   solver driver, not here, so the cache key is independent of solver options. *)
let assertion_block (vc : vc) : string =
  let buf = Buffer.create 256 in
  List.iter
    (fun (name, sort) ->
      Buffer.add_string buf
        (Printf.sprintf "(declare-const %s %s)\n" name (string_of_sort sort)))
    vc.decls;
  List.iter
    (fun a -> Buffer.add_string buf (Printf.sprintf "(assert %s)\n" (render a)))
    vc.assumptions;
  Buffer.add_string buf (Printf.sprintf "(assert %s)\n" (render (Not vc.goal)));
  Buffer.contents buf
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dune build test/test_refine.exe && ./_build/default/test/test_refine.exe`
Expected: PASS — `smoke` and `smt` suites green (4 cases total).

- [ ] **Step 5: Commit**

```bash
git add lib/refine/smt.ml test/test_refine.ml
git commit -m "feat(refine): SMT-LIB2 term AST + renderer (Int/Bool fragment)"
```

---

## Task 3: Pure s-expression model parser

**Files:**
- Create: `lib/refine/model.ml`
- Modify: `test/test_refine.ml` (add `model` suite)

- [ ] **Step 1: Write the failing test**

In `test/test_refine.ml`, add this suite definition immediately before the final `let () = Alcotest.run ...`:

```ocaml
let model_suite =
  [ Alcotest.test_case "parses define-fun ints" `Quick (fun () ->
        let s =
          "(\n\
          \  (define-fun d () Int 0)\n\
          \  (define-fun i () Int 10)\n\
           )"
        in
        let m = Model.of_string s in
        Alcotest.(check (option string)) "d" (Some "0") (List.assoc_opt "d" m);
        Alcotest.(check (option string)) "i" (Some "10") (List.assoc_opt "i" m));

    Alcotest.test_case "parses negative and bool values" `Quick (fun () ->
        let s =
          "(model\n\
          \  (define-fun n () Int (- 3))\n\
          \  (define-fun b () Bool true)\n\
           )"
        in
        let m = Model.of_string s in
        Alcotest.(check (option string)) "n" (Some "(- 3)") (List.assoc_opt "n" m);
        Alcotest.(check (option string)) "b" (Some "true") (List.assoc_opt "b" m)) ]
```

Then update the final line to include the new suite:

```ocaml
let () =
  Alcotest.run "march-refine"
    [ ("smoke", smoke_suite);
      ("smt", smt_suite);
      ("model", model_suite) ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dune build test/test_refine.exe 2>&1 | head -20`
Expected: FAIL — `Model.of_string` undefined (module `Model` does not exist).

- [ ] **Step 3: Implement the s-expression parser**

Create `lib/refine/model.ml`:

```ocaml
(* Parses Z3's `(get-model)` output into a (symbol -> value-string) assoc list,
   for rendering counterexamples.  Pure; no solver dependency.

   Handles both shapes Z3 emits:
     ( (define-fun d () Int 0) ... )        -- SMT-LIB 2.6 default
     (model (define-fun d () Int 0) ... )   -- legacy / :model-style
   by recursively collecting every (define-fun NAME () SORT VALUE) form. *)

type sexp = Atom of string | List of sexp list

let parse_sexps (s : string) : sexp list =
  let n = String.length s in
  let pos = ref 0 in
  let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' in
  let is_delim c = c = '(' || c = ')' || is_ws c in
  let skip_ws () = while !pos < n && is_ws s.[!pos] do incr pos done in
  let rec parse_one () : sexp =
    skip_ws ();
    if !pos >= n then failwith "model: unexpected eof"
    else if s.[!pos] = '(' then begin
      incr pos;
      let items = ref [] in
      let rec loop () =
        skip_ws ();
        if !pos < n && s.[!pos] = ')' then incr pos
        else begin
          items := parse_one () :: !items;
          loop ()
        end
      in
      loop ();
      List (List.rev !items)
    end
    else begin
      let start = !pos in
      while !pos < n && not (is_delim s.[!pos]) do incr pos done;
      Atom (String.sub s start (!pos - start))
    end
  in
  let items = ref [] in
  (try
     while true do
       skip_ws ();
       if !pos >= n then raise Exit;
       items := parse_one () :: !items
     done
   with Exit -> ());
  List.rev !items

let rec render_sexp = function
  | Atom a -> a
  | List xs -> "(" ^ String.concat " " (List.map render_sexp xs) ^ ")"

let of_string (s : string) : (string * string) list =
  let defs = ref [] in
  let rec collect = function
    | List [ Atom "define-fun"; Atom name; List []; _sort; value ] ->
        defs := (name, render_sexp value) :: !defs
    | List xs -> List.iter collect xs
    | Atom _ -> ()
  in
  List.iter collect (parse_sexps s);
  List.rev !defs
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dune build test/test_refine.exe && ./_build/default/test/test_refine.exe`
Expected: PASS — `model` suite green (2 cases).

- [ ] **Step 5: Commit**

```bash
git add lib/refine/model.ml test/test_refine.ml
git commit -m "feat(refine): s-expression parser for z3 get-model output"
```

---

## Task 4: Z3 subprocess driver

**Files:**
- Create: `lib/refine/solver.ml`
- Modify: `test/test_refine.ml` (add `solver` suite, gated on z3 presence)

- [ ] **Step 1: Write the failing test (gated on z3 availability)**

In `test/test_refine.ml`, add this suite definition immediately before the final `let () = Alcotest.run ...`:

```ocaml
(* Solver tests require a real z3 on PATH.  When absent (e.g. CI), they print a
   skip notice and pass — matching the spec's graceful-degradation design. *)
let with_solver name f =
  Alcotest.test_case name `Quick (fun () ->
      match Solver.create () with
      | None -> Printf.printf "\n[skip] %s: no z3 on PATH\n" name
      | Some s -> Fun.protect ~finally:(fun () -> Solver.close s) (fun () -> f s))

let solver_suite =
  [ with_solver "valid VC is unsat (verified)" (fun s ->
        let vc : Smt.vc =
          { decls = [ ("d", Smt.SInt) ];
            assumptions = [ Smt.Gt (Smt.Const "d", Smt.IntLit 0) ];
            goal = Smt.Ne (Smt.Const "d", Smt.IntLit 0) }
        in
        match Solver.check s vc with
        | Solver.Unsat -> ()
        | Solver.Sat _ -> Alcotest.fail "expected unsat, got sat"
        | Solver.Unknown -> Alcotest.fail "expected unsat, got unknown");

    with_solver "invalid VC is sat with d=0 counterexample" (fun s ->
        let vc : Smt.vc =
          { decls = [ ("d", Smt.SInt) ];
            assumptions = [];
            goal = Smt.Ne (Smt.Const "d", Smt.IntLit 0) }
        in
        match Solver.check s vc with
        | Solver.Sat model ->
            Alcotest.(check (option string)) "d=0" (Some "0")
              (List.assoc_opt "d" model)
        | Solver.Unsat -> Alcotest.fail "expected sat, got unsat"
        | Solver.Unknown -> Alcotest.fail "expected sat, got unknown");

    with_solver "two checks on one process are independent" (fun s ->
        let valid : Smt.vc =
          { decls = [ ("x", Smt.SInt) ];
            assumptions = [ Smt.Ge (Smt.Const "x", Smt.IntLit 1) ];
            goal = Smt.Gt (Smt.Const "x", Smt.IntLit 0) }
        in
        let invalid : Smt.vc =
          { decls = [ ("x", Smt.SInt) ]; assumptions = []; goal =
            Smt.Gt (Smt.Const "x", Smt.IntLit 0) }
        in
        (match Solver.check s valid with
         | Solver.Unsat -> ()
         | _ -> Alcotest.fail "valid VC should be unsat");
        (match Solver.check s invalid with
         | Solver.Sat _ -> ()
         | _ -> Alcotest.fail "invalid VC should be sat (push/pop leaked?)")) ]
```

Then update the final `Alcotest.run` list to include `("solver", solver_suite)`:

```ocaml
let () =
  Alcotest.run "march-refine"
    [ ("smoke", smoke_suite);
      ("smt", smt_suite);
      ("model", model_suite);
      ("solver", solver_suite) ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dune build test/test_refine.exe 2>&1 | head -20`
Expected: FAIL — `Solver.create`, `Solver.check`, `Solver.close`, `Solver.Unsat` undefined.

- [ ] **Step 3: Implement the solver driver**

Create `lib/refine/solver.ml`:

```ocaml
(* Long-lived `z3 -in` subprocess driver.  One process per compilation unit;
   each VC is checked inside a (push)/(pop) pair so assumptions don't leak. *)

type t = { ic : in_channel; oc : out_channel; pid : int }

type result =
  | Unsat                          (* goal holds — verified *)
  | Sat of (string * string) list  (* goal can fail — counterexample model *)
  | Unknown                        (* solver could not decide *)

(* Locate z3: MARCH_Z3 override, else first "z3" on PATH.  None => unavailable. *)
let find_z3 () : string option =
  match Sys.getenv_opt "MARCH_Z3" with
  | Some p -> if Sys.file_exists p then Some p else None
  | None -> (
      match Sys.getenv_opt "PATH" with
      | None -> None
      | Some path ->
          String.split_on_char ':' path
          |> List.find_map (fun dir ->
                 let p = Filename.concat dir "z3" in
                 if Sys.file_exists p then Some p else None))

let create () : t option =
  match find_z3 () with
  | None -> None
  | Some path ->
      let stdin_r, stdin_w = Unix.pipe () in
      let stdout_r, stdout_w = Unix.pipe () in
      let pid =
        Unix.create_process path [| path; "-in" |] stdin_r stdout_w Unix.stderr
      in
      Unix.close stdin_r;
      Unix.close stdout_w;
      let oc = Unix.out_channel_of_descr stdin_w in
      let ic = Unix.in_channel_of_descr stdout_r in
      (* print-success off: we only read explicit (check-sat)/(get-model) output *)
      output_string oc "(set-option :print-success false)\n";
      flush oc;
      Some { ic; oc; pid }

(* Read one balanced-parens s-expression block (the (get-model) reply). *)
let read_balanced (ic : in_channel) : string =
  let buf = Buffer.create 256 in
  let depth = ref 0 in
  let started = ref false in
  let continue = ref true in
  while !continue do
    let line = input_line ic in
    Buffer.add_string buf line;
    Buffer.add_char buf '\n';
    String.iter
      (fun c ->
        if c = '(' then (
          incr depth;
          started := true)
        else if c = ')' then decr depth)
      line;
    if !started && !depth <= 0 then continue := false
  done;
  Buffer.contents buf

let check (t : t) (vc : Smt.vc) : result =
  output_string t.oc "(push 1)\n";
  output_string t.oc (Smt.assertion_block vc);
  output_string t.oc "(check-sat)\n";
  flush t.oc;
  let verdict = String.trim (input_line t.ic) in
  let result =
    match verdict with
    | "unsat" -> Unsat
    | "unknown" -> Unknown
    | "sat" ->
        output_string t.oc "(get-model)\n";
        flush t.oc;
        Sat (Model.of_string (read_balanced t.ic))
    | other -> failwith ("refine: unexpected z3 verdict: " ^ other)
  in
  output_string t.oc "(pop 1)\n";
  flush t.oc;
  result

let close (t : t) : unit =
  (try
     output_string t.oc "(exit)\n";
     flush t.oc
   with _ -> ());
  (try close_out t.oc with _ -> ());
  (try close_in t.ic with _ -> ());
  (try ignore (Unix.waitpid [] t.pid) with _ -> ())
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dune build test/test_refine.exe && ./_build/default/test/test_refine.exe`
Expected (z3 present locally): PASS — `solver` suite green (3 cases).
Expected (no z3): PASS — each solver case prints `[skip] ...: no z3 on PATH`.

- [ ] **Step 5: Verify the skip path actually works**

Run: `MARCH_Z3=/nonexistent ./_build/default/test/test_refine.exe`
Expected: PASS — `find_z3` returns `None`, all solver cases print the skip notice and pass.

- [ ] **Step 6: Commit**

```bash
git add lib/refine/solver.ml test/test_refine.ml
git commit -m "feat(refine): long-lived z3 -in driver with push/pop per VC"
```

---

## Task 5: BLAKE3-keyed verdict cache

**Files:**
- Create: `lib/refine/vc_cache.ml`
- Modify: `test/test_refine.ml` (add `cache` suite)

- [ ] **Step 1: Write the failing test**

In `test/test_refine.ml`, add this suite definition immediately before the final `let () = Alcotest.run ...`:

```ocaml
let cache_suite =
  (* Unique temp root per process to avoid concurrent-session collisions. *)
  let root =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march_refine_cache_%d" (Unix.getpid ()))
  in
  let vc : Smt.vc =
    { decls = [ ("d", Smt.SInt) ]; assumptions = []; goal =
      Smt.Ne (Smt.Const "d", Smt.IntLit 0) }
  in
  [ Alcotest.test_case "key is stable for equal VCs" `Quick (fun () ->
        Alcotest.(check string) "key" (Vc_cache.key_of_vc vc)
          (Vc_cache.key_of_vc vc));

    Alcotest.test_case "miss then store then hit (unsat)" `Quick (fun () ->
        let key = Vc_cache.key_of_vc vc in
        Alcotest.(check bool) "initial miss" true
          (Vc_cache.lookup ~root key = None);
        Vc_cache.store ~root key Solver.Unsat;
        Alcotest.(check bool) "hit unsat" true
          (Vc_cache.lookup ~root key = Some Solver.Unsat));

    Alcotest.test_case "round-trips a sat model" `Quick (fun () ->
        let key = "ff" ^ String.make 62 'a' in
        let r = Solver.Sat [ ("d", "0"); ("i", "10") ] in
        Vc_cache.store ~root key r;
        Alcotest.(check bool) "hit sat" true
          (Vc_cache.lookup ~root key = Some r)) ]
```

Then add `("cache", cache_suite)` to the final `Alcotest.run` list.

- [ ] **Step 2: Run the test to verify it fails**

Run: `dune build test/test_refine.exe 2>&1 | head -20`
Expected: FAIL — `Vc_cache.key_of_vc`, `Vc_cache.lookup`, `Vc_cache.store` undefined.

- [ ] **Step 3: Implement the cache**

Create `lib/refine/vc_cache.ml`:

```ocaml
(* Content-addressed verdict cache under <root>/.march/cas/vc/.
   Key = BLAKE3 of the VC's canonical assertion block; the solver is consulted
   only on a miss.  Mirrors the git-style <prefix2>/<rest> layout used by the
   rest of the CAS. *)

let key_of_vc (vc : Smt.vc) : string =
  March_cas.Blake3.hash_string (Smt.assertion_block vc)

let string_of_result : Solver.result -> string = function
  | Solver.Unsat -> "unsat"
  | Solver.Unknown -> "unknown"
  | Solver.Sat model ->
      "sat\n"
      ^ String.concat "\n" (List.map (fun (k, v) -> k ^ "\t" ^ v) model)

let result_of_string (s : string) : Solver.result =
  match String.split_on_char '\n' s with
  | "unsat" :: _ -> Solver.Unsat
  | "unknown" :: _ -> Solver.Unknown
  | "sat" :: rest ->
      let model =
        List.filter_map
          (fun line ->
            match String.index_opt line '\t' with
            | Some i ->
                Some
                  ( String.sub line 0 i,
                    String.sub line (i + 1) (String.length line - i - 1) )
            | None -> None)
          rest
      in
      Solver.Sat model
  | _ -> Solver.Unknown

let cache_dir ~root =
  List.fold_left Filename.concat root [ ".march"; "cas"; "vc" ]

let rec mkdir_p dir =
  if dir = "/" || dir = "." || dir = Filename.dirname dir then ()
  else if Sys.file_exists dir then ()
  else begin
    mkdir_p (Filename.dirname dir);
    try Unix.mkdir dir 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let path_for ~root key =
  let prefix = String.sub key 0 2 in
  let rest = String.sub key 2 (String.length key - 2) in
  Filename.concat (Filename.concat (cache_dir ~root) prefix) rest

let lookup ~root key : Solver.result option =
  let p = path_for ~root key in
  if Sys.file_exists p then
    Some (result_of_string (In_channel.with_open_bin p In_channel.input_all))
  else None

let store ~root key (r : Solver.result) : unit =
  let p = path_for ~root key in
  mkdir_p (Filename.dirname p);
  Out_channel.with_open_bin p (fun oc ->
      Out_channel.output_string oc (string_of_result r))
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dune build test/test_refine.exe && ./_build/default/test/test_refine.exe`
Expected: PASS — `cache` suite green (3 cases).

- [ ] **Step 5: Commit**

```bash
git add lib/refine/vc_cache.ml test/test_refine.ml
git commit -m "feat(refine): BLAKE3-keyed verdict cache under .march/cas/vc"
```

---

## Task 6: Orchestration — cache→solver→outcome

**Files:**
- Create: `lib/refine/refine.ml`
- Modify: `test/test_refine.ml` (add `refine` suite)

- [ ] **Step 1: Write the failing test**

In `test/test_refine.ml`, add this suite definition immediately before the final `let () = Alcotest.run ...`:

```ocaml
let refine_suite =
  let root =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march_refine_disc_%d" (Unix.getpid ()))
  in
  [ Alcotest.test_case "cached unsat returns Verified without a solver" `Quick
      (fun () ->
        (* Pre-seed the cache so discharge never needs z3 — keeps this case
           green in CI.  A subsequent lookup must report Verified. *)
        let vc : Smt.vc =
          { decls = [ ("d", Smt.SInt) ];
            assumptions = [ Smt.Gt (Smt.Const "d", Smt.IntLit 0) ];
            goal = Smt.Ne (Smt.Const "d", Smt.IntLit 0) }
        in
        Vc_cache.store ~root (Vc_cache.key_of_vc vc) Solver.Unsat;
        match Refine.discharge ~root vc with
        | Refine.Verified -> ()
        | Refine.Refuted _ -> Alcotest.fail "expected Verified, got Refuted"
        | Refine.Unverified -> Alcotest.fail "expected Verified, got Unverified");

    Alcotest.test_case "cached sat returns Refuted with model" `Quick (fun () ->
        let vc : Smt.vc =
          { decls = [ ("d", Smt.SInt) ]; assumptions = []; goal =
            Smt.Ne (Smt.Const "d", Smt.IntLit 0) }
        in
        Vc_cache.store ~root (Vc_cache.key_of_vc vc)
          (Solver.Sat [ ("d", "0") ]);
        match Refine.discharge ~root vc with
        | Refine.Refuted model ->
            Alcotest.(check (option string)) "d=0" (Some "0")
              (List.assoc_opt "d" model)
        | _ -> Alcotest.fail "expected Refuted") ]
```

Then add `("refine", refine_suite)` to the final `Alcotest.run` list.

- [ ] **Step 2: Run the test to verify it fails**

Run: `dune build test/test_refine.exe 2>&1 | head -20`
Expected: FAIL — `Refine.discharge`, `Refine.Verified`, `Refine.Refuted`, `Refine.Unverified` undefined.

- [ ] **Step 3: Implement the orchestration**

Create `lib/refine/refine.ml`:

```ocaml
(* Top-level discharge: cache lookup -> shared solver -> cache store, mapping the
   raw solver verdict to a caller-facing outcome.  The solver is created lazily
   and shared across the run; if z3 is unavailable the result is Unverified and
   is NOT cached (z3 may be installed before the next build). *)

type outcome =
  | Verified                          (* goal proved (unsat of its negation) *)
  | Refuted of (string * string) list (* goal can fail; counterexample model *)
  | Unverified                        (* unknown, or z3 unavailable *)

(* None  = not yet attempted; Some None = attempted, z3 absent; Some (Some s) = live. *)
let shared_solver : Solver.t option option ref = ref None

let get_solver () : Solver.t option =
  match !shared_solver with
  | Some s -> s
  | None ->
      let s = Solver.create () in
      shared_solver := Some s;
      s

let discharge ~root (vc : Smt.vc) : outcome =
  let key = Vc_cache.key_of_vc vc in
  let result =
    match Vc_cache.lookup ~root key with
    | Some r -> r
    | None -> (
        match get_solver () with
        | None -> Solver.Unknown (* z3 unavailable; do not cache *)
        | Some s ->
            let r = Solver.check s vc in
            Vc_cache.store ~root key r;
            r)
  in
  match result with
  | Solver.Unsat -> Verified
  | Solver.Sat model -> Refuted model
  | Solver.Unknown -> Unverified
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dune build test/test_refine.exe && ./_build/default/test/test_refine.exe`
Expected: PASS — `refine` suite green (2 cases); entire suite green.

- [ ] **Step 5: End-to-end check with the real solver (local only)**

Run: `./_build/default/test/test_refine.exe`
Expected (z3 present): every suite green, including `solver`. This exercises render → spawn → check → parse → cache → outcome end to end.

- [ ] **Step 6: Commit**

```bash
git add lib/refine/refine.ml test/test_refine.ml
git commit -m "feat(refine): discharge orchestration (cache->solver->outcome)"
```

---

## Task 7: Full-suite regression and spec bookkeeping

**Files:**
- Modify: `specs/progress.md`
- Modify: `specs/todos.md`

- [ ] **Step 1: Run the full project test suite (must not regress)**

Run: `scripts/run-tests.sh`
Expected: the whole suite passes (the new `test_refine` runs under `dune runtest`; everything else is unchanged). Judge by exit code: `echo $?` must be `0`.

- [ ] **Step 2: Confirm the new suite is wired into `dune runtest`**

Run: `dune build @runtest --force 2>&1 | grep -i refine || echo "ran clean"`
Expected: no refine-related failures (either a green refine line or "ran clean").

- [ ] **Step 3: Update `specs/progress.md`**

Under the type-system feature bullets, add:

```markdown
- **Refinement-types Z3 bridge (Phase A0)** — `lib/refine/`: SMT-LIB2 renderer
  for the Int/Bool linear-arithmetic + EUF fragment, a long-lived `z3 -in`
  driver (push/pop per VC), a BLAKE3-keyed verdict cache under
  `.march/cas/vc/`, and a `discharge` orchestrator. Standalone and unit-tested
  (`test/test_refine.ml`); graceful skip when z3 is absent. Not yet wired into
  the typechecker (that is Phase A1).
```

- [ ] **Step 4: Update `specs/todos.md`**

Move the A0 line to the Done section (or add it there if not present):

```markdown
- [x] Refinement types A0: standalone Z3 bridge (`lib/refine/`) — render, solve,
      cache, discharge; proven by `test/test_refine.ml`. Next: A1 (wire VC
      emission into `typecheck.ml` for Int-only preconditions).
```

- [ ] **Step 5: Commit**

```bash
git add specs/progress.md specs/todos.md
git commit -m "docs(refine): record Phase A0 (standalone Z3 bridge) in specs"
```

---

## Self-Review (completed during planning)

**Spec coverage (against `specs/2026-06-20-...-design.md` A0 exit criteria):**
- "SMT-LIB2 renderer" → Task 2 (`Smt`).
- "long-lived `z3 -in` driver with push/pop" → Task 4 (`Solver`).
- "CAS `vc/` cache" → Task 5 (`Vc_cache`).
- "counterexample-model parser" → Task 3 (`Model`) + Task 4 model extraction.
- "returns unsat/sat(+model)/unknown correctly on fixture VCs" → Task 4 solver suite.
- "cache hits on repeat" → Task 5 miss→store→hit; Task 6 cached-discharge.
- "missing-z3 path returns a clean unavailable signal (no crash)" → Task 4 Step 5 (`MARCH_Z3=/nonexistent`); Task 6 `Unverified` + no-cache path.
- "no typechecker involvement" → the library depends only on `march_cas` + `unix`; no `march_typecheck`/`march_ast` dependency anywhere.

**Type consistency:** `Smt.vc` fields (`decls`/`assumptions`/`goal`) are identical across Tasks 2–6. `Solver.result` (`Unsat`/`Sat`/`Unknown`) is produced in Task 4 and consumed unchanged in Tasks 5–6. `Refine.outcome` (`Verified`/`Refuted`/`Unverified`) is defined and tested in Task 6. `Model.of_string` and `Vc_cache.{key_of_vc,lookup,store}` signatures match their call sites in the tests.

**Placeholder scan:** every code step contains complete, compilable code; every run step has an exact command and expected result. No TBD/TODO.

**Scope:** A0 only — a single self-contained, independently testable library. A1 (typechecker wiring) is a separate plan.
