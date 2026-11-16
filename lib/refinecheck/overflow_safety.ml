(* Overflow-safety checker for `cap no_panic` modules.

   Since the Int overflow trap (specs/progress/2026-10-30-int-overflow-trap.md)
   `a + b`, `a - b`, `a * b` and `-a` on `Int` panic when the result leaves
   [-2^62, 2^62), so each is a panic site like `/`.  This pass finds every one in
   a module declared `cap no_panic` and discharges `-2^62 <= result < 2^62` with
   Z3, the way [Division_safety] discharges `divisor != 0`.  Anything short of
   proof is an error: `cap no_panic` is a guarantee.

   What a VC may assume:
   - Every Int value the program holds is in range.  The trap is what makes this
     true: a value outside it would have panicked where it was computed.  So each
     variable, and each sub-expression the encoder cannot reflect (a call, a
     field, an `if`), becomes a constant bounded to [-2^62, 2^62).
   - The site's operands were evaluated before the operator (March is strict),
     so each operand, including a nested `a + b`, is in range too.  The same holds
     for a tracked `let` right-hand side, which ran to completion before the
     site.  It does NOT hold inside a path condition: under `p && q`, `q` may
     never have run, so a guard contributes its comparison but no range fact
     about its own arithmetic.
   - Path conditions, Int-refined parameters and tracked `let` values, from the
     same shadowing-aware walker [Division_safety] uses
     ([Division_safety.iter_sites]).  A guard is used only where the
     typechecker recorded Int on a side of each comparison: a Float guard read
     as an Int fact could be unsatisfiable over the integers (`0.0 < x && x <
     1.0`) and prove anything.

   Which sites: `+ - *` are `Num`-polymorphic, so the typechecker's span ->
   type table decides.  A site recorded as `Float` (or any other concrete
   non-Int type) is skipped; `Int`, an unresolved type variable, or no table at
   all is checked (fail closed).  `int_wrapping_add` / `_sub` / `_mul` are
   ordinary calls, never sites; so are `int_abs`, `int_pow` and `int_shl`,
   which still wrap (`specs/lang/type-system.md`, "Int width and overflow"). *)

module A = March_ast.Ast
module Smt = March_refine.Smt
module Refine = March_refine.Refine
module Err = March_errors.Errors
module T = March_typecheck.Typecheck
module D = Division_safety

(* March's Int is OCaml's native int: both are 63-bit two's complement. *)
let int_lo = min_int (* -2^62 *)
let int_hi = max_int (* 2^62 - 1 *)

(* ── Types from the typechecker ──────────────────────────────────────────── *)

let type_map : (A.span, T.ty) Hashtbl.t option ref = ref None

let rec strip t = match T.repr t with T.TLin (_, b) -> strip b | t -> t

(* [Some name] for a concrete nullary type constructor recorded at [sp]. *)
let con_at (sp : A.span) : string option =
  match !type_map with
  | None -> None
  | Some tm ->
    (match Hashtbl.find_opt tm sp with
     | Some t -> (match strip t with T.TCon (n, []) -> Some (March_typecheck.Typecheck_nominal.refine_name n) | _ -> None)
     | None -> None)

let is_int_expr (e : A.expr) : bool =
  match e with
  | A.ELit (A.LitInt _, _) -> true
  | _ -> con_at (T.span_of_expr e) = Some "Int"

(* A site is checked unless the typechecker says it is some concrete type
   other than Int (in practice Float). *)
let site_is_int (sp : A.span) : bool =
  match con_at sp with Some n -> n = "Int" | None -> true

(* ── Sites ───────────────────────────────────────────────────────────────── *)

let arith_ops = [ "+"; "-"; "*" ]

let site_of (e : A.expr) : (string * A.expr list * A.span) option =
  match e with
  | A.EApp (A.EVar { A.txt = op; _ }, [ a; b ], sp) when List.mem op arith_ops ->
    Some (op, [ a; b ], sp)
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], sp) -> Some ("negate", [ a ], sp)
  | _ -> None

(* ── Encoding ────────────────────────────────────────────────────────────── *)

(* One VC under construction: the Int constants it mentions and the facts it
   assumes.  Constants are declared on first use; every one is bounded. *)
type vc = {
  mutable consts : string list;
  mutable facts : Smt.term list;
  mutable fresh : int;
}

