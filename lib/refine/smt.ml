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
type sort =
  | SInt
  | SBool
  | SFloat
  (* A named declared sort, with its type arguments when the datatype is
     parametric: [SData ("M_List", [SInt])] is the List(Int) instance, and
     [SData ("M_Rec", [])] is the monomorphic `M_Rec`.  Opaque built-in sorts
     (`Elem`, `$Str`) are nullary [SData] too.

     Every instance is declared to z3 as a MONOMORPHIC datatype of its own,
     named by [instance_name] (`M_List$Int`); the instance whose arguments
     are all the opaque `Elem` keeps the bare datatype name (`M_List`), which
     is exactly the declaration every query used before instances existed.
     z3 4.8.12 (CI) segfaults on satisfiable queries that carry a recursion
     axiom over a `(par …)` datatype with two recursive fields, so parametric
     declarations are never emitted. *)
  | SData of string * sort list
  (* The [i]th type parameter of the datatype a constructor field belongs to.
     Only ever appears inside a constructor's field sorts; [instantiate]
     replaces it before a sort reaches a declaration or a term. *)
  | SParam of int
  (* A finite set of elements at the given sort, encoded as Z3's
     `(Array <elem> Bool)` — the Liquid Haskell / liquid-fixpoint encoding.
     Every set operator below is a quantifier-free array term, so a VC that
     mentions sets stays inside the decidable extensional-array fragment.
     [set_unknown_elem] is the placeholder element sort a producer uses when
     it cannot yet tell the element sort (an `elts$xs` constant standing for
     an opaque list); [Refine_encode.resolve_set_sorts] unifies every set
     term in a VC and replaces the placeholder before rendering.  A term that
     still carries it at render time renders at the opaque `Elem` sort. *)
  | SSet of sort

let set_unknown_elem = SData ("?", [])

(* A nullary named sort. *)
let sdata (n : string) : sort = SData (n, [])

(* Substitute a datatype instance's arguments for its type parameters. *)
let rec instantiate (args : sort list) (s : sort) : sort =
  match s with
  | SParam i -> (match List.nth_opt args i with Some a -> a | None -> SData ("Elem", []))
  | SData (n, xs) -> SData (n, List.map (instantiate args) xs)
  | SSet e -> SSet (instantiate args e)
  | SInt | SBool | SFloat -> s

type term =
  | Const of string          (* a declared symbol: "_", "i", or a measure-applied const *)
  | App of string * term list (* uninterpreted-fn application *)
  (* A datatype constructor application at a known datatype instance.  The
     instance is carried because every instance of a datatype declares the
     same constructor names, so a constructor of a parametric datatype renders
     qualified, `((as Some M_Option$Int) x)`.  A monomorphic constructor
     renders exactly as a plain application. *)
  | Ctor of string * sort * term list
  | IsCtor of string * term  (* Z3 datatype tester: ((_ is Ctor) x) *)
  (* A tester at a known datatype instance, with the constructor's field
     count.  z3 (4.8 and 4.16) rejects `(_ is C)` as ambiguous once two
     instances of one datatype are in scope (they share constructor names), so
     a parametric instance renders the equivalent `(= x ((as C S) (C_0 x) … ))`:
     [x] is built by [C] iff it equals [C] applied to its own selectors. *)
  | IsCtorAt of string * sort * int * term
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
  (* General (possibly NON-linear) multiplication.  [MulLit] is still the right
     constructor whenever one factor is a literal — it keeps the query in LIA,
     where z3 is complete and fast.  [Mul] exists for the predicates that are
     genuinely non-linear (`v * v > 0`, which is exactly `v != 0` over the
     integers): the driver emits no `(set-logic …)`, so z3 runs its `ALL`
     tactic and decides these instantly.  Where it cannot, the answer is
     `unknown`, which every caller already treats as *not proved*. *)
  | Mul of term * term
  (* Integer `div`/`mod` by a NON-ZERO integer literal (the int is the
     divisor).  SMT-LIB's `div`/`mod` are Euclidean; March's `/`/`%`
     truncate toward zero.  The two agree exactly when the dividend is
     non-negative (for either sign of divisor), so these are constructed
     ONLY where the reflector has established that — see [smt_of_r_marked]'s
     division arm in lib/refinecheck/refine_scope.ml.  Anywhere else,
     rendering one as the other would certify code that can fail. *)
  | DivLit of term * int
  | ModLit of term * int
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
  (* ── Finite sets (specs/2026-09-13-set-refinements-design.md §4.2) ─────
     [SetEmpty]/[SetSng] carry the ELEMENT sort, because `(as const …)` needs
     the full array sort spelled out; [SetMem] and [SetSub] are Bool-valued,
     the rest set-valued.  Subset is DEFINED by union — `(= (union a b) b)` —
     so no user VC ever contains a quantifier. *)
  | SetEmpty of sort
  | SetSng of sort * term
  | SetMem of term * term
  | SetUnion of term * term
  | SetInter of term * term
  | SetDiff of term * term
  | SetSub of term * term
  (* The number of elements of a set, at the set's element sort (plan step
     3.1).  An uninterpreted `card$<elem>` per element sort: no quantified
     axiom ever mentions it; [Refine_encode.card_facts] adds ground facts that
     are theorems of finite sets, and congruence gives `a == b => card a ==
     card b` for free. *)
  | SetCard of sort * term

