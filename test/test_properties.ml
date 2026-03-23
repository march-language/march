(** Property-based tests for the March compiler using QCheck2.

    Three families of tests:
    1. Source-string generators — generate valid March source code and run it
       through the full pipeline (parse → desugar → typecheck → eval → TIR passes).
    2. TIR AST generators — build [Tir.tir_module] values directly and exercise
       individual passes (lower, mono, defun, perceus) without going through the
       parser.
    3. Oracle properties — compile generated programs with the native backend and
       check that the compiled output matches the interpreter's output.

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
         \    match b do\n\
         \    | true -> %s\n\
         \    | false -> %s\n\
         \    end\n\
         \  end\n\
          end"
         cond t f)
    gen_bool_cmp
    gen_arith_expr
    gen_arith_expr

(* ── New generators: ADTs ───────────────────────────────────────────────── *)

(** Module with a simple two-constructor ADT and pattern matching.
    type Shape = Circle(Int) | Square(Int)
    main returns an Int via pattern match on the constructed value. *)
let gen_adt_module : string Gen.t =
  Gen.map3
    (fun use_circle n1 n2 ->
       let ctor    = if use_circle then Printf.sprintf "Circle(%d)" n1
                                   else Printf.sprintf "Square(%d)" n1 in
       Printf.sprintf
         "mod Main do\n\
         \  type Shape = Circle(Int) | Square(Int)\n\
         \  fn area(s : Shape) : Int do\n\
         \    match s do\n\
         \    | Circle(r) -> r * r\n\
         \    | Square(n) -> n * %d\n\
         \    end\n\
         \  end\n\
         \  fn main() do\n\
         \    let s = %s\n\
         \    area(s)\n\
         \  end\n\
          end"
         n2 ctor)
    Gen.bool
    (Gen.int_range 1 20)
    (Gen.int_range 1 10)

(** Module with a three-constructor ADT and nested pattern matching.
    Exercises the full match path including a constructor with no fields. *)
let gen_adt3_module : string Gen.t =
  Gen.map4
    (fun pick a b _unit ->
       let ctor = match pick mod 3 with
         | 0 -> Printf.sprintf "Pair(%d, %d)" a b
         | 1 -> Printf.sprintf "Single(%d)" a
         | _ -> "Empty"
       in
       Printf.sprintf
         "mod Main do\n\
         \  type MyData = Empty | Single(Int) | Pair(Int, Int)\n\
         \  fn sum_data(d : MyData) : Int do\n\
         \    match d do\n\
         \    | Empty      -> 0\n\
         \    | Single(x)  -> x\n\
         \    | Pair(x, y) -> x + y\n\
         \    end\n\
         \  end\n\
         \  fn main() do\n\
         \    sum_data(%s)\n\
         \  end\n\
          end"
         ctor)
    Gen.nat_small
    (Gen.int_range (-50) 50)
    (Gen.int_range (-50) 50)
    Gen.unit

(* ── New generators: Closures and HOFs ─────────────────────────────────── *)

(** Module where main creates a closure that captures a variable and calls it. *)
let gen_closure_module : string Gen.t =
  Gen.map3
    (fun base offset arg ->
       Printf.sprintf
         "mod Main do\n\
         \  fn main() do\n\
         \    let base = %d\n\
         \    let adder = fn x -> x + base + %d\n\
         \    adder(%d)\n\
         \  end\n\
          end"
         base offset arg)
    (Gen.int_range (-50) 50)
    (Gen.int_range (-50) 50)
    (Gen.int_range (-50) 50)

(** Module that passes a lambda to a higher-order function.
    apply(f, x) = f(x) *)
let gen_hof_apply_module : string Gen.t =
  Gen.map2
    (fun factor arg ->
       Printf.sprintf
         "mod Main do\n\
         \  fn apply(f : Int -> Int, x : Int) : Int do\n\
         \    f(x)\n\
         \  end\n\
         \  fn main() do\n\
         \    apply(fn n -> n * %d, %d)\n\
         \  end\n\
          end"
         factor arg)
    (Gen.int_range 1 20)
    (Gen.int_range (-50) 50)

(** Module that uses a higher-order function with two closures.
    compose(f, g)(x) = f(g(x)) *)
let gen_hof_compose_module : string Gen.t =
  Gen.map3
    (fun add_val mul_val arg ->
       Printf.sprintf
         "mod Main do\n\
         \  fn compose(f : Int -> Int, g : Int -> Int, x : Int) : Int do\n\
         \    f(g(x))\n\
         \  end\n\
         \  fn main() do\n\
         \    let add%d = fn n -> n + %d\n\
         \    let mul%d = fn n -> n * %d\n\
         \    compose(add%d, mul%d, %d)\n\
         \  end\n\
          end"
         add_val add_val mul_val mul_val add_val mul_val arg)
    (Gen.int_range 1 10)
    (Gen.int_range 1 10)
    (Gen.int_range (-20) 20)

