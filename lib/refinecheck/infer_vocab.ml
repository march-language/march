(* The mined candidate vocabulary for inference-lite
   (specs/2026-10-20-refinement-suggest-lite-design.md §1.3-§1.4).

   The fixed sign grammar of the shipped suggest tools stays, as a fallback.
   The primary source is what the program already says, in rank order:
     1. Demand — the predicate a skipped obligation in the slot's function asks
        for, in the caller's scope ([Obligation.t.inst]) when transported;
     2. House — every refinement predicate written in a signature of the unit;
     3. Body — comparisons in the slot's own function against its binder;
     4. Fixed — today's grammar ([Precond_infer.int_candidates] and friends).
   Candidates are filtered syntactically before any probe, capped at 12 per
   slot, and ordered weakest first by implication (asked of the real checker,
   cached in-process). *)

module A = March_ast.Ast
module PI = Precond_infer
module IS = Infer_slot
module Ob = Obligation

type source = Demand | House | Body | Fixed

type cand = { c : PI.candidate; source : source }

let source_name = function Demand -> "demand" | House -> "house" | Body -> "body" | Fixed -> "fixed"
let source_rank = function Demand -> 1 | House -> 2 | Body -> 3 | Fixed -> 4

let cap = 12

(* ── Text <-> AST ─────────────────────────────────────────────────────────── *)

let rec respan (sp : A.span) (e : A.expr) : A.expr =
  let go = respan sp in
  match e with
  | A.EVar n -> A.EVar { n with A.span = sp }
  | A.ELit (l, _) -> A.ELit (l, sp)
  | A.EApp (f, xs, _) -> A.EApp (go f, List.map go xs, sp)
  | A.ETuple (xs, _) -> A.ETuple (List.map go xs, sp)
  | A.EField (r, n, _) -> A.EField (go r, n, sp)
  | other -> other

(* Parse a predicate the way a user writes one — inside a refinement — and
   rebuild its text from the AST, so text and AST cannot disagree. *)
let candidate_of_text (text : string) : PI.candidate option =
  let src = Printf.sprintf "mod InferVocab do\n  fn f(x : {Int | %s}) : Int do 0 end\nend\n" text in
  match March_parser.Parse.module_of_lexbuf (Lexing.from_string src) with
  | exception _ -> None
  | m -> (
    match m.A.mod_decls with
    | [ A.DFn ({ A.fn_clauses = c :: _; _ }, _) ] -> (
      match c.A.fc_params with
      | [ A.FPNamed { A.param_ty = Some (A.TyRefine (_, _, pred)); _ } ] ->
        Some { PI.c_text = Refine_scope.pred_str pred; c_pred = (fun sp -> respan sp pred) }
      | _ -> None)
    | _ -> None)

(* ── Syntactic filters ───────────────────────────────────────────────────── *)

let rec names_of (acc : string list) (e : A.expr) : string list =
  match e with
  | A.EVar { A.txt; _ } -> txt :: acc
  | A.EApp (A.EVar _, xs, _) -> List.fold_left names_of acc xs
  | A.EApp (f, xs, _) -> List.fold_left names_of (names_of acc f) xs
  | A.ETuple (xs, _) -> List.fold_left names_of acc xs
  | A.EField (r, _, _) -> names_of acc r
  | _ -> acc

let rec heads_of (acc : string list) (e : A.expr) : string list =
  match e with
  | A.EApp (A.EVar { A.txt; _ }, xs, _) -> List.fold_left heads_of (txt :: acc) xs
  | A.EApp (f, xs, _) -> List.fold_left heads_of (heads_of acc f) xs
  | A.ETuple (xs, _) -> List.fold_left heads_of acc xs
  | A.EField (r, _, _) -> heads_of acc r
  | _ -> acc

(* Names a candidate for [s] may mention besides `_`: for a parameter slot the
   parameters EARLIER in the list (§1.2 row K5), for a return slot any
   parameter. *)
