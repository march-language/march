(** Property-based tests for the March compiler using QCheck2.

    Two families of tests:
    1. Source-string generators — generate valid March source code and run it
       through the full pipeline (parse → desugar → typecheck → eval → TIR passes).
    2. TIR AST generators — build [Tir.tir_module] values directly and exercise
       individual passes (lower, mono, defun, perceus) without going through the
       parser.

    The interpreter ([March_eval.Eval]) acts as the reference oracle: any
    algebraic property that holds over the semantics must hold in the evaluation
    results, and every TIR pass must be semantics-preserving (tested here as
    "does not crash + result is structurally well-formed"). *)

open QCheck2

(* ── Pipeline helpers ──────────────────────────────────────────────────── *)

module Ast    = March_ast.Ast
module Tir    = March_tir.Tir
module Errors = March_errors.Errors

(** Parse a March source string into an AST module.
    Raises [March_parser.Parser.Error] on syntax error. *)
let parse_src src =
  let lexbuf = Lexing.from_string src in
  March_parser.Parser.module_ March_lexer.Lexer.token lexbuf

(** Full pipeline through typecheck; returns [None] on parse error. *)
let pipeline_up_to_typecheck src =
  match (try Some (parse_src src) with _ -> None) with
  | None   -> None
  | Some m ->
    let m      = March_desugar.Desugar.desugar_module m in
    let errors, type_map = March_typecheck.Typecheck.check_module m in
    Some (m, errors, type_map)

(** Call the reference interpreter and return the value of [main()].
    Resets scheduler/actor state before each call. *)
let eval_main m =
  March_eval.Eval.reset_scheduler_state ();
  let env = March_eval.Eval.eval_module_env m in
  match List.assoc_opt "main" env with
  | None    -> None
  | Some fn -> Some (March_eval.Eval.apply fn [])

(* ── Source string generators ──────────────────────────────────────────── *)

(** Wrap an expression body in a minimal module with a [main] function. *)
let wrap_main body =
  "mod Main do\n  fn main() do\n    " ^ body ^ "\n  end\nend"

(** Integer literal in range [-100, 100]. *)
let gen_int_lit : string Gen.t =
  Gen.map string_of_int (Gen.int_range (-100) 100)

(** Positive integer literal (avoids divide-by-zero, negative-mod surprises). *)
let gen_pos_int_lit : string Gen.t =
  Gen.map string_of_int (Gen.int_range 1 100)

(** Int arithmetic expression with no free variables.
    Depth controls maximum nesting. *)
let gen_arith_expr : string Gen.t =
  Gen.fix (fun self depth ->
    if depth = 0 then
      gen_int_lit
    else
      Gen.oneof_weighted [
        4, gen_int_lit;
        2, Gen.map2 (fun a b -> "(" ^ a ^ " + " ^ b ^ ")") (self (depth-1)) (self (depth-1));
        2, Gen.map2 (fun a b -> "(" ^ a ^ " - " ^ b ^ ")") (self (depth-1)) (self (depth-1));
        1, Gen.map2 (fun a b -> "(" ^ a ^ " * " ^ b ^ ")") (self (depth-1)) (self (depth-1));
      ]
  ) 3

(** Boolean comparison expression (always well-typed: Int < Int → Bool). *)
let gen_bool_cmp : string Gen.t =
  Gen.map4
    (fun a op b _ -> a ^ " " ^ op ^ " " ^ b)
    gen_int_lit
    (Gen.oneof_list ["=="; "!="; "<"; ">"; "<="; ">="])
    gen_int_lit
    Gen.unit

(** if/then/else with integer branches, condition is a bool comparison. *)
let gen_if_int_expr : string Gen.t =
  Gen.map3
    (fun cond t f -> "if " ^ cond ^ " then " ^ t ^ " else " ^ f)
    gen_bool_cmp
    gen_arith_expr
    gen_arith_expr