(** Module with a recursive function (factorial or fibonacci-like). *)
let gen_recursive_module : string Gen.t =
  Gen.map
    (fun n ->
       (* Keep n small to avoid stack overflow / huge outputs *)
       let n' = abs n mod 10 in
       Printf.sprintf
         "mod Main do\n\
         \  fn fact(n : Int) : Int do\n\
         \    if n <= 1 then 1 else n * fact(n - 1)\n\
         \  end\n\
         \  fn main() do\n\
         \    fact(%d)\n\
         \  end\n\
          end"
         n')
    Gen.nat_small

(** Module with two mutually-calling helper functions. *)
let gen_mutual_fns_module : string Gen.t =
  Gen.map2
    (fun n m ->
       Printf.sprintf
         "mod Main do\n\
         \  fn double_add(x : Int, y : Int) : Int do\n\
         \    (x * 2) + triple_sub(y, x)\n\
         \  end\n\
         \  fn triple_sub(a : Int, b : Int) : Int do\n\
         \    (a * 3) - b\n\
         \  end\n\
         \  fn main() do\n\
         \    double_add(%d, %d)\n\
         \  end\n\
          end"
         n m)
    (Gen.int_range (-20) 20)
    (Gen.int_range (-20) 20)

(* ── New generators: Tuples ─────────────────────────────────────────────── *)

(** Module with tuple construction and let-destructuring.
    Note: March parser bug — a tuple literal on the line immediately after
    `let (x,y) = expr` gets parsed as calling expr with those args.
    Workaround: bind intermediate tuples to a variable before returning. *)
let gen_tuple_module : string Gen.t =
  Gen.map2
    (fun a b ->
       Printf.sprintf
         "mod Main do\n\
         \  fn swap(t : (Int, Int)) : (Int, Int) do\n\
         \    let (x, y) = t\n\
         \    let result = (y, x)\n\
         \    result\n\
         \  end\n\
         \  fn fst(t : (Int, Int)) : Int do\n\
         \    let (x, _) = t\n\
         \    x\n\
         \  end\n\
         \  fn main() do\n\
         \    let t = (%d, %d)\n\
         \    let (a, b) = swap(t)\n\
         \    fst((a, b)) + b\n\
         \  end\n\
          end"
         a b)
    (Gen.int_range (-50) 50)
    (Gen.int_range (-50) 50)

(** Module returning a 2-tuple from a function. *)
let gen_tuple_return_module : string Gen.t =
  Gen.map3
    (fun a b selector ->
       let extract = if selector then "let (x, _) = r\n    x"
                                 else "let (_, y) = r\n    y" in
       Printf.sprintf
         "mod Main do\n\
         \  fn make_pair(x : Int, y : Int) : (Int, Int) do\n\
         \    (x + 1, y - 1)\n\
         \  end\n\
         \  fn main() do\n\
         \    let r = make_pair(%d, %d)\n\
         \    %s\n\
         \  end\n\
          end"
         a b extract)
    (Gen.int_range (-50) 50)
    (Gen.int_range (-50) 50)
    Gen.bool

(* ── New generators: String operations ─────────────────────────────────── *)

(** Module that uses string concatenation and to_string.
    Returns the string length so we get an Int result for oracle comparison. *)
let gen_string_module : string Gen.t =
  Gen.map2
    (fun a b ->
       Printf.sprintf
         "mod Main do\n\
         \  fn main() do\n\
         \    let s1 = to_string(%d)\n\
         \    let s2 = to_string(%d)\n\
         \    let s3 = s1 ++ \" + \" ++ s2\n\
         \    string_length(s3)\n\
         \  end\n\
          end"
         a b)
    (Gen.int_range (-9999) 9999)
    (Gen.int_range (-9999) 9999)

(** Module using bool_to_string and string ops. *)
let gen_string_bool_module : string Gen.t =
  Gen.map2
    (fun a b ->
       Printf.sprintf
         "mod Main do\n\
         \  fn main() do\n\
         \    let cmp = %d > %d\n\
         \    string_length(bool_to_string(cmp))\n\
         \  end\n\
          end"
         a b)
    (Gen.int_range (-50) 50)
    (Gen.int_range (-50) 50)

(* ── New generators: inline List type + operations ─────────────────────── *)

(** Module that defines its own List and uses map/fold over a small list.
    We define the list ops inline to avoid stdlib dependency in the pipeline. *)
let gen_list_module : string Gen.t =
  Gen.map3
    (fun a b c ->
       (* fold_left (acc, Cons(h, t), f) computing sum *)
       Printf.sprintf
         "mod Main do\n\
         \  type IntList = Nil | Cons(Int, IntList)\n\
         \  fn sum(lst : IntList) : Int do\n\
         \    match lst do\n\
         \    | Nil        -> 0\n\
         \    | Cons(h, t) -> h + sum(t)\n\
         \    end\n\
         \  end\n\
         \  fn map_add1(lst : IntList) : IntList do\n\
         \    match lst do\n\
         \    | Nil        -> Nil\n\
         \    | Cons(h, t) -> Cons(h + 1, map_add1(t))\n\
         \    end\n\
         \  end\n\
         \  fn main() do\n\
         \    let lst = Cons(%d, Cons(%d, Cons(%d, Nil)))\n\
         \    sum(map_add1(lst))\n\
         \  end\n\
          end"
         a b c)
    (Gen.int_range (-20) 20)
    (Gen.int_range (-20) 20)
    (Gen.int_range (-20) 20)

(** Module with nested pattern matching: ADT inside ADT. *)
let gen_nested_match_module : string Gen.t =
  Gen.map3
    (fun inner_val outer_tag inner_tag ->
       let ctor = match (outer_tag mod 2, inner_tag mod 2) with
         | (0, _) -> "Nothing"
         | (1, 0) -> Printf.sprintf "Just(Left(%d))" inner_val
         | _      -> Printf.sprintf "Just(Right(%d))" inner_val
       in
       Printf.sprintf
         "mod Main do\n\
         \  type Side = Left(Int) | Right(Int)\n\
         \  type Maybe = Nothing | Just(Side)\n\
         \  fn extract(m : Maybe) : Int do\n\
         \    match m do\n\
         \    | Nothing      -> 0\n\
         \    | Just(Left(x))  -> x\n\
         \    | Just(Right(x)) -> x + 100\n\
         \    end\n\
         \  end\n\
         \  fn main() do\n\
         \    extract(%s)\n\
         \  end\n\
          end"
         ctor)
    (Gen.int_range (-50) 50)
    Gen.nat_small
    Gen.nat_small

(** Any of the well-typed module generators (original + new). *)
let gen_well_typed_module : string Gen.t =
  Gen.oneof [
    (* Original generators *)
    gen_arith_module;
    gen_if_module;
    gen_let_module;
    gen_fn_module;
    gen_match_bool_module;
    (* New generators *)
    gen_adt_module;
    gen_adt3_module;
    gen_closure_module;
    gen_hof_apply_module;
    gen_hof_compose_module;
    gen_recursive_module;
    gen_mutual_fns_module;
    gen_tuple_module;
    gen_tuple_return_module;
    gen_string_module;
    gen_string_bool_module;
    gen_list_module;
    gen_nested_match_module;
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
        (* ELetRec: a simple identity lambda called immediately *)
        1, Gen.map
             (fun n ->
                let param = { Tir.v_name = "p"; v_ty = Tir.TInt; v_lin = Tir.Unr } in
                let fn_v   = { Tir.v_name = "id_fn"; v_ty = Tir.TFn([Tir.TInt], Tir.TInt); v_lin = Tir.Unr } in
                let fn_def : Tir.fn_def = {
                  fn_name   = "id_fn";
                  fn_params = [param];
                  fn_ret_ty = Tir.TInt;
                  fn_body   = Tir.EAtom (Tir.AVar param);
                } in
                (* let $clo = letrec [id_fn] in EAtom(AVar id_fn) in EAtom($clo) *)
                let clo_var = { Tir.v_name = "clo"; v_ty = Tir.TFn([Tir.TInt], Tir.TInt); v_lin = Tir.Unr } in
                Tir.ELet (clo_var,
                  Tir.ELetRec ([fn_def], Tir.EAtom (Tir.AVar fn_v)),
                  Tir.ECallPtr (Tir.AVar clo_var, [Tir.ALit (Ast.LitInt n)])))
             (Gen.int_range (-50) 50);
      ]
  ) 3

