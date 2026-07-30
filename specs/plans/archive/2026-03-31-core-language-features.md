# Core Language Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 4 remaining core March language features: list comprehensions, `with` expressions, default argument values, and opaque types with `opaque` keyword.

**Architecture:** List comprehensions and `with` expressions desugar directly in the parser (like string interpolation already does) — no new AST nodes needed for them. Default args add `FPDefault` to the AST and expand to multi-clause fns in the desugar pass. Opaque types add `OPAQUE` keyword; the parser emits `DType(Public, ...)` with variants marked `Private`, leveraging the existing constructor-visibility filtering in typecheck.

**Tech Stack:** OCaml 5.3.0, ocamllex (lexer), Menhir (parser), Alcotest (tests). Build: `dune build`, test: `dune runtest`.

---

## File Map

| File | What changes |
|------|-------------|
| `lib/lexer/lexer.mll` | Add `in`, `opaque` keywords; `<-` as `GETS`; `\\` as `DSLASH` |
| `lib/parser/parser.mly` | Token decls; helper fns; comprehension/with/opaque/default rules |
| `lib/ast/ast.ml` | Add `FPDefault of param * expr` to `fn_param` |
| `lib/desugar/desugar.ml` | Handle `FPDefault`: expand to multi-arity fn clauses |
| `lib/format/format.ml` | Handle `FPDefault` in `fmt_fn_param` |
| `lib/dump/dump.ml` | Handle `FPDefault` in param printing |
| `lib/search/search.ml` | Handle `FPDefault` in param extraction |
| `lib/tir/lower.ml` | Handle `FPDefault` (treat as `FPNamed`) |
| `test/test_march.ml` | Add ~16 new tests across 4 feature groups |
| `syntax_reference.md` | Add comprehension, with, default args, opaque type sections |

---

## Task 1: Lexer — new tokens

**Files:** Modify `lib/lexer/lexer.mll`

- [ ] **Step 1: Add keywords and operators**

  In the keyword table (after `("for", FOR);`), add:
  ```ocaml
  ("in", IN);
  ("opaque", OPAQUE);
  ```

  In the `rule token` section, after `| "|>" { PIPE_ARROW }`, add:
  ```ocaml
  | "<-"          { GETS }
  | "\\\\"        { DSLASH }
  ```
  (`"\\\\"` in ocamllex = two backslashes `\\` in source code)

