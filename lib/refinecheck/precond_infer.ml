(* Precondition inference: propose a parameter refinement that discharges the
   obligations a function's own body leaves unproven.

   ── Why this is "assume and re-check", not a second VC generator ───────────
   The obligation ledger ([Obligation.t]) records a span, a callee, a predicate
   and a verdict — it does NOT record which PARAMETER is to blame, and there is
   no honest way to recover that after the fact (an argument is an arbitrary
   expression over several parameters).  So this module does not attribute
   anything.  It hypothesises a refinement, re-runs the REAL checker over the
   function, and asks the ledger whether the debt shrank.

   That is the whole design, and the property it buys is the important one: a
   suggestion is accepted only because [Refine_check] itself proved the
   obligations under it, so `march --check` after applying the suggestion says
   exactly what this tool predicted.  There is no parallel implementation of VC
   generation to drift out of sync — the failure mode that a "suggest" tool
   would otherwise develop silently, since a wrong suggestion still looks like
   a suggestion.

   ── Cost ──────────────────────────────────────────────────────────────────
   A full [Refine_check.check_module] is ~1s, almost all of it parsing and
   registering the stdlib, and probing needs tens of re-checks.  So the caller
   runs [check_module] ONCE (which leaves every registration global — ADT
   tables, measure preamble, alias gates — populated), and each probe re-walks
   a PRUNED decl tree holding only the target function plus the context-bearing
   decls of its enclosing modules ([prune]).  Each probe is then a handful of
   Z3 queries, most of which the content-addressed VC cache answers.

   ── What "silence" means here ─────────────────────────────────────────────
   No suggestion is not "the function is fine": it may mean the grammar below
   has nothing that fits.  [status] distinguishes the cases so the CLI never
   has to report an ambiguous silence — the same discipline [Obligation] exists
   to enforce for the checker proper. *)

module A = March_ast.Ast
module Err = March_errors.Errors
module Ob = Obligation
module RC = Refine_check

(* ── Candidates ───────────────────────────────────────────────────────────── *)

(* A candidate carries BOTH its surface text and its AST, built side by side.
   They must agree: the text is what `--apply` writes into the source, the AST
   is what the prover saw.  [test_precond_infer_candidate_text_parses] parses
   every [c_text] and compares it to [c_pred] so a typo in one cannot ship. *)
type candidate = {
  c_text : string;                 (* predicate as written, with `_` as the binder *)
  c_pred : A.span -> A.expr;       (* same predicate as AST, spans set to the param's *)
}

let evar sp txt = A.EVar { A.txt; A.span = sp }
let bin sp op a b = A.EApp (evar sp op, [ a; b ], sp)
let call1 sp f a = A.EApp (evar sp f, [ a ], sp)
let ilit sp n = A.ELit (A.LitInt n, sp)
let flit sp f = A.ELit (A.LitFloat f, sp)
let hole sp = evar sp "_"

(* Int candidates, ordered WEAKEST FIRST.  The order is the tie-break rule: when
   several candidates discharge the same obligations, the earliest wins, so the
   proposal is the one that rejects the fewest callers.  `_ != 0` leads because a
   divisor contract should not also forbid negatives; `_ >= 0` precedes `_ > 0`
   for the same reason. *)
let int_candidates ~(measurable : string list) : candidate list =
  let basics =
    [ ("_ != 0", fun sp -> bin sp "!=" (hole sp) (ilit sp 0));
      ("_ >= 0", fun sp -> bin sp ">=" (hole sp) (ilit sp 0));
      ("_ > 0",  fun sp -> bin sp ">"  (hole sp) (ilit sp 0));
      ("_ <= 0", fun sp -> bin sp "<=" (hole sp) (ilit sp 0));
      ("_ < 0",  fun sp -> bin sp "<"  (hole sp) (ilit sp 0)) ]
  in
  (* Index contracts, one family per List/String parameter in the same clause.
     `_ < len(xs)` before the conjunction: it is strictly weaker, and where the
     non-negativity is already implied it is the honest proposal. *)
  let indexed =
    List.concat_map
      (fun l ->
        [ (Printf.sprintf "_ < len(%s)" l,
           fun sp -> bin sp "<" (hole sp) (call1 sp "len" (evar sp l)));
          (Printf.sprintf "_ >= 0 && _ < len(%s)" l,
           fun sp ->
             bin sp "&&"
               (bin sp ">=" (hole sp) (ilit sp 0))
               (bin sp "<" (hole sp) (call1 sp "len" (evar sp l)))) ])
      measurable
  in
  List.map (fun (c_text, c_pred) -> { c_text; c_pred }) (basics @ indexed)

let float_candidates : candidate list =
  List.map
    (fun (c_text, c_pred) -> { c_text; c_pred })
    [ ("_ != 0.0", fun sp -> bin sp "!=" (hole sp) (flit sp 0.0));
      ("_ >= 0.0", fun sp -> bin sp ">=" (hole sp) (flit sp 0.0));
      ("_ > 0.0",  fun sp -> bin sp ">"  (hole sp) (flit sp 0.0)) ]

(* `len` is the measure for both List and String (the String meaning is chosen
   from the DECLARED type — see [Refine_check.fn_sig.param_str] — never guessed). *)
let measured_candidates : candidate list =
  [ { c_text = "len(_) > 0";
      c_pred = (fun sp -> bin sp ">" (call1 sp "len" (hole sp)) (ilit sp 0)) } ]

(* ── Parameter classification ─────────────────────────────────────────────── *)

type kind = KInt | KFloat | KList | KString | KOther

let kind_of_ty (t : A.ty) : kind =
  match t with
  | A.TyCon ({ A.txt = "Int"; _ }, []) -> KInt
  | A.TyCon ({ A.txt = "Float"; _ }, []) -> KFloat
  | A.TyCon ({ A.txt = "String"; _ }, []) -> KString
  | A.TyCon ({ A.txt = "List"; _ }, [ _ ]) -> KList
  | _ -> KOther

(* Render a base type back to source.  Deliberately partial: a type this cannot
   spell is a type `--apply` must not rewrite, so [None] suppresses the whole
   suggestion rather than producing an approximate annotation. *)
let rec ty_text (t : A.ty) : string option =
  match t with
  | A.TyCon (n, []) -> Some n.A.txt
  | A.TyCon (n, args) ->
    let parts = List.map ty_text args in
    if List.exists (fun p -> p = None) parts then None
    else
      Some
        (Printf.sprintf "%s(%s)" n.A.txt
           (String.concat ", " (List.map Option.get parts)))
  | A.TyVar n -> Some n.A.txt
  | A.TyTuple ts ->
    let parts = List.map ty_text ts in
    if List.exists (fun p -> p = None) parts then None
    else Some (Printf.sprintf "(%s)" (String.concat ", " (List.map Option.get parts)))
  | _ -> None

(* Named parameters of a clause, with their declared type.  A pattern parameter
   (`fn fib(0)`) has no name to annotate and a parameter with no annotation has
   no base type to refine — both are simply not candidates. *)
let named_params (c : A.fn_clause) : (string * A.ty) list =
  List.filter_map
    (function
      | A.FPNamed { A.param_name; param_ty = Some t; _ }
      | A.FPDefault ({ A.param_name; param_ty = Some t; _ }, _) ->
        Some (param_name.A.txt, t)
      | _ -> None)
    c.A.fc_params

let already_refined (t : A.ty) : bool =
  match t with A.TyRefine _ -> true | _ -> false

(* ── Contracts that contradict the function's own intent ──────────────────── *)

(* A candidate can be provably debt-discharging and still be the WRONG advice.

   Found on the real stdlib: `Stats.mean_safe(xs : List(Float))` is documented
   "returning Err on empty list" and opens with `match xs do Nil -> Err(…)`.
   Its `_` arm calls `mean(xs)`, whose `len > 0` precondition the checker cannot
   derive from "the Nil arm was excluded" — so there IS real debt, and
   `{List(Float) | len(_) > 0}` does discharge it.  It also forbids the exact
   input the function exists to accept, makes the `Nil` arm dead, and moves the
   obligation onto every caller.  Three of the four suggestions in a full
   stdlib sweep were this shape.

   The distinction that matters is what the excluded case DOES.  A branch that
   returns `Err`/`None`/a value is the author handling the input deliberately —
   a contract forbidding it contradicts them.  A branch that PANICS is the
   opposite: turning that runtime panic into a compile error is the entire
   point of a refinement, so those must still be proposed.

   v1 covers the case that fires on real code: a `len`-bearing candidate on a
   parameter whose own `match` has an empty-list arm.  The analogous Int guard
   (an `if n <= 0 do Err(…)` shape) is not covered yet — see the todo. *)

let rec mentions_panic (e : A.expr) : bool =
  match e with
  | A.EApp (A.EVar { A.txt = ("panic" | "raise" | "exit" | "todo"); _ }, _, _) -> true
  | A.EApp (f, args, _) -> mentions_panic f || List.exists mentions_panic args
  | A.EBlock (es, _) -> List.exists mentions_panic es
  | A.ELet (b, _) -> mentions_panic b.A.bind_expr
  | A.EIf (c, t, f, _) -> mentions_panic c || mentions_panic t || mentions_panic f
  | A.EMatch (s, brs, _) ->
    mentions_panic s
    || List.exists (fun (br : A.branch) -> mentions_panic br.A.branch_body) brs
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) -> mentions_panic e
  | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) ->
    List.exists mentions_panic es
  | A.ELam (_, b, _) | A.ELetFn (_, _, _, b, _) -> mentions_panic b
  | A.EPipe (a, b, _) -> mentions_panic a || mentions_panic b
  | _ -> false