let scope_names (s : IS.slot) : string list =
  match s.IS.fd.A.fn_clauses with
  | [] -> []
  | c :: _ -> (
    let ps = List.map fst (PI.named_params c) in
    match IS.root s.IS.path with
    | IS.Param x ->
      let rec before = function [] -> [] | y :: tl -> if y = x then [] else y :: before tl in
      before ps
    | IS.Return -> ps
    | _ -> [])

(* Is [e] well sorted for a value of the slot's base?  An ill-sorted
   candidate can never be proved, and it costs a solver timeout to find out. *)
let rec sorted_for (k : PI.kind) (e : A.expr) : bool =
  let on_hole = function A.EVar { A.txt = "_"; _ } -> true | _ -> false in
  match e with
  | A.ELit (A.LitFloat _, _) -> k = PI.KFloat
  | A.EApp (A.EVar { A.txt = h; _ }, [ x ], _) when on_hole x && not (List.mem h [ "not"; "!" ]) ->
    (* A measure or tester applied to the value itself. *)
    (k = PI.KList || k = PI.KString) && h = "len"
  | A.EApp (A.EVar { A.txt = op; _ }, [ a; b ], _) when List.mem op [ "<"; "<="; ">"; ">="; "=="; "!=" ] ->
    let int_lit = function A.ELit (A.LitInt _, _) -> true | _ -> false in
    (not (k = PI.KFloat && ((on_hole a && int_lit b) || (on_hole b && int_lit a))))
    && (not ((k = PI.KList || k = PI.KString) && (on_hole a || on_hole b)))
    && sorted_for k a && sorted_for k b
  | A.EApp (_, xs, _) -> List.for_all (sorted_for k) xs
  | _ -> true

let admissible_text (s : IS.slot) (c : PI.candidate) : bool =
  let e = c.PI.c_pred A.dummy_span in
  let allowed = "_" :: scope_names s in
  (* A predicate that does not mention the value (`true`, the House
     predicate of a relation's free slot `{x : Int | true}`) says nothing
     about it; installed it can still "close" a slot's `true` sub-goal at a
     caller, which is no contract. *)
  List.mem "_" (names_of [] e) &&
  (List.mem IS.K6 s.IS.kinds || sorted_for (PI.kind_of_ty s.IS.base) e) &&
  List.for_all (fun n -> List.mem n allowed) (names_of [] e)
  && List.for_all
       (fun h ->
         (Refine_post.known_predicate_fn h || h = "len")
         && (List.mem IS.K6 s.IS.kinds || h <> "p"))
       (heads_of [] e)

(* ── Sources ─────────────────────────────────────────────────────────────── *)

let within (o : A.span) (sp : A.span) =
  sp.A.file = o.A.file
  && (sp.A.start_line, sp.A.start_col) >= (o.A.start_line, o.A.start_col)
  && (sp.A.end_line, sp.A.end_col) <= (o.A.end_line, o.A.end_col)

let demands (s : IS.slot) (ledger : Ob.t list) : string list =
  List.filter_map
    (fun (o : Ob.t) ->
      match o.Ob.verdict with
      | Ob.Skipped _ when List.exists (fun (c : A.fn_clause) -> within c.A.fc_span o.Ob.span) s.IS.fd.A.fn_clauses -> (
        match o.Ob.inst with
        | Some t -> Some t
        | None -> (
          match candidate_of_text o.Ob.predicate with
          | Some c when List.for_all (fun n -> n = "_") (names_of [] (c.PI.c_pred A.dummy_span)) -> Some o.Ob.predicate
          | _ -> None))
      | _ -> None)
    ledger

(* Every refinement written in a signature of the unit, binder renamed `_`. *)
let house ?(keep = fun (_ : string) (_ : A.fn_def) -> true) (decls : A.decl list) : string list =
  let out = ref [] in
  let rec ty (t : A.ty) =
    match t with
    | A.TyRefine (b, binder, pred) ->
      let pred =
        match binder with
        | Some n when n.A.txt <> "_" -> Refine_encode.subst_params [ (n.A.txt, A.EVar { A.txt = "_"; A.span = A.dummy_span }) ] pred
        | _ -> pred
      in
      out := Refine_scope.pred_str pred :: !out;
      ty b
    | A.TyCon (_, ts) | A.TyTuple ts -> List.iter ty ts
    | A.TyArrow (a, b) -> ty a; ty b
    | A.TyLinear (_, t) -> ty t
    | _ -> ()
  in
  List.iter
    (fun ((_, (fd : A.fn_def)) as pf) ->
      if keep (PI.qualified_of pf) fd then begin
      Option.iter ty fd.A.fn_ret_ty;
      match fd.A.fn_clauses with
      | c :: _ -> List.iter (fun (_, t) -> ty t) (PI.named_params c)
      | [] -> ()
      end)
    (PI.enum_fns [] decls);
  List.rev !out

let comparison_ops = [ "<"; "<="; ">"; ">="; "!="; "==" ]
let flip = function "<" -> ">" | "<=" -> ">=" | ">" -> "<" | ">=" -> "<=" | op -> op

(* Comparisons in the slot's function where one side is its binder (the
   parameter itself; for an element slot, a lambda parameter ranging over the
   elements) and the other a literal, a parameter, or `len(param)`. *)