let in_range (t : Smt.term) : Smt.term =
  Smt.And (Smt.Le (Smt.IntLit int_lo, t), Smt.Le (t, Smt.IntLit int_hi))

let declare (v : vc) (x : string) : Smt.term =
  if not (List.mem x v.consts) then begin
    v.consts <- x :: v.consts;
    v.facts <- in_range (Smt.Const x) :: v.facts
  end;
  Smt.Const x

(* A value this encoder cannot see into.  `%` cannot occur in a March name. *)
let opaque (v : vc) : Smt.term =
  v.fresh <- v.fresh + 1;
  declare v (Printf.sprintf "opaque%%%d" v.fresh)

(* What a builtin's Int result is known to lie in, beyond the Int range.  A
   fresh constant with these bounds is sound whether or not the call ran: it
   only constrains itself. *)
let builtin_ranges =
  [ ("string_byte_at", (-1, 255));          (* a byte, or -1 past the end *)
    ("string_byte_length", (0, int_hi));
    ("string_length", (0, int_hi)) ]

(* Reflect an Int-typed expression.  Total: what does not reflect is opaque.
   [~evaluated] says the expression ran to completion, so each arithmetic node
   in it is in range (see the header). *)
let rec int_term ~evaluated (v : vc) (e : A.expr) : Smt.term =
  let go = int_term ~evaluated v in
  let node t = if evaluated then v.facts <- in_range t :: v.facts; t in
  match e with
  | A.ELit (A.LitInt n, _) -> Smt.IntLit n
  | A.EVar { A.txt = x; _ } -> declare v x
  | A.EAnnot (inner, _, _) -> go inner
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ a; b ], _) -> node (Smt.Add (go a, go b))
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a; b ], _) -> node (Smt.Sub (go a, go b))
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ a; b ], _) ->
    node
      (match go a, go b with
       | Smt.IntLit k, t | t, Smt.IntLit k -> Smt.MulLit (k, t)
       | ta, tb -> Smt.Mul (ta, tb))
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) -> node (Smt.Neg (go a))
  (* `/` and `%` by a positive literal.  March truncates toward zero and SMT
     `div`/`mod` are Euclidean; the two agree on a non-negative dividend, so a
     negative one is mapped through its negation. *)
  | A.EApp (A.EVar { A.txt = ("/" | "%") as op; _ }, [ a; A.ELit (A.LitInt k, _) ], _)
    when k > 0 ->
    let ta = go a and r = opaque v in
    let f x = if op = "/" then Smt.DivLit (x, k) else Smt.ModLit (x, k) in
    let nonneg = Smt.Ge (ta, Smt.IntLit 0) in
    v.facts <-
      Smt.Implies (nonneg, Smt.Eq (r, f ta))
      :: Smt.Implies (Smt.Not nonneg, Smt.Eq (r, Smt.Neg (f (Smt.Neg ta))))
      :: v.facts;
    r
  | A.EApp (A.EVar { A.txt = f; _ }, _, _) when List.mem_assoc f builtin_ranges ->
    let r = opaque v in
    let lo, hi = List.assoc f builtin_ranges in
    v.facts <- Smt.Le (Smt.IntLit lo, r) :: Smt.Le (r, Smt.IntLit hi) :: v.facts;
    r
  | _ -> opaque v

(* A term the fact [e] (negated when [neg]) implies, or [None].  A weakening:
   a conjunct that does not reflect is dropped, a disjunction needs both arms. *)