(* Does this pattern match the empty list? *)
let rec is_empty_list_pat (p : A.pattern) : bool =
  match p with
  | A.PatCon ({ A.txt = "Nil"; _ }, []) -> true
  (* `[]` desugars to the `Nil` constructor, so the literal form needs no case
     of its own; an or-pattern counts if any alternative does. *)
  | A.PatOr (ps, _) -> List.exists is_empty_list_pat ps
  | A.PatAs (p, _, _) -> is_empty_list_pat p
  | _ -> false

(* Walk [e] for `match <param> do … end` and report whether an empty-list arm
   exists that handles the case NON-fatally. *)
let rec handles_empty_nonfatally (param : string) (e : A.expr) : bool =
  let sub = handles_empty_nonfatally param in
  match e with
  | A.EMatch (A.EVar { A.txt = s; _ }, brs, _) when s = param ->
    List.exists
      (fun (br : A.branch) ->
        is_empty_list_pat br.A.branch_pat && not (mentions_panic br.A.branch_body))
      brs
    || List.exists (fun (br : A.branch) -> sub br.A.branch_body) brs
  | A.EMatch (s, brs, _) ->
    sub s || List.exists (fun (br : A.branch) -> sub br.A.branch_body) brs
  | A.EBlock (es, _) -> List.exists sub es
  | A.ELet (b, _) -> sub b.A.bind_expr
  | A.EIf (c, t, f, _) -> sub c || sub t || sub f
  | A.EApp (f, args, _) -> sub f || List.exists sub args
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) -> sub e
  | A.ELam (_, b, _) | A.ELetFn (_, _, _, b, _) -> sub b
  | A.EPipe (a, b, _) -> sub a || sub b
  | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) -> List.exists sub es
  | _ -> false

(* [true] when proposing [cand] for [param] would forbid an input the function
   visibly handles on purpose. *)
let contradicts_handled_case (fd : A.fn_def) ~(param : string) (cand : candidate)
    : bool =
  let excludes_empty =
    (* Every measured candidate is a lower bound on `len`, so all of them
       exclude the empty collection. *)
    String.length cand.c_text >= 4 && String.sub cand.c_text 0 4 = "len("
  in
  excludes_empty
  && List.exists
       (fun (c : A.fn_clause) -> handles_empty_nonfatally param c.A.fc_body)
       fd.A.fn_clauses

(* ── AST surgery ──────────────────────────────────────────────────────────── *)

(* Attach [mk]'s predicate to [param]'s declared type in every clause.  The
   binder is [None] (the implicit `_`), matching every candidate's text. *)
let with_refinement (fd : A.fn_def) ~(param : string) ~(mk : A.span -> A.expr) :
    A.fn_def =
  let upd_param (p : A.param) : A.param =
    if p.A.param_name.A.txt <> param then p
    else
      match p.A.param_ty with
      | Some base when not (already_refined base) ->
        { p with
          A.param_ty = Some (A.TyRefine (base, None, mk p.A.param_name.A.span)) }
      | _ -> p
  in
  let upd_fp = function
    | A.FPNamed p -> A.FPNamed (upd_param p)
    | A.FPDefault (p, e) -> A.FPDefault (upd_param p, e)
    | other -> other
  in
  { fd with
    A.fn_clauses =
      List.map
        (fun (c : A.fn_clause) ->
          { c with A.fc_params = List.map upd_fp c.A.fc_params })
        fd.A.fn_clauses }

(* Decls that carry CONTEXT for the walk rather than work: imports and aliases
   decide callee resolution, `cap` directives decide escalation.  Types and
   ADTs are absent on purpose — [Refine_check.check_module] registered those
   globally before we were called, and re-walking them would cost the stdlib. *)
let context_decls (decls : A.decl list) : A.decl list =
  List.filter
    (function A.DUse _ | A.DAlias _ | A.DNeeds _ | A.DOpts _ -> true | _ -> false)
    decls

(* Locate the function at [path]/[name] and return it together with a rebuilder
   that puts a REPLACEMENT function back at the same place in a decl tree that
   holds nothing else.  The rebuilder is what makes probing cheap. *)
let rec prune (path : string list) (name : string) (decls : A.decl list) :
    (A.fn_def * (A.fn_def -> A.decl list)) option =
  match path with
  | [] ->
    let rec find = function
      | [] -> None
      | A.DFn (fd, sp) :: _ when fd.A.fn_name.A.txt = name ->
        Some (fd, fun fd' -> context_decls decls @ [ A.DFn (fd', sp) ])
      | _ :: tl -> find tl
    in
    find decls
  | m :: rest ->
    let rec find = function
      | [] -> None
      | A.DMod (n, vis, inner, sp) :: _ when n.A.txt = m ->
        (match prune rest name inner with
         | None -> None
         | Some (fd, mk) ->
           Some (fd, fun fd' -> context_decls decls @ [ A.DMod (n, vis, mk fd', sp) ]))
      | _ :: tl -> find tl
    in
    find decls

