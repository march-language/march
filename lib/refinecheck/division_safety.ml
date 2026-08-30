(* Division-safety checker for `cap no_panic` modules.
   A post-typecheck pass that finds every integer division/modulo operation in
   modules declared `cap no_panic` and verifies — via Z3 — that the divisor
   cannot be zero.  Uses the same definite-failure soundness stance as the
   rest of refinecheck: only flag when we can prove the divisor CAN be zero (or
   when there is no refinement at all).  When Z3 is unavailable or the VC is
   unknown the error is still raised, preserving the guarantee of `cap no_panic`.

   Supported:
   - Literal divisors: 0 → always error; non-zero → always safe.
   - Variable divisors with an Int refinement `{v | pred}`: syntactic fast-path
     for common patterns (v > 0, v >= 1, v != 0, v < 0, …); otherwise a Z3
     discharge, ATTEMPTED even when the predicate does not reflect — an
     unreflectable predicate is outside this file's fragment, not necessarily
     the solver's, and the path conditions alone may settle the goal.  Only a
     genuine non-[Verified] verdict is an error.
   - Variable divisors without a refinement: always error.
   - Complex divisors (arbitrary expressions): always error (conservative). *)

module A = March_ast.Ast
module Smt = March_refine.Smt
module Refine = March_refine.Refine
module Err = March_errors.Errors

let div_ops = [ "/"; "%"; "int_div"; "int_mod"; "int_div_euclid"; "int_mod_euclid" ]

(* ── Syntactic non-zero check (no Z3) ──────────────────────────────────── *)

(* Returns true when [pred] with binder [b] syntactically implies b ≠ 0.
   Handles the common patterns so that z3 absence doesn't force an error for
   the obvious cases (v > 0, v >= 1, v != 0, v < 0). *)
let rec syntactic_nonzero (b : string) (pred : A.expr) : bool =
  let is_b = function A.EVar { A.txt = x; _ } -> x = b || x = "_" | _ -> false in
  let int_of = function A.ELit (A.LitInt n, _) -> Some n | _ -> None in
  match pred with
  | A.EApp (A.EVar { A.txt = op; _ }, [ a; rhs ], _) ->
    (match op with
     (* v > n  where n ≥ 0  ⟹  v > 0  ⟹  v ≠ 0 *)
     | ">" ->
       (is_b a && Option.fold ~none:false ~some:(fun n -> n >= 0) (int_of rhs))
       || (is_b rhs && Option.fold ~none:false ~some:(fun n -> n <= 0) (int_of a))
     (* v >= n  where n ≥ 1  ⟹  v ≠ 0 *)
     | ">=" ->
       (is_b a && Option.fold ~none:false ~some:(fun n -> n >= 1) (int_of rhs))
       || (is_b rhs && Option.fold ~none:false ~some:(fun n -> n <= -1) (int_of a))
     (* v < n  where n ≤ 0  ⟹  v < 0  ⟹  v ≠ 0 *)
     | "<" ->
       (is_b a && Option.fold ~none:false ~some:(fun n -> n <= 0) (int_of rhs))
       || (is_b rhs && Option.fold ~none:false ~some:(fun n -> n >= 0) (int_of a))
     (* v <= n  where n ≤ -1  ⟹  v ≠ 0 *)
     | "<=" ->
       (is_b a && Option.fold ~none:false ~some:(fun n -> n <= -1) (int_of rhs))
       || (is_b rhs && Option.fold ~none:false ~some:(fun n -> n >= 1) (int_of a))
     (* v != 0  directly *)
     | "!=" ->
       (is_b a && int_of rhs = Some 0) || (is_b rhs && int_of a = Some 0)
     (* conjunction: either branch suffices *)
     | "&&" -> syntactic_nonzero b a || syntactic_nonzero b rhs
     | _ -> false)
  | _ -> false

(* ── Minimal SMT reflection of integer predicates ──────────────────────── *)

(* Reflects [e] into an Smt.term, substituting binder [b] with const [var].
   Returns None for anything outside the linear Int/Bool fragment. *)