(** Let-chain: two let bindings then an arithmetic combination. *)
let gen_let_chain : string Gen.t =
  Gen.map2
    (fun e1 e2 ->
       "let a = " ^ e1 ^ "\n    let b = " ^ e2 ^ "\n    a + b")
    gen_arith_expr
    gen_arith_expr

(** Module with just arithmetic in main. *)
let gen_arith_module : string Gen.t =
  Gen.map wrap_main gen_arith_expr

(** Module with an if/then/else expression in main. *)
let gen_if_module : string Gen.t =
  Gen.map wrap_main gen_if_int_expr

(** Module with let bindings in main. *)
let gen_let_module : string Gen.t =
  Gen.map wrap_main gen_let_chain

(** Module with a named helper function and a call to it. *)
let gen_fn_module : string Gen.t =
  Gen.map3
    (fun offset arg1 arg2 ->
       Printf.sprintf
         "mod Main do\n\
         \  fn add_offset(x) do\n\
         \    x + %s\n\
         \  end\n\
         \  fn main() do\n\
         \    add_offset(%s) + add_offset(%s)\n\
         \  end\n\
          end"
         offset arg1 arg2)
    gen_pos_int_lit
    gen_arith_expr
    gen_arith_expr

(** Module with pattern matching on a boolean. *)
let gen_match_bool_module : string Gen.t =
  Gen.map3
    (fun cond t f ->
       Printf.sprintf
         "mod Main do\n\
         \  fn main() do\n\
         \    let b = %s\n\
         \    match b with\n\
         \    | true -> %s\n\
         \    | false -> %s\n\
         \    end\n\
         \  end\n\
          end"
         cond t f)
    gen_bool_cmp
    gen_arith_expr
    gen_arith_expr

(** Any of the well-typed module generators. *)
let gen_well_typed_module : string Gen.t =
  Gen.oneof [
    gen_arith_module;
    gen_if_module;
    gen_let_module;
    gen_fn_module;
    gen_match_bool_module;
  ]

(* ── TIR AST generators ─────────────────────────────────────────────────── *)

(** Generate a [Tir.atom] for a literal integer. *)
let gen_tir_int_atom : Tir.atom Gen.t =
  Gen.map (fun n -> Tir.ALit (Ast.LitInt n)) (Gen.int_range (-50) 50)

(** Generate a [Tir.atom] for a literal bool. *)
let gen_tir_bool_atom : Tir.atom Gen.t =
  Gen.map (fun b -> Tir.ALit (Ast.LitBool b)) Gen.bool

(** Generate a TIR expression that is closed (no free variables) and has
    type Int.  Kept shallow to stay tractable. *)
let gen_tir_int_expr : Tir.expr Gen.t =
  Gen.fix (fun self depth ->
    if depth = 0 then
      Gen.map (fun a -> Tir.EAtom a) gen_tir_int_atom
    else
      Gen.oneof_weighted [
        3, Gen.map (fun a -> Tir.EAtom a) gen_tir_int_atom;
        (* let v : Int = <literal> in <sub-expr> *)
        2, Gen.map2
             (fun n sub ->
                let v = { Tir.v_name = Printf.sprintf "x%d" depth;
                          v_ty = Tir.TInt; v_lin = Tir.Unr } in
                Tir.ELet (v, Tir.EAtom (Tir.ALit (Ast.LitInt n)), sub))
             (Gen.int_range (-50) 50)
             (self (depth-1));
        (* tuple of two ints *)
        1, Gen.map2
             (fun a b -> Tir.ETuple [a; b])
             gen_tir_int_atom
             gen_tir_int_atom;
        (* case b of { true -> n1 | false -> n2 } — exercises perceus branch *)
        1, Gen.map3
             (fun b n1 n2 ->
                let bv = { Tir.v_name = Printf.sprintf "b%d" depth;
                           Tir.v_ty = Tir.TBool; Tir.v_lin = Tir.Unr } in
                let br_true  = { Tir.br_tag = "true";  Tir.br_vars = [];
                                 Tir.br_body = Tir.EAtom (Tir.ALit (Ast.LitInt n1)) } in
                let br_false = { Tir.br_tag = "false"; Tir.br_vars = [];
                                 Tir.br_body = Tir.EAtom (Tir.ALit (Ast.LitInt n2)) } in
                Tir.ELet (bv, Tir.EAtom b,
                  Tir.ECase (Tir.AVar bv, [br_true; br_false], None)))
             gen_tir_bool_atom
             (Gen.int_range (-50) 50)
             (Gen.int_range (-50) 50);
      ]
  ) 3

