# REPL Improvements & Actor Handler Diagnostics — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add rich actor handler type error messages, wire the typechecker into the REPL for type-error feedback and recovery, and enable multi-line paste input.

**Architecture:** Three independent changes to two files. `typecheck.ml` gets `types_equal` + `actor_handler_hints` helpers and a rewritten handler check. `bin/main.ml` gets the REPL multi-line accumulator, a persistent typechecker env, and a top-level error recovery wrapper. No new files needed.

**Tech Stack:** OCaml 5.3.0, dune, Alcotest, Menhir, `str` stdlib library

**Build command:** `PATH="/Users/80197052/.opam/march/bin:$PATH" dune build`
**Test command:** `PATH="/Users/80197052/.opam/march/bin:$PATH" dune runtest`

---

## File Map

| File | Change |
|------|--------|
| `lib/typecheck/typecheck.ml` | Add `types_equal`, `actor_handler_hints`; rewrite handler body check |
| `bin/main.ml` | Print `notes`; multi-line accumulator; typechecker in REPL; top-level error recovery |
| `bin/dune` | Add `str` library |
| `test/test_march.ml` | Add actor handler diagnostic tests |

---

## Task 1: Actor Handler Rich Diagnostics

**Files:**
- Modify: `lib/typecheck/typecheck.ml` (around lines 1310, 1372–1386)
- Modify: `bin/main.ml` (lines 107–119)
- Modify: `test/test_march.ml` (add to `typecheck` suite)

### Step 1.1: Write failing tests

Add these two test functions to `test/test_march.ml`, just before the `let () = Alcotest.run` block:

```ocaml
let contains sub s =
  let sl = String.length sub and tl = String.length s in
  let rec go i = i <= tl - sl && (String.sub s i sl = sub || go (i + 1))
  in go 0

let test_actor_handler_extra_field () =
  (* Handler returns an extra field not in state → error with note *)
  let ctx = typecheck {|mod Test do
    actor Counter do
      state { value : Int }
      init { value = 0 }
      on Bad() do
        { value = 0, extra = true }
      end
    end
  end|} in
  Alcotest.(check bool) "extra field: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  (match List.find_opt (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags with
  | None -> Alcotest.fail "expected an Error diagnostic"
  | Some d ->
    Alcotest.(check bool) "message mentions handler 'Bad'" true
      (contains "Bad" d.March_errors.Errors.message);
    Alcotest.(check bool) "message mentions actor 'Counter'" true
      (contains "Counter" d.March_errors.Errors.message);
    Alcotest.(check bool) "has at least one note" true
      (d.March_errors.Errors.notes <> []);
    Alcotest.(check bool) "note mentions 'extra'" true
      (List.exists (fun n -> contains "extra" n)
        d.March_errors.Errors.notes))

let test_actor_handler_missing_field () =
  (* Handler omits a state field → error with missing-field note *)
  let ctx = typecheck {|mod Test do
    actor Widget do
      state { value : Int, name : String }
      init { value = 0, name = "x" }
      on Reset() do
        { value = 0 }
      end
    end
  end|} in
  Alcotest.(check bool) "missing field: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  (match List.find_opt (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags with
  | None -> Alcotest.fail "expected an Error diagnostic"
  | Some d ->
    Alcotest.(check bool) "note mentions 'name'" true
      (List.exists (fun n -> contains "name" n)
        d.March_errors.Errors.notes))

let test_actor_handler_correct () =
  (* Correct handler → no errors *)
  let ctx = typecheck {|mod Test do
    actor Counter do
      state { value : Int }
      init { value = 0 }
      on Inc() do
        { value = state.value + 1 }
      end
    end
  end|} in
  Alcotest.(check bool) "correct handler: no errors" false (has_errors ctx)
```

Register the tests in `Alcotest.run` inside the existing `"typecheck"` suite entry:

```ocaml
Alcotest.test_case "actor handler extra field"   `Quick test_actor_handler_extra_field;
Alcotest.test_case "actor handler missing field" `Quick test_actor_handler_missing_field;
Alcotest.test_case "actor handler correct"       `Quick test_actor_handler_correct;
```

- [ ] Add the `contains` helper and three test functions to `test/test_march.ml` before `let () = Alcotest.run`
- [ ] Add the three `Alcotest.test_case` lines to the `"typecheck"` list in `Alcotest.run`

### Step 1.2: Run tests — verify they fail

```bash
PATH="/Users/80197052/.opam/march/bin:$PATH" dune runtest 2>&1 | grep -A3 "actor handler"
```

Expected: all three new tests fail (the two error tests fail because the diagnostic message doesn't contain the actor/handler name; the correct-handler test may pass already).

- [ ] Run tests, confirm failure

### Step 1.3: Add helpers to `typecheck.ml`

Add these two functions to `lib/typecheck/typecheck.ml`, immediately before the `let rec check_decl` definition (around line 1310):

```ocaml
(** Structural equality after repr — works for concrete types; may give
    false-positive wrong-type hints when two distinct unresolved TVars
    happen not to be linked yet (acceptable in actor handler context). *)
let types_equal a b = repr a = repr b

(** Build hint strings explaining why an actor handler body has the wrong type.
    state_ty and inferred_ty should both be repr-ed before calling. *)
let actor_handler_hints state_ty inferred_ty =
  match inferred_ty with
  | TRecord inferred_fields ->
    (match state_ty with
     | TRecord [] ->
       ["the state has no fields — return an empty record {}"]
     | TRecord state_fields ->
       let state_names    = List.map fst state_fields in
       let inferred_names = List.map fst inferred_fields in
       let extra   = List.filter (fun n -> not (List.mem n state_names)) inferred_names in
       let missing = List.filter (fun n -> not (List.mem n inferred_names)) state_names in
       let wrong_type = List.filter_map (fun (fname, st) ->
           match List.assoc_opt fname inferred_fields with
           | Some it when not (types_equal st it) ->
             Some (Printf.sprintf
               "field '%s' has type %s but state declares it as %s"
               fname (pp_ty (repr it)) (pp_ty (repr st)))
           | _ -> None) state_fields in
       List.map (fun n -> Printf.sprintf
         "field '%s' is not part of the actor state \
          — remove it, or add it to the state declaration" n) extra
       @ List.map (fun n -> Printf.sprintf
         "field '%s' is missing from the returned record" n) missing
       @ wrong_type
     | _ -> [])
  | t ->
    [Printf.sprintf "handler must return a record matching the state, not %s" (pp_ty t)]
```

- [ ] Add `types_equal` and `actor_handler_hints` to `typecheck.ml` before `check_decl`

### Step 1.4: Rewrite handler body check in `check_decl`

In `lib/typecheck/typecheck.ml`, find the `DActor` handler loop (around line 1372–1386). It currently reads:

```ocaml
        (* Handler body must return the state record type *)
        check_expr handler_env h.ah_body state_ty
          ~reason:(Some (RBuiltin (Printf.sprintf "handler `%s` must return the state record" h.ah_msg.txt)))
```

Replace that single `check_expr` call with:

```ocaml
        (* Handler body must return the state record type — emit rich diagnostic *)
        let inferred = infer_expr handler_env h.ah_body in
        let shadow_env = { handler_env with errors = Err.create () } in
        (* Note: pending_constraints and type_map are shared (shallow copy) —
           intentional; only error reporting is isolated. *)
        unify shadow_env ~span:h.ah_msg.span ~reason:None
          (repr inferred) (repr state_ty);
        if Err.has_errors shadow_env.errors then
          Err.report handler_env.errors
            { severity = Error;
              span = h.ah_msg.span;
              message = Printf.sprintf
                "handler '%s' in actor '%s' must return the state type\
                 \n  expected: %s\
                 \n  got:      %s"
                h.ah_msg.txt name.txt
                (pp_ty (repr state_ty)) (pp_ty (repr inferred));
              labels = [];
              notes = actor_handler_hints (repr state_ty) (repr inferred) }