let rec fact_term (v : vc) (e : A.expr) (neg : bool) : Smt.term option =
  let atom mk a b =
    if is_int_expr a || is_int_expr b then
      let t = mk (int_term ~evaluated:false v a) (int_term ~evaluated:false v b) in
      Some (if neg then Smt.Not t else t)
    else None
  in
  let both f a b =
    match fact_term v a neg, fact_term v b neg with
    | Some x, Some y -> Some (f x y)
    | _ -> None
  in
  let either a b =
    match fact_term v a neg, fact_term v b neg with
    | Some x, Some y -> Some (Smt.And (x, y))
    | Some x, None | None, Some x -> Some x
    | None, None -> None
  in
  match e with
  | A.ELit (A.LitBool b, _) -> Some (Smt.BoolLit (b <> neg))
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) -> fact_term v a (not neg)
  | A.EApp (A.EVar { A.txt = "&&"; _ }, [ a; b ], _) ->
    if neg then both (fun x y -> Smt.Or (x, y)) a b else either a b
  | A.EApp (A.EVar { A.txt = "||"; _ }, [ a; b ], _) ->
    if neg then either a b else both (fun x y -> Smt.Or (x, y)) a b
  | A.EApp (A.EVar { A.txt = op; _ }, [ a; b ], _) ->
    (match op with
     | "==" -> atom (fun x y -> Smt.Eq (x, y)) a b
     | "!=" -> atom (fun x y -> Smt.Ne (x, y)) a b
     | "<" -> atom (fun x y -> Smt.Lt (x, y)) a b
     | "<=" -> atom (fun x y -> Smt.Le (x, y)) a b
     | ">" -> atom (fun x y -> Smt.Gt (x, y)) a b
     | ">=" -> atom (fun x y -> Smt.Ge (x, y)) a b
     | _ -> None)
  | _ -> None

(* The variables a refinement predicate compares: [EVar]s in argument
   positions, not the operator heads (`<`, `&&`) that [D.spine_vars] keeps. *)
let rec pred_vars (e : A.expr) (acc : string list) : string list =
  match e with
  | A.EVar { A.txt = x; _ } -> x :: acc
  | A.EApp (_, args, _) -> List.fold_left (fun acc a -> pred_vars a acc) acc args
  | A.EAnnot (inner, _, _) -> pred_vars inner acc
  | _ -> acc

(* z3 prints a negative model value as `(- n)`. *)
let smt_int (s : string) : string =
  let n = String.length s in
  if n > 4 && String.sub s 0 3 = "(- " && s.[n - 1] = ')' then "-" ^ String.sub s 3 (n - 4)
  else s

(* ── Per-site VC ─────────────────────────────────────────────────────────── *)

let describe = function
  | "+" -> "addition" | "-" -> "subtraction" | "*" -> "multiplication"
  | _ -> "negation"

let wrapping_hint = function
  | "+" -> "`int_wrapping_add`" | "-" -> "`int_wrapping_sub`"
  | "*" -> "`int_wrapping_mul`" | _ -> "`int_wrapping_sub(0, x)`"

let suggestion op =
  Printf.sprintf
    "\n\nBound the operands with a refinement (`{v : Int | v < 1000000}`) or a \
     guard (`if x < n do x + 1 ...`), or spell it %s if wrapping modulo 2^63 \
     is what you want."
    (wrapping_hint op)

(* The literal-only case, settled without a solver. *)
let literal_value op (args : A.expr list) : int option option =
  let lit = function A.ELit (A.LitInt n, _) -> Some n | _ -> None in
  match op, List.map lit args with
  | "negate", [ Some a ] -> Some (if a = min_int then None else Some (-a))
  | "+", [ Some a; Some b ] ->
    let r = a + b in
    Some (if (a >= 0) = (b >= 0) && (r >= 0) <> (a >= 0) then None else Some r)
  | "-", [ Some a; Some b ] ->
    let r = a - b in
    Some (if (a >= 0) <> (b >= 0) && (r >= 0) <> (a >= 0) then None else Some r)
  | "*", [ Some a; Some b ] ->
    Some
      (if a = 0 || b = 0 then Some 0
       else
         let r = a * b in
         if r / b = a && not (a = -1 && b = min_int) && not (b = -1 && a = min_int)
         then Some r else None)
  | _ -> None