let body (s : IS.slot) : string list =
  let params = match s.IS.fd.A.fn_clauses with c :: _ -> List.map fst (PI.named_params c) | [] -> [] in
  let binders = ref [] in
  let elem = match s.IS.path with IS.Elem _ | IS.Arg _ -> true | _ -> false in
  let rec lam_params (e : A.expr) =
    match e with
    | A.ELam (ps, b, _) -> List.iter (fun (p : A.param) -> binders := p.A.param_name.A.txt :: !binders) ps; lam_params b
    | A.EApp (f, xs, _) -> lam_params f; List.iter lam_params xs
    | A.EBlock (es, _) | A.ETuple (es, _) -> List.iter lam_params es
    | A.ELet (b, _) -> lam_params b.A.bind_expr
    | A.EIf (c, t, f, _) -> lam_params c; lam_params t; lam_params f
    | A.EMatch (sc, brs, _) -> lam_params sc; List.iter (fun (br : A.branch) -> lam_params br.A.branch_body) brs
    | _ -> ()
  in
  List.iter (fun (c : A.fn_clause) -> lam_params c.A.fc_body) s.IS.fd.A.fn_clauses;
  let is_binder x =
    if elem then List.mem x !binders
    else match IS.root s.IS.path with IS.Param p -> x = p | _ -> false
  in
  let other_ok (e : A.expr) =
    match e with
    | A.ELit (A.LitInt _, _) | A.ELit (A.LitFloat _, _) -> true
    | A.EVar { A.txt; _ } -> List.mem txt params
    | A.EApp (A.EVar { A.txt = "len"; _ }, [ A.EVar { A.txt; _ } ], _) -> List.mem txt params
    | _ -> false
  in
  let out = ref [] in
  let rec walk (e : A.expr) =
    (match e with
     | A.EApp (A.EVar { A.txt = op; _ }, [ a; b ], _) when List.mem op comparison_ops -> (
       match a, b with
       | A.EVar { A.txt = x; _ }, o when is_binder x && other_ok o ->
         out := Printf.sprintf "_ %s %s" op (Refine_scope.pred_str o) :: !out
       | o, A.EVar { A.txt = x; _ } when is_binder x && other_ok o ->
         out := Printf.sprintf "_ %s %s" (flip op) (Refine_scope.pred_str o) :: !out
       | _ -> ())
     | _ -> ());
    match e with
    | A.EApp (f, xs, _) -> walk f; List.iter walk xs
    | A.EBlock (es, _) | A.ETuple (es, _) -> List.iter walk es
    | A.ELet (b, _) -> walk b.A.bind_expr
    | A.EIf (c, t, f, _) -> walk c; walk t; walk f
    | A.EMatch (sc, brs, _) -> walk sc; List.iter (fun (br : A.branch) -> walk br.A.branch_body) brs
    | A.ELam (_, b, _) -> walk b
    | _ -> ()
  in
  List.iter (fun (c : A.fn_clause) -> walk c.A.fc_body) s.IS.fd.A.fn_clauses;
  List.rev !out