```

- [ ] Replace the `check_expr` call in the `DActor` handler loop

### Step 1.5: Print `notes` in the file compiler diagnostic loop

In `bin/main.ml`, find the `List.iter` that prints diagnostics (lines 107–119). It currently ends after printing `d.message`. Add note printing immediately after:

```ocaml
  List.iter (fun (d : March_errors.Errors.diagnostic) ->
      let sev = match d.severity with
        | March_errors.Errors.Error   -> "error"
        | March_errors.Errors.Warning -> "warning"
        | March_errors.Errors.Hint    -> "hint"
      in
      Printf.printf "%s:%d:%d: %s: %s\n"
        d.span.March_ast.Ast.file
        d.span.March_ast.Ast.start_line
        d.span.March_ast.Ast.start_col
        sev
        d.message;
      List.iter (fun note ->
          Printf.printf "note: %s\n" note
        ) d.notes
    ) diags;
```

- [ ] Update diagnostic print loop in `bin/main.ml`

### Step 1.6: Build and run tests

```bash
PATH="/Users/80197052/.opam/march/bin:$PATH" dune build && \
PATH="/Users/80197052/.opam/march/bin:$PATH" dune runtest 2>&1 | grep -A5 "actor handler"
```

Expected: all three actor handler tests pass; all prior tests still pass.

- [ ] Run `dune build` — fix any compilation errors
- [ ] Run `dune runtest` — verify all tests pass

### Step 1.7: Commit

```bash
git add lib/typecheck/typecheck.ml bin/main.ml test/test_march.ml
git commit -m "feat(typecheck): rich actor handler return type diagnostics with field-level hints"
```

- [ ] Commit

---

## Task 2: REPL Multi-line Input

**Files:**
- Modify: `bin/dune`
- Modify: `bin/main.ml`

### Step 2.1: Add `str` to `bin/dune`

Current contents of `bin/dune`:
```
(executable
 (name main)
 (public_name march)
 (libraries march_lexer march_parser march_ast march_desugar march_typecheck march_codegen march_effects march_errors march_eval march_tir))
```

Add `str` to the libraries list:
```
(executable
 (name main)
 (public_name march)
 (libraries str march_lexer march_parser march_ast march_desugar march_typecheck march_codegen march_effects march_errors march_eval march_tir))
```

- [ ] Add `str` to `bin/dune`

### Step 2.2: Add multi-line accumulator helpers to `bin/main.ml`

Add these helpers at the top of `bin/main.ml`, after the `let dump_tir = ref false` line and before the REPL section:

```ocaml
(* ------------------------------------------------------------------ *)
(* Multi-line REPL input                                              *)
(* ------------------------------------------------------------------ *)

(** Count exact whole-word occurrences of [tok] in [buf].
    Splits on non-identifier characters so "done" does not count as "do". *)
let count_token tok buf =
  let words = Str.split (Str.regexp "[^a-zA-Z0-9_']") buf in
  List.length (List.filter (( = ) tok) words)

(** Net depth of open do/end blocks in [buf].
    Positive means we are inside an unclosed block.
    Known limitation: `do` or `end` inside string literals are miscounted;
    use a blank line to force-submit in that case. *)
let do_end_depth buf =
  count_token "do" buf - count_token "end" buf

(** Last non-blank line in [buf], trimmed. *)
let last_non_blank_line buf =
  let lines = String.split_on_char '\n' buf in
  match List.rev (List.filter (fun l -> String.trim l <> "") lines) with
  | []    -> ""
  | l :: _ -> String.trim l

(** True if the last non-blank line ends with the token "with". *)
let ends_with_with buf =
  let l = last_non_blank_line buf in
  let words = String.split_on_char ' ' (String.trim l) in
  match List.rev words with
  | "with" :: _ -> true
  | _            -> false

(** True if the last non-blank line starts with '|' (match arm continuation). *)
let starts_with_pipe buf =
  let l = last_non_blank_line buf in
  String.length l > 0 && l.[0] = '|'

(** Read one complete REPL input, possibly spanning multiple lines.
    Returns [None] on EOF with empty buffer (exit signal),
    [Some src] when the input is judged complete. *)