type vc = {
  decls : (string * sort) list;   (* free symbols to declare *)
  assumptions : term list;        (* hypotheses (path context + known refinements) *)
  goal : term;                    (* the predicate we want to hold *)
}

(* A term's immediate subterms. *)
let children (t : term) : term list =
  match t with
  | Const _ | IntLit _ | BoolLit _ | FloatLit _ | SetEmpty _ -> []
  | App (_, args) | Ctor (_, _, args) -> args
  | IsCtor (_, a) | IsCtorAt (_, _, _, a) | MulLit (_, a) | DivLit (a, _) | ModLit (a, _)
  | Neg a | Not a | SetSng (_, a) | SetCard (_, a) -> [ a ]
  | Add (a, b) | Sub (a, b) | Mul (a, b) | And (a, b) | Or (a, b) | Implies (a, b) | Eq (a, b)
  | Ne (a, b) | Lt (a, b) | Le (a, b) | Gt (a, b) | Ge (a, b) | FpEq (a, b) | FpLt (a, b)
  | FpLe (a, b) | FpGt (a, b) | FpGe (a, b) | SetMem (a, b) | SetUnion (a, b) | SetInter (a, b)
  | SetDiff (a, b) | SetSub (a, b) -> [ a; b ]

(* The `define-sort` name of a set sort.  `$` cannot occur in a March
   identifier, so no user symbol can collide with one of these. *)
let rec string_of_sort = function
  | SInt -> "Int"
  | SBool -> "Bool"
  | SFloat -> "Float64"
  | SData (n, []) -> n
  | SData (n, args) -> instance_name n args
  | SParam i -> "T" ^ string_of_int i
  | SSet e -> "MSet$" ^ set_elem_tag e

(* The declared name of datatype [n]'s instance at [args]: the bare name when
   every argument is the opaque `Elem`, else `n$arg1$…`.  Arities are fixed per
   datatype, so the spelling is unambiguous. *)
and instance_name (n : string) (args : sort list) : string =
  if List.for_all is_elem_arg args then n
  else n ^ "$" ^ String.concat "$" (List.map set_elem_tag args)

and is_elem_arg = function
  | SData (("Elem" | "?"), []) -> true
  | _ -> false

(* A sort as a fragment of an SMT symbol (no spaces or parentheses), for
   names derived from it: `MSet$Int`, `MSet$M_List$Int`. *)
and set_elem_tag = function
  | SInt -> "Int"
  | SBool -> "Bool"
  | SFloat -> "Float"
  | SData ("?", []) -> "Elem"
  | SData ("$Str", []) -> "Str"
  | SData (n, []) -> n
  | SData (n, args) -> instance_name n args
  | SParam i -> "T" ^ string_of_int i
  | SSet e -> "Set" ^ set_elem_tag e

(* The uninterpreted cardinality function over sets of [e]. *)
let card_fn (e : sort) : string = "card$" ^ set_elem_tag e

(* The element sort actually RENDERED for a set: the placeholder becomes the
   opaque `Elem` sort. *)
let render_elem_sort = function
  | SData ("?", []) -> SData ("Elem", [])
  | s -> s

(* One `(define-sort MSet$X () (Array X Bool))` line per element sort.  The
   caller is responsible for the underlying sort (`Elem`, `$Str`) being
   declared FIRST in the same push. *)
let set_sort_defs (elems : sort list) : string =
  String.concat ""
    (List.map
       (fun e ->
         let e = render_elem_sort e in
         Printf.sprintf "(define-sort %s () (Array %s Bool))\n"
           (string_of_sort (SSet e)) (string_of_sort e))
       (List.sort_uniq compare (List.map render_elem_sort elems)))

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

(* The instance-qualified tester [IsCtorAt] renders to, over a rendered term. *)
let tester_at (c : string) (s : sort) (n : int) (t : string) : string =
  if n = 0 then Printf.sprintf "(= %s (as %s %s))" t c (string_of_sort s)
  else
    Printf.sprintf "(= %s ((as %s %s) %s))" t c (string_of_sort s)
      (String.concat " " (List.init n (fun i -> Printf.sprintf "(%s_%d %s)" c i t)))

let rec render = function
  | Const s -> s
  | App (f, []) -> f
  | App (f, args) -> Printf.sprintf "(%s %s)" f (String.concat " " (List.map render args))
  | Ctor (c, SData (_, []), []) -> c
  | Ctor (c, SData (_, []), args) ->
    Printf.sprintf "(%s %s)" c (String.concat " " (List.map render args))
  | Ctor (c, s, []) -> Printf.sprintf "(as %s %s)" c (string_of_sort s)
  | Ctor (c, s, args) ->
    Printf.sprintf "((as %s %s) %s)" c (string_of_sort s) (String.concat " " (List.map render args))
  (* A tester applied directly to a constructor term is decided here: z3
     (4.8 and 4.16 alike) rejected `((_ is Some) ((as Some …) x))` for a
     parametric datatype, and the answer is syntactic anyway. *)
  | IsCtor (c, Ctor (c', _, _)) | IsCtorAt (c, _, _, Ctor (c', _, _)) -> if c = c' then "true" else "false"
  | IsCtor (c, t) | IsCtorAt (c, SData (_, []), _, t) -> Printf.sprintf "((_ is %s) %s)" c (render t)
  | IsCtorAt (c, s, n, t) -> tester_at c s n (render t)
  | IntLit n -> if n < 0 then Printf.sprintf "(- %d)" (- n) else string_of_int n
  | BoolLit b -> if b then "true" else "false"
  | FloatLit (neg, d) -> render_float neg d
  | Add (a, b) -> Printf.sprintf "(+ %s %s)" (render a) (render b)
  | Sub (a, b) -> Printf.sprintf "(- %s %s)" (render a) (render b)
  | MulLit (k, a) -> Printf.sprintf "(* %d %s)" k (render a)
  | Mul (a, b) -> Printf.sprintf "(* %s %s)" (render a) (render b)
  | DivLit (a, k) -> Printf.sprintf "(div %s %s)" (render a) (render (IntLit k))
  | ModLit (a, k) -> Printf.sprintf "(mod %s %s)" (render a) (render (IntLit k))
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
  | SetEmpty e ->
    Printf.sprintf "((as const %s) false)" (string_of_sort (SSet (render_elem_sort e)))
  | SetSng (e, x) ->
    Printf.sprintf "(store ((as const %s) false) %s true)"
      (string_of_sort (SSet (render_elem_sort e))) (render x)
  | SetMem (x, s) -> Printf.sprintf "(select %s %s)" (render s) (render x)
  | SetUnion (a, b) -> Printf.sprintf "((_ map or) %s %s)" (render a) (render b)
  | SetInter (a, b) -> Printf.sprintf "((_ map and) %s %s)" (render a) (render b)
  | SetDiff (a, b) ->
    Printf.sprintf "((_ map and) %s ((_ map not) %s))" (render a) (render b)
  | SetSub (a, b) -> Printf.sprintf "(= ((_ map or) %s %s) %s)" (render a) (render b) (render b)
  | SetCard (e, a) -> Printf.sprintf "(%s %s)" (card_fn (render_elem_sort e)) (render a)

(* The canonical assertion block for a VC: declare every free symbol, assert the
   hypotheses, and assert the NEGATED goal.  Sent to z3 between push/pop and also
   used (verbatim) as the BLAKE3 cache key.  `(check-sat)` is appended by the
   solver driver, not here, so the cache key is independent of solver options. *)
let assertion_block (vc : vc) : string =
  let buf = Buffer.create 256 in
  List.iter
    (fun (name, sort) ->
      let sort = match sort with SSet e -> SSet (render_elem_sort e) | s -> s in
      Buffer.add_string buf
        (Printf.sprintf "(declare-const %s %s)\n" name (string_of_sort sort)))
    vc.decls;
  List.iter
    (fun a -> Buffer.add_string buf (Printf.sprintf "(assert %s)\n" (render a)))
    vc.assumptions;
  Buffer.add_string buf (Printf.sprintf "(assert %s)\n" (render (Not vc.goal)));
  Buffer.contents buf