let rec smt_of ~b ~var (e : A.expr) : Smt.term option =
  let go = smt_of ~b ~var in
  let bin op a rhs =
    match go a, go rhs with
    | Some ta, Some tb -> Some (op ta tb)
    | _ -> None
  in
  match e with
  | A.ELit (A.LitInt n, _) -> Some (Smt.IntLit n)
  | A.ELit (A.LitBool v, _) -> Some (Smt.BoolLit v)
  | A.EVar { A.txt = x; _ } ->
    if x = b || x = "_" then Some (Smt.Const var) else Some (Smt.Const x)
  | A.EApp (A.EVar { A.txt = op; _ }, [ a; rhs ], _) ->
    (match op with
     | "+"  -> bin (fun a b -> Smt.Add (a, b)) a rhs
     | "-"  -> bin (fun a b -> Smt.Sub (a, b)) a rhs
     (* A literal factor stays in linear arithmetic; anything else becomes a
        general [Smt.Mul].  Refusing non-linear products here was a REGRESSION
        source, not a safety measure: `{v : Int | v * v > 0}` is exactly
        `v != 0` over the integers and z3 decides it instantly, yet the
        unreflectable arm below rejected the program.  A product z3 cannot
        decide comes back `unknown` → [Refine.Unverified] → still an error. *)
     | "*"  ->
       (match go a, go rhs with
        | Some (Smt.IntLit k), Some t | Some t, Some (Smt.IntLit k) ->
          Some (Smt.MulLit (k, t))
        | Some ta, Some tb -> Some (Smt.Mul (ta, tb))
        | _ -> None)
     | "==" -> bin (fun a b -> Smt.Eq  (a, b)) a rhs
     | "!=" -> bin (fun a b -> Smt.Ne  (a, b)) a rhs
     | "<"  -> bin (fun a b -> Smt.Lt  (a, b)) a rhs
     | "<=" -> bin (fun a b -> Smt.Le  (a, b)) a rhs
     | ">"  -> bin (fun a b -> Smt.Gt  (a, b)) a rhs
     | ">=" -> bin (fun a b -> Smt.Ge  (a, b)) a rhs
     | "&&" -> bin (fun a b -> Smt.And (a, b)) a rhs
     | "||" -> bin (fun a b -> Smt.Or  (a, b)) a rhs
     | _    -> None)
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) ->
    Option.map (fun t -> Smt.Not t) (go a)
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a ], _) ->
    Option.map (fun t -> Smt.Neg t) (go a)
  | _ -> None

(* True when every symbol [t] mentions has been declared in the VC.  Only the
   shapes [smt_of] can produce are recognised; anything else answers false,
   which drops the assumption — the fail-closed direction, since fewer
   assumptions can only make a goal harder to prove. *)
let rec consts_declared (declared : string list) (t : Smt.term) : bool =
  let both a b = consts_declared declared a && consts_declared declared b in
  match t with
  | Smt.Const x -> List.mem x declared
  | Smt.IntLit _ | Smt.BoolLit _ -> true
  | Smt.Add (a, b) | Smt.Sub (a, b) | Smt.Mul (a, b)
  | Smt.Eq (a, b) | Smt.Ne (a, b)
  | Smt.Lt (a, b) | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b)
  | Smt.And (a, b) | Smt.Or (a, b) | Smt.Implies (a, b) -> both a b
  | Smt.MulLit (_, a) | Smt.Neg a | Smt.Not a -> consts_declared declared a
  | _ -> false

(* ── Param collection ───────────────────────────────────────────────────── *)

(* Returns [(param_name, binder, pred)] for each Int-refined parameter. *)
let clause_refined_params (clause : A.fn_clause) =
  List.filter_map
    (function
      | A.FPNamed { A.param_name; param_ty = Some (A.TyRefine (base, binder, pred)); _ }
        when (match base with A.TyCon ({ A.txt = "Int"; _ }, []) -> true | _ -> false) ->
        let bdr = match binder with None -> "_" | Some n -> n.A.txt in
        Some (param_name.A.txt, bdr, pred)
      | A.FPDefault ({ A.param_name; param_ty = Some (A.TyRefine (base, binder, pred)); _ }, _)
        when (match base with A.TyCon ({ A.txt = "Int"; _ }, []) -> true | _ -> false) ->
        let bdr = match binder with None -> "_" | Some n -> n.A.txt in
        Some (param_name.A.txt, bdr, pred)
      | _ -> None)
    clause.A.fc_params

(* ── Division-site walker ───────────────────────────────────────────────── *)