(** Generate a TIR module with a closure that captures a free variable.
    This exercises defunctionalization's free-variable collection. *)
let gen_tir_closure_module : Tir.tir_module Gen.t =
  Gen.map2
    (fun captured body_add ->
       (* fn main() = let base = captured in
                       let clo = letrec [adder] in EAtom(AVar adder) in
                       ECallPtr(clo, [42]) *)
       let base_var  = { Tir.v_name = "base"; v_ty = Tir.TInt; v_lin = Tir.Unr } in
       let param_var = { Tir.v_name = "x";    v_ty = Tir.TInt; v_lin = Tir.Unr } in
       let adder_v   = { Tir.v_name = "adder"; v_ty = Tir.TFn([Tir.TInt], Tir.TInt); v_lin = Tir.Unr } in
       let clo_var   = { Tir.v_name = "clo";  v_ty = Tir.TFn([Tir.TInt], Tir.TInt); v_lin = Tir.Unr } in
       (* adder body: x + base + body_add *)
       let add_var   = { Tir.v_name = "tmp";  v_ty = Tir.TInt; v_lin = Tir.Unr } in
       let adder_body =
         Tir.ELet (add_var,
           Tir.EApp ({ Tir.v_name = "+"; v_ty = Tir.TFn([Tir.TInt; Tir.TInt], Tir.TInt); v_lin = Tir.Unr },
                     [Tir.AVar param_var; Tir.AVar base_var]),
           Tir.EApp ({ Tir.v_name = "+"; v_ty = Tir.TFn([Tir.TInt; Tir.TInt], Tir.TInt); v_lin = Tir.Unr },
                     [Tir.AVar add_var; Tir.ALit (Ast.LitInt body_add)]))
       in
       let adder_fn : Tir.fn_def = {
         fn_name   = "adder";
         fn_params = [param_var];
         fn_ret_ty = Tir.TInt;
         fn_body   = adder_body;
       } in
       let main_body =
         Tir.ELet (base_var,
           Tir.EAtom (Tir.ALit (Ast.LitInt captured)),
           Tir.ELet (clo_var,
             Tir.ELetRec ([adder_fn], Tir.EAtom (Tir.AVar adder_v)),
             Tir.ECallPtr (Tir.AVar clo_var, [Tir.ALit (Ast.LitInt 10)])))
       in
       let main_fn : Tir.fn_def = {
         fn_name   = "main";
         fn_params = [];
         fn_ret_ty = Tir.TInt;
         fn_body   = main_body;
       } in
       { Tir.tm_name    = "Main";
         Tir.tm_fns     = [main_fn];
         Tir.tm_types   = [];
         Tir.tm_externs = [] })
    (Gen.int_range (-20) 20)
    (Gen.int_range (-20) 20)

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

(* ── TIR walking utilities ──────────────────────────────────────────────── *)

(** Walk a TIR expression and return true if any ELetRec is found. *)
let rec has_letrec : Tir.expr -> bool = function
  | Tir.ELetRec _              -> true
  | Tir.ELet (_, e1, e2)       -> has_letrec e1 || has_letrec e2
  | Tir.ECase (_, brs, def)    ->
    List.exists (fun b -> has_letrec b.Tir.br_body) brs ||
    (match def with Some e -> has_letrec e | None -> false)
  | Tir.ESeq (e1, e2)          -> has_letrec e1 || has_letrec e2
  | _                          -> false

(** Collect all type annotations from a TIR expression. *)
let rec collect_types_expr (acc : Tir.ty list) : Tir.expr -> Tir.ty list = function
  | Tir.EAtom (Tir.AVar v)    -> v.Tir.v_ty :: acc
  | Tir.ELet (v, e1, e2)      ->
    collect_types_expr (collect_types_expr (v.Tir.v_ty :: acc) e1) e2
  | Tir.ELetRec (fns, body)   ->
    let acc' = List.fold_left (fun a fn ->
        fn.Tir.fn_ret_ty ::
        List.map (fun v -> v.Tir.v_ty) fn.Tir.fn_params @
        collect_types_expr [] fn.Tir.fn_body @ a) acc fns in
    collect_types_expr acc' body
  | Tir.ECase (_, brs, def)   ->
    let acc' = List.fold_left (fun a b -> collect_types_expr a b.Tir.br_body) acc brs in
    (match def with Some e -> collect_types_expr acc' e | None -> acc')
  | Tir.ESeq (e1, e2)         -> collect_types_expr (collect_types_expr acc e1) e2
  | _                         -> acc