(* Does [e] call [name]?  Syntactic and deliberately over-approximate (a bare
   [name] or any qualified [M.name]): a false positive costs one more function
   in the probe walk, a false negative hides exactly the caller a hypothesis
   would break. *)
let rec calls_name (name : string) (e : A.expr) : bool =
  let any = List.exists (calls_name name) in
  let is_target = function
    | A.EVar n -> n.A.txt = name || Filename.check_suffix n.A.txt ("." ^ name)
    | _ -> false
  in
  match e with
  | A.EApp (f, args, _) -> is_target f || calls_name name f || any args
  | A.EBlock (es, _) -> any es
  | A.ELet (b, _) -> calls_name name b.A.bind_expr
  | A.EIf (c, t, f, _) -> calls_name name c || calls_name name t || calls_name name f
  | A.EMatch (s, brs, _) ->
    calls_name name s
    || List.exists (fun (br : A.branch) -> calls_name name br.A.branch_body) brs
  | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) -> any es
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) -> calls_name name e
  | A.ELam (_, b, _) | A.ELetFn (_, _, _, b, _) -> calls_name name b
  | A.EPipe (a, b, _) | A.ESend (a, b, _) -> calls_name name a || calls_name name b
  | A.ERecord (fs, _) -> List.exists (fun (_, v) -> calls_name name v) fs
  | A.ERecordUpdate (r, fs, _) ->
    calls_name name r || List.exists (fun (_, v) -> calls_name name v) fs
  | A.EField (e, _, _) -> calls_name name e
  | _ -> false

let fn_calls (name : string) (fd : A.fn_def) : bool =
  List.exists (fun (c : A.fn_clause) -> calls_name name c.A.fc_body) fd.A.fn_clauses

(* Like [prune], but the rebuilt tree also keeps every function ANYWHERE in the
   unit that calls the target (other modules included), each at its own place,
   with the context decls of every module on the way.  A precondition's cost
   lands at its callers, so a probe that cannot see them cannot see what it
   breaks (design 2026-10-20 §0 row G0, §5.1).  Over-approximate by name:
   an extra function only costs walk time. *)
let prune_with_callers (path : string list) (name : string) (decls : A.decl list) :
    (A.fn_def * (A.fn_def -> A.decl list)) option =
  match prune path name decls with
  | None -> None
  | Some (fd0, _) ->
    let rec has_fn = function
      | [] -> false
      | A.DFn _ :: _ -> true
      | A.DMod (_, _, inner, _) :: tl -> has_fn inner || has_fn tl
      | _ :: tl -> has_fn tl
    in
    let rec filt (prefix : string list) (fd' : A.fn_def) (decls : A.decl list) : A.decl list =
      context_decls decls
      @ List.filter_map
          (function
            | A.DFn (f, sp) when prefix = path && f.A.fn_name.A.txt = name -> Some (A.DFn (fd', sp))
            | A.DFn (f, sp) when fn_calls name f -> Some (A.DFn (f, sp))
            | A.DMod (n, vis, inner, sp) ->
              let inner' = filt (prefix @ [ n.A.txt ]) fd' inner in
              if has_fn inner' then Some (A.DMod (n, vis, inner', sp)) else None
            | _ -> None)
          decls
    in
    Some (fd0, fun fd' -> filt [] fd' decls)

(* ── Resolving a call to the function it names ─────────────────────────── *)

(* Every function of [decls], as "M.N.f". *)
let defined_fns (decls : A.decl list) : (string, unit) Hashtbl.t =
  let t = Hashtbl.create 256 in
  let rec go prefix = function
    | [] -> ()
    | A.DFn (f, _) :: tl -> Hashtbl.replace t (String.concat "." (prefix @ [ f.A.fn_name.A.txt ])) (); go prefix tl
    | A.DMod (n, _, inner, _) :: tl -> go (prefix @ [ n.A.txt ]) inner; go prefix tl
    | _ :: tl -> go prefix tl
  in
  go [] decls;
  t

(* The function a reference [r] ("go", "B.go", "T.B.go") written in module
   [caller] names: lexical scoping, innermost enclosing module first.  A
   leading segment that names no module of the unit (the top-level module's
   own name) is dropped if the reference does not resolve with it.  [None]
   for a reference that names no function of the unit (an alias, a local
   binder, a builtin). *)
let resolve_call ~(defined : (string, unit) Hashtbl.t) ~(caller : string list) (r : string) : string option =
  let rec scopes p = p :: (match List.rev p with [] -> [] | _ :: tl -> scopes (List.rev tl)) in
  let try_rs rs =
    List.find_map
      (fun k -> let q = String.concat "." (k @ rs) in if Hashtbl.mem defined q then Some q else None)
      (scopes caller)
  in
  let rs = String.split_on_char '.' r in
  match try_rs rs with
  | Some q -> Some q
  | None -> (match rs with _ :: (_ :: _ as tl) -> try_rs tl | _ -> None)

(* Does [e], written in module [caller], call the function [target]
   ("M.f")?  A QUALIFIED reference that resolves to nothing in the unit is
   counted when its last segment is [target]'s (an alias may hide the
   module); an unresolved BARE name is a local binder (`let go = …`, a
   parameter) or a builtin, never another module's function. *)
let rec calls_target ~defined ~(caller : string list) ~(target : string) (e : A.expr) : bool =
  let last q = match List.rev (String.split_on_char '.' q) with x :: _ -> x | [] -> q in
  let any = List.exists (calls_target ~defined ~caller ~target) in
  let is_target = function
    | A.EVar n -> (
      match resolve_call ~defined ~caller n.A.txt with
      | Some q -> q = target
      | None -> String.contains n.A.txt '.' && last n.A.txt = last target)
    | _ -> false
  in
  let go = calls_target ~defined ~caller ~target in
  match e with
  | A.EApp (f, args, _) -> is_target f || go f || any args
  | A.EBlock (es, _) -> any es
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.EIf (c, t, f, _) -> go c || go t || go f
  | A.EMatch (s, brs, _) -> go s || List.exists (fun (br : A.branch) -> go br.A.branch_body) brs
  | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) -> any es
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) -> go e
  | A.ELam (_, b, _) | A.ELetFn (_, _, _, b, _) -> go b
  | A.EPipe (a, b, _) | A.ESend (a, b, _) -> go a || go b
  | A.ERecord (fs, _) -> List.exists (fun (_, v) -> go v) fs
  | A.ERecordUpdate (r, fs, _) -> go r || List.exists (fun (_, v) -> go v) fs
  | A.EField (e, _, _) -> go e
  | _ -> false

let fn_calls_target ~defined ~caller ~target (fd : A.fn_def) : bool =
  List.exists (fun (c : A.fn_clause) -> calls_target ~defined ~caller ~target c.A.fc_body) fd.A.fn_clauses

(* Does any function of the unit other than [path]/[name] call it?  Calls are
   resolved: `B.go`'s callers are not `A.go`'s. *)