- [ ] **Step 2: Build to verify no errors**

  Run: `/Users/80197052/.opam/march/bin/dune build 2>&1 | head -30`
  Expected: errors only about undeclared tokens IN, OPAQUE, GETS, DSLASH (parser doesn't declare them yet)

---

## Task 2: Parser — declare tokens + add comprehension helpers

**Files:** Modify `lib/parser/parser.mly`

- [ ] **Step 1: Declare new tokens**

  After `%token IMPORT ALIAS ONLY EXCEPT PFN PTYPE DERIVE FOR` add:
  ```
  %token IN OPAQUE GETS DSLASH
  ```

- [ ] **Step 2: Add helper functions in `%{...%}` header**

  After the `group_fn_clauses` function, before the closing `%}`, add:

  ```ocaml
  (** Build a lambda from a pattern and body for comprehension desugaring.
      PatVar names become a simple named param.
      All other patterns wrap in a match. *)
  let mk_comp_lambda pat body sp =
    match pat with
    | PatVar name ->
      ELam ([{ param_name = name; param_ty = None; param_lin = Unrestricted }], body, sp)
    | _ ->
      let arg = { txt = "__celem"; span = sp } in
      let br = { branch_pat = pat; branch_guard = None; branch_body = body } in
      ELam (
        [{ param_name = arg; param_ty = None; param_lin = Unrestricted }],
        EMatch (EVar arg, [br], sp),
        sp)

  (** [x * 2 for x in xs]         → List.map(xs, fn x -> x * 2)
      [x * 2 for x in xs, x > 3]  → List.map(List.filter(xs, fn x -> x > 3), fn x -> x * 2) *)
  let desugar_list_comp body pat src pred_opt sp =
    let map_lam    = mk_comp_lambda pat body sp in
    let mk_var txt = EVar { txt; span = sp } in
    let source = match pred_opt with
      | None -> src
      | Some pred ->
        let filter_lam = mk_comp_lambda pat pred sp in
        EApp (mk_var "List.filter", [src; filter_lam], sp)
    in
    EApp (mk_var "List.map", [source; map_lam], sp)

  (** Build nested EMatch for a `with` expression.
      with Ok(a) <- e1, Ok(b) <- e2 do body else Err(x) -> h end
      →  match e1 do Ok(a) -> match e2 do Ok(b) -> body | Err(x) -> h end | Err(x) -> h end *)
  let rec build_with bindings body else_arms sp =
    match bindings with
    | [] -> body
    | (pat, e) :: rest ->
      let inner = build_with rest body else_arms sp in
      let ok_br = { branch_pat = pat; branch_guard = None; branch_body = inner } in
      EMatch (e, ok_br :: else_arms, sp)
  ```

- [ ] **Step 3: Build to verify helpers compile**

  Run: `/Users/80197052/.opam/march/bin/dune build 2>&1 | head -30`
  Expected: Clean build (new tokens declared, helpers valid OCaml)

---

## Task 3: Parser — list comprehension rules

**Files:** Modify `lib/parser/parser.mly`

The comprehension rules go in `expr_atom`, **before** the list literal rule `| LBRACKET; elems = ...`.

- [ ] **Step 1: Add comprehension grammar rules**

  In `expr_atom`, before the `(* List literals: [1, 2, 3] ... *)` comment, insert:

  ```mly
  (* List comprehension: [expr for pat in expr] or [expr for pat in expr, pred] *)
  | LBRACKET; body = expr; FOR; pat = pattern; IN; src = expr; RBRACKET
    { let sp = mk_span ($loc) in
      desugar_list_comp body pat src None sp }
  | LBRACKET; body = expr; FOR; pat = pattern; IN; src = expr; COMMA; pred = expr; RBRACKET
    { let sp = mk_span ($loc) in
      desugar_list_comp body pat src (Some pred) sp }
  ```

- [ ] **Step 2: Build**

  Run: `/Users/80197052/.opam/march/bin/dune build 2>&1 | head -30`
  Expected: Clean build. Menhir may emit shift/reduce warnings about the `COMMA` in comprehension vs list; these are resolved by Menhir's default (shift), which is correct here.

- [ ] **Step 3: Write failing tests for list comprehensions**

  In `test/test_march.ml`, after the `test_eval_string_interp_multi` function, add:

  ```ocaml
  (* ── List comprehensions ─────────────────────────────────────────────── *)

  let test_comp_basic () =
    (* [x * 2 for x in [1, 2, 3]] should equal [2, 4, 6] *)
    let env = eval_module {|mod Test do
      fn run() do [x * 2 for x in [1, 2, 3]] end
    end|} in
    let v = call_fn env "run" [] in
    Alcotest.(check (list int)) "basic comprehension"
      [2; 4; 6]
      (List.map vint (vlist v))

  let test_comp_filter () =
    (* [x for x in [1, 2, 3, 4, 5], x > 2] should equal [3, 4, 5] *)
    let env = eval_module {|mod Test do
      fn run() do [x for x in [1, 2, 3, 4, 5], x > 2] end
    end|} in
    let v = call_fn env "run" [] in
    Alcotest.(check (list int)) "filtered comprehension"
      [3; 4; 5]
      (List.map vint (vlist v))

  let test_comp_tuple_pat () =
    (* [(k, v * 10) for (k, v) in [(1, 2), (3, 4)]] *)
    let env = eval_module {|mod Test do
      fn run() do [(k, v * 10) for (k, v) in [(1, 2), (3, 4)]] end
    end|} in
    let v = call_fn env "run" [] in
    let pairs = vlist v in
    let to_pair = function
      | March_eval.Eval.VTuple [k; v] -> (vint k, vint v)
      | _ -> failwith "expected pair" in
    Alcotest.(check (list (pair int int))) "tuple pattern comprehension"
      [(1, 20); (3, 40)]
      (List.map to_pair pairs)

  let test_comp_empty () =
    (* [x for x in [], x > 0] should equal [] *)
    let env = eval_module {|mod Test do
      fn run() do [x for x in [], x > 0] end
    end|} in
    let v = call_fn env "run" [] in
    Alcotest.(check int) "empty comprehension" 0 (List.length (vlist v))
  ```

- [ ] **Step 4: Register tests**

  In `test/test_march.ml`, find the `("string interp", [...])` test group and add a new group after it:

  ```ocaml
  ("comprehensions", [
    Alcotest.test_case "basic map"      `Quick test_comp_basic;
    Alcotest.test_case "filter"         `Quick test_comp_filter;
    Alcotest.test_case "tuple pattern"  `Quick test_comp_tuple_pat;
    Alcotest.test_case "empty source"   `Quick test_comp_empty;
  ]);
  ```

- [ ] **Step 5: Run tests**

  Run: `/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -A3 "comprehension"`
  Expected: All 4 comprehension tests pass.

---

## Task 4: Parser — `with` expressions

**Files:** Modify `lib/parser/parser.mly`

- [ ] **Step 1: Add `with` grammar rules in `expr`**

  In the `expr:` production, after the `MATCH` rules and before the last `| e = expr { e }` fallthrough, add:

  ```mly
  | WITH; bindings = separated_nonempty_list(COMMA, with_binding);
    DO; body = block_body; END
    { build_with bindings body [] (mk_span ($loc)) }
  | WITH; bindings = separated_nonempty_list(COMMA, with_binding);
    DO; body = block_body;
    ELSE; option(arm_sep); else_arms = separated_nonempty_list(arm_sep, branch); END
    { build_with bindings body else_arms (mk_span ($loc)) }
  ```

  Then add the `with_binding` production (e.g. after the `branch` rule):

  ```mly
  with_binding:
    | pat = pattern; GETS; e = expr
      { (pat, e) }
  ```

- [ ] **Step 2: Build**

  Run: `/Users/80197052/.opam/march/bin/dune build 2>&1 | head -30`
  Expected: Clean build. The `WITH` token is already used in record update syntax `{ base with ... }` but that's in `expr_atom` (inside braces), not at `expr` level — no conflict.

- [ ] **Step 3: Write failing tests**

  In `test/test_march.ml`, after the comprehension tests, add:

  ```ocaml
  (* ── With expressions ────────────────────────────────────────────────── *)

  let test_with_basic () =
    (* with expression chains Ok results *)
    let env = eval_module {|mod Test do
      fn find_user(id) do
        if id > 0 do Ok(id * 10) else Err("not found") end
      end
      fn run(id) do
        with Ok(user) <- find_user(id) do
          user + 1
        else
          Err(e) -> 0
        end
      end
    end|} in
    let v = call_fn env "run" [March_eval.Eval.VInt 5] in
    Alcotest.(check int) "with basic ok" 51 (vint v)

  let test_with_else_fires () =
    let env = eval_module {|mod Test do
      fn find_user(id) do
        if id > 0 do Ok(id * 10) else Err("not found") end
      end
      fn run(id) do
        with Ok(user) <- find_user(id) do
          user + 1
        else
          Err(_e) -> 0
        end
      end
    end|} in
    let v = call_fn env "run" [March_eval.Eval.VInt (-1)] in
    Alcotest.(check int) "with else fires" 0 (vint v)

  let test_with_chain () =
    (* two bindings, both succeed *)
    let env = eval_module {|mod Test do
      fn step1(x) do Ok(x + 1) end
      fn step2(x) do Ok(x * 2) end
      fn run() do
        with Ok(a) <- step1(3),
             Ok(b) <- step2(a) do
          b
        else
          Err(_) -> 0
        end
      end
    end|} in
    let v = call_fn env "run" [] in
    Alcotest.(check int) "with chain" 8 (vint v)

  let test_with_no_else () =
    (* with without else clause: partial match (unsafe but should parse/eval) *)
    let env = eval_module {|mod Test do
      fn run() do
        with Ok(x) <- Ok(42) do
          x * 2
        end
      end
    end|} in
    let v = call_fn env "run" [] in
    Alcotest.(check int) "with no else" 84 (vint v)
  ```

- [ ] **Step 4: Register tests**

  ```ocaml
  ("with_expressions", [
    Alcotest.test_case "basic ok path"   `Quick test_with_basic;
    Alcotest.test_case "else fires"      `Quick test_with_else_fires;
    Alcotest.test_case "chain"           `Quick test_with_chain;
    Alcotest.test_case "no else"         `Quick test_with_no_else;
  ]);
  ```

- [ ] **Step 5: Run tests**

  Run: `/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -A3 "with_expr"`
  Expected: All 4 with tests pass.

---

## Task 5: AST — add `FPDefault`

**Files:** Modify `lib/ast/ast.ml`

- [ ] **Step 1: Add FPDefault to fn_param**

  Find the `fn_param` type:
  ```ocaml
  and fn_param =
    | FPPat of pattern              (** Pattern parameter: fn fib(0) *)
    | FPNamed of param              (** Named parameter: fn greet(name : String) *)
  ```

  Add the new variant:
  ```ocaml
  and fn_param =
    | FPPat of pattern              (** Pattern parameter: fn fib(0) *)
    | FPNamed of param              (** Named parameter: fn greet(name : String) *)
    | FPDefault of param * expr     (** Default value: fn greet(name, greeting \\ "Hello") *)
  ```

- [ ] **Step 2: Build — expect exhaustiveness warnings**

  Run: `/Users/80197052/.opam/march/bin/dune build 2>&1 | grep "Warning\|Error" | head -20`
  Expected: Warnings about non-exhaustive matches in format.ml, dump.ml, search.ml, tir/lower.ml.

---

## Task 6: Handle `FPDefault` in all passes

**Files:** `lib/format/format.ml`, `lib/dump/dump.ml`, `lib/search/search.ml`, `lib/tir/lower.ml`

- [ ] **Step 1: Update format.ml**

  Find `fmt_fn_param`:
  ```ocaml
  let fmt_fn_param = function
    | FPPat  p -> fmt_pat p
    | FPNamed p -> fmt_param p
  ```

  Add the new case:
  ```ocaml
  let fmt_fn_param = function
    | FPPat  p -> fmt_pat p
    | FPNamed p -> fmt_param p
    | FPDefault (p, default_e) -> fmt_param p ^ " \\\\ " ^ expr_inline default_e
  ```

- [ ] **Step 2: Update dump.ml**

  Find the param dump (around line 115):
  ```ocaml
  | FPPat pat  ->
  ...
  | FPNamed p  -> param_to_str p
  ```

  Add after `FPNamed`:
  ```ocaml
  | FPDefault (p, _e) -> param_to_str p ^ " \\\\ ..."
  ```

- [ ] **Step 3: Update search.ml**

  Find the fn_param extraction (around line 96):
  ```ocaml
  | Ast.FPNamed p ->
  ...
  | Ast.FPPat _ -> ("_", "_")
  ```

  Add:
  ```ocaml
  | Ast.FPDefault (p, _) ->
    (p.param_name.txt,
     match p.param_ty with Some t -> show_ty t | None -> "_")
  ```

- [ ] **Step 4: Update tir/lower.ml**

  Find the fn_param handling (around line 805):
  ```ocaml
  | Ast.FPNamed p ->
  ...
  | Ast.FPPat (Ast.PatVar n) ->
  ```

  Add after `FPNamed`:
  ```ocaml
  | Ast.FPDefault (p, _) ->
    (* Default is already expanded to multi-arity by the desugar pass;
       by the time TIR lowering runs, FPDefault never appears. *)
    { March_tir.Tir.v_name = p.param_name.txt; ... }
  ```

  Actually, since desugar expands `FPDefault` before TIR lowering, this branch should be unreachable. Add it as a failwith:
  ```ocaml
  | Ast.FPDefault _ ->
    failwith "FPDefault should have been eliminated by desugar pass"
  ```

- [ ] **Step 5: Build clean**

  Run: `/Users/80197052/.opam/march/bin/dune build 2>&1 | head -20`
  Expected: Clean build.

---

## Task 7: Parser — default argument syntax

**Files:** Modify `lib/parser/parser.mly`

- [ ] **Step 1: Add default arg rules to `fn_param`**

  Find the `fn_param:` production:
  ```mly
  fn_param:
    | p = pattern { FPPat p }
    | name = lower_name; COLON; t = ty
      { FPNamed { param_name = name; param_ty = Some t; param_lin = Unrestricted } }
    | LINEAR; name = lower_name; COLON; t = ty
      { FPNamed { param_name = name; param_ty = Some t; param_lin = Linear } }
  ```

  Add two new alternatives at the end:
  ```mly
    | name = lower_name; DSLASH; default_e = expr
      { FPDefault ({ param_name = name; param_ty = None; param_lin = Unrestricted }, default_e) }
    | name = lower_name; COLON; t = ty; DSLASH; default_e = expr
      { FPDefault ({ param_name = name; param_ty = Some t; param_lin = Unrestricted }, default_e) }
  ```

- [ ] **Step 2: Build**

  Run: `/Users/80197052/.opam/march/bin/dune build 2>&1 | head -20`
  Expected: Clean build.

---

## Task 8: Desugar — expand default args

**Files:** Modify `lib/desugar/desugar.ml`

- [ ] **Step 1: Update `is_trivial_param` to handle FPDefault**

  Find:
  ```ocaml
  let is_trivial_param = function
    | FPNamed _ -> true
    | FPPat (PatVar _) -> true
    | FPPat _ -> false
  ```

  Update:
  ```ocaml
  let is_trivial_param = function
    | FPNamed _ -> true
    | FPPat (PatVar _) -> true
    | FPPat _ -> false
    | FPDefault _ -> false  (* forces full desugar to handle expansion *)
  ```

- [ ] **Step 2: Update `fn_param_to_pattern`**

  Find:
  ```ocaml
  let fn_param_to_pattern : fn_param -> pattern = function
    | FPNamed p -> PatVar p.param_name
    | FPPat  p  -> p
  ```

  Add:
  ```ocaml
  let fn_param_to_pattern : fn_param -> pattern = function
    | FPNamed p -> PatVar p.param_name
    | FPPat  p  -> p
    | FPDefault (p, _) -> PatVar p.param_name
  ```

- [ ] **Step 3: Add `expand_defaults_in_def` helper**

  After `desugar_expr` and before `desugar_fn_def`, add:

  ```ocaml
  (** Normalize an fn_param: FPDefault → FPNamed (strips the default,
      which is only needed during the expansion phase). *)
  let fp_strip_default : fn_param -> fn_param = function
    | FPDefault (p, _) -> FPNamed p
    | other -> other

  (** Given a fn_def, if any clause has FPDefault params, prepend shortened
      clauses that call the function with the defaults filled in.

      Example: fn greet(name, greeting \\ "Hello") do body end
      Generates:
        fn greet(name) do greet(name, "Hello") end   ← new shortened clause
        fn greet(name, greeting) do body end          ← original (defaults stripped)

      For M trailing defaults, M new clauses are prepended. *)
  let expand_defaults_in_def (def : fn_def) (fn_sp : span) : fn_def =
    let expand_one_clause (clause : fn_clause) : fn_clause list =
      (* Collect (index, default_expr) for FPDefault params *)
      let defaults = List.filter_map (fun (i, p) ->
          match p with
          | FPDefault (_, d) -> Some (i, d)
          | _ -> None)
        (List.mapi (fun i p -> (i, p)) clause.fc_params) in
      if defaults = [] then [clause]
      else begin
        let n_params = List.length clause.fc_params in
        let n_defaults = List.length defaults in
        (* Index of first default (defaults must be trailing) *)
        let first_default_idx = fst (List.hd defaults) in
        (* Generate shortened clauses for each number of trailing defaults to fill *)
        let extra_clauses = List.init n_defaults (fun i ->
          (* Clause with (n_params - n_defaults + i) params: fill in last (n_defaults - i) defaults *)
          let n_short = first_default_idx + i in
          let short_params = List.filteri (fun j _ -> j < n_short)
            (List.map fp_strip_default clause.fc_params) in
          (* Fill-in defaults: the defaults from index i onwards *)
          let fill_defaults = List.filteri (fun j _ -> j >= i) (List.map snd defaults) in
          (* Build call: def.fn_name(arg0, ..., arg_{n_short-1}, default_i, ...) *)
          let arg_exprs = List.map (function
            | FPNamed p -> EVar p.param_name
            | FPPat (PatVar n) -> EVar n
            | FPDefault (p, _) -> EVar p.param_name
            | FPPat _ ->
              (* This shouldn't happen; pattern params don't have names *)
              let synth = fresh_arg_name 999 in EVar synth
          ) short_params in
          let call = EApp (EVar def.fn_name, arg_exprs @ fill_defaults, fn_sp) in
          { clause with fc_params = short_params; fc_guard = None; fc_body = call }
        ) in
        (* Full clause with defaults stripped *)
        let full_clause = { clause with
          fc_params = List.map fp_strip_default clause.fc_params } in
        extra_clauses @ [full_clause]
      end
    in
    let expanded = List.concat_map expand_one_clause def.fn_clauses in
    { def with fn_clauses = expanded }
  ```

- [ ] **Step 4: Call expansion in `desugar_decl`**

  Find in `desugar_decl`:
  ```ocaml
  | DFn (def, sp) ->
    DFn (desugar_fn_def def sp, sp)
  ```

  Update:
  ```ocaml
  | DFn (def, sp) ->
    let def' = expand_defaults_in_def def sp in
    DFn (desugar_fn_def def' sp, sp)
  ```

- [ ] **Step 5: Build**

  Run: `/Users/80197052/.opam/march/bin/dune build 2>&1 | head -20`
  Expected: Clean build.

- [ ] **Step 6: Write failing tests for default args**

  In `test/test_march.ml`, add:

  ```ocaml
  (* ── Default argument values ─────────────────────────────────────────── *)

  let test_default_arg_basic () =
    (* calling with default *)
    let env = eval_module {|mod Test do
      fn greet(name, greeting \\ "Hello") do
        greeting ++ ", " ++ name ++ "!"
      end
    end|} in
    let v1 = call_fn env "greet" [March_eval.Eval.VString "World"] in
    let v2 = call_fn env "greet" [March_eval.Eval.VString "World"; March_eval.Eval.VString "Hi"] in
    Alcotest.(check string) "default used"    "Hello, World!" (vstr v1);
    Alcotest.(check string) "override works"  "Hi, World!"    (vstr v2)

  let test_default_arg_multi () =
    (* two defaults *)
    let env = eval_module {|mod Test do
      fn fmt(val, prefix \\ "[", suffix \\ "]") do
        prefix ++ to_string(val) ++ suffix
      end
    end|} in
    let v0 = call_fn env "fmt" [March_eval.Eval.VInt 42] in
    let v1 = call_fn env "fmt" [March_eval.Eval.VInt 42; March_eval.Eval.VString "("] in
    let v2 = call_fn env "fmt" [March_eval.Eval.VInt 42; March_eval.Eval.VString "("; March_eval.Eval.VString ")"] in
    Alcotest.(check string) "both defaults" "[42]" (vstr v0);
    Alcotest.(check string) "one override"  "(42]" (vstr v1);
    Alcotest.(check string) "both override" "(42)" (vstr v2)

  let test_default_arg_typed () =
    (* default with type annotation *)
    let env = eval_module {|mod Test do
      fn repeat(s : String, n : Int \\ 3) do
        let go = fn (i) -> if i <= 0 do "" else s ++ go(i - 1) end
        go(n)
      end
    end|} in
    let v = call_fn env "repeat" [March_eval.Eval.VString "ha"] in
    Alcotest.(check string) "typed default" "hahaha" (vstr v)
  ```

- [ ] **Step 7: Register tests**

  ```ocaml
  ("default_args", [
    Alcotest.test_case "basic default"  `Quick test_default_arg_basic;
    Alcotest.test_case "multi defaults" `Quick test_default_arg_multi;
    Alcotest.test_case "typed default"  `Quick test_default_arg_typed;
  ]);
  ```

- [ ] **Step 8: Run tests**

  Run: `/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -A3 "default_args"`
  Expected: All 3 default_args tests pass.

---

## Task 9: Parser — opaque type keyword

**Files:** Modify `lib/parser/parser.mly`

- [ ] **Step 1: Add opaque type_decl rules**

  Find the `type_decl:` production and add two new rules at the start (before the existing `TYPE` rules):

  ```mly
  (* opaque type: type name is public, constructors are private to module *)
  | OPAQUE; TYPE; name = upper_name; tparams = option(type_params); EQUALS;
    variants = separated_nonempty_list(PIPE, variant)
    { let tps = match tparams with Some ps -> ps | None -> [] in
      (* Mark all constructors as Private so they're not exported *)
      let private_variants = List.map (fun v -> { v with var_vis = Private }) variants in
      DType (Public, name, tps, TDVariant private_variants, mk_span ($loc)) }
  | OPAQUE; TYPE; name = upper_name; tparams = option(type_params); EQUALS;
    LBRACE; fields = separated_list(COMMA, field); RBRACE
    { let tps = match tparams with Some ps -> ps | None -> [] in
      (* Record opaque type: type public, but treat as opaque — fields private *)
      (* We reuse Private variants trick: mark as Private type but Public name *)
      (* Actually for records, just emit Public type — constructor hiding not applicable *)
      DType (Public, name, tps, TDRecord fields, mk_span ($loc)) }
  ```

  Note: For record-based opaque types, field access is not restricted by visibility in the current system. Only variant constructor hiding works. So for simplicity, record opaque types are just `DType (Public, ...)` — the opaque keyword is mainly useful for ADTs.

- [ ] **Step 2: Build**

  Run: `/Users/80197052/.opam/march/bin/dune build 2>&1 | head -20`
  Expected: Clean build.

- [ ] **Step 3: Write failing tests for opaque types**

  In `test/test_march.ml`, add:

  ```ocaml
  (* ── Opaque types ────────────────────────────────────────────────────── *)

  let test_opaque_type_name_accessible () =
    (* opaque type: type name is accessible outside module *)
    let ctx = typecheck {|mod Test do
      mod M do
        opaque type Handle = Handle(Int)
        fn make(n : Int) : Handle do Handle(n) end
      end
      fn main() do M.make(42) end
    end|} in
    Alcotest.(check bool) "opaque type name accessible" false (has_errors ctx)

  let test_opaque_type_ctors_hidden () =
    (* opaque type: constructors are NOT accessible outside the module *)
    let ctx = typecheck {|mod Test do
      mod M do
        opaque type Handle = Handle(Int)
        fn make(n : Int) : Handle do Handle(n) end
      end
      fn main() do Handle(42) end
    end|} in
    Alcotest.(check bool) "opaque type ctors hidden" true (has_errors ctx)

  let test_opaque_type_ctors_inside_ok () =
    (* opaque type: constructors ARE accessible INSIDE the defining module *)
    let ctx = typecheck {|mod Test do
      mod M do
        opaque type Handle = Handle(Int)
        fn make(n : Int) : Handle do Handle(n) end
        fn get(Handle(n)) : Int do n end
      end
    end|} in
    Alcotest.(check bool) "opaque ctors inside module ok" false (has_errors ctx)

  let test_opaque_type_eval () =
    (* opaque type works at runtime via its public API *)
    let env = eval_module {|mod Test do
      mod M do
        opaque type Counter = Counter(Int)
        fn new() : Counter do Counter(0) end
        fn inc(Counter(n)) : Counter do Counter(n + 1) end
        fn value(Counter(n)) : Int do n end
      end
      fn run() do
        let c = M.new()
        let c2 = M.inc(c)
        let c3 = M.inc(c2)
        M.value(c3)
      end
    end|} in
    let v = call_fn env "run" [] in
    Alcotest.(check int) "opaque type counter" 2 (vint v)
  ```

- [ ] **Step 4: Register tests**

  ```ocaml
  ("opaque_types", [
    Alcotest.test_case "type name accessible"     `Quick test_opaque_type_name_accessible;
    Alcotest.test_case "ctors hidden outside"     `Quick test_opaque_type_ctors_hidden;
    Alcotest.test_case "ctors inside ok"          `Quick test_opaque_type_ctors_inside_ok;
    Alcotest.test_case "eval via public API"      `Quick test_opaque_type_eval;
  ]);
  ```

- [ ] **Step 5: Run tests**

  Run: `/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -A3 "opaque_types"`
  Expected: All 4 opaque tests pass.

---

## Task 10: Full test suite + fix regressions

- [ ] **Step 1: Run full test suite**

  Run: `/Users/80197052/.opam/march/bin/dune runtest 2>&1 | tail -20`
  Expected: 0 failures beyond any pre-existing failures.

- [ ] **Step 2: Fix any regressions**

  If any existing tests fail, investigate and fix. Common causes:
  - `IN` as a new keyword breaking tests that use `in` as a variable (search for `"in"` in test source)
  - `DSLASH` conflicting with `\\` in string literals (should not — `\\` in strings is escape, `\\` at param position is new)
  - Parser conflicts from new rules (check Menhir warnings)

---

## Task 11: Update syntax_reference.md

**File:** Modify `syntax_reference.md`

- [ ] **Step 1: Add new sections before the Testing section**

  Add after the `## Pattern Matching` section:

  ````markdown
  ## List Comprehensions

  ```march
  [x * 2 for x in list]                    -- map over list
  [x * 2 for x in list, x > 3]            -- map with filter
  [to_string(x) for x in [1, 2, 3]]       -- transform
  [(a, b) for (a, b) in pairs, a > 0]     -- tuple pattern
  ```

  Desugars to `List.map` / `List.filter` chains.

  ---

  ## With Expressions

  Elixir-style monadic chaining for `Result`/`Option` pipelines:

  ```march
  with Ok(user) <- find_user(id),
       Ok(profile) <- load_profile(user),
       Ok(avatar) <- fetch_avatar(profile) do
    format_response(user, profile, avatar)
  else
    Err(e) -> handle_error(e)
  end
  ```

  Each `<-` binding matches the success case. If any binding fails to match, the `else` branches are tried. The `else` block is optional (omitting it means a non-matching value causes a match failure at runtime).

  ---

  ## Default Argument Values

  ```march
  fn greet(name, greeting \\ "Hello") do
    greeting ++ ", " ++ name ++ "!"
  end

  greet("World")          -- "Hello, World!"
  greet("World", "Hi")    -- "Hi, World!"
  ```

  Multiple defaults:
  ```march
  fn fmt(val, prefix \\ "[", suffix \\ "]") do
    prefix ++ to_string(val) ++ suffix
  end
  ```

  Defaults must be **trailing** parameters. They desugar to multiple function clauses: a function with N defaults generates N+1 clauses. Type annotations work: `fn f(x : Int \\ 0)`.

  ---

  ## Opaque Types

  ```march
  mod Counter do
    opaque type Counter = Counter(Int)

    fn new() : Counter do Counter(0) end
    fn inc(Counter(n)) : Counter do Counter(n + 1) end
    fn value(Counter(n)) : Int do n end
  end

  -- Outside the module:
  Counter.new()          -- OK: Counter type name is accessible
  Counter.inc(c)         -- OK: public functions work
  Counter(0)             -- ERROR: constructor hidden outside module
  ```

  The `opaque` keyword makes the type name **public** but its constructors **private** — callers can hold values of the type and pass them to the module's API, but cannot construct or deconstruct them directly. This enforces abstraction boundaries.

  Compare:
  - `type Foo = ...` — type and constructors all public
  - `ptype Foo = ...` — type and constructors all private
  - `opaque type Foo = ...` — type public, constructors private (new)
  ````

---

## Task 12: Update specs/todos.md and specs/progress.md

- [ ] **Step 1: Update specs/todos.md**

  Find the `## P1` or `## P2` section and add:
  ```markdown
  - ✅ **List comprehensions** — `[expr for pat in list]` and `[expr for pat in list, pred]` syntax, desugared to `List.map`/`List.filter` chains. 4 tests.
  - ✅ **`with` expressions** — Elixir-style monadic chaining `with Pat <- expr, ... do body else arms end`. Desugared to nested match in parser. 4 tests.
  - ✅ **Default argument values** — `fn f(x, y \\ default)` syntax. Desugar generates multi-arity clauses. 3 tests.
  - ✅ **`opaque type` keyword** — `opaque type Foo = ...` makes type name public, constructors private. Reuses existing ctor-visibility filtering. 4 tests.
  ```

- [ ] **Step 2: Update specs/progress.md**

  In the "Current State" section, increment the test count to match new total.

  In the feature list, add:
  ```
  - `[expr for pat in list]` / `[expr for pat in list, pred]` — list comprehensions
  - `with Pat <- expr, ... do body else arms end` — with expressions
  - `fn f(x, y \\ default)` — default argument values
  - `opaque type Foo = A | B(Int)` — opaque types with keyword
  ```

---

## Task 13: Commit and merge

- [ ] **Step 1: Stage files explicitly**

  ```bash
  git add lib/lexer/lexer.mll lib/parser/parser.mly lib/ast/ast.ml \
          lib/desugar/desugar.ml lib/format/format.ml lib/dump/dump.ml \
          lib/search/search.ml lib/tir/lower.ml \
          test/test_march.ml syntax_reference.md \
          specs/todos.md specs/progress.md
  ```

- [ ] **Step 2: Build and test one final time**

  Run: `/Users/80197052/.opam/march/bin/dune build && /Users/80197052/.opam/march/bin/dune runtest 2>&1 | tail -5`
  Expected: Clean build, 0 new failures.

- [ ] **Step 3: Commit**

  ```bash
  git commit -m "feat: add list comprehensions, with expressions, default args, opaque types"
  ```

- [ ] **Step 4: Merge to main**

  ```bash
  git checkout main
  git merge --no-ff claude/unruffled-cori -m "Merge branch 'claude/unruffled-cori' into main"
  ```
