# Design: REPL Improvements & Actor Handler Diagnostics

**Date:** 2026-03-18
**Status:** Approved

## Overview

Three features for the March compiler:

1. **Actor handler return type diagnostics** — rich error messages when a handler body returns the wrong type
2. **REPL error recovery** — catch all errors per-input, continue the session; wire typechecker into REPL loop
3. **REPL multi-line paste** — accumulate lines using `do`/`end` depth + trailing-`with` / leading-`|` heuristics

---

## 1. Actor Handler Return Type Diagnostics

### Problem

When a handler body returns the wrong type, the error is a generic type mismatch with no context about which actor or handler is at fault.

### Approach

In `check_actor` (around line 1372–1386 of `lib/typecheck/typecheck.ml`), replace the single `check_expr` call for each handler body with:

1. **Infer first:** call `infer_expr handler_env h.ah_body` to get the concrete inferred type.
2. **Unify via shadow env:** build `shadow_env = { handler_env with errors = Err.create () }`. Call `unify shadow_env ~span ~reason:None (repr inferred) (repr state_ty)`. This performs all type-variable side-effects (union-find updates, occurs-check, level adjustment) without emitting a generic error into the real `env.errors`.

   **Note on shared mutable state:** `{ handler_env with errors = shadow_ctx }` does a shallow copy. `pending_constraints` (a `ref`) and `type_map` (a `Hashtbl.t`) are shared between `handler_env` and `shadow_env`. Any mutations to these during the shadow unify persist globally — this is intentional and correct (we want type-map writes to be recorded), but the shadow is not a fully isolated sandbox, only error-reporting is isolated.

3. **Emit custom diagnostic if unification failed:** if `Err.has_errors shadow_env.errors` then emit a rich diagnostic to `env.errors` using `actor_handler_hints`. If unification succeeded, emit nothing.

The `span` for the diagnostic: `actor_handler` has `ah_body : expr` with no separate span field (confirmed from `ast.ml` line 191). Use `h.ah_msg.span` (the handler message name span) as a reasonable approximation, or extract the span from the body expression via a helper.

### Hint generation — `actor_handler_hints`

A new local helper function defined before `check_decl`:

```ocaml
let types_equal a b = (repr a = repr b)
(* Note: structural equality on repr-ed types. Works for fully concrete types.
   May produce false-positive wrong-type hints when comparing two distinct unresolved
   TVar nodes that would eventually unify — acceptable in actor handler context. *)

let actor_handler_hints state_ty inferred_ty =
  match repr inferred_ty with
  | TRecord inferred_fields ->
    (match repr state_ty with
     | TRecord [] ->
       ["the state has no fields — return an empty record {}"]
     | TRecord state_fields ->
       let state_names  = List.map fst state_fields in
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
         "field '%s' is not part of the actor state — remove it, or add it to the state declaration" n) extra
       @ List.map (fun n -> Printf.sprintf
         "field '%s' is missing from the returned record" n) missing
       @ wrong_type
     | _ -> [])
  | t ->
    [Printf.sprintf "handler must return a record matching the state, not %s" (pp_ty t)]
```

### Rich diagnostic

```ocaml
Err.report env.errors {
  severity = Error;
  span = h.ah_msg.span;
  message = Printf.sprintf
    "handler '%s' in actor '%s' must return the state type\n  expected: %s\n  got:      %s"
    h.ah_msg.txt name.txt   (* name is bound by | Ast.DActor (name, actor, _sp) -> *)
    (pp_ty (repr state_ty)) (pp_ty (repr inferred));
  labels = [];
  notes = actor_handler_hints state_ty inferred;
}
```

### `notes` field printing in `bin/main.ml`

The diagnostic print loop (lines 107–119) ignores `d.notes`. Update it to print each note:

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

### Output example

```
main.march:5:4: error: handler 'Increment' in actor 'Counter' must return the state type
  expected: { value : Int }
  got:      { value : Int, extra : Bool }
note: field 'extra' is not part of the actor state — remove it, or add it to the state declaration
```

---

## 2. REPL Error Recovery + Typechecker Integration

### Problem

The REPL never calls the typechecker. Type errors go undetected and produce confusing runtime behaviour. Runtime exceptions can also escape the loop if thrown outside the existing per-branch `try/with` blocks.

### Approach

**Part A — Typechecker env in the REPL:**

`lib/typecheck/typecheck.ml` has no `.mli` file, so all internal types — including `env`, `scheme`, `ctor_info`, etc. — are accessible from `bin/main.ml` via `March_typecheck.Typecheck.env`. No API changes to the typecheck module are needed.

The REPL maintains a persistent `tc_env : March_typecheck.Typecheck.env ref` alongside the existing `eval_env ref`. Initialise it at REPL startup:

```ocaml
let type_map = Hashtbl.create 64 in
let init_ctx = March_errors.Errors.create () in
let tc_env = ref (March_typecheck.Typecheck.make_env init_ctx type_map) in
```

`make_env` is already defined at line 270 of `typecheck.ml` and takes `errors` + `type_map`.

**Part B — Per-input typecheck with fresh error context:**

For each input, create a fresh `Err.ctx` and shadow the env's `errors` field so diagnostics are isolated to this input:

```ocaml
let input_ctx = March_errors.Errors.create () in
let input_tc_env = { !tc_env with errors = input_ctx } in
```

Then:
- For a `ReplDecl d`: call `March_typecheck.Typecheck.check_decl input_tc_env d` → `new_tc_env`.
  - If `Err.has_errors input_ctx`: print diagnostics, do not update `tc_env` or `eval_env`.
  - Else: update `tc_env := { new_tc_env with errors = March_errors.Errors.create () }`, proceed to eval.