let has_in_unit_callers (path : string list) (name : string) (decls : A.decl list) : bool =
  let defined = defined_fns decls in
  let target = String.concat "." (path @ [ name ]) in
  let rec go prefix = function
    | [] -> false
    | A.DFn (f, _) :: tl ->
      ((not (prefix = path && f.A.fn_name.A.txt = name)) && fn_calls_target ~defined ~caller:prefix ~target f)
      || go prefix tl
    | A.DMod (n, _, inner, _) :: tl -> go (prefix @ [ n.A.txt ]) inner || go prefix tl
    | _ :: tl -> go prefix tl
  in
  go [] decls

(* ── Debt ─────────────────────────────────────────────────────────────────── *)

(* [debt] counts obligations that are NOT discharged.  [Trusted] is not debt: it
   is a deliberate, declared hole (`@[trusted]`), and proposing a contract to
   close something the author already waved through would be noise. *)
(* Admissibility of a hypothesis, from the per-site diff it produced against
   the ledger it was tried on (design 2026-10-20 §2): it must CLOSE at least
   one site, OPEN none (a previously settled site that is now anything else),
   create no violation, and pay for every new skip with a close.  The count
   this replaced scored "proved two, broke one" as +1 and accepted it. *)
let admissible (d : (Ledger_diff.key * Ledger_diff.change) list) : bool =
  let n = List.length in
  let closed = Ledger_diff.closed d in
  closed <> []
  && Ledger_diff.opened d = []
  && Ledger_diff.new_violated d = []
  && n closed - n (Ledger_diff.new_skipped d) >= 0

(* One probe: re-walk the pruned tree and read the ledger back.

   The error context is a THROWAWAY — a hypothesis that does not pan out must
   not leave a diagnostic in the user's build.  The exception guard is for the
   same reason: a hypothesised signature is compiler input the author never
   wrote, and a crash while exploring it should cost that candidate, not the
   command. *)
let walk_ledger ~root ~defs (decls : A.decl list) : Ledger_diff.snapshot =
  Ob.reset ();
  (* Each walk predicts what a fresh `--check` of the hypothesis program will
     report, and a fresh check starts the witness executor with its whole
     module budget: a skip it can promote to a demonstrated violation (by
     running the enclosing function) is promoted there.  Without the reset
     the earlier probes spend the budget, a later walk files the same site as
     a skip, and the applied program's re-check disagrees. *)
  Witness.wall_budget := Witness.initial_wall_budget;
  let errctx = Err.create () in
  (* The same postcondition gate a real check runs before its walk
     ([Refine_check.check_module]): a declared return travels to callers, and
     reaches a return tail that calls it, only once proved.  Without it a
     probe lent every declared return, proved or not, so a self-recursive
     `f(x) = f(x)` "proved" its own contract and the prediction disagreed
     with the re-check (demand chains, 2026-10-24).  On a copy: the caller's
     table is reused across probes. *)
  let defs = Hashtbl.copy defs in
  (try RC.gate_unverified_posts ~root errctx defs decls with _ -> ());
  (try RC.visit_decls ~root errctx defs RC.rctx0 decls
   with _ -> ());
  (* Division safety is a SEPARATE pass — [Refine_check.visit_decls] never
     reaches it — so it has to be re-run here for its obligations to move
     under a hypothesis.  Recording them in [Division_safety] without also
     running it here would leave the count frozen at whatever the first walk
     produced: every candidate would appear to discharge nothing, the search
     would report [No_candidate], and the whole feature would still be dead
     while looking wired up.
     [context_decls] keeps `DOpts`, so the pruned tree still carries the
     `cap no_panic` that makes these obligations exist at all.
     [check_decls], not [check_module]: the latter registers its module with
     the witness executor, and the executor must keep the REAL program — a
     pruned probe tree has lost the stdlib, so every later witness run (the
     one that promotes a skip to a demonstrated violation) would fail and the
     probe would predict a skip the applied program does not have. *)
  (try Division_safety.check_decls ~root errctx decls with _ -> ());
  Ledger_diff.snapshot ()

(* ── Results ──────────────────────────────────────────────────────────────── *)

type suggestion = {
  sg_param : string;
  sg_base : string;      (* base type as it will be re-spelled, e.g. "Int" *)
  sg_pred : string;      (* predicate text, e.g. "_ > 0" *)
  sg_discharged : int;   (* obligations this candidate moved off the debt list *)
}

type status =
  | No_debt        (* every obligation in the body is already proved *)
  | Solved         (* the proposal discharges all of it *)
  | Partial        (* it discharges some; the remainder is reported *)
  | No_candidate   (* there is debt, but nothing in the grammar shifts it *)
  (* The probe budget ran out with debt still outstanding.  Deliberately NOT
     folded into [No_candidate]: "nothing in the grammar fits your code" and "I
     stopped looking" are different facts, and reporting the second as the first
     is the silent-cap failure — a truncated search that reads exactly like a
     complete one.  Raise --budget and ask again. *)
  | Budget_exhausted
  | Not_found      (* the named function is not a module-level fn in user code *)
  (* Some candidate would have discharged the body's debt, but only by turning
     a CALLER's call into a violation (or making the clause unsatisfiable).
     Reported, with the sites, instead of being proposed
     (design 2026-10-20 §5.1; decision D2). *)
  | Refused of refusal

and refusal = { rf_reason : string; rf_sites : A.span list }

type t = {
  rs_fn : string;                    (* qualified name *)
  rs_span : A.span;
  rs_status : status;
  rs_debt_before : int;
  rs_debt_after : int;
  rs_suggestions : suggestion list;
  rs_queries : int;                  (* probes spent, for the budget report *)
  (* A public function with no caller anywhere in the unit: its callers are
     external, so the caller impact of a proposed precondition is unknown
     (decision D3: proposed, marked; `--apply` skips it without
     `--apply-public`). *)
  rs_external_callers : bool;
}

let status_name = function
  | Refused _ -> "refused"
  | No_debt -> "no-debt"
  | Solved -> "solved"
  | Partial -> "partial"
  | No_candidate -> "no-candidate"
  | Budget_exhausted -> "budget-exhausted"
  | Not_found -> "not-found"

(* ── The greedy loop ──────────────────────────────────────────────────────── *)

(* Candidates for one parameter, given the other parameters that `len` applies
   to.  A parameter that is already refined is skipped entirely: this tool
   proposes contracts, it does not second-guess declared ones. *)
let candidates_for ~(measurable : string list) ~(fd : A.fn_def)
    ~(param : string) (ty : A.ty) : candidate list =
  if already_refined ty then []
  else
    let all =
      match kind_of_ty ty with
      | KInt -> int_candidates ~measurable
      | KFloat -> float_candidates
      | KList | KString -> measured_candidates
      | KOther -> []
    in
    (* Drop candidates that would forbid an input this function visibly handles
       on purpose.  Filtering here rather than after probing also means such a
       candidate never spends budget. *)
    List.filter (fun c -> not (contradicts_handled_case fd ~param c)) all

(* Is the conjunction of [fd]'s (first clause's) parameter refinements
   satisfiable?  Asked of the REAL checker rather than a hand-built query: a
   probe function with [fd]'s parameters calls a callee demanding [false]; that
   obligation is proved exactly when the parameters admit no value, i.e. when
   a proposal would make the body vacuously proved and every caller a
   violation in waiting (design 2026-10-20 §2). *)