(** Generate a minimal TIR module with a single [main] function whose body
    is a closed integer expression. *)
let gen_tir_module : Tir.tir_module Gen.t =
  Gen.map
    (fun body ->
       let fn : Tir.fn_def = {
         fn_name   = "main";
         fn_params = [];
         fn_ret_ty = Tir.TInt;
         fn_body   = body;
       } in
       { Tir.tm_name    = "Main";
         Tir.tm_fns     = [fn];
         Tir.tm_types   = [];
         Tir.tm_externs = [] })
    gen_tir_int_expr

(* ── Helper: extract VInt from a value ─────────────────────────────────── *)

let value_to_int = function
  | March_eval.Eval.VInt n -> Some n
  | _                      -> None

(* ── End-to-end properties (source string generators) ─────────────────── *)

(** 1. Parse + desugar should never raise unexpected exceptions on any of
       our well-typed source programs (parse errors are ok, panics are not). *)
let prop_parse_no_unexpected_exception =
  Test.make ~name:"parse: no unexpected exceptions on generated programs"
    ~count:500
    gen_well_typed_module
    (fun src ->
       match parse_src src with
       | _  -> true
       | exception March_parser.Parser.Error -> true
       | exception _ -> false)

(** 2. Typecheck should never raise an exception (only record diagnostics). *)
let prop_typecheck_no_crash =
  Test.make ~name:"typecheck: no crash on generated well-formed programs"
    ~count:500
    gen_well_typed_module
    (fun src ->
       try
         ignore (pipeline_up_to_typecheck src);
         true
       with _ -> false)

(** 3. Well-typed programs should typecheck without errors. *)
let prop_generated_programs_are_well_typed =
  Test.make ~name:"generated programs: no type errors"
    ~count:500
    gen_well_typed_module
    (fun src ->
       match pipeline_up_to_typecheck src with
       | None -> true  (* parse error counts as skip *)
       | Some (_, errors, _) -> not (Errors.has_errors errors))

(** 4. Well-typed programs should not crash the interpreter. *)
let prop_type_sound_eval_no_crash =
  Test.make ~name:"type soundness: well-typed → eval does not crash"
    ~count:500
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, _) ->
           ignore (eval_main m);
           true
       with _ -> false)

(** 5. Well-typed programs should survive the lowering pass. *)
let prop_lower_no_crash =
  Test.make ~name:"lowering: no crash on well-typed programs"
    ~count:300
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, type_map) ->
           ignore (March_tir.Lower.lower_module ~type_map m);
           true
       with _ -> false)

(** 6. Monomorphization should not crash on lowered programs. *)
let prop_mono_no_crash =
  Test.make ~name:"mono: no crash on lowered programs"
    ~count:300
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, type_map) ->
           let tir = March_tir.Lower.lower_module ~type_map m in
           ignore (March_tir.Mono.monomorphize tir);
           true
       with _ -> false)

(** 7. Defunctionalization should not crash on monomorphized programs. *)
let prop_defun_no_crash =
  Test.make ~name:"defun: no crash on mono programs"
    ~count:300
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, type_map) ->
           let tir  = March_tir.Lower.lower_module ~type_map m in
           let mono = March_tir.Mono.monomorphize tir in
           ignore (March_tir.Defun.defunctionalize mono);
           true
       with _ -> false)