(* What is known at a division site.  All THREE channels key on a bare variable
   NAME — a path condition is `(d != 0, negated)`, a refined parameter is
   `("d", binder, pred)`, and a `let` value is `("d", rhs)` — so none of them
   survives that name being rebound.  Every binding construct must retire the
   names it shadows before descending, or a fact is attributed to the INNER
   value:

     if d == 0 do 0 else
       let d = 0
       10 / d        -- `not (d == 0)` is about the PARAMETER, not this `d`

   That program passed `--check` and then panicked with "division by zero", as
   did the `fn d -> 10 / d` and `Some(d) -> 10 / d` variants; so did the
   then-side `if d != 0 do (let d = 0; 10 / d)`.

   The direction of error here is the OPPOSITE of the refinement pass's.  There,
   dropping a fact means silence and keeping a stale one means a false positive.
   Here, dropping a fact means an ERROR and keeping a stale one means a division
   that panics inside a module that promised it could not — so over-approximating
   [shadowed] is still the safe direction, but for the opposite reason. *)
type dctx = {
  path : (A.expr * bool) list;    (* guard conditions, with a negated flag *)
  shadowed : string list;         (* names rebound since the parameter scope *)
  lets : (string * A.expr) list;  (* innermost tracked `let` value per name *)
}

let dctx_empty = { path = []; shadowed = []; lets = [] }

(* Retire [names] from every channel. *)
let retire (names : string list) (c : dctx) : dctx =
  if names = [] then c
  else
    { path = Refine_check.path_shadow c.path names
    ; shadowed = names @ c.shadowed
    ; lets = List.filter (fun (n, _) -> not (List.mem n names)) c.lets }

(* `let n = rhs`: retire the old [n] everywhere, then record the new value.
   [n] joins [shadowed] because any refinement or guard about the OUTER `n` is
   now stale; the fresh [lets] entry is what the checker may use instead. *)
let bind_let (n : string) (rhs : A.expr) (c : dctx) : dctx =
  let c = retire [ n ] c in
  { c with lets = (n, rhs) :: c.lets }

(* Names an [A.ELam] / [A.ELetFn] parameter list binds. *)
let lam_param_names (ps : A.param list) : string list =
  List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps

(* The names a block statement binds for the REST of the block, and how. *)
let stmt_binding (c : dctx) (stmt : A.expr) : dctx =
  match stmt with
  | A.ELet (b, _) ->
    (match b.A.bind_pat with
     | A.PatVar n -> bind_let n.A.txt b.A.bind_expr c
     (* A destructuring pattern binds names whose values this pass does not
        track: retire them and offer nothing in exchange. *)
     | p -> retire (Refine_check.pat_binders p) c)
  | A.ELetFn (n, _, _, _, _) -> retire [ n.A.txt ] c
  | _ -> c

(* Calls [f span divisor_expr ctx] for every integer division/modulo site. *)
let rec iter_div_sites
    (f : A.span -> A.expr -> dctx -> unit) (c : dctx) (e : A.expr) : unit =
  let go e = iter_div_sites f c e in
  let under names e = iter_div_sites f (retire names c) e in
  match e with
  | A.EApp (A.EVar { A.txt = op; _ }, [ lhs; rhs ], sp) when List.mem op div_ops ->
    f sp rhs c;
    go lhs;
    go rhs
  | A.EApp (fn, args, _) ->
    go fn; List.iter go args
  | A.ECon (_, args, _) | A.ETuple (args, _) | A.EAtom (_, args, _) ->
    List.iter go args
  | A.ERecord (fields, _) ->
    List.iter (fun (_, e) -> go e) fields
  | A.ERecordUpdate (r, fields, _) ->
    go r; List.iter (fun (_, e) -> go e) fields
  (* A `let` (or local `fn`) binds for the REST of the block, so the context is
     THREADED through the statements rather than one being reused for all of
     them.  Each statement is walked in the context that PRECEDES it, so a
     binding does not shadow its own right-hand side (`let d = 10 / d` divides
     by the outer `d`).  This also means only the `let`s that actually precede
     a division are visible to it; the pre-pass this replaced collected the
     whole block, including bindings written after the division site. *)
  | A.EBlock (es, _) ->
    ignore
      (List.fold_left
         (fun c stmt -> iter_div_sites f c stmt; stmt_binding c stmt)
         c es)
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.EMatch (scrut, arms, _) ->
    go scrut;
    List.iter
      (fun (arm : A.branch) ->
        (* Pattern binders are in scope for the guard as well as the body. *)
        let ac = retire (Refine_check.pat_binders arm.A.branch_pat) c in
        Option.iter (iter_div_sites f ac) arm.A.branch_guard;
        let ac =
          match arm.A.branch_guard with
          | Some g -> { ac with path = (g, false) :: ac.path }
          | None -> ac
        in
        iter_div_sites f ac arm.A.branch_body)
      arms
  | A.EIf (cond, t, e, _) ->
    go cond;
    iter_div_sites f { c with path = (cond, false) :: c.path } t;
    iter_div_sites f { c with path = (cond, true) :: c.path } e
  | A.ECond (arms, _) ->
    List.iter
      (fun (cond, b) ->
        go cond;
        iter_div_sites f { c with path = (cond, false) :: c.path } b)
      arms
  | A.EField (inner, _, _) -> go inner
  | A.EPipe (a, b, _) -> go a; go b
  | A.EAnnot (inner, _, _) -> go inner
  | A.ELam (ps, body, _) -> under (lam_param_names ps) body
  (* A local `fn go(...)` binds its own name (it may recurse) and its
     parameters throughout its body. *)
  | A.ELetFn (n, ps, _, body, _) -> under (n.A.txt :: lam_param_names ps) body
  | A.ELetQ (p, rhs, body, _) | A.ELetStar (p, rhs, body, _) ->
    go rhs; under (Refine_check.pat_binders p) body
  | A.EAssert (inner, _) -> go inner
  | A.ESend (cap, msg, _) -> go cap; go msg
  | A.ESpawn (inner, _) -> go inner
  | A.EDbg (e_opt, _) -> Option.iter go e_opt
  | A.ESigil (_, inner, _) -> go inner
  | A.EVar _ | A.ELit _ | A.EHole _ | A.EResultRef _ -> ()