- For a `ReplExpr e`: call `March_typecheck.Typecheck.infer_expr input_tc_env e` → `inferred_ty`.
  - Always print `note: inferred type was <T>` using `pp_ty (repr inferred_ty)` — even if there are type errors.
  - If `Err.has_errors input_ctx`: print diagnostics, do not eval.
  - Else: proceed to eval.

**Part C — Top-level error recovery:**

Wrap the entire loop body in a top-level `try/with` to catch anything not handled by inner blocks:

```ocaml
while !running do
  (* ... read input ... *)
  (try
     (* parse → desugar → typecheck → eval *)
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

**Environment invariant:** On any error, neither `tc_env` nor `eval_env` is updated. No partial bindings leak.

**Pipeline per input:**

```
parse → desugar → typecheck (fresh ctx) →
  if type errors: print diagnostics + inferred type note, skip eval
  else: eval → print result, update both envs
```

**REPL behaviour table:**

| Input result | Printed | Envs updated |
|-------------|---------|--------------|
| Parse error | `parse error at col N` | No |
| Lexer error | `lexer error: msg` | No |
| Type error | diagnostics + `note: inferred type was T` | No |
| Runtime error | `runtime error: msg` | No |
| Match failure | `match failure: msg` | No |
| Decl success | `val name = <fn>` or `val name = value` | Yes |
| Expr success | `= value` (+ inferred type available but not printed on success) | Yes |

---

## 3. REPL Multi-line Input

### Problem

The REPL uses `input_line` — returns after the first newline. Pasting multi-line declarations (actors, functions, modules) only processes the first line.

### Approach

Replace `input_line` with an accumulator function `read_repl_input ()` that collects lines until the buffer is considered complete.

#### Completion check — `is_complete buffer`

Applied after each line is appended:

1. **Blank line entered** — force-submit (escape hatch), even mid-block
2. **`do`/`end` depth > 0** — keep accumulating
3. **Last non-blank line ends with token `with`** — keep accumulating
4. **Last non-blank line starts with `|`** — keep accumulating
5. **Otherwise** — submit

#### `do`/`end` depth counting

```ocaml
let count_token tok buf =
  let words = Str.split (Str.regexp "[^a-zA-Z0-9_']") buf in
  List.length (List.filter (( = ) tok) words)

let do_end_depth buf =
  count_token "do" buf - count_token "end" buf
```

Requires `str` in `bin/dune` dependencies.

**Known limitation:** String literals containing `do` or `end` (e.g. `let s = "do it"`) will be miscounted. Accepted — users can hit blank line to force submit.

#### Trailing heuristics

```ocaml
let last_non_blank_line buf =
  let lines = String.split_on_char '\n' buf in
  match List.rev (List.filter (fun l -> String.trim l <> "") lines) with
  | [] -> ""
  | l :: _ -> String.trim l

let ends_with_with buf =
  let l = last_non_blank_line buf in
  let words = String.split_on_char ' ' (String.trim l) in
  match List.rev words with "with" :: _ -> true | _ -> false

let starts_with_pipe buf =
  let l = last_non_blank_line buf in
  String.length l > 0 && l.[0] = '|'
```

#### Accumulator loop

```ocaml
let read_repl_input () =
  let buf = Buffer.create 64 in
  let continuation = ref false in
  let result = ref None in
  while !result = None do
    Printf.printf "%s%!" (if !continuation then "     | " else "march> ");
    continuation := true;
    (match (try Some (input_line stdin) with End_of_file -> None) with
     | None ->
       result := Some (if Buffer.length buf = 0 then None else Some (Buffer.contents buf))
     | Some line ->
       if Buffer.length buf > 0 then Buffer.add_char buf '\n';
       Buffer.add_string buf line;
       let contents = Buffer.contents buf in
       if String.trim line = "" then
         result := Some (Some contents)
       else if do_end_depth contents > 0 then ()
       else if ends_with_with contents then ()
       else if starts_with_pipe contents then ()
       else result := Some (Some contents))
  done;
  match !result with Some r -> r | None -> assert false
```

Returns `None` on EOF with empty buffer (signal to exit REPL), `Some src` with the accumulated source.

#### Prompt

- First line: `march> ` (7 chars)
- Continuation lines: `     | ` (7 chars, visually aligned)

#### Example — pasting an actor

```
march> actor Logger do
     |   state { count : Int }
     |   init { count = 0 }
     |   on Log(msg : String) do
     |     println(msg)
     |     { state with count = state.count + 1 }
     |   end
     |   on Stats() do
     |     state
     |   end
     | end
[submits — depth returns to 0]
```

#### Example — naked match (uses trailing heuristics)

```
march> match x with
     | | A -> 1
     | | B -> 2
     |
[blank line → force submit]
```

---

## Files Changed

| File | Change |
|------|--------|
| `lib/typecheck/typecheck.ml` | `types_equal`, `actor_handler_hints` helpers; replace `check_expr` with infer+shadow-unify+rich-diagnostic in `check_actor` |
| `bin/main.ml` | Print `notes` in diagnostic loop; wire typechecker into REPL; top-level error recovery; multi-line accumulator |
| `bin/dune` | Add `str` library dependency |

## Testing

- Typecheck test: handler returning wrong record type → error contains actor name, handler name, expected/got, and field-level note
- Typecheck test: actor with empty state, handler returning non-empty record → "state has no fields" note
- Manual REPL: paste the Logger actor → works in one paste
- Manual REPL: trigger a runtime error → session continues
- Manual REPL: write ill-typed expression → shows type error + inferred type note, session continues