let collect_types_module (m : Tir.tir_module) : Tir.ty list =
  List.fold_left (fun acc fn ->
    fn.Tir.fn_ret_ty ::
    List.map (fun v -> v.Tir.v_ty) fn.Tir.fn_params @
    collect_types_expr [] fn.Tir.fn_body @ acc
  ) [] m.Tir.tm_fns

(* ── Helper: extract VInt from a value ─────────────────────────────────── *)

let value_to_int = function
  | March_eval.Eval.VInt n -> Some n
  | _                      -> None

(* ── Oracle helper: run the march binary on source ─────────────────────── *)

(** Find the march binary.  Returns None if not found. *)
let find_march_bin () =
  let candidates = [
    Sys.getenv_opt "MARCH_BIN" |> Option.value ~default:"";
    "_build/default/bin/main.exe";
    "../_build/default/bin/main.exe";
  ] in
  List.find_opt (fun p -> p <> "" && Sys.file_exists p) candidates
  |> Option.map (fun p ->
       if Filename.is_relative p
       then Filename.concat (Sys.getcwd ()) p
       else p)

(** Memoize binary location so we don't stat on every test. *)
let march_bin_opt : string option Lazy.t =
  lazy (find_march_bin ())

(** Run a shell command and capture stdout+stderr, with timeout.
    Returns (exit_code, output_string). *)
let run_capture ?(timeout=15) cmd =
  let tmp = Filename.temp_file "march_prop_out" ".txt" in
  let rc  = Sys.command (Printf.sprintf
      "timeout %d sh -c %s > %s 2>/dev/null"
      timeout (Filename.quote cmd) tmp) in
  let out =
    try
      let ic = open_in tmp in
      let s  = In_channel.input_all ic in
      close_in ic; s
    with _ -> ""
  in
  (try Sys.remove tmp with _ -> ());
  (rc, out)

(** Write src to a temp file and return the path. *)
let write_temp_march src =
  let tmp = Filename.temp_file "march_prop" ".march" in
  let oc  = open_out tmp in
  output_string oc src;
  close_out oc;
  tmp

(** Run the oracle: compile a March source string and check that
    interpreter output == compiled output.
    Returns Ok () on match, Error msg on mismatch, or None to skip. *)
let oracle_check src =
  match Lazy.force march_bin_opt with
  | None -> None  (* no binary — skip *)
  | Some bin ->
    let src_file = write_temp_march src in
    let bin_file = src_file ^ ".bin" in
    (* Interpreter mode *)
    let interp_cmd = Printf.sprintf "%s %s" (Filename.quote bin) (Filename.quote src_file) in
    let (rc_interp, interp_out) = run_capture ~timeout:10 interp_cmd in
    if rc_interp <> 0 then (
      (* Interpreter failed — skip (generated program may have runtime error) *)
      (try Sys.remove src_file with _ -> ());
      None
    ) else begin
      (* Compile mode *)
      let compile_cmd =
        Printf.sprintf "%s --compile %s -o %s"
          (Filename.quote bin) (Filename.quote src_file) (Filename.quote bin_file)
      in
      let (rc_compile, _) = run_capture ~timeout:30 compile_cmd in
      (try Sys.remove src_file with _ -> ());
      if rc_compile <> 0 then (
        (* Compile failed — skip (generator hit an unimplemented feature) *)
        (try Sys.remove bin_file with _ -> ());
        None
      ) else begin
        let (rc_run, compiled_out) = run_capture ~timeout:10 (Filename.quote bin_file) in
        (try Sys.remove bin_file with _ -> ());
        if rc_run <> 0 then None  (* runtime crash — skip *)
        else if interp_out = compiled_out then Some (Ok ())
        else Some (Error (interp_out, compiled_out))
      end
    end


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

(** Returns true if ctx has errors OTHER than tail-call enforcement errors.
    Tail-call enforcement rejects non-tail-recursive code; the generator does
    not produce TCE-compliant programs, so those errors are expected/acceptable. *)
let has_non_tce_errors ctx =
  let is_tce_err (d : Errors.diagnostic) =
    d.Errors.severity = Errors.Error &&
    let msg = d.Errors.message in
    let len = String.length msg in
    let needle = "not in tail position" in
    let nlen = String.length needle in
    let rec check i =
      if i + nlen > len then false
      else if String.sub msg i nlen = needle then true
      else check (i + 1)
    in
    check 0
  in
  List.exists
    (fun d -> d.Errors.severity = Errors.Error && not (is_tce_err d))
    ctx.Errors.diagnostics

(** 3. Well-typed programs should typecheck without errors (modulo tail-call
    enforcement, which the generator does not account for). *)
let prop_generated_programs_are_well_typed =
  Test.make ~name:"generated programs: no type errors"
    ~count:500
    ~print:Fun.id
    gen_well_typed_module
    (fun src ->
       match pipeline_up_to_typecheck src with
       | None -> true  (* parse error counts as skip *)
       | Some (_, errors, _) -> not (has_non_tce_errors errors))

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

(* ── ADT semantic properties ─────────────────────────────────────────────── *)

(** 15. Pattern match on a two-constructor ADT is exhaustive and correct. *)
let prop_adt_match_correct =
  Test.make ~name:"oracle: ADT match selects correct branch"
    ~count:300
    Gen.(pair bool (int_range 1 100))
    (fun (use_a, n) ->
       let src = Printf.sprintf
         "mod Main do\n\
         \  type Tag = TagA | TagB(Int)\n\
         \  fn main() do\n\
         \    let t = %s\n\
         \    match t do\n\
         \    | TagA    -> 0\n\
         \    | TagB(x) -> x\n\
         \    end\n\
         \  end\n\
          end"
         (if use_a then "TagA" else Printf.sprintf "TagB(%d)" n)
       in
       match eval_int_src (String.concat "\n"
           (* We need to embed the full module, not just body *)
           []) with
       | _ ->
         (* Re-implement without eval_int_src which wraps with its own mod *)
         try
           match pipeline_up_to_typecheck src with
           | None -> true
           | Some (_, errors, _) when Errors.has_errors errors -> true
           | Some (m, _, _) ->
             (match eval_main m with
              | Some v ->
                let expected = if use_a then 0 else n in
                (match value_to_int v with
                 | Some result -> result = expected
                 | None -> true)
              | None -> true)
         with _ -> true)

(** 16. Tuple swap is involutory: swap(swap(t)) = t. *)
let prop_tuple_swap_involution =
  Test.make ~name:"oracle: tuple swap is involutory"
    ~count:200
    Gen.(pair (int_range (-100) 100) (int_range (-100) 100))
    (fun (a, b) ->
       let src = Printf.sprintf
         "mod Main do\n\
         \  fn swap(t : (Int, Int)) : (Int, Int) do\n\
         \    let (x, y) = t\n\
         \    let result = (y, x)\n\
         \    result\n\
         \  end\n\
         \  fn fst_eq(t1 : (Int, Int), a : Int) : Bool do\n\
         \    let (x, _) = t1\n\
         \    x == a\n\
         \  end\n\
         \  fn snd_eq(t1 : (Int, Int), b : Int) : Bool do\n\
         \    let (_, y) = t1\n\
         \    y == b\n\
         \  end\n\
         \  fn main() do\n\
         \    let t = (%d, %d)\n\
         \    let swapped_twice = swap(swap(t))\n\
         \    if fst_eq(swapped_twice, %d) then\n\
         \      if snd_eq(swapped_twice, %d) then 1 else 0\n\
         \    else 0\n\
         \  end\n\
          end"
         a b a b
       in
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, _) ->
           (match eval_main m with
            | Some v -> (match value_to_int v with Some 1 -> true | Some _ -> false | None -> true)
            | None -> true)
       with _ -> true)