(* ── Per-divisor VC ─────────────────────────────────────────────────────── *)

let division_suggestion =
  "\n\nUse `Math.checked_div` or `Math.checked_mod` to return `Option(Int)` \
   instead of panicking, or annotate the divisor parameter with \
   `{v : Int | v != 0}` (or `v > 0`) to prove it is safe."

(* Syntactically check whether path conditions prove [var] ≠ 0.

   NEGATED conditions count.  `path` carries `(cond, negated)`, where `negated`
   marks the ELSE side of an `if`; on that side the fact in scope is `not cond`.
   Ignoring those entries — as this used to — made the syntactic fallback
   asymmetric with the z3 path below, which reflects negations properly, so
   `if d == 0 do 0 else 10 / d end` was reported even though the guard alone
   makes the division unreachable with zero.  A negated comparison is handled by
   dualising the operator (`==` ↦ `!=`, `<` ↦ `>=`, …), which is exact for the
   total orders involved.

   BOOLEAN CONNECTIVES count too.  Matching only an atomic comparison meant any
   `&&`/`||` anywhere in the guard defeated this — including `if p > 0 && d > 0
   do n / d`, the most idiomatic safe spelling there is, and including a
   disjunction over the divisor itself.  The divisor then fell through to the
   unrefined arm and `cap no_panic` reported a division the guard makes
   unreachable: a FALSE POSITIVE, and a hard error rather than a hint.  (Found
   by running this pass over forgepm, whose metrics module has exactly the
   `if prev <= 0 || dt <= 0 do 0 else … / dt` shape.)

   The polarity is the entire content of the rule, so state it explicitly.  A
   path entry is a FACT — `cond` when not negated, `not cond` when negated —
   and the question is whether that fact entails `var ≠ 0`:

     - a CONJUNCTIVE fact is proved by EITHER side (one true conjunct is enough);
     - a DISJUNCTIVE fact is proved only if BOTH sides prove it independently,
       since either arm may be the one that holds.

   De Morgan decides which is which: `A && B` is conjunctive un-negated and
   disjunctive negated, `A || B` the reverse — i.e. conjunctive exactly when
   `(op = "&&") <> negated`.  Both arms inherit the SAME negation flag
   (`¬(A ∧ B) = ¬A ∨ ¬B`), so polarity threads through unchanged; only the
   combinator flips.  Getting this backwards would be unsound rather than
   merely incomplete, which is why each direction has a negative control in the
   `divsafety-boolean-guard` suite.

   Anything that is neither a connective nor a recognised comparison still
   answers false — fail-closed, as before. *)
