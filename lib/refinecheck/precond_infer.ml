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

(* ── Debt ─────────────────────────────────────────────────────────────────── *)

(* [debt] counts obligations that are NOT discharged.  [Trusted] is not debt: it
   is a deliberate, declared hole (`@[trusted]`), and proposing a contract to
   close something the author already waved through would be noise. *)
type debt = { d_total : int; d_violated : int }

let count_debt () : debt =
  List.fold_left
    (fun acc (o : Ob.t) ->
      match o.Ob.verdict with
      | Ob.Proved | Ob.Trusted -> acc
      | Ob.Violated -> { d_total = acc.d_total + 1; d_violated = acc.d_violated + 1 }
      | Ob.Skipped _ -> { acc with d_total = acc.d_total + 1 })
    { d_total = 0; d_violated = 0 }
    (Ob.all ())

(* One probe: re-walk the pruned tree and read the ledger back.

   The error context is a THROWAWAY — a hypothesis that does not pan out must
   not leave a diagnostic in the user's build.  The exception guard is for the
   same reason: a hypothesised signature is compiler input the author never
   wrote, and a crash while exploring it should cost that candidate, not the
   command. *)
let walk_debt ~root ~defs (decls : A.decl list) : debt =
  Ob.reset ();
  let errctx = Err.create () in
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
     `cap no_panic` that makes these obligations exist at all. *)
  (try
     Division_safety.check_module ~root errctx
       { A.mod_name = { A.txt = "<probe>"; A.span = A.dummy_span }
       ; A.mod_decls = decls }
   with _ -> ());
  count_debt ()

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

type t = {
  rs_fn : string;                    (* qualified name *)
  rs_span : A.span;
  rs_status : status;
  rs_debt_before : int;
  rs_debt_after : int;
  rs_suggestions : suggestion list;
  rs_queries : int;                  (* probes spent, for the budget report *)
}

let status_name = function
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

let infer_fn ~root ~defs ~(decls : A.decl list) ~(path : string list)
    ~(budget : int ref) (fn_name : string) : t option =
  let qualified = String.concat "." (path @ [ fn_name ]) in
  match prune path fn_name decls with
  | None -> None
  | Some (fd0, rebuild) ->
    let span = fd0.A.fn_name.A.span in
    let base = walk_debt ~root ~defs (rebuild fd0) in
    let mk_result ?(suggestions = []) ~after status =
      Some
        { rs_fn = qualified; rs_span = span; rs_status = status;
          rs_debt_before = base.d_total; rs_debt_after = after;
          rs_suggestions = suggestions; rs_queries = 0 }
    in
    if base.d_total = 0 then mk_result ~after:0 No_debt
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
      let rec round acc_fd acc_sugs (cur : debt) (remaining : (string * A.ty) list) =
        if cur.d_total = 0 || remaining = [] || !budget <= 0 then
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
                    let d = walk_debt ~root ~defs (rebuild hyp) in
                    let gained = cur.d_total - d.d_total in
                    (* Admissible only if it strictly shrinks the debt AND
                       introduces no new violation.  A candidate that turns a
                       silent skip into a proved-false obligation is a wrong
                       contract, however much else it discharges. *)
                    if gained > 0 && d.d_violated <= cur.d_violated then
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
      let starved = !budget <= 0 && final.d_total > 0 in
      let status =
        if final.d_total = 0 then Solved
        else if starved then Budget_exhausted
        else if sugs = [] then No_candidate
        else Partial
      in
      Some
        { rs_fn = qualified; rs_span = span; rs_status = status;
          rs_debt_before = base.d_total; rs_debt_after = final.d_total;
          rs_suggestions = sugs; rs_queries = !queries }
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
let suggest ?(root = Sys.getcwd ()) ?(budget = default_budget)
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
        rs_queries = 0 } ]
  | hits ->
    List.filter_map
      (fun (path, (fd : A.fn_def)) ->
        (* Per function, for the same reason as [suggest_all]: an ambiguous
           target matches several functions, and a shared pool would starve
           whichever ones sort last for a reason unrelated to their code. *)
        let budget = ref budget in
        infer_fn ~root ~defs ~decls:m.A.mod_decls ~path ~budget
          fd.A.fn_name.A.txt)
      hits

(** Sweep every user function.  Reports only functions that HAVE a suggestion:
    a project-wide listing of "no debt" lines would bury the signal. *)
let suggest_all ?(root = Sys.getcwd ()) ?(budget = default_budget)
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
           infer_fn ~root ~defs ~decls:m.A.mod_decls ~path ~budget
             fd.A.fn_name.A.txt
         with
         | Some r when r.rs_suggestions <> [] -> Some r
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
              | Partial | No_debt | No_candidate | Budget_exhausted | Not_found
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