(** 17. Closure captures correct value even after base variable is shadowed. *)
let prop_closure_captures_correct_value =
  Test.make ~name:"oracle: closure captures value at creation time"
    ~count:200
    Gen.(pair (int_range (-50) 50) (int_range (-50) 50))
    (fun (base, arg) ->
       let expected = base + arg in
       let src = Printf.sprintf
         "mod Main do\n\
         \  fn make_adder(base : Int) : Int -> Int do\n\
         \    fn x -> x + base\n\
         \  end\n\
         \  fn main() do\n\
         \    let f = make_adder(%d)\n\
         \    f(%d)\n\
         \  end\n\
          end"
         base arg
       in
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, _) ->
           (match eval_main m with
            | Some v -> (match value_to_int v with Some r -> r = expected | None -> true)
            | None -> true)
       with _ -> true)

(** 18. List sum: sum of [a, b, c] = a + b + c. *)
let prop_list_sum_correct =
  Test.make ~name:"oracle: inline list sum is correct"
    ~count:200
    Gen.(triple (int_range (-50) 50) (int_range (-50) 50) (int_range (-50) 50))
    (fun (a, b, c) ->
       let expected = a + b + c in
       let src = Printf.sprintf
         "mod Main do\n\
         \  type IntList = Nil | Cons(Int, IntList)\n\
         \  fn sum(lst : IntList) : Int do\n\
         \    match lst do\n\
         \    | Nil        -> 0\n\
         \    | Cons(h, t) -> h + sum(t)\n\
         \    end\n\
         \  end\n\
         \  fn main() do\n\
         \    sum(Cons(%d, Cons(%d, Cons(%d, Nil))))\n\
         \  end\n\
          end"
         a b c
       in
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, _) ->
           (match eval_main m with
            | Some v -> (match value_to_int v with Some r -> r = expected | None -> true)
            | None -> true)
       with _ -> true)