let path_proves_nonzero (var : string) (path : (A.expr * bool) list) : bool =
  (* `not (a op b)` ⟺ `a (dual op) b` *)
  let dual = function
    | "==" -> Some "!=" | "!=" -> Some "=="
    | "<"  -> Some ">=" | ">=" -> Some "<"
    | ">"  -> Some "<=" | "<=" -> Some ">"
    | _ -> None
  in
  (* `a op b` ⟺ `b (flipped op) a` — used to normalise to `var op literal`. *)
  let flip = function
    | "<" -> ">" | ">" -> "<" | "<=" -> ">=" | ">=" -> "<="
    | op -> op (* == and != are symmetric *)
  in
  (* Does `var op n` imply var ≠ 0? *)
  let proves op n =
    match op with
    | "!=" -> n = 0
    | "==" -> n <> 0
    | ">"  -> n >= 0
    | ">=" -> n >= 1
    | "<"  -> n <= 0
    | "<=" -> n <= -1
    | _ -> false
  in
  (* A single comparison, under the given polarity. *)
  let atomic op0 a b negated =
    let is_var e =
      match e with A.EVar { A.txt = x; _ } -> x = var | _ -> false
    in
    let int_of e = match e with A.ELit (A.LitInt n, _) -> Some n | _ -> None in
    (* Normalise to `var op n`, then dualise if we are on the else side. *)
    let normalised =
      match int_of b, int_of a with
      | Some n, _ when is_var a -> Some (op0, n)
      | _, Some n when is_var b -> Some (flip op0, n)
      | _ -> None
    in
    match normalised with
    | None -> false
    | Some (op, n) ->
      (match (if negated then dual op else Some op) with
       | None -> false
       | Some op -> proves op n)
  in
  (* Does the fact [cond] (negated when [negated]) entail `var ≠ 0`? *)
  let rec entails (cond : A.expr) (negated : bool) : bool =
    match cond with
    | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) -> entails a (not negated)
    | A.EApp (A.EVar { A.txt = ("&&" | "||") as op; _ }, [ a; b ], _) ->
      if (op = "&&") <> negated then
        (* conjunctive fact: one side suffices *)
        entails a negated || entails b negated
      else
        (* disjunctive fact: every arm must prove it on its own *)
        entails a negated && entails b negated
    | A.EApp (A.EVar { A.txt = op0; _ }, [ a; b ], _) -> atomic op0 a b negated
    | _ -> false
  in
  List.exists (fun (cond, negated) -> entails cond negated) path

(* [c.shadowed] names have been rebound since the parameter scope, so a
   refinement declared on the parameter of that name says nothing about the
   value being divided by.  Retiring them here is what stops
   `if d != 0 do (let d = 0; 10 / d)` — and its `fn d -> …` and `Some(d) -> …`
   siblings — from reading the outer fact. *)
(* [check_var_divisor], wrapped so every variable divisor leaves a trace in the
   obligation ledger.

   Why it matters: `Precond_infer` measures a function's debt by counting that
   ledger, and division safety is a SEPARATE pass from [Refine_check].  With
   nothing recorded here, a `cap no_panic` module whose only problem is
   `n / d` counted as zero debt, so `--refine-suggest-all` had nothing to
   shrink and printed "no suggestions" — for the one case where the compiler's
   own error already names the fix.

   The verdict is read off the error context rather than threaded back through
   [check_var_divisor]'s many exit paths: under `cap no_panic` anything short
   of proof IS an error (there is no [Skipped] middle ground the way there is
   for a precondition), so "did this call report?" is exactly the verdict.
   Note [Err.report] suppresses an exact duplicate, but two divisions never
   share a span, so a genuine second obligation can never be swallowed. *)
let rec check_var_divisor ~root errctx span var_name all_params (c : dctx) =
  let before = List.length errctx.Err.diagnostics in
  check_var_divisor_inner ~root errctx span var_name all_params c;
  let verdict =
    if List.length errctx.Err.diagnostics = before then Obligation.Proved
    else Obligation.Violated
  in
  Obligation.record
    { Obligation.span; callee = var_name; predicate = "_ != 0"; verdict
    ; kind = Obligation.Division }