(* Relational scalar returns (the G1 shape, checked since 2026-10-24): for a
   scalar return slot, `_ OP x` over a parameter [x] of the return's own sort,
   read off the body's TAILS — never the whole cross product of parameters
   and operators.  A tail
     `x`              gives `_ >= x`, `_ <= x`, `_ == x`;
     `x + c` (c > 0)  gives `_ > x`, `_ >= x`, `_ == x + c`;
     `x - c` (c > 0)  gives `_ < x`, `_ <= x`, `_ == x - c`;
     `x + y`, `x - y` gives `_ == x + y`, `_ == x - y` (both parameters).
   Inequalities first, then equalities; at most [rel_return_cap].  Only for a
   function with an in-unit caller: a return is USEFUL only where a caller's
   site closes, so without one every probe would be wasted. *)
let rel_return_cap = 4

(* A demand a return could meet: an unsettled obligation in the body of a
   function that calls [s]'s function (by name, over-approximate).  A return
   is USEFUL only by closing such a site, so without one every probe is
   wasted.  Measured on `test/native` (2026-10-25): without this gate the
   relational returns and the per-argument `Result(a, e)` return slots cost
   +0.4x aggregate time and proposed nothing. *)
let caller_has_skip (s : IS.slot) ~(ledger : Ob.t list) ~(unit_decls : A.decl list) : bool =
  (* Spans first, bodies last: the unit includes the stdlib, and walking
     every body for a call (as [PI.fn_calls] does) per slot cost seconds per
     file; only a function that holds a skip is walked. *)
  let skips = List.filter (fun (o : Ob.t) -> match o.Ob.verdict with Ob.Skipped _ -> true | _ -> false) ledger in
  skips <> []
  &&
  let name = s.IS.fd.A.fn_name.A.txt in
  List.exists
    (fun (_, (g : A.fn_def)) ->
      g != s.IS.fd
      && List.exists
           (fun (o : Ob.t) -> List.exists (fun (c : A.fn_clause) -> within c.A.fc_span o.Ob.span) g.A.fn_clauses)
           skips
      && PI.fn_calls name g)
    (PI.enum_fns [] unit_decls)