let read_repl_input () =
  let buf        = Buffer.create 64 in
  let first_line = ref true in
  let result     = ref None in
  while !result = None do
    Printf.printf "%s%!" (if !first_line then "march> " else "     | ");
    first_line := false;
    (match (try Some (input_line stdin) with End_of_file -> None) with
     | None ->
       (* EOF *)
       let s = Buffer.contents buf in
       result := Some (if s = "" then None else Some s)
     | Some line ->
       if Buffer.length buf > 0 then Buffer.add_char buf '\n';
       Buffer.add_string buf line;
       let contents = Buffer.contents buf in
       if String.trim line = "" then
         (* Blank line: force submit (escape hatch) *)
         result := Some (Some contents)
       else if do_end_depth contents > 0 then
         ()   (* still inside an open block — keep accumulating *)
       else if ends_with_with contents then
         ()   (* match expression continues — keep accumulating *)
       else if starts_with_pipe contents then
         ()   (* match arm — keep accumulating *)
       else
         result := Some (Some contents))
  done;
  match !result with
  | Some r -> r
  | None   -> assert false
```

- [ ] Add the multi-line helpers to `bin/main.ml`

### Step 2.3: Integrate `read_repl_input` into the REPL loop

In `bin/main.ml`, the REPL currently uses:

```ocaml
  while !running do
    Printf.printf "march> %!";
    let line =
      try Some (input_line stdin)
      with End_of_file -> None
    in
    match line with
    | None -> running := false
    | Some ":quit" | Some ":q" -> running := false
    | Some ":env" ->
      List.iter (fun (k, _) -> Printf.printf "  %s\n" k) !env
    | Some src when String.trim src = "" -> ()
    | Some src ->
```

Replace the `Printf.printf "march> %!"` + `let line = ...` + the `match line with` opener with:

```ocaml
  while !running do
    match read_repl_input () with
    | None -> running := false
    | Some ":quit" | Some ":q" -> running := false
    | Some ":env" ->
      List.iter (fun (k, _) -> Printf.printf "  %s\n" k) !env
    | Some src when String.trim src = "" -> ()
    | Some src ->
```

Everything inside `| Some src ->` remains unchanged for now.

- [ ] Replace `input_line`-based input with `read_repl_input ()` in the REPL loop

### Step 2.4: Build and smoke test

```bash
PATH="/Users/80197052/.opam/march/bin:$PATH" dune build
```

Then manually test by running the REPL and pasting:
```
actor Logger do
  state { count : Int }
  init { count = 0 }
  on Log(msg : String) do
    println(msg)
    { state with count = state.count + 1 }
  end
end
```

Expected: the REPL accumulates all lines (showing `     | ` prompt) and submits after the final `end`.

- [ ] `dune build` — fix any errors
- [ ] Manual smoke test: paste multi-line actor, verify it submits at the right time

### Step 2.5: Commit

```bash
git add bin/dune bin/main.ml
git commit -m "feat(repl): multi-line input accumulator with do/end depth and match heuristics"
```

- [ ] Commit

---

## Task 3: REPL Error Recovery + Typechecker

**Files:**
- Modify: `bin/main.ml`

### Step 3.1: Add a REPL-local diagnostic printer

Add this helper function in `bin/main.ml`, in the REPL section (before the `repl ()` function definition):

```ocaml
(** Print a diagnostic in REPL style (no file/line prefix — interactive context). *)
let print_repl_diag (d : March_errors.Errors.diagnostic) =
  let sev = match d.severity with
    | March_errors.Errors.Error   -> "error"
    | March_errors.Errors.Warning -> "warning"
    | March_errors.Errors.Hint    -> "hint"
  in
  Printf.eprintf "%s: %s\n%!" sev d.message;
  List.iter (fun note ->
      Printf.eprintf "note: %s\n%!" note
    ) d.notes
```

- [ ] Add `print_repl_diag` to `bin/main.ml`

### Step 3.2: Initialize typechecker env in `repl ()`

In `bin/main.ml`, inside `repl ()`, the current setup is:

```ocaml
let repl () =
  Printf.printf "March REPL — :quit to exit, :env to list bindings\n%!";
  let env = ref March_eval.Eval.base_env in
  let running = ref true in