and check_var_divisor_inner ~root errctx span var_name all_params (c : dctx) =
  let params =
    List.filter (fun (n, _, _) -> not (List.mem n c.shadowed)) all_params
  in
  let path = c.path and let_values = c.lets in
  match List.find_opt (fun (n, _, _) -> n = var_name) params with
  | None ->
    if path_proves_nonzero var_name path then ()
    else
      (* Not a refined parameter — check let-binding scope. *)
      (match List.assoc_opt var_name let_values with
       | Some (A.ELit (A.LitInt 0, _)) ->
         Err.error errctx ~span
           "division by zero literal in `cap no_panic` module."
       | Some (A.ELit (A.LitInt _, _)) ->
         () (* non-zero literal let-binding: trivially safe *)
       | Some rhs ->
         (match smt_of ~b:"\x00" ~var:"\x00" rhs with
          | None ->
            Err.error errctx ~span
              (Printf.sprintf
                 "division by `%s` in `cap no_panic` module may be by zero — \
                  bound expression cannot be verified non-zero.%s"
                 var_name division_suggestion)
          | Some rhs_term ->
            let param_decls =
              List.map (fun (n, _, _) -> (n, Smt.SInt)) params
            in
            let param_assumes =
              List.filter_map
                (fun (n, bdr, pred) -> smt_of ~b:bdr ~var:n pred)
                params
            in
            let vc =
              Smt.
                { decls = (var_name, Smt.SInt) :: param_decls
                ; assumptions =
                    Smt.Eq (Smt.Const var_name, rhs_term) :: param_assumes
                ; goal = Smt.Ne (Smt.Const var_name, Smt.IntLit 0)
                }
            in
            (match Refine.discharge ~root vc with
             | Refine.Verified -> ()
             | _ ->
               Err.error errctx ~span
                 (Printf.sprintf
                    "division by `%s` in `cap no_panic` module may be by zero — \
                     cannot prove bound expression is non-zero.%s"
                    var_name division_suggestion)))
       | None ->
         Err.error errctx ~span
           (Printf.sprintf
              "division by `%s` in `cap no_panic` module may be by zero — \
               no refinement proves `%s ≠ 0`.%s"
              var_name var_name division_suggestion))
  | Some (_, bdr, pred) ->
    (* Two z3-free fast paths first, so the obvious cases still discharge on a
       machine with no solver. *)
    if syntactic_nonzero bdr pred then ()
    else if path_proves_nonzero var_name path then ()
    else begin
      (* Whether or not the refinement itself reflects, ATTEMPT the discharge:
         an unreflectable predicate is outside *this file's* fragment, not
         necessarily outside z3's, and the path conditions alone may settle the
         obligation.  What must not change is the stance — `cap no_panic` is a
         guarantee, so anything short of [Refine.Verified] is an error.  The
         reflection failure only picks the wording. *)
      let refinement = smt_of ~b:bdr ~var:var_name pred in
      (* Every Int-refined parameter is a declared Int const whose refinement is
         a fact in scope; [var_name] is one of them (we just found it). *)
      let decls = List.map (fun (n, _, _) -> (n, Smt.SInt)) params in
      let declared = List.map fst decls in
      (* Both assumption channels are filtered the same way: a term mentioning
         a symbol this VC did not declare is DROPPED rather than sent.  z3's
         reply to an ill-sorted assertion is an `(error …)` that
         [Solver.read_verdict] consumes and reports as `Unknown`, so sending one
         does not break the channel — it just forces the whole query to
         [Refine.Unverified], turning an answerable question into a guaranteed
         failure.  A sibling parameter refined against an undeclared name
         (`a : {v : Int | v > k}`) used to poison the divisor's query that way.
         Dropping an assumption can only make the goal harder to prove, so this
         stays fail-closed. *)
      let param_assumes =
        List.filter_map
          (fun (n, b, p) ->
            match smt_of ~b ~var:n p with
            | Some t when consts_declared declared t -> Some t
            | _ -> None)
          params
      in
      let path_assumes =
        List.filter_map
          (fun (cond, negated) ->
            match smt_of ~b:"\x00" ~var:"\x00" cond with
            | Some t when consts_declared declared t ->
              Some (if negated then Smt.Not t else t)
            | _ -> None)
          path
      in
      let vc =
        Smt.
          { decls
          ; assumptions = param_assumes @ path_assumes
          ; goal = Smt.Ne (Smt.Const var_name, Smt.IntLit 0)
          }
      in
      (* A Refuted verdict carries a model; when the witness validator
         confirms it (params satisfy their own refinements, path facts hold,
         divisor evaluates to zero), the error names the concrete admissible
         input.  An unconfirmable model keeps the bare wording. *)
      let div_cx model =
        match Witness.confirm_div ~params ~path ~divisor:var_name ~model with
        | Some entries ->
          (match Witness.render_entries entries with
           | Some s -> Printf.sprintf " (e.g. %s)" s
           | None -> "")
        | None -> ""
      in
      match Refine.discharge ~root vc, refinement with
      | Refine.Verified, _ -> () (* z3: the facts in scope prove divisor ≠ 0 *)
      | Refine.Refuted model, None ->
        (* An unreflectable predicate is NOT a proof.  Treating it as one made a
           meaningless refinement more permissive than no refinement at all —
           `{Int | is_prime(_)}` passed while a bare `Int` divisor correctly
           errored. *)
        Err.error errctx ~span
          (Printf.sprintf
             "division by `%s` in `cap no_panic` module: the refinement on \
              `%s` is outside the checkable fragment, so it cannot prove \
              `%s != 0`.%s%s"
             var_name var_name var_name (div_cx model) division_suggestion)
      | Refine.Unverified, None ->
        Err.error errctx ~span
          (Printf.sprintf
             "division by `%s` in `cap no_panic` module: the refinement on \
              `%s` is outside the checkable fragment, so it cannot prove \
              `%s != 0`.%s"
             var_name var_name var_name division_suggestion)
      | Refine.Refuted model, Some _ ->
        Err.error errctx ~span
          (Printf.sprintf
             "division by `%s` in `cap no_panic` module: refinement \
              does not rule out zero%s.%s"
             var_name (div_cx model) division_suggestion)
      | Refine.Unverified, Some _ ->
        (* Z3 absent or unknown — be conservative *)
        Err.error errctx ~span
          (Printf.sprintf
             "division by `%s` in `cap no_panic` module: cannot verify \
              divisor is non-zero (Z3 unavailable or VC unknown).%s"
             var_name division_suggestion)
    end