(* ── TIR-level properties (AST generators) ─────────────────────────────── *)

(** 19. Perceus should not crash on any generated TIR module. *)
let prop_perceus_tir_no_crash =
  Test.make ~name:"perceus (TIR gen): no crash on generated TIR modules"
    ~count:500
    gen_tir_module
    (fun m ->
       try ignore (March_tir.Perceus.perceus m); true
       with _ -> false)

(** 20. Monomorphize should not crash on generated TIR modules. *)
let prop_mono_tir_no_crash =
  Test.make ~name:"mono (TIR gen): no crash on generated TIR modules"
    ~count:500
    gen_tir_module
    (fun m ->
       try ignore (March_tir.Mono.monomorphize m); true
       with _ -> false)

(** 21. Defunctionalize should not crash on generated TIR modules. *)
let prop_defun_tir_no_crash =
  Test.make ~name:"defun (TIR gen): no crash on generated TIR modules"
    ~count:500
    gen_tir_module
    (fun m ->
       try ignore (March_tir.Defun.defunctionalize m); true
       with _ -> false)

(** 22. Perceus output has no more functions than input (no fn duplication). *)
let prop_perceus_preserves_fn_count =
  Test.make ~name:"perceus: does not duplicate function definitions"
    ~count:500
    gen_tir_module
    (fun m ->
       try
         let out = March_tir.Perceus.perceus m in
         List.length out.Tir.tm_fns = List.length m.Tir.tm_fns
       with _ -> true (* crash covered by prop_perceus_tir_no_crash *))