```

Add typechecker env initialization right after `let env = ref ...`:

```ocaml
let repl () =
  Printf.printf "March REPL — :quit to exit, :env to list bindings\n%!";
  let env = ref March_eval.Eval.base_env in
  let type_map = Hashtbl.create 64 in
  (* base_env (line 470 of typecheck.ml) pre-populates built-in types, ctors,
     and vars (Int, String, Bool, println, etc.) — unlike bare make_env. *)
  let tc_env = ref
    (March_typecheck.Typecheck.base_env
       (March_errors.Errors.create ()) type_map) in
  let running = ref true in
```

**Note on single-pass limitation:** `check_decl` performs only one pass, so self-recursive function definitions entered in the REPL will produce false "undefined variable" errors (the full compiler uses a two-pass approach). This is a known limitation — non-recursive definitions and multi-line actors work correctly.

- [ ] Add `type_map` and `tc_env` initialization inside `repl ()`

### Step 3.3: Wire typechecker into the `ReplExpr` path

Find the `| Some (March_ast.Ast.ReplExpr e) ->` branch in the REPL loop. It currently reads:

```ocaml
       | Some (March_ast.Ast.ReplExpr e) ->
         let e' = March_desugar.Desugar.desugar_expr e in
         (try
            let v = March_eval.Eval.eval_expr !env e' in
            Printf.printf "= %s\n%!" (March_eval.Eval.value_to_string v)
          with
          | March_eval.Eval.Eval_error msg ->
            Printf.eprintf "runtime error: %s\n%!" msg
          | March_eval.Eval.Match_failure msg ->
            Printf.eprintf "match failure: %s\n%!" msg)
```

Replace with:

```ocaml
       | Some (March_ast.Ast.ReplExpr e) ->
         let e' = March_desugar.Desugar.desugar_expr e in
         let input_ctx = March_errors.Errors.create () in
         let input_tc  = { !tc_env with errors = input_ctx } in
         let inferred  = March_typecheck.Typecheck.infer_expr input_tc e' in
         let ty_str    = March_typecheck.Typecheck.pp_ty
           (March_typecheck.Typecheck.repr inferred) in
         List.iter print_repl_diag (March_errors.Errors.sorted input_ctx);
         if March_errors.Errors.has_errors input_ctx then
           Printf.eprintf "note: inferred type was %s\n%!" ty_str
         else begin
           (try
              let v = March_eval.Eval.eval_expr !env e' in
              Printf.printf "= %s\n%!" (March_eval.Eval.value_to_string v)
            with
            | March_eval.Eval.Eval_error msg ->
              Printf.eprintf "runtime error: %s\n%!" msg
            | March_eval.Eval.Match_failure msg ->
              Printf.eprintf "match failure: %s\n%!" msg)
         end
```

- [ ] Replace the `ReplExpr` branch

### Step 3.4: Wire typechecker into the `ReplDecl` path

Find the `| Some (March_ast.Ast.ReplDecl d) ->` branch. It currently reads:

```ocaml
       | Some (March_ast.Ast.ReplDecl d) ->
         let d' = March_desugar.Desugar.desugar_decl d in
         (try
            env := March_eval.Eval.eval_decl !env d';
            (match d' with
             | March_ast.Ast.DFn (def, _) ->
               Printf.printf "val %s = <fn>\n%!" def.fn_name.txt
             | March_ast.Ast.DLet (b, _) ->
               (match b.bind_pat with
                | March_ast.Ast.PatVar n ->
                  let v = List.assoc n.txt !env in
                  Printf.printf "val %s = %s\n%!" n.txt
                    (March_eval.Eval.value_to_string v)
                | _ -> Printf.printf "val _ = ...\n%!")
             | _ -> ())
          with
          | March_eval.Eval.Eval_error msg ->
            Printf.eprintf "runtime error: %s\n%!" msg
          | March_eval.Eval.Match_failure msg ->
            Printf.eprintf "match failure: %s\n%!" msg)