let satisfiable ?(root = Sys.getcwd ()) (fd : A.fn_def) : bool =
  let never = "__refine_sat_never__" in
  let callee =
    match
      (March_parser.Parse.module_of_lexbuf
         (Lexing.from_string
            (Printf.sprintf "mod SatProbe do\n  fn %s(x : {Int | _ < 0 && _ > 0}) : Int do x end\nend\n" never)))
        .A.mod_decls
    with
    | [ d ] -> d
    | _ -> failwith "satisfiable: probe callee did not parse"
  in
  (* One call per Int parameter, the parameter itself as the subject: a goal
     loads the facts of the names its subject (and their refinements) mention,
     so a contradiction among parameters is reached through those mentions. *)
  let int_params =
    match fd.A.fn_clauses with
    | c :: _ ->
      let rec base = function A.TyRefine (t, _, _) -> base t | t -> t in
      List.filter_map
        (function
          | A.FPNamed { A.param_name; param_ty = Some t; _ }
          | A.FPDefault ({ A.param_name; param_ty = Some t; _ }, _)
            when kind_of_ty (base t) = KInt -> Some param_name
          | _ -> None)
        c.A.fc_params
    | [] -> []
  in
  (* The subject carries the PARAMETER's own span: a fact is admitted by the
     sort the typechecker recorded at a span, and a dummy span has none. *)
  let call_of (n : A.name) =
    A.EApp
      ( A.EVar { A.txt = never; A.span = n.A.span },
        [ A.EVar { A.txt = n.A.txt; A.span = n.A.span } ],
        n.A.span )
  in
  let call = A.EBlock (List.map call_of int_params, A.dummy_span) in
  let probe =
    { fd with
      A.fn_name = { fd.A.fn_name with A.txt = "__refine_sat_probe__" };
      A.fn_ret_ty = None;
      A.fn_clauses =
        (match fd.A.fn_clauses with
         | c :: _ -> [ { c with A.fc_guard = None; A.fc_body = call } ]
         | [] -> []) }
  in
  let decls = [ callee; A.DFn (probe, A.dummy_span) ] in
  if int_params = [] then true else
  Ob.with_scratch @@ fun () ->
  let defs = RC.collect_all_defs decls in
  let snap = walk_ledger ~root ~defs decls in
  not (List.exists (fun ((k : Ledger_diff.key), v) -> k.Ledger_diff.callee = never && v = Ob.Proved) snap)

(* ── Is a site still reachable? (the vacuous-branch probe) ────────────────
   A precondition can close a site without satisfying its demand: `n <= j`
   makes the `else` of `if j >= n do v else Array.set(v, j, …) end` dead, so
   the `Array.set` obligation is proved vacuously (path ∧ hypothesis ⊢
   false).  That is admissible by the ledger and satisfiable, and it is not a
   contract (specs/progress/2026-10-23-refine-infer-vacuous-branch-preconditions.md).

   Asked of the REAL checker, the way [satisfiable] asks: at each site, put a
   call demanding [false] just before the site's expression.  Its query is
   built by the same [check_call] from the same path context the site's own
   obligation saw, plus the parameters' refinements, so it is proved exactly
   when the site's path condition is inconsistent with what is in scope —
   i.e. when no execution reaches the site.

   The demand's subject is one Int parameter ([subject] when it is one, else
   the first): every path condition is translated into the query whatever the
   subject, together with the scope facts of the names the conditions
   mention, and the subject's own refinement is loaded through it.  A site
   with no Int parameter to name, or whose span no instrumentable expression
   covers (a clause guard, a `let` itself), is reported REACHABLE — the
   pre-fix behaviour, never a false rejection. *)
let reach_never = "__refine_reach_never__"

let reach_never_decl : A.decl Lazy.t =
  lazy
    (match
       (March_parser.Parse.module_of_lexbuf
          (Lexing.from_string
             (Printf.sprintf "mod ReachProbe do\n  fn %s(x : {Int | _ < 0 && _ > 0}) : Int do x end\nend\n" reach_never)))
         .A.mod_decls
     with
     | [ (A.DFn _ as d) ] | [ A.DMod (_, _, [ (A.DFn _ as d) ], _) ] -> d
     | _ -> failwith "reach probe callee did not parse")

let span_contains (o : A.span) (s : A.span) =
  s.A.file = o.A.file
  && (s.A.start_line, s.A.start_col) >= (o.A.start_line, o.A.start_col)
  && (s.A.end_line, s.A.end_col) <= (o.A.end_line, o.A.end_col)

(* One-level pre-order map, the forms [check_call]'s walk carries a path
   through.  A form not listed is a leaf here: a site inside it is
   instrumented at the leaf, under a weaker path (reported reachable more
   often, never less). *)