let check_site ~root errctx params (op, args, span) (c : D.dctx) : bool =
  match literal_value op args with
  | Some (Some _) -> true
  | Some None ->
    Err.error ~code:Err.Code.int_overflow errctx ~span
      (Printf.sprintf "this %s of literals overflows Int in a `cap no_panic` module.%s"
         (describe op) (suggestion op));
    false
  | None ->
    let v = { consts = []; facts = []; fresh = 0 } in
    let operands = List.map (int_term ~evaluated:true v) args in
    List.iter (fun t -> v.facts <- in_range t :: v.facts) operands;
    let result =
      match op, operands with
      | "+", [ a; b ] -> Smt.Add (a, b)
      | "-", [ a; b ] -> Smt.Sub (a, b)
      | "*", [ Smt.IntLit k; t ] | "*", [ t; Smt.IntLit k ] -> Smt.MulLit (k, t)
      | "*", [ a; b ] -> Smt.Mul (a, b)
      | _, [ a ] -> Smt.Neg a
      | _ -> Smt.IntLit 0
    in
    (* Path conditions, each a weakening of the guard in scope. *)
    List.iter
      (fun (cond, negated) ->
        Option.iter (fun t -> v.facts <- t :: v.facts) (fact_term v cond negated))
      c.D.path;
    (* Refined parameters still bound to the parameter (not rebound since). *)
    List.iter
      (fun (n, bdr, pred) ->
        if not (List.mem n c.D.shadowed) then
          match D.smt_of ~b:bdr ~var:n pred with
          | Some t ->
            ignore (declare v n);
            List.iter
              (fun x -> if x <> bdr && x <> "_" then ignore (declare v x))
              (pred_vars pred []);
            v.facts <- t :: v.facts
          | None -> ())
      params;
    (* `let` values for the names the VC mentions, transitively.  The walker
       has already dropped every entry a later rebinding made stale
       ([Division_safety.retire]): `let a = x + 1; let x = 0; a + 1` must not
       read `a = 0 + 1`. *)
    let used = ref [] in
    let rec close () =
      let added = ref false in
      List.iter
        (fun (n, rhs) ->
          if List.mem n v.consts && not (List.mem n !used)
             && is_int_expr rhs
          then begin
            used := n :: !used;
            added := true;
            let t = int_term ~evaluated:true v rhs in
            v.facts <- Smt.Eq (Smt.Const n, t) :: v.facts
          end)
        c.D.lets;
      if !added then close ()
    in
    close ();
    let vc =
      Smt.
        { decls = List.rev_map (fun x -> (x, Smt.SInt)) v.consts
        ; assumptions = List.rev v.facts
        ; goal = in_range result
        }
    in
    let what = describe op in
    (match Refine.discharge ~root vc with
     | Refine.Verified -> true
     | Refine.Refuted model ->
       let shown =
         List.filter
           (fun (x, _) ->
             not (String.contains x '%') && List.mem x v.consts)
           model
       in
       let cx =
         match shown with
         | [] -> ""
         | kvs ->
           " (e.g. "
           ^ String.concat ", " (List.map (fun (k, x) -> k ^ " = " ^ smt_int x) kvs)
           ^ ")"
       in
       Err.error ~code:Err.Code.int_overflow errctx ~span
         (Printf.sprintf
            "this %s may overflow Int in a `cap no_panic` module: nothing in \
             scope keeps the result within [-2^62, 2^62)%s.%s"
            what cx (suggestion op));
       false
     | Refine.Unverified ->
       Err.error ~code:Err.Code.int_overflow errctx ~span
         (Printf.sprintf
            "this %s may overflow Int in a `cap no_panic` module: cannot verify \
             the result stays within [-2^62, 2^62) (Z3 unavailable or the VC \
             is unknown).%s"
            what (suggestion op));
       false)

(* Every site leaves an [Overflow] obligation in the ledger, as every divisor
   leaves a [Division] one (see [Division_safety.check_var_divisor]). *)
let record span op ok =
  Obligation.record
    { Obligation.span; callee = op; predicate = "-2^62 <= _ < 2^62"
    ; verdict = (if ok then Obligation.Proved else Obligation.Violated)
    ; kind = Obligation.Overflow; inst = None }

let check_clause ~root errctx (clause : A.fn_clause) : unit =
  let params = D.clause_refined_params clause in
  let init =
    match clause.A.fc_guard with
    | Some g -> { D.dctx_empty with D.path = [ (g, false) ] }
    | None -> D.dctx_empty
  in
  D.iter_sites
    ~site:(fun e ->
      match site_of e with Some (_, _, sp) -> site_is_int sp | None -> false)
    (fun e c ->
      match site_of e with
      | Some ((op, _, span) as s) -> record span op (check_site ~root errctx params s c)
      | None -> ())
    init clause.A.fc_body

let check_decls ~root errctx (decls : A.decl list) : unit =
  D.check_decls_with ~clause:(check_clause ~root errctx) decls

let check_module ?(root = Sys.getcwd ()) ?type_map:tm (errctx : Err.ctx) (m : A.module_)
  : unit =
  type_map := tm;
  check_decls ~root errctx m.A.mod_decls