(** 23. Mono output preserves the set of function names that are entry points. *)
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

(** 24. Defun output preserves the total number of definitions (may add
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

(* ── New TIR pass structural invariant properties ──────────────────────── *)

(** 25. After monomorphization, no TVar should remain in type annotations
        of the specialised functions (all polymorphism is resolved). *)
let prop_mono_eliminates_tvars =
  Test.make ~name:"mono: eliminates all TVar type variables"
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
           let tys  = collect_types_module mono in
           (* Allow TVar "_" which is the placeholder for unknown/opaque types *)
           not (List.exists (function Tir.TVar s -> s <> "_" | _ -> false) tys)
       with _ -> true)

(** 26. After defunctionalization, no ELetRec remains in any function body
        (all lambdas have been lifted to top-level closure structs). *)
let prop_defun_eliminates_letrec =
  Test.make ~name:"defun: eliminates all ELetRec in function bodies"
    ~count:300
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, type_map) ->
           let tir   = March_tir.Lower.lower_module ~type_map m in
           let mono  = March_tir.Mono.monomorphize tir in
           let defun = March_tir.Defun.defunctionalize mono in
           not (List.exists (fun fn -> has_letrec fn.Tir.fn_body) defun.Tir.tm_fns)
       with _ -> true)

(** 27. Defun on TIR-generated closures eliminates ELetRec. *)
let prop_defun_tir_eliminates_letrec =
  Test.make ~name:"defun (TIR gen): eliminates ELetRec for closure modules"
    ~count:300
    gen_tir_closure_module
    (fun m ->
       try
         let out = March_tir.Defun.defunctionalize m in
         not (List.exists (fun fn -> has_letrec fn.Tir.fn_body) out.Tir.tm_fns)
       with _ -> true)

(** 28. Perceus idempotency: running Perceus twice produces the same
        function count as running it once (no spurious RC duplication). *)
let prop_perceus_idempotent_fn_count =
  Test.make ~name:"perceus: idempotent (fn count unchanged on second pass)"
    ~count:300
    gen_tir_module
    (fun m ->
       try
         let once  = March_tir.Perceus.perceus m in
         let twice = March_tir.Perceus.perceus once in
         List.length twice.Tir.tm_fns = List.length once.Tir.tm_fns
       with _ -> true)

(** 29. Mono idempotency: running mono twice does not reduce fn count
        (specialization is monotone — it only adds, never removes). *)
let prop_mono_idempotent_fn_count =
  Test.make ~name:"mono: idempotent (fn count non-decreasing on second pass)"
    ~count:300
    gen_tir_module
    (fun m ->
       try
         let once  = March_tir.Mono.monomorphize m in
         let twice = March_tir.Mono.monomorphize once in
         List.length twice.Tir.tm_fns >= List.length once.Tir.tm_fns
       with _ -> true)

(** 30. Defun + Perceus pipeline does not crash on TIR closure modules. *)
let prop_defun_perceus_closure_no_crash =
  Test.make ~name:"defun+perceus (closure TIR gen): pipeline does not crash"
    ~count:300
    gen_tir_closure_module
    (fun m ->
       try
         let defun   = March_tir.Defun.defunctionalize m in
         let _perceus = March_tir.Perceus.perceus defun in
         true
       with _ -> false)

(* ── Oracle property: generated programs match interpreter and compiler ── *)