(** 8. Perceus RC insertion should not crash on the full TIR pipeline. *)
let prop_perceus_no_crash =
  Test.make ~name:"perceus: no crash on defun programs"
    ~count:300
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, type_map) ->
           let tir    = March_tir.Lower.lower_module ~type_map m in
           let mono   = March_tir.Mono.monomorphize tir in
           let defun  = March_tir.Defun.defunctionalize mono in
           ignore (March_tir.Perceus.perceus defun);
           true
       with _ -> false)

(* ── Algebraic oracle properties ─────────────────────────────────────────
   The interpreter is the reference oracle.  These properties check that
   the evaluator respects basic arithmetic laws.  If any fail, there's a
   bug in the interpreter semantics. *)

(** Helper: evaluate a program of the form "mod Main do fn main() do <e> end end"
    and return the integer result, or None on any failure. *)
let eval_int_src body =
  try
    match pipeline_up_to_typecheck (wrap_main body) with
    | None -> None
    | Some (_, errors, _) when Errors.has_errors errors -> None
    | Some (m, _, _) ->
      (match eval_main m with
       | Some v -> value_to_int v
       | None   -> None)
  with _ -> None

(** 9. Addition is commutative: eval(a + b) = eval(b + a). *)
let prop_add_commutative =
  Test.make ~name:"oracle: addition is commutative"
    ~count:300
    Gen.(pair (int_range (-100) 100) (int_range (-100) 100))
    (fun (a, b) ->
       let lhs = eval_int_src (Printf.sprintf "(%d + %d)" a b) in
       let rhs = eval_int_src (Printf.sprintf "(%d + %d)" b a) in
       match lhs, rhs with
       | Some l, Some r -> l = r
       | _ -> true (* skip if eval failed *))

(** 10. Adding zero is identity: eval(a + 0) = eval(a). *)
let prop_add_zero_identity =
  Test.make ~name:"oracle: a + 0 = a"
    ~count:300
    (Gen.int_range (-100) 100)
    (fun a ->
       let lhs = eval_int_src (Printf.sprintf "(%d + 0)" a) in
       let rhs = eval_int_src (string_of_int a) in
       match lhs, rhs with
       | Some l, Some r -> l = r
       | _ -> true)

(** 11. Multiplying by one is identity: eval(a * 1) = eval(a). *)
let prop_mul_one_identity =
  Test.make ~name:"oracle: a * 1 = a"
    ~count:300
    (Gen.int_range (-100) 100)
    (fun a ->
       let lhs = eval_int_src (Printf.sprintf "(%d * 1)" a) in
       let rhs = eval_int_src (string_of_int a) in
       match lhs, rhs with
       | Some l, Some r -> l = r
       | _ -> true)

(** 12. Subtraction of self is zero: eval(a - a) = 0. *)
let prop_sub_self_zero =
  Test.make ~name:"oracle: a - a = 0"
    ~count:300
    (Gen.int_range (-100) 100)
    (fun a ->
       match eval_int_src (Printf.sprintf "(%d - %d)" a a) with
       | Some n -> n = 0
       | None   -> true)

(** 13. If-then-else: when condition is false, else branch is taken. *)
let prop_if_else_branch =
  Test.make ~name:"oracle: if false then t else f = f"
    ~count:300
    Gen.(pair (int_range (-100) 100) (int_range (-100) 100))
    (fun (t, f) ->
       let body = Printf.sprintf "if (1 == 2) then %d else %d" t f in
       match eval_int_src body with
       | Some n -> n = f
       | None   -> true)

(** 14. If-then-else: when condition is true, then branch is taken. *)
let prop_if_then_branch =
  Test.make ~name:"oracle: if true then t else f = t"
    ~count:300
    Gen.(pair (int_range (-100) 100) (int_range (-100) 100))
    (fun (t, f) ->
       let body = Printf.sprintf "if (1 == 1) then %d else %d" t f in
       match eval_int_src body with
       | Some n -> n = t
       | None   -> true)