let rec instrument_at (site : A.span) (mk : A.expr -> A.expr option) (e : A.expr) : A.expr * bool =
  let sp = March_typecheck.Typecheck_types.span_of_expr e in
  let is_probe = match e with A.EApp (A.EVar { A.txt; _ }, _, _) -> txt = reach_never | _ -> false in
  (* An earlier site's probe call carries that site's span: never descend into it. *)
  if is_probe || not (span_contains sp site) then (e, false)
  else begin
    let hit = ref false in
    let go x = let x', h = instrument_at site mk x in if h then hit := true; x' in
    let e' =
      match e with
      | A.EApp (h, xs, sp) -> A.EApp (go h, List.map go xs, sp)
      | A.EBlock (es, sp) -> A.EBlock (List.map go es, sp)
      | A.ELet (b, sp) -> A.ELet ({ b with A.bind_expr = go b.A.bind_expr }, sp)
      | A.EIf (c, t, f, sp) -> A.EIf (go c, go t, go f, sp)
      | A.EMatch (sc, brs, sp) ->
        A.EMatch (go sc, List.map (fun (br : A.branch) -> { br with A.branch_body = go br.A.branch_body }) brs, sp)
      | A.ETuple (es, sp) -> A.ETuple (List.map go es, sp)
      | A.ELam (ps, b, sp) -> A.ELam (ps, go b, sp)
      | A.EPipe (a, b, sp) -> A.EPipe (go a, go b, sp)
      | A.EAnnot (x, t, sp) -> A.EAnnot (go x, t, sp)
      | other -> other
    in
    if !hit then (e', true)
    else
      match mk e with
      | Some w -> (w, true)
      | None -> (e, false)
  end

(* [sites] of [fd] that no execution reaches under [fd]'s own signature.
   [tree] rebuilds the probe's decl tree around a version of the function (the
   oracle's pruned tree: the target and its callers); [defs] is the signature
   table the probe walks under.  One walk for all the sites. *)
let unreachable_sites ~root ~defs ~(tree : A.fn_def -> A.decl list) ?subject (fd : A.fn_def)
    (sites : A.span list) : A.span list =
  let int_params =
    match fd.A.fn_clauses with
    | c :: _ ->
      let rec base = function A.TyRefine (t, _, _) -> base t | t -> t in
      List.filter_map
        (function
          | A.FPNamed { A.param_name; param_ty = Some t; _ }
          | A.FPDefault ({ A.param_name; param_ty = Some t; _ }, _)
            when kind_of_ty (base t) = KInt -> Some param_name
          | _ -> None)
        c.A.fc_params
    | [] -> []
  in
  let subj =
    match List.find_opt (fun (n : A.name) -> Some n.A.txt = subject) int_params with
    | Some n -> Some n
    | None -> (match int_params with n :: _ -> Some n | [] -> None)
  in
  let sites = List.sort_uniq compare sites in
  match subj with
  | None -> []
  | Some _ when sites = [] -> []
  | Some n ->
    let call_at (site : A.span) =
      A.EApp
        ( A.EVar { A.txt = reach_never; A.span = site },
          [ A.EVar { A.txt = n.A.txt; A.span = n.A.span } ],
          site )
    in
    let mk site (e : A.expr) =
      match e with
      | A.ELet _ | A.ELetQ _ | A.ELetFn _ | A.ELetStar _ -> None
      | _ -> Some (A.EBlock ([ call_at site; e ], March_typecheck.Typecheck_types.span_of_expr e))
    in
    let placed = ref [] in
    let body0 = List.map (fun (c : A.fn_clause) -> c.A.fc_body) fd.A.fn_clauses in
    let bodies =
      List.fold_left
        (fun bodies site ->
          let hit = ref false in
          let bodies =
            List.map
              (fun b -> if !hit then b else let b', h = instrument_at site (mk site) b in if h then hit := true; b')
              bodies
          in
          if !hit then placed := site :: !placed;
          bodies)
        body0 sites
    in
    if !placed = [] then []
    else
      let probe =
        { fd with
          A.fn_clauses = List.map2 (fun (c : A.fn_clause) b -> { c with A.fc_body = b }) fd.A.fn_clauses bodies }
      in
      let never_d = Lazy.force reach_never_decl in
      let decls = never_d :: tree probe in
      let defs = Hashtbl.copy defs in
      Hashtbl.iter (fun k v -> Hashtbl.replace defs k v) (RC.collect_all_defs [ never_d ]);
      Ob.with_scratch @@ fun () ->
      let snap = walk_ledger ~root ~defs decls in
      List.filter
        (fun site ->
          List.exists
            (fun ((k : Ledger_diff.key), v) -> k.Ledger_diff.callee = reach_never && k.Ledger_diff.span = site && v = Ob.Proved)
            snap)
        !placed

let infer_fn ?(allow_caller_violations = false) ~root ~defs ~(decls : A.decl list)
    ~(path : string list) ~(budget : int ref) (fn_name : string) : t option =
  let qualified = String.concat "." (path @ [ fn_name ]) in
  match prune_with_callers path fn_name decls with
  | None -> None
  | Some (fd0, rebuild) ->
    let span = fd0.A.fn_name.A.span in
    let external_callers =
      fd0.A.fn_vis = A.Public && not (has_in_unit_callers path fn_name decls)
    in
    (* Sites inside the target's own clauses; every other site is a caller's. *)
    let in_body (sp : A.span) =
      List.exists
        (fun (c : A.fn_clause) ->
          let o = c.A.fc_span in
          sp.A.file = o.A.file
          && (sp.A.start_line, sp.A.start_col) >= (o.A.start_line, o.A.start_col)
          && (sp.A.end_line, sp.A.end_col) <= (o.A.end_line, o.A.end_col))
        fd0.A.fn_clauses
    in
    let base = walk_ledger ~root ~defs (rebuild fd0) in
    let mk_result ?(suggestions = []) ~after status =
      Some
        { rs_fn = qualified; rs_span = span; rs_status = status;
          rs_debt_before = Ledger_diff.debt base; rs_debt_after = after;
          rs_suggestions = suggestions; rs_queries = 0;
          rs_external_callers = external_callers }
    in
    (* Caller violations a candidate would create, recorded so that a search
       that proposes nothing can say WHY instead of "no candidate". *)
    let refused_sites = ref [] in
    let refused_unsat = ref false in
    if Ledger_diff.debt base = 0 then mk_result ~after:0 No_debt
    else begin
      (* Parameters are taken from the first clause: a multi-clause function
         shares one signature, and March's desugar has already collapsed
         multi-head functions into one clause by the time we see them. *)
      let params =
        match fd0.A.fn_clauses with c :: _ -> named_params c | [] -> []
      in
      let measurable =
        List.filter_map
          (fun (n, t) ->
            match kind_of_ty t with KList | KString -> Some n | _ -> None)
          params
      in
      let queries = ref 0 in
      (* Greedy: at each round take the candidate that discharges the most debt,
         breaking ties toward the WEAKEST (grammar order).  One candidate per
         parameter — the loop never conjoins two proposals onto one parameter,
         so it cannot synthesise a contradictory contract that "proves"
         everything vacuously. *)
      let rec round acc_fd acc_sugs (cur : Ledger_diff.snapshot) (remaining : (string * A.ty) list) =
        if Ledger_diff.debt cur = 0 || remaining = [] || !budget <= 0 then
          (acc_sugs, cur)
        else begin
          let best = ref None in
          List.iter
            (fun (pname, pty) ->
              List.iter
                (fun cand ->
                  if !budget > 0 then begin
                    decr budget;
                    incr queries;
                    let hyp = with_refinement acc_fd ~param:pname ~mk:cand.c_pred in
                    (* The callers resolve the target through [defs], built
                       once from the unmodified module: give them the
                       hypothesised signature or they never see it. *)
                    let defs_h = Hashtbl.copy defs in
                    Hashtbl.replace defs_h qualified (RC.entry_of_sig (RC.sig_of_fn hyp));
                    let d = walk_ledger ~root ~defs:defs_h (rebuild hyp) in
                    let delta = Ledger_diff.diff ~before:cur ~after:d in
                    let gained = List.length (Ledger_diff.closed delta) in
                    (* A new violation at a CALLER is the precondition's cost
                       landing where it is owed: refused unless the user asked
                       for it (D2), and never silently.  Everything else must
                       pass [admissible]: close a site, open none, no
                       violation. *)
                    let caller_viol =
                      List.filter (fun (k : Ledger_diff.key) -> not (in_body k.Ledger_diff.span))
                        (Ledger_diff.new_violated delta)
                    in
                    let delta_wo_callers =
                      List.filter
                        (fun ((k : Ledger_diff.key), c) ->
                          not (c = Ledger_diff.New_violated && not (in_body k.Ledger_diff.span)))
                        delta
                    in
                    let ok =
                      if caller_viol = [] then admissible delta
                      else if admissible delta_wo_callers then begin
                        if allow_caller_violations then true
                        else begin
                          refused_sites :=
                            List.map (fun (k : Ledger_diff.key) -> k.Ledger_diff.span) caller_viol
                            @ !refused_sites;
                          false
                        end
                      end
                      else false
                    in
                    let ok =
                      ok
                      && (satisfiable ~root hyp
                          || (refused_unsat := true; false))
                    in
                    if ok then
                      match !best with
                      | Some (g, _, _, _, _) when g >= gained -> ()
                      | _ -> best := Some (gained, pname, pty, cand, d)
                  end)
                (candidates_for ~measurable ~fd:fd0 ~param:pname pty))
            remaining;
          match !best with
          | None -> (acc_sugs, cur)
          | Some (gained, pname, pty, cand, d) ->
            (match ty_text pty with
             | None -> (acc_sugs, cur)
             | Some bt ->
               let sug =
                 { sg_param = pname; sg_base = bt; sg_pred = cand.c_text;
                   sg_discharged = gained }
               in
               round
                 (with_refinement acc_fd ~param:pname ~mk:cand.c_pred)
                 (acc_sugs @ [ sug ]) d
                 (List.filter (fun (n, _) -> n <> pname) remaining))
        end
      in
      let (sugs, final) = round fd0 [] base params in
      (* A budget that ran out means the search was TRUNCATED, so neither
         "nothing fits" nor "this is all that fits" is an honest report. *)
      let starved = !budget <= 0 && Ledger_diff.debt final > 0 in
      let status =
        if Ledger_diff.debt final = 0 then Solved
        else if starved then Budget_exhausted
        else if sugs = [] && !refused_sites <> [] then
          Refused
            { rf_reason = "caller-violation";
              rf_sites = List.sort_uniq compare !refused_sites }
        else if sugs = [] && !refused_unsat then
          Refused { rf_reason = "unsatisfiable"; rf_sites = [] }
        else if sugs = [] then No_candidate
        else Partial
      in
      Some
        { rs_fn = qualified; rs_span = span; rs_status = status;
          rs_debt_before = Ledger_diff.debt base; rs_debt_after = Ledger_diff.debt final;
          rs_suggestions = sugs; rs_queries = !queries;
          rs_external_callers = external_callers }
    end

(* ── Entry points ─────────────────────────────────────────────────────────── *)

(* Every module-level function, with its module path. *)
let rec enum_fns (prefix : string list) (decls : A.decl list) :
    (string list * A.fn_def) list =
  List.concat_map
    (function
      | A.DFn (fd, _) -> [ (List.rev prefix, fd) ]
      | A.DMod (n, _, inner, _) -> enum_fns (n.A.txt :: prefix) inner
      | _ -> [])
    decls

let qualified_of (path, (fd : A.fn_def)) =
  String.concat "." (path @ [ fd.A.fn_name.A.txt ])

(* A target matches on the full qualified name or on any dotted SUFFIX of it, so
   `forge refine chunks` finds `Text.Split.chunks` without the user spelling the
   path.  An ambiguous target returns every match and the caller reports it —
   silently picking one would be the wrong kind of convenience. *)
let matches_target ~(target : string) (path, fd) : bool =
  let q = qualified_of (path, fd) in
  q = target
  ||
  let qs = String.split_on_char '.' q and ts = String.split_on_char '.' target in
  let nq = List.length qs and nt = List.length ts in
  nt < nq
  && ts = List.filteri (fun i _ -> i >= nq - nt) qs

let default_budget = 200

(** Suggest preconditions for [target] in [m].

    [is_user] filters to the user's own code: the module handed to the checker
    has the whole stdlib prepended, and suggesting contracts for stdlib
    functions from inside someone's project would be noise at best.

    The caller MUST have run [Refine_check.check_module] on [m] first — the
    registration globals it populates (ADT tables, measure preamble, alias
    gates) are what every probe here reflects against. *)
let suggest ?(allow_caller_violations = false) ?(root = Sys.getcwd ()) ?(budget = default_budget)
    ~(is_user : A.span -> bool) ~(target : string) (m : A.module_) : t list =
  (* [Ob.with_scratch]: every probe below [Ob.reset]s and refills the ledger
     AND the per-call-site index from a hypothesis module.  Leaving that
     behind corrupts any later consumer of [Ob.by_span] — see the note on
     [Obligation.with_scratch]. *)
  Ob.with_scratch @@ fun () ->
  let defs = RC.collect_all_defs m.A.mod_decls in
  let all = enum_fns [] m.A.mod_decls in
  (* The ENTRY file's own `mod Name do … end` contributes its decls at the top
     level, not under a `DMod Name` (only imported modules are wrapped), so
     `Name.f` — the spelling a user reads off their own source — would not match
     the qualified name `f` that [enum_fns] produces.  Accept it by also trying
     the target with that prefix stripped. *)
  let self = m.A.mod_name.A.txt ^ "." in
  let n = String.length self in
  let targets =
    target
    ::
    (if String.length target > n && String.sub target 0 n = self then
       [ String.sub target n (String.length target - n) ]
     else [])
  in
  let hits =
    List.filter
      (fun (_, fd) -> is_user fd.A.fn_name.A.span)
      (List.filter
         (fun f -> List.exists (fun target -> matches_target ~target f) targets)
         all)
  in
  match hits with
  | [] ->
    [ { rs_fn = target; rs_span = A.dummy_span; rs_status = Not_found;
        rs_debt_before = 0; rs_debt_after = 0; rs_suggestions = [];
        rs_queries = 0; rs_external_callers = false } ]
  | hits ->
    List.filter_map
      (fun (path, (fd : A.fn_def)) ->
        (* Per function, for the same reason as [suggest_all]: an ambiguous
           target matches several functions, and a shared pool would starve
           whichever ones sort last for a reason unrelated to their code. *)
        let budget = ref budget in
        infer_fn ~allow_caller_violations ~root ~defs ~decls:m.A.mod_decls ~path ~budget
          fd.A.fn_name.A.txt)
      hits

(** Sweep every user function.  Reports only functions that HAVE a suggestion:
    a project-wide listing of "no debt" lines would bury the signal. *)
let suggest_all ?(allow_caller_violations = false) ?(root = Sys.getcwd ()) ?(budget = default_budget)
    ~(is_user : A.span -> bool) (m : A.module_) : t list =
  (* Scratch ledger+index for the whole sweep — see [suggest] above. *)
  Ob.with_scratch @@ fun () ->
  let defs = RC.collect_all_defs m.A.mod_decls in
  enum_fns [] m.A.mod_decls
  |> List.filter (fun (_, (fd : A.fn_def)) -> is_user fd.A.fn_name.A.span)
  |> List.filter_map (fun (path, (fd : A.fn_def)) ->
         (* The budget is PER FUNCTION, not per sweep.  A single shared pool
            would be spent by whichever functions happen to sort first, and
            every function after that would report "no candidate" for a reason
            that has nothing to do with its code — a silent cap that reads
            exactly like a real answer. *)
         let budget = ref budget in
         match
           infer_fn ~allow_caller_violations ~root ~defs ~decls:m.A.mod_decls ~path ~budget
             fd.A.fn_name.A.txt
         with
         | Some r when r.rs_suggestions <> [] -> Some r
         (* A refusal is an answer, not silence: report it (D4). *)
         | Some ({ rs_status = Refused _; _ } as r) -> Some r
         | _ -> None)

(* ── Attaching the suggestion to a promoted call-site failure ─────────────── *)

(* Re-spell a clause's parameter list, substituting [refined]'s annotation for
   the parameters it names.  This is BOTH the text `forge fix` writes and the
   text the help block prints — one rendering, so the message can never
   advertise a signature different from the one the fix applies.

   Deliberately partial, exactly as [ty_text] is: a pattern parameter, a
   default argument, a linearity annotation or an unannotated parameter is
   something this cannot re-spell faithfully, and re-writing a parameter list
   approximately is worse than printing no fix at all. *)
let params_text (c : A.fn_clause) ~(refined : (string * string) list) :
    string option =
  let one (p : A.fn_param) =
    match p with
    | A.FPNamed { A.param_name; A.param_ty = Some t; A.param_lin = A.Unrestricted }
      -> (
      match List.assoc_opt param_name.A.txt refined with
      | Some annot -> Some (param_name.A.txt ^ " : " ^ annot)
      | None -> Option.map (fun bt -> param_name.A.txt ^ " : " ^ bt) (ty_text t))
    | _ -> None
  in
  let parts = List.map one c.A.fc_params in
  if List.exists (fun p -> p = None) parts then None
  else Some ("(" ^ String.concat ", " (List.map Option.get parts) ^ ")")

(** Upgrade every promoted call-site diagnostic in [errctx] with the
    precondition its enclosing function should declare, as help text AND as a
    machine-applicable [Err.FReplace] over that function's parameter list.

    Runs as a POST-PASS: [Refine_check.check_module] must have completed, and
    this must not be called from inside its walk — see
    [Refine_check.promoted_sites].  Cost is confined to promotion: with no
    promoted site this returns without probing anything.

    Silent when the suggestion is not [Solved].  [Partial] leaves debt behind,
    so applying it would not remove the failure that was just reported, and a
    `forge fix` that does not fix the thing is worse than no offer. *)
let attach_promoted_fixes ?(root = Sys.getcwd ()) ?(budget = default_budget)
    (errctx : Err.ctx) (m : A.module_) : unit =
  match List.rev !RC.promoted_sites with
  | [] -> ()
  | sites ->
    RC.promoted_sites := [];
    (* The checker's own notion of "not the user's code", snapshotted rather
       than read per call: probing re-walks hypothesis trees, and a second
       definition of "user code" here is exactly the drift [suggest]'s own
       [~is_user] parameter exists to avoid. *)
    let stdlib = !RC.stdlib_source_files in
    let is_user (sp : A.span) = not (List.mem sp.A.file stdlib) in
    (* Probe ONCE per target function, not once per promoted call site.  Two
       sites in the same enclosing function ask the same question — "what
       precondition discharges this body's debt?" — and running the full
       assume-and-recheck search twice for one answer doubles precisely the
       cost that confining this to promotion exists to bound. *)
    let targets =
      List.sort_uniq compare (List.map (fun (_, q, _) -> q) sites)
    in
    let searched =
      List.map
        (fun q ->
          let results = suggest ~root ~budget ~is_user ~target:q m in
          (* Select by IDENTITY, never by position.  [matches_target] accepts
             any dotted SUFFIX of a qualified name — that rule is why
             `forge refine chunks` finds `Text.Split.chunks` — and an entry
             file's top-level function is qualified by nothing at all, so
             `~target:"go"` also matches `Inner.go`, `Other.go`, and every
             other `go` in the program.  [suggest] returns one result per
             hit and their order is decl order, so taking the head would let
             an unrelated same-named helper decide this signature: its
             refinement is applied to the RECORDED function's parameters BY
             NAME, which rewrites the base type too (`ys : List(Int)` became
             `ys : Int` in the reviewer's repro) and hands `forge fix` a
             source-corrupting edit.  [rs_fn] is
             [String.concat "." (path @ [fn_name])], exactly what
             [Witness.qualified_fn_name] builds from the same [mod_decls], so
             an exact match is well-defined; no exact match means we cannot
             say which function was searched, and we decline. *)
          (q, List.find_opt (fun r -> r.rs_fn = q) results))
        targets
    in
    let upgrades =
      List.filter_map
        (fun (span, qname, (fd : A.fn_def)) ->
          let short = fd.A.fn_name.A.txt in
          let solved =
            match List.assoc_opt qname searched with
            | Some (Some r) -> (
              (* Every constructor named, no wildcard: [status] exists so that
                 "nothing in the grammar fits" ([No_candidate]) and "I stopped
                 looking" ([Budget_exhausted]) are never conflated, and a `_`
                 here would re-conflate them.  Only [Solved] discharges the
                 debt this diagnostic is about — [Partial] leaves some of it
                 behind, so applying its proposal would not remove the failure
                 being reported. *)
              match r.rs_status with
              | Solved -> Some r.rs_suggestions
              | Partial | No_debt | No_candidate | Budget_exhausted | Not_found | Refused _
                -> None)
            | Some None | None -> None
          in
          match solved with
          | None | Some [] -> None
          | Some sugs -> (
            let refined =
              List.map
                (fun s ->
                  (s.sg_param, Printf.sprintf "{%s | %s}" s.sg_base s.sg_pred))
                sugs
            in
            match fd.A.fn_clauses with
            | [] -> None
            | c :: _ ->
              let psp = c.A.fc_params_span in
              (* Three ways to decline, all of them "the offer would be a lie":

                 - A clause SYNTHESIZED by desugar carries its own [fc_span]
                   here rather than a real parameter list (see
                   [fc_params_span]'s comment), and rewriting that span would
                   overwrite the body.
                 - `forge fix` applies an [FReplace] only when it stays on ONE
                   line (`forge/lib/cmd_fix.ml`, the `start_line = end_line`
                   guard) and silently drops it otherwise, so a parameter list
                   broken across lines would advertise a fix that never
                   arrives — the exact anti-pattern this task exists to avoid.
                 - A span outside the user's own files is not ours to rewrite.

                 In each case the Task 6 finding still stands; it just comes
                 without the offer. *)
              if psp = c.A.fc_span || psp.A.start_line <= 0
                 || psp.A.start_line <> psp.A.end_line || not (is_user psp)
              then None
              else
                Option.map
                  (fun ptext ->
                    (* The DISPLAY line carries the return type as well, so
                       what the user reads is a signature they could type; the
                       [FReplace] stays scoped to the parameter list, which is
                       the only span there is to rewrite.  A return type this
                       cannot spell is simply omitted rather than guessed. *)
                    let ret =
                      match Option.bind fd.A.fn_ret_ty ty_text with
                      | Some t -> " : " ^ t
                      | None -> ""
                    in
                    ( span,
                      short,
                      (* Hard-wrapped near 78 columns: the renderer does not
                         reflow. *)
                      Printf.sprintf
                        "\n\nhelp: declare what `%s` actually needs —\n\
                        \        fn %s%s%s\n\
                         `forge fix` can apply this."
                        short short ptext ret,
                      Err.FReplace { span = psp; text = ptext } ))
                  (params_text c ~refined)))
        sites
    in
    (* Probing re-walks hypothesis trees through [Refine_check.visit_decls],
       which can promote inside them; those sites describe a signature the user
       never wrote, so discard whatever the loop above accumulated. *)
    RC.promoted_sites := [];
    if upgrades <> [] then
      errctx.Err.diagnostics <-
        List.map
          (fun (d : Err.diagnostic) ->
            match
              List.find_opt
                (fun (sp, short, _, _) ->
                  d.Err.span = sp
                  && String.length d.Err.message > String.length short + 2
                  && String.sub d.Err.message 0 (String.length short + 2)
                     = "`" ^ short ^ "`")
                upgrades
            with
            | Some (_, _, help, fix) when d.Err.fix = None ->
              { d with Err.message = d.Err.message ^ help; Err.fix = Some fix }
            | _ -> d)
          errctx.Err.diagnostics