```

Replace with:

```ocaml
       | Some (March_ast.Ast.ReplDecl d) ->
         let d' = March_desugar.Desugar.desugar_decl d in
         let input_ctx = March_errors.Errors.create () in
         let input_tc  = { !tc_env with errors = input_ctx } in
         let new_tc    = March_typecheck.Typecheck.check_decl input_tc d' in
         List.iter print_repl_diag (March_errors.Errors.sorted input_ctx);
         if not (March_errors.Errors.has_errors input_ctx) then begin
           tc_env := { new_tc with errors = March_errors.Errors.create () };
           (try
              env := March_eval.Eval.eval_decl !env d';
              (match d' with
               | March_ast.Ast.DFn (def, _) ->
                 Printf.printf "val %s = <fn>\n%!" def.fn_name.txt
               | March_ast.Ast.DLet (b, _) ->
                 (match b.bind_pat with
                  | March_ast.Ast.PatVar n ->
                    let v = List.assoc n.txt !env in
                    Printf.printf "val %s = %s\n%!" n.txt
                      (March_eval.Eval.value_to_string v)
                  | _ -> Printf.printf "val _ = ...\n%!")
               | _ -> ())
            with
            | March_eval.Eval.Eval_error msg ->
              Printf.eprintf "runtime error: %s\n%!" msg
            | March_eval.Eval.Match_failure msg ->
              Printf.eprintf "match failure: %s\n%!" msg)
         end
```

- [ ] Replace the `ReplDecl` branch

### Step 3.5: Add top-level error recovery wrapper

Wrap the entire inner body of the `while !running do ... done` loop in a top-level `try/with`. The loop currently starts with `match read_repl_input () with`. Wrap it:

```ocaml
  while !running do
    (try
       (match read_repl_input () with
        | None -> running := false
        | Some ":quit" | Some ":q" -> running := false
        | Some ":env" ->
          List.iter (fun (k, _) -> Printf.printf "  %s\n" k) !env
        | Some src when String.trim src = "" -> ()
        | Some src ->
          (* ... all existing parse/eval branches unchanged ... *)
          )
     with
     | March_lexer.Lexer.Lexer_error msg ->
       Printf.eprintf "lexer error: %s\n%!" msg
     | March_eval.Eval.Eval_error msg ->
       Printf.eprintf "runtime error: %s\n%!" msg
     | March_eval.Eval.Match_failure msg ->
       Printf.eprintf "match failure: %s\n%!" msg
     | exn ->
       Printf.eprintf "internal error: %s\n%!" (Printexc.to_string exn))
  done
```

- [ ] Wrap the loop body in top-level `try/with`

### Step 3.6: Build and smoke test

```bash
PATH="/Users/80197052/.opam/march/bin:$PATH" dune build
PATH="/Users/80197052/.opam/march/bin:$PATH" dune runtest
```

Then manually test the REPL:

**Test 1 — type error shows inferred type:**
```
march> 1 + true
```
Expected: error about type mismatch + `note: inferred type was ...`; session continues.

**Test 2 — runtime error recovery:**
```
march> match 1 with | 2 -> "two" end
```
Expected: `match failure: ...`; session continues.

**Test 3 — successful declaration accumulates tc_env:**
```
march> fn double(x : Int) : Int do x + x end
march> double(21)
```
Expected: `val double = <fn>`, then `= 42`.

**Test 4 — actor definition type-checked:**
```
march> actor Counter do
     |   state { value : Int }
     |   init { value = 0 }
     |   on Bad() do
     |     { value = 0, extra = true }
     |   end
     | end
```
Expected: error with actor name, handler name, and note about `extra` field.

- [ ] `dune build` — fix any errors
- [ ] `dune runtest` — all tests pass
- [ ] Manual smoke tests 1–4 pass

### Step 3.7: Commit

```bash
git add bin/main.ml
git commit -m "feat(repl): wire typechecker into REPL, add error recovery and inferred type notes"
```

- [ ] Commit