(* ── Per-clause check ───────────────────────────────────────────────────── *)

let check_clause ~root errctx (clause : A.fn_clause) : unit =
  let params = clause_refined_params clause in
  let init =
    match clause.A.fc_guard with
    | Some g -> { dctx_empty with path = [ (g, false) ] }
    | None -> dctx_empty
  in
  iter_div_sites
    (fun span divisor c ->
      match divisor with
      | A.ELit (A.LitInt 0, _) ->
        Err.error errctx ~span
          "division by zero literal in `cap no_panic` module."
      | A.ELit (A.LitInt _, _) ->
        () (* non-zero literal: trivially safe *)
      | A.EVar { A.txt = var_name; _ } ->
        check_var_divisor ~root errctx span var_name params c
      | _ ->
        (* Complex expression — always flag conservatively *)
        Err.error errctx ~span
          ("division by a complex expression in `cap no_panic` module: \
            cannot prove divisor is non-zero."
           ^ division_suggestion))
    init
    clause.A.fc_body

let check_fn ~root errctx (fd : A.fn_def) : unit =
  List.iter (check_clause ~root errctx) fd.A.fn_clauses

(* A body that is not a function clause — a top-level `let`, an actor handler,
   a `test` body.  [params] carries whatever bindings ARE in scope (an actor
   handler's parameters may be refined); everything else is empty, so the
   divisor can only be discharged by a literal, a path condition, or a `let`
   value collected from the body itself. *)
let check_body ~root errctx (params : A.fn_param list) (body : A.expr) : unit =
  check_clause ~root errctx
    { A.fc_params = params; A.fc_guard = None; A.fc_body = body;
      A.fc_span = A.dummy_span; A.fc_params_span = A.dummy_span }

(* ── Module-level walk ──────────────────────────────────────────────────── *)

let rec check_decls ~root errctx (decls : A.decl list) : unit =
  let no_panic =
    List.exists
      (function A.DOpts (opts, _) -> List.mem "no_panic" opts | _ -> false)
      decls
  in
  (* Which `impl` method contracts callers are actually obliged to establish.
     Shared with [Refine_check] so the two passes cannot drift: a divisor
     refinement on an impl method may discharge a division HERE only if the
     same rule made it visible to callers THERE. *)
  let adoptable = Refine_check.adoptable_impl_methods decls in
  List.iter (check_decl ~root errctx ~no_panic ~adoptable) decls

(* One declaration.  Every constructor of [A.decl] is named — there is NO
   wildcard, deliberately.  This walk used to descend only into [DFn] and
   [DMod] and end in `| _ -> ()`, so `cap no_panic` promised nothing about a
   division inside an `impl` method, a top-level `let`, or an actor handler:
   `100 / n` in an impl body passed `--check` silently and then panicked with
   "division by zero" at run time.  Exhaustive, a 25th decl form is a COMPILE
   ERROR here rather than another silent hole. *)
and check_decl ~root errctx ~no_panic ~adoptable (d : A.decl) : unit =
  let body params e = if no_panic then check_body ~root errctx params e in
  let expr e = body [] e in
  match d with
  | A.DFn (fd, _) -> if no_panic then check_fn ~root errctx fd
  (* A nested module re-derives its own `cap` directive: capabilities do not
     inherit inward (bin/main.ml prepends the whole stdlib as sibling DMods). *)
  | A.DMod (_, _, inner_decls, _) -> check_decls ~root errctx inner_decls
  (* A `describe` block is part of its module's scope, so unlike DMod it
     INHERITS [no_panic] rather than re-deriving it from its own decl list —
     which carries no `cap` directive and would silently disable the check. *)
  | A.DDescribe (_, ds, _) -> List.iter (check_decl ~root errctx ~no_panic ~adoptable) ds
  (* A divisor refinement declared on an `impl` method is a fact only if some
     caller is obliged to establish it.  When the method name is ambiguous (a
     `fn` owns it, or two impls define it) nothing obliges anyone, so the
     refinement is STRIPPED and the division must prove itself some other way.
     Otherwise `fn run(b, k : {Int | k != 0})` would discharge `m / k` while
     `run(Box(4), 0)` sailed through — the exact assume-without-check this
     capability exists to prevent. *)
  | A.DImpl (idf, _) ->
    if no_panic then
      List.iter
        (fun ((mn : A.name), (fd : A.fn_def)) ->
          check_fn ~root errctx
            (if List.mem mn.A.txt adoptable then fd
             else Refine_check.strip_param_refinements fd))
        idf.A.impl_methods
  | A.DInterface (idf, _) ->
    (* Default method bodies are real code; the signatures are not. *)
    List.iter
      (fun (m : A.method_decl) -> Option.iter expr m.A.md_default)
      idf.A.iface_methods
  | A.DLet (_, b, _) -> expr b.A.bind_expr
  | A.DActor (_, _, ad, _) ->
    expr ad.A.actor_init;
    List.iter
      (fun (h : A.actor_handler) ->
        body (List.map (fun p -> A.FPNamed p) h.A.ah_params) h.A.ah_body)
      ad.A.actor_handlers;
    Option.iter expr ad.A.actor_invariant
  | A.DApp (app, _) ->
    expr app.A.app_body;
    Option.iter expr app.A.app_on_start;
    Option.iter expr app.A.app_on_stop
  | A.DTest (t, _) -> expr t.A.test_body
  | A.DSetup (e, _) | A.DSetupAll (e, _) -> expr e
  (* ── Inert: no expression in which a division can appear.  Named
     individually so a new decl form breaks the build here. ─────────────── *)
  | A.DType _                (* type definitions: types only, no terms *)
  | A.DAlwaysLinearType _    (* likewise, plus a linearity marker *)
  | A.DSig _                 (* module signature: names and types only *)
  | A.DProtocol _            (* session type: message types, no bodies *)
  | A.DTransitions _         (* state-machine edges: names of fns declared elsewhere *)
  | A.DExtern _              (* FFI declarations: signatures, bodies live in C *)
  | A.DNeeds _               (* capability manifest: capability paths *)
  | A.DProofCap _            (* proof-capability declaration: a name *)
  | A.DOpts _                (* the `cap` directive itself, read above *)
  | A.DDeriving _            (* desugared into DImpl before this pass runs *)
  | A.DSatisfy _             (* likewise desugared into DImpl *)
  | A.DUse _                 (* import: no expressions *)
  | A.DAlias _ -> ()         (* alias: no expressions *)

let check_module ?(root = Sys.getcwd ()) (errctx : Err.ctx) (m : A.module_) : unit =
  (* No-op when [Refine_check.check_module] already registered this module
     (the production pipeline); makes the pass self-sufficient when driven
     directly (tests, tools). *)
  Witness.set_module m;
  check_decls ~root errctx m.A.mod_decls