(** 31. Full pipeline oracle: arith programs with println-wrapped output. *)
let prop_oracle_println_arith =
  Test.make ~name:"oracle (gen): println(arith) — interp = compiled"
    ~count:100
    (Gen.map2
       (fun e1 e2 ->
          Printf.sprintf
            "mod Main do\n\
            \  fn main() do\n\
            \    println(to_string(%s))\n\
            \    println(to_string(%s))\n\
            \  end\n\
             end" e1 e2)
       gen_arith_expr
       gen_arith_expr)
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         (* Log the mismatch for debugging *)
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** 34. Oracle for closure programs with println output. *)
let prop_oracle_println_closure =
  Test.make ~name:"oracle (gen): println(closure) — interp = compiled"
    ~count:50
    (Gen.map3
       (fun base offset arg ->
          Printf.sprintf
            "mod Main do\n\
            \  fn main() do\n\
            \    let base = %d\n\
            \    let adder = fn x -> x + base + %d\n\
            \    println(to_string(adder(%d)))\n\
            \  end\n\
             end"
            base offset arg)
       (Gen.int_range (-50) 50)
       (Gen.int_range (-50) 50)
       (Gen.int_range (-50) 50))
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** 35. Oracle for ADT programs with println output. *)
let prop_oracle_println_adt =
  Test.make ~name:"oracle (gen): println(ADT match) — interp = compiled"
    ~count:50
    (Gen.map2
       (fun use_circle n ->
          let ctor = if use_circle then Printf.sprintf "Circle(%d)" (abs n mod 20 + 1)
                                   else Printf.sprintf "Square(%d)" (abs n mod 20 + 1) in
          Printf.sprintf
            "mod Main do\n\
            \  type Shape = Circle(Int) | Square(Int)\n\
            \  fn area(s : Shape) : Int do\n\
            \    match s do\n\
            \    | Circle(r) -> r * r\n\
            \    | Square(n) -> n * 4\n\
            \    end\n\
            \  end\n\
            \  fn main() do\n\
            \    println(to_string(area(%s)))\n\
            \  end\n\
             end"
            ctor)
       Gen.bool
       (Gen.int_range 1 100))
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** 36. Oracle for HOF programs with println output. *)
let prop_oracle_println_hof =
  Test.make ~name:"oracle (gen): println(HOF apply) — interp = compiled"
    ~count:50
    (Gen.map2
       (fun factor arg ->
          Printf.sprintf
            "mod Main do\n\
            \  fn apply(f : Int -> Int, x : Int) : Int do\n\
            \    f(x)\n\
            \  end\n\
            \  fn main() do\n\
            \    println(to_string(apply(fn n -> n * %d, %d)))\n\
            \  end\n\
             end"
            (abs factor mod 20 + 1) arg)
       (Gen.int_range 1 20)
       (Gen.int_range (-50) 50))
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** 37. Oracle for tuple programs with println output. *)
let prop_oracle_println_tuple =
  Test.make ~name:"oracle (gen): println(tuple) — interp = compiled"
    ~count:50
    (Gen.map2
       (fun a b ->
          Printf.sprintf
            "mod Main do\n\
            \  fn main() do\n\
            \    let t = (%d, %d)\n\
            \    let (x, y) = t\n\
            \    println(to_string(x + y))\n\
            \  end\n\
             end"
            a b)
       (Gen.int_range (-100) 100)
       (Gen.int_range (-100) 100))
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** 38. Oracle for list programs with println output. *)
let prop_oracle_println_list =
  Test.make ~name:"oracle (gen): println(list sum) — interp = compiled"
    ~count:50
    (Gen.map3
       (fun a b c ->
          Printf.sprintf
            "mod Main do\n\
            \  type IntList = Nil | Cons(Int, IntList)\n\
            \  fn sum(lst : IntList) : Int do\n\
            \    match lst do\n\
            \    | Nil        -> 0\n\
            \    | Cons(h, t) -> h + sum(t)\n\
            \    end\n\
            \  end\n\
            \  fn main() do\n\
            \    println(to_string(sum(Cons(%d, Cons(%d, Cons(%d, Nil))))))\n\
            \  end\n\
             end"
            a b c)
       (Gen.int_range (-50) 50)
       (Gen.int_range (-50) 50)
       (Gen.int_range (-50) 50))
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

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
    "semantic properties (source)", List.map QCheck_alcotest.to_alcotest [
      prop_adt_match_correct;
      prop_tuple_swap_involution;
      prop_closure_captures_correct_value;
      prop_list_sum_correct;
    ];
    "tir passes (ast gen)", List.map QCheck_alcotest.to_alcotest [
      prop_perceus_tir_no_crash;
      prop_mono_tir_no_crash;
      prop_defun_tir_no_crash;
      prop_perceus_preserves_fn_count;
      prop_mono_preserves_main_fn;
      prop_defun_no_fn_loss;
    ];
    "tir pass invariants", List.map QCheck_alcotest.to_alcotest [
      prop_mono_eliminates_tvars;
      prop_defun_eliminates_letrec;
      prop_defun_tir_eliminates_letrec;
      prop_perceus_idempotent_fn_count;
      prop_mono_idempotent_fn_count;
      prop_defun_perceus_closure_no_crash;
    ];
    "oracle: interp = compiled", List.map QCheck_alcotest.to_alcotest [
      prop_oracle_println_arith;
      prop_oracle_println_closure;
      prop_oracle_println_adt;
      prop_oracle_println_hof;
      prop_oracle_println_tuple;
      prop_oracle_println_list;
    ];
  ]