(* ── TIR-level properties (AST generators) ─────────────────────────────── *)

(** 15. Perceus should not crash on any generated TIR module. *)
let prop_perceus_tir_no_crash =
  Test.make ~name:"perceus (TIR gen): no crash on generated TIR modules"
    ~count:500
    gen_tir_module
    (fun m ->
       try ignore (March_tir.Perceus.perceus m); true
       with _ -> false)

(** 16. Monomorphize should not crash on generated TIR modules. *)
let prop_mono_tir_no_crash =
  Test.make ~name:"mono (TIR gen): no crash on generated TIR modules"
    ~count:500
    gen_tir_module
    (fun m ->
       try ignore (March_tir.Mono.monomorphize m); true
       with _ -> false)

(** 17. Defunctionalize should not crash on generated TIR modules. *)
let prop_defun_tir_no_crash =
  Test.make ~name:"defun (TIR gen): no crash on generated TIR modules"
    ~count:500
    gen_tir_module
    (fun m ->
       try ignore (March_tir.Defun.defunctionalize m); true
       with _ -> false)

(** 18. Perceus output has no more functions than input (no fn duplication). *)
let prop_perceus_preserves_fn_count =
  Test.make ~name:"perceus: does not duplicate function definitions"
    ~count:500
    gen_tir_module
    (fun m ->
       try
         let out = March_tir.Perceus.perceus m in
         List.length out.Tir.tm_fns = List.length m.Tir.tm_fns
       with _ -> true (* crash covered by prop_perceus_tir_no_crash *))

(** 19. Mono output preserves the set of function names that are entry points. *)
let prop_mono_preserves_main_fn =
  Test.make ~name:"mono: main function is still present after monomorphization"
    ~count:500
    gen_tir_module
    (fun m ->
       try
         let out = March_tir.Mono.monomorphize m in
         (* mono may specialize or copy fns; main should survive *)
         List.exists (fun (fn : Tir.fn_def) -> fn.fn_name = "main") out.Tir.tm_fns
       with _ -> true)

(** 20. Defun output preserves the total number of definitions (may add
        closure-dispatch helpers, so output count >= input count). *)
let prop_defun_no_fn_loss =
  Test.make ~name:"defun: does not lose function definitions"
    ~count:500
    gen_tir_module
    (fun m ->
       try
         let out = March_tir.Defun.defunctionalize m in
         List.length out.Tir.tm_fns >= List.length m.Tir.tm_fns
       with _ -> true)

(* ── Test suite registration ────────────────────────────────────────────── *)

let () =
  let open Alcotest in
  run "March property tests" [
    "parse+typecheck", List.map QCheck_alcotest.to_alcotest [
      prop_parse_no_unexpected_exception;
      prop_typecheck_no_crash;
      prop_generated_programs_are_well_typed;
    ];
    "type soundness + eval", List.map QCheck_alcotest.to_alcotest [
      prop_type_sound_eval_no_crash;
    ];
    "tir pipeline (source)", List.map QCheck_alcotest.to_alcotest [
      prop_lower_no_crash;
      prop_mono_no_crash;
      prop_defun_no_crash;
      prop_perceus_no_crash;
    ];
    "algebraic oracle", List.map QCheck_alcotest.to_alcotest [
      prop_add_commutative;
      prop_add_zero_identity;
      prop_mul_one_identity;
      prop_sub_self_zero;
      prop_if_then_branch;
      prop_if_else_branch;
    ];
    "tir passes (ast gen)", List.map QCheck_alcotest.to_alcotest [
      prop_perceus_tir_no_crash;
      prop_mono_tir_no_crash;
      prop_defun_tir_no_crash;
      prop_perceus_preserves_fn_count;
      prop_mono_preserves_main_fn;
      prop_defun_no_fn_loss;
    ];
  ]
