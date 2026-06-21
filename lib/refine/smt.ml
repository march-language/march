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