(* A skip in [s]'s own body: the only place a precondition can close one. *)
let body_has_skip (s : IS.slot) ~(ledger : Ob.t list) : bool =
  List.exists
    (fun (o : Ob.t) ->
      match o.Ob.verdict with
      | Ob.Skipped _ -> List.exists (fun (c : A.fn_clause) -> within c.A.fc_span o.Ob.span) s.IS.fd.A.fn_clauses
      | _ -> false)
    ledger

let rel_returns (s : IS.slot) ~(ledger : Ob.t list) ~(unit_decls : A.decl list) : string list =
  match s.IS.path, s.IS.fd.A.fn_clauses with
  | IS.Return, c :: _ when (match PI.kind_of_ty s.IS.base with PI.KInt | PI.KFloat -> true | _ -> false) ->
    let k = PI.kind_of_ty s.IS.base in
    let same = List.filter_map (fun (n, t) -> if PI.kind_of_ty t = k then Some n else None) (PI.named_params c) in
    if same = [] || not (caller_has_skip s ~ledger ~unit_decls) then []
    else begin
      let rec tails (e : A.expr) : A.expr list =
        match e with
        | A.EBlock (es, _) -> (match List.rev es with x :: _ -> tails x | [] -> [])
        | A.EIf (_, t, f, _) -> tails t @ tails f
        | A.EMatch (_, brs, _) -> List.concat_map (fun (br : A.branch) -> tails br.A.branch_body) brs
        | A.EAnnot (x, _, _) -> tails x
        | e -> [ e ]
      in
      let param = function A.EVar { A.txt; _ } when List.mem txt same -> Some txt | _ -> None in
      let pos_lit = function
        | A.ELit (A.LitInt n, _) when n > 0 -> true
        | A.ELit (A.LitFloat f, _) when f > 0.0 -> true
        | _ -> false
      in
      let ineq = ref [] and eq = ref [] in
      let add r t = if not (List.mem t !r) then r := !r @ [ t ] in
      let lit e = Refine_scope.pred_str e in
      List.iter
        (fun (t : A.expr) ->
          match t with
          | A.EVar _ -> (
            match param t with
            | Some x -> add ineq (Printf.sprintf "_ >= %s" x); add ineq (Printf.sprintf "_ <= %s" x); add eq (Printf.sprintf "_ == %s" x)
            | None -> ())
          | A.EApp (A.EVar { A.txt = "+"; _ }, [ a; b ], _) -> (
            match param a, param b with
            | Some x, Some y -> add eq (Printf.sprintf "_ == %s + %s" x y)
            | Some x, None when pos_lit b ->
              add ineq (Printf.sprintf "_ > %s" x); add ineq (Printf.sprintf "_ >= %s" x);
              add eq (Printf.sprintf "_ == %s + %s" x (lit b))
            | None, Some x when pos_lit a ->
              add ineq (Printf.sprintf "_ > %s" x); add ineq (Printf.sprintf "_ >= %s" x);
              add eq (Printf.sprintf "_ == %s + %s" x (lit a))
            | _ -> ())
          | A.EApp (A.EVar { A.txt = "-"; _ }, [ a; b ], _) -> (
            match param a, param b with
            | Some x, Some y -> add eq (Printf.sprintf "_ == %s - %s" x y)
            | Some x, None when pos_lit b ->
              add ineq (Printf.sprintf "_ < %s" x); add ineq (Printf.sprintf "_ <= %s" x);
              add eq (Printf.sprintf "_ == %s - %s" x (lit b))
            | _ -> ())
          | _ -> ())
        (List.concat_map (fun (c : A.fn_clause) -> tails c.A.fc_body) s.IS.fd.A.fn_clauses);
      List.filteri (fun i _ -> i < rel_return_cap) (!ineq @ !eq)
    end
  | _ -> []

let fixed (s : IS.slot) : PI.candidate list =
  let measurable =
    match s.IS.fd.A.fn_clauses with
    | c :: _ ->
      List.filter_map
        (fun (n, t) -> match PI.kind_of_ty t with PI.KList | PI.KString -> Some n | _ -> None)
        (PI.named_params c)
    | [] -> []
  in
  match PI.kind_of_ty s.IS.base with
  | PI.KInt -> PI.int_candidates ~measurable
  | PI.KFloat -> PI.float_candidates
  | PI.KList | PI.KString -> PI.measured_candidates
  | PI.KOther -> []

(* ── Mining ──────────────────────────────────────────────────────────────── *)

let mine_full (s : IS.slot) ~(ledger : Ob.t list) ~(unit_decls : A.decl list) : cand list * bool =
  let of_texts src ts = List.filter_map (fun t -> Option.map (fun c -> { c; source = src }) (candidate_of_text t)) ts in
  let all =
    of_texts Demand (demands s ledger)
    @ of_texts House
        (house
           ~keep:(fun q (fd : A.fn_def) ->
             (* user code (empty or the slot's own file), or a function the
                slot's function calls *)
             fd.A.fn_name.A.span.A.file = s.IS.fd.A.fn_name.A.span.A.file
             || PI.fn_calls (match List.rev (String.split_on_char '.' q) with x :: _ -> x | [] -> q) s.IS.fd)
           unit_decls)
    @ of_texts Body (body s)
    @ List.map (fun c -> { c; source = Fixed }) (fixed s)
  in
  let seen = Hashtbl.create 16 in
  let uniq =
    List.filter
      (fun c ->
        let t = c.c.PI.c_text in
        if Hashtbl.mem seen t then false else (Hashtbl.add seen t (); true))
      (List.filter (fun c -> admissible_text s c.c) all)
  in
  let n = List.length uniq in
  let kept, truncated = if n > cap then (List.filteri (fun i _ -> i < cap) uniq, true) else (uniq, false) in
  (* The relational returns have their own allowance on top of the cap, so
     they never displace a candidate the other sources supplied. *)
  let rel =
    List.filter
      (fun c -> admissible_text s c.c && not (List.exists (fun k -> k.c.PI.c_text = c.c.PI.c_text) kept))
      (of_texts Body (rel_returns s ~ledger ~unit_decls))
  in
  (kept @ rel, truncated)

let mine s ~ledger ~unit_decls = fst (mine_full s ~ledger ~unit_decls)

(* ── Implication order ───────────────────────────────────────────────────── *)

let implies_cache : (string, bool) Hashtbl.t = Hashtbl.create 64

(* Does [c1] imply [c2] for a value of type [base], with [scope]'s names free?
   Asked of the real checker: a probe whose parameter is refined by [c1] passes
   it to a callee demanding [c2]. *)
let implies ~(root : string) ~(scope : (string * A.ty) list) ~(base : A.ty) (c1 : string) (c2 : string) : bool =
  let ty_s t = Option.value (IS.render IS.Return t) ~default:"Int" in
  let base_s = ty_s base in
  (* The scope names come BEFORE `v`: a refinement may name only an earlier
     parameter (a later one leaves `v` an unconstrained subject, and every
     relational implication was then "not proved", so relational candidates
     were never ordered; found 2026-10-25). *)
  let extra = String.concat "" (List.map (fun (n, t) -> Printf.sprintf "%s : %s, " n (ty_s t)) scope) in
  let args = String.concat "" (List.map (fun (n, _) -> n ^ ", ") scope) in
  let key = String.concat "\x00" [ base_s; extra; c1; c2 ] in
  match Hashtbl.find_opt implies_cache key with
  | Some b -> b
  | None ->
    let src =
      Printf.sprintf
        "mod InferImp do\n  fn __infer_imp_need__(%s__infer_imp_v__ : {%s | %s}) : Int do 0 end\n  fn __infer_imp_probe__(%s__infer_imp_v__ : {%s | %s}) : Int do __infer_imp_need__(%s__infer_imp_v__) end\nend\n"
        extra base_s c2 extra base_s c1 args
    in
    let b =
      match March_parser.Parse.module_of_lexbuf (Lexing.from_string src) with
      | exception _ -> false
      | m ->
        Ob.with_scratch @@ fun () ->
        let defs = Refine_check.collect_all_defs m.A.mod_decls in
        let snap = PI.walk_ledger ~root ~defs m.A.mod_decls in
        List.exists
          (fun ((k : Ledger_diff.key), v) -> k.Ledger_diff.callee = "__infer_imp_need__" && v = Ob.Proved)
          snap
    in
    Hashtbl.replace implies_cache key b;
    b

(* Weakest first.  A candidate is placed when no remaining one is strictly
   weaker than it; ties by source rank, then text.  Mutually implying
   candidates are one: the shortest text is kept. *)
let order ~(root : string) ~(scope : (string * A.ty) list) ~(base : A.ty) (cs : cand list) : cand list =
  let imp a b = implies ~root ~scope ~base a.c.PI.c_text b.c.PI.c_text in
  let key c = (source_rank c.source, c.c.PI.c_text) in
  (* dedupe equivalents *)
  let rec dedupe acc = function
    | [] -> List.rev acc
    | c :: tl ->
      let same, rest = List.partition (fun d -> imp c d && imp d c) tl in
      let best =
        List.fold_left
          (fun a b -> if String.length b.c.PI.c_text < String.length a.c.PI.c_text then b else a)
          c same
      in
      dedupe (best :: acc) rest
  in
  let rec go acc remaining =
    if remaining = [] then List.rev acc
    else
      let weakest =
        List.filter
          (fun c -> not (List.exists (fun d -> d != c && imp c d && not (imp d c)) remaining))
          remaining
      in
      let pick =
        match List.sort (fun a b -> compare (key a) (key b)) weakest with
        | p :: _ -> p
        | [] -> List.hd remaining
      in
      go (pick :: acc) (List.filter (fun c -> c != pick) remaining)
  in
  go [] (dedupe [] cs)
