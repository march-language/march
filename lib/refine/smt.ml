(* SMT-LIB2 term AST and renderer for the refinement Z3 bridge.
   v1 supports the Int/Bool linear-arithmetic + EUF fragment. *)

let version = "a0"

(* ── Why `SFloat` is Z3's FloatingPoint sort and NOT `Real` ────────────────
   `Float64` is the IEEE-754 binary64 sort — the one March's `Float` actually
   is, NaN and signed zeros included.  Modelling floats as mathematical reals
   would be unsound in the FALSE-POSITIVE direction, which is the one failure
   this subsystem must never have.  The discriminating query:

     ¬(x >= 0.0) ∧ ¬(x <= 0.0)

   is SATISFIABLE over floats (witness: NaN, which compares false against
   everything) and UNSATISFIABLE over reals (trichotomy).  The checker reports a
   violation exactly when it proves a predicate can never hold, so under a reals
   encoding it would "prove" that a perfectly ordinary float predicate is
   unsatisfiable and flag correct code.  Do not "simplify" this to Real. *)
type sort = SInt | SBool | SFloat | SData of string  (* a named (algebraic-datatype) sort *)

type term =
  | Const of string          (* a declared symbol: "_", "i", or a measure-applied const *)
  | App of string * term list (* uninterpreted-fn / datatype-constructor application *)
  | IsCtor of string * term  (* Z3 datatype tester: ((_ is Ctor) x) *)
  | IntLit of int
  | BoolLit of bool
  (* A binary64 literal, pre-rendered by [float_decimal] as (is_negative,
     plain-decimal-magnitude).  The magnitude is stored already validated
     because SMT-LIB accepts neither exponent notation nor a leading `-`: a
     negative literal is the s-expression `(- 1.0)`, and a value with no short
     plain-decimal form never becomes a term at all (see [float_decimal]). *)
  | FloatLit of bool * string
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
  (* IEEE-754 comparisons.  [FpEq] is `fp.eq`, NOT `=`: `fp.eq` is IEEE
     equality, under which `+0.0` and `-0.0` are equal and NaN equals nothing,
     whereas `=` on Float64 is BITWISE identity.  The difference is not
     academic — with `=`, the contract `{Float | _ != 0.0}` would accept `-0.0`,
     which is just as bad a divisor as `+0.0`.  `!=` is rendered as the negation
     of [FpEq] rather than getting a constructor of its own. *)
  | FpEq of term * term
  | FpLt of term * term
  | FpLe of term * term
  | FpGt of term * term
  | FpGe of term * term

type vc = {
  decls : (string * sort) list;   (* free symbols to declare *)
  assumptions : term list;        (* hypotheses (path context + known refinements) *)
  goal : term;                    (* the predicate we want to hold *)
}

let string_of_sort = function
  | SInt -> "Int"
  | SBool -> "Bool"
  | SFloat -> "Float64"
  | SData n -> n

(* Split a binary64 into (is_negative, plain SMT-LIB decimal magnitude), or
   [None] when it has no such form and must therefore not be reflected at all.

   SMT-LIB's `<decimal>` is `<numeral>.<numeral>` — digits, one point, nothing
   else.  Exponent notation (`1e-05`), `inf` and `nan` are all rejected by the
   parser, and an integral `%g` rendering ("4") is not a decimal either, so it
   gains an explicit ".0".

   The round-trip test is what makes this EXACT rather than approximate: a
   candidate is accepted only when [float_of_string] maps it back to the very
   double we started from.  `((_ to_fp 11 53) RNE d)` rounds the exact decimal
   `d` to nearest-even, which for such a `d` is that same double.  When no
   candidate round-trips (a very large or very small magnitude), the answer is
   [None] and the caller skips the predicate — silence, never a guess. *)
let float_decimal (f : float) : (bool * string) option =
  if not (Float.is_finite f) then None
  else
    let neg = f < 0.0 || (f = 0.0 && 1.0 /. f < 0.0) in
    let x = Float.abs f in
    let plain s =
      s <> ""
      && String.for_all (fun c -> (c >= '0' && c <= '9') || c = '.') s
      && (try float_of_string s = x with _ -> false)
    in
    match List.find_opt plain [ Printf.sprintf "%.17g" x; Printf.sprintf "%.17f" x ] with
    | None -> None
    | Some s -> Some (neg, if String.contains s '.' then s else s ^ ".0")

(* `((_ to_fp 11 53) RNE …)` is the binary64 conversion of a decimal; 11/53 are
   binary64's exponent and significand widths. *)
let render_float (neg : bool) (d : string) : string =
  if neg then Printf.sprintf "((_ to_fp 11 53) RNE (- %s))" d
  else Printf.sprintf "((_ to_fp 11 53) RNE %s)" d

let rec render = function
  | Const s -> s
  | App (f, []) -> f
  | App (f, args) -> Printf.sprintf "(%s %s)" f (String.concat " " (List.map render args))
  | IsCtor (c, t) -> Printf.sprintf "((_ is %s) %s)" c (render t)
  | IntLit n -> if n < 0 then Printf.sprintf "(- %d)" (- n) else string_of_int n
  | BoolLit b -> if b then "true" else "false"
  | FloatLit (neg, d) -> render_float neg d
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
  | FpEq (a, b) -> Printf.sprintf "(fp.eq %s %s)" (render a) (render b)
  | FpLt (a, b) -> Printf.sprintf "(fp.lt %s %s)" (render a) (render b)
  | FpLe (a, b) -> Printf.sprintf "(fp.leq %s %s)" (render a) (render b)
  | FpGt (a, b) -> Printf.sprintf "(fp.gt %s %s)" (render a) (render b)
  | FpGe (a, b) -> Printf.sprintf "(fp.geq %s %s)" (render a) (render b)

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
