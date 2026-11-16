(* The candidate search for lemma-call inference (`--refine-infer`, reflection
   phase 7; specs/2026-10-29-refinement-reflection-design.md §10 "Phase 7",
   plan specs/plans/2026-11-04-reflection-phase7-infer-lemmas-plan.md).

   Pure AST work: which obligations are targets, where a call would go and
   what is in scope there, which source terms the obligation is about, and
   which lemmas match them.  Nothing here decides whether a candidate helps;
   [Refine_infer.infer_lemmas] re-checks every one with the real checker. *)

module A = March_ast.Ast
module Ob = Obligation

(* ── Targets (ruling 1) ─────────────────────────────────────────────────── *)

(* A precondition only.  An `Int` result contract now sees the lemma calls
   before its tails ([Refine_post.post_walk_verdict],
   specs/progress/2026-11-04-return-contract-block-facts.md), but its
   obligation's span is the clause, not a tail, so [find_site] has no
   statement to place a call before. *)
let is_target ~(is_user : A.span -> bool) (o : Ob.t) =
  is_user o.Ob.span
  && o.Ob.kind = Ob.Precondition
  && match o.Ob.verdict with Ob.Skipped (Ob.Reflect_fuel _ | Ob.Reflect_budget) -> true | _ -> false

(* ── Spans ───────────────────────────────────────────────────────────────── *)

let within = Infer_vocab.within

(* ── Expressions, up to spans ────────────────────────────────────────────── *)

let last_seg (s : string) =
  match String.rindex_opt s '.' with Some i -> String.sub s (i + 1) (String.length s - i - 1) | None -> s

let rec same (a : A.expr) (b : A.expr) =
  match a, b with
  | A.EVar x, A.EVar y -> x.A.txt = y.A.txt
  | A.ELit (l, _), A.ELit (m, _) -> l = m
  | A.EApp (f, xs, _), A.EApp (g, ys, _) -> same f g && List.length xs = List.length ys && List.for_all2 same xs ys
  | A.ECon (c, xs, _), A.ECon (d, ys, _) ->
    c.A.txt = d.A.txt && List.length xs = List.length ys && List.for_all2 same xs ys
  | A.ETuple (xs, _), A.ETuple (ys, _) -> List.length xs = List.length ys && List.for_all2 same xs ys
  | A.EField (x, n, _), A.EField (y, m, _) -> n.A.txt = m.A.txt && same x y
  | _ -> false

(* Every application of a named function in [e], outermost first. *)
let rec calls (e : A.expr) : A.expr list =
  match e with
  | A.EApp (A.EVar _, args, _) -> e :: List.concat_map calls args
  | A.EApp (f, args, _) -> calls f @ List.concat_map calls args
  | A.ECon (_, args, _) | A.ETuple (args, _) -> List.concat_map calls args
  | A.EField (x, _, _) | A.EAnnot (x, _, _) -> calls x
  | A.EIf (c, a, b, _) -> calls c @ calls a @ calls b
  | _ -> []

(* The variables [e] reads (not application heads). *)
let rec free_vars (e : A.expr) : string list =
  match e with
  | A.EVar v -> [ v.A.txt ]
  | A.EApp (A.EVar _, args, _) -> List.concat_map free_vars args
  | A.EApp (f, args, _) -> free_vars f @ List.concat_map free_vars args
  | A.ECon (_, args, _) | A.ETuple (args, _) -> List.concat_map free_vars args
  | A.EField (x, _, _) | A.EAnnot (x, _, _) -> free_vars x
  | A.EIf (c, a, b, _) -> free_vars c @ free_vars a @ free_vars b
  | A.ELit _ -> []
  | _ -> [ "$opaque" ]

let rec pat_vars (p : A.pattern) : string list =
  match p with
  | A.PatVar n -> [ n.A.txt ]
  | A.PatCon (_, ps) | A.PatAtom (_, ps, _) | A.PatTuple (ps, _) -> List.concat_map pat_vars ps
  | A.PatRecord (fs, _) -> List.concat_map (fun (_, p) -> pat_vars p) fs
  | A.PatAs (p, n, _) -> n.A.txt :: pat_vars p
  | A.PatOr (p :: _, _) -> pat_vars p
  | _ -> []

(* ── The site (ruling 4) ─────────────────────────────────────────────────── *)

type site = {
  fn : string list * A.fn_def;  (** the enclosing function, with its module path *)
  clause : int;  (** which clause *)
  stmt : A.expr;  (** the statement the call goes before *)
  scope : string list;  (** the names in scope there *)
  lets : (string * A.expr) list;  (** the [let x = e] in scope, innermost first *)
  rebuild : A.expr -> A.expr;  (** the clause body with a statement inserted *)
}

let span_of = March_typecheck.Typecheck.span_of_expr

(* A binder of [names] hides every [let] entry for one of them, and every
   entry whose right-hand side reads one of them (it read the older one). *)
let rebind (names : string list) (lets : (string * A.expr) list) =
  List.filter (fun (x, e) -> not (List.mem x names || List.exists (fun v -> List.mem v names) (free_vars e))) lets

let bind names scope lets = (names @ scope, rebind names lets)

(* The innermost block statement of [body] containing [sp], with what is in
   scope at it.  A context that holds an expression but is not a block (an
   arm body, a branch, a lambda body) counts as a one-statement block, and
   inserting there wraps it. *)
let locate (body : A.expr) (sp : A.span) (params : string list) :
    (A.expr * string list * (string * A.expr) list * (A.expr -> A.expr)) option =
  let contains e = within (span_of e) sp in
  (* [slot] is a position holding one expression; [k] rebuilds the parent. *)
  let rec slot scope lets (e : A.expr) (k : A.expr -> A.expr) =
    if not (contains e) then None
    else
      match e with
      | A.EBlock (es, bsp) -> block scope lets [] es (fun es' -> k (A.EBlock (es', bsp)))
      | _ -> (
        match inner scope lets e k with
        | Some r -> Some r
        | None -> Some (e, scope, lets, fun c -> k (A.EBlock ([ c; e ], span_of e))))
  and block scope lets before es k =
    match es with
    | [] -> None
    | s :: rest ->
      if contains s then
        match inner scope lets s (fun s' -> k (List.rev_append before (s' :: rest))) with
        | Some r -> Some r
        | None -> Some (s, scope, lets, fun c -> k (List.rev_append before (c :: s :: rest)))
      else
        let scope, lets =
          match s with
          | A.ELet ({ A.bind_pat = A.PatVar n; bind_expr; _ }, _) ->
            let x = n.A.txt in
            (* `let n = n - 1` reads the n it shadows: no entry for it. *)
            let own = if List.mem x (free_vars bind_expr) then [] else [ (x, bind_expr) ] in
            (x :: scope, own @ rebind [ x ] lets)
          | A.ELet ({ A.bind_pat; _ }, _) -> bind (pat_vars bind_pat) scope lets
          | A.ELetFn (n, _, _, _, _) -> bind [ n.A.txt ] scope lets
          | _ -> (scope, lets)
        in
        block scope lets (s :: before) rest k
  (* Below a statement [e]: the nested slots that may hold [sp]. *)
  and inner scope lets (e : A.expr) (k : A.expr -> A.expr) =
    let first l = List.find_map (fun f -> f ()) l in
    match e with
    | A.EBlock _ -> slot scope lets e k
    | A.ELet (b, lsp) -> inner scope lets b.A.bind_expr (fun x -> k (A.ELet ({ b with A.bind_expr = x }, lsp)))
    | A.EIf (c, a, b, isp) ->
      first
        [ (fun () -> inner scope lets c (fun c' -> k (A.EIf (c', a, b, isp))));
          (fun () -> slot scope lets a (fun a' -> k (A.EIf (c, a', b, isp))));
          (fun () -> slot scope lets b (fun b' -> k (A.EIf (c, a, b', isp)))) ]
    | A.EMatch (s, brs, msp) ->
      first
        ((fun () -> inner scope lets s (fun s' -> k (A.EMatch (s', brs, msp))))
        :: List.mapi
             (fun i (br : A.branch) () ->
               let scope, lets = bind (pat_vars br.A.branch_pat) scope lets in
               slot scope lets br.A.branch_body (fun b' ->
                   k (A.EMatch (s, List.mapi (fun j br -> if i = j then { br with A.branch_body = b' } else br) brs, msp))))
             brs)
    | A.ELam (ps, b, lsp) ->
      let scope, lets = bind (List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps) scope lets in
      slot scope lets b (fun b' -> k (A.ELam (ps, b', lsp)))
    | A.ELetFn (n, ps, t, b, fsp) ->
      let scope, lets = bind (n.A.txt :: List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps) scope lets in
      slot scope lets b (fun b' -> k (A.ELetFn (n, ps, t, b', fsp)))
    | _ -> None
  in
  slot params [] body (fun b -> b)

let clause_params (fc : A.fn_clause) =
  List.concat_map (function A.FPNamed p | A.FPDefault (p, _) -> [ p.A.param_name.A.txt ] | A.FPPat p -> pat_vars p) fc.A.fc_params

let find_site (decls : A.decl list) (sp : A.span) : site option =
  List.find_map
    (fun ((_, (fd : A.fn_def)) as pf) ->
      List.find_map
        (fun (i, (fc : A.fn_clause)) ->
          if not (within (span_of fc.A.fc_body) sp) then None
          else
            Option.map
              (fun (stmt, scope, lets, rebuild) -> { fn = pf; clause = i; stmt; scope; lets; rebuild })
              (locate fc.A.fc_body sp (clause_params fc)))
        (List.mapi (fun i c -> (i, c)) fd.A.fn_clauses))
    (Precond_infer.enum_fns [] decls)

(* ── The pool (ruling 2) ─────────────────────────────────────────────────── *)

(* The expression whose span is [sp], searched in [e]. *)
let rec at_span (sp : A.span) (e : A.expr) : A.expr option =
  if span_of e = sp then Some e
  else if not (within (span_of e) sp) then None
  else
    let sub =
      match e with
      | A.EApp (f, args, _) -> f :: args
      | A.ECon (_, args, _) | A.ETuple (args, _) -> args
      | A.EBlock (es, _) -> es
      | A.ELet (b, _) -> [ b.A.bind_expr ]
      | A.EIf (c, a, b, _) -> [ c; a; b ]
      | A.EMatch (s, brs, _) -> s :: List.map (fun (b : A.branch) -> b.A.branch_body) brs
      | A.ELam (_, b, _) | A.ELetFn (_, _, _, b, _) -> [ b ]
      | A.EField (x, _, _) | A.EAnnot (x, _, _) -> [ x ]
      | _ -> []
    in
    List.find_map (at_span sp) sub

(* The call subterms the obligation at [o] is about, with the right-hand
   sides of the [let]s they read, transitively. *)
let pool (s : site) (o : Ob.t) : A.expr list =
  let roots = match at_span o.Ob.span s.stmt with Some (A.EApp (_, args, _)) -> args | _ -> [] in
  let rec expand seen acc = function
    | [] -> List.rev acc
    | e :: rest ->
      let vs = List.filter (fun v -> List.mem_assoc v s.lets && not (List.mem v seen)) (free_vars e) in
      let seen = vs @ seen in
      expand seen (List.rev_append (calls e) acc) (rest @ List.map (fun v -> List.assoc v s.lets) vs)
  in
  expand [] [] roots

(* ── Matching (ruling 3) ─────────────────────────────────────────────────── *)

(* Bind the lemma parameters [ps] so that [pat] (from the theorem) is [t]
   (from the program); heads compare by last name segment. *)
let rec unify (ps : string list) (env : (string * A.expr) list) (pat : A.expr) (t : A.expr) :
    (string * A.expr) list option =
  match pat, t with
  | A.EVar x, _ when List.mem x.A.txt ps -> (
    match List.assoc_opt x.A.txt env with
    | Some b -> if same b t then Some env else None
    | None -> Some ((x.A.txt, t) :: env))
  | A.EVar x, A.EVar y -> if last_seg x.A.txt = last_seg y.A.txt then Some env else None
  | A.ELit (l, _), A.ELit (m, _) -> if l = m then Some env else None
  | A.EApp (A.EVar f, xs, _), A.EApp (A.EVar g, ys, _)
    when last_seg f.A.txt = last_seg g.A.txt && List.length xs = List.length ys ->
    unify_all ps env xs ys
  | A.ECon (c, xs, _), A.ECon (d, ys, _) when last_seg c.A.txt = last_seg d.A.txt && List.length xs = List.length ys
    ->
    unify_all ps env xs ys
  | A.ETuple (xs, _), A.ETuple (ys, _) when List.length xs = List.length ys -> unify_all ps env xs ys
  | _ -> None

and unify_all ps env xs ys =
  List.fold_left2 (fun acc x y -> match acc with None -> None | Some env -> unify ps env x y) (Some env) xs ys

type lemma = { l_name : string; l_fd : A.fn_def; l_params : string list; l_theorem : A.expr }

let lemma_of ((q, fd, _) : string * A.fn_def * bool) : lemma option =
  match fd.A.fn_clauses, Refine_post.assumed_return fd with
  | [ fc ], Some th ->
    let ps = List.filter_map (function A.FPNamed p -> Some p.A.param_name.A.txt | A.FPPat _ | A.FPDefault _ -> None) fc.A.fc_params in
    if List.length ps = List.length fc.A.fc_params then Some { l_name = q; l_fd = fd; l_params = ps; l_theorem = th }
    else None
  | _ -> None

(* Every instantiation of [l] one pool term determines, as the argument list
   in parameter order; arguments must be in [scope]. *)
let matches (l : lemma) ~(scope : string list) (pool : A.expr list) : A.expr list list =
  let pats = calls l.l_theorem in
  let found = ref [] in
  List.iter
    (fun pat ->
      List.iter
        (fun t ->
          match unify l.l_params [] pat t with
          | Some env when List.for_all (fun p -> List.mem_assoc p env) l.l_params ->
            let args = List.map (fun p -> List.assoc p env) l.l_params in
            if List.for_all (fun a -> List.for_all (fun v -> List.mem v scope) (free_vars a)) args
               && not (List.exists (fun prev -> List.for_all2 same prev args) !found)
            then found := args :: !found
          | _ -> ())
        pool)
    pats;
  List.rev !found

(* ── Skeletons (ruling 6) ────────────────────────────────────────────────── *)

(* [e] with the variables of [env] replaced, in the predicate fragment. *)
let rec subst (env : (string * A.expr) list) (e : A.expr) : A.expr =
  let go = subst env in
  match e with
  | A.EVar v -> ( match List.assoc_opt v.A.txt env with Some r -> r | None -> e)
  | A.EApp (A.EVar f, args, sp) -> A.EApp (A.EVar f, List.map go args, sp)
  | A.EApp (f, args, sp) -> A.EApp (go f, List.map go args, sp)
  | A.ECon (c, args, sp) -> A.ECon (c, List.map go args, sp)
  | A.ETuple (args, sp) -> A.ETuple (List.map go args, sp)
  | A.EField (x, n, sp) -> A.EField (go x, n, sp)
  | A.EAnnot (x, t, sp) -> A.EAnnot (go x, t, sp)
  | A.EIf (c, a, b, sp) -> A.EIf (go c, go a, go b, sp)
  (* A bounded quantifier's body: the binder shadows [env], and a replacement
     that mentions the binder would be captured, so leave that body alone. *)
  | A.ELam (ps, b, sp) ->
    let bound = List.map (fun p -> p.A.param_name.A.txt) ps in
    let env = List.filter (fun (v, _) -> not (List.mem v bound)) env in
    if List.exists (fun (_, r) -> List.exists (fun x -> March_ast.Bounded_pred.may_mention x r) bound) env then e
    else A.ELam (ps, subst env b, sp)
  | _ -> e

let refined (t : A.ty option) = match t with Some (A.TyRefine (_, b, p)) -> Some ((match b with Some n -> n.A.txt | None -> "_"), p) | _ -> None

let named_params (fc : A.fn_clause) : (string * A.ty option) list option =
  let ps = List.filter_map (function A.FPNamed p -> Some (p.A.param_name.A.txt, p.A.param_ty) | _ -> None) fc.A.fc_params in
  if List.length ps = List.length fc.A.fc_params then Some ps else None

(** What a skeleton lemma would state: [sk_goal] over the enclosing function's
    parameters [sk_params] (each with its declared type). *)
type skeleton = { sk_name : string; sk_params : (string * A.ty) list; sk_goal : A.expr }

(* The precondition at [o], stated over the enclosing function's parameters:
   the callee's predicate at the call's arguments, with every [let]-bound
   local replaced by its right-hand side.  [text_of] reads a
   predicate's source, to find which refined parameter [o] is about. *)
let goal_of ~(text_of : A.span -> string option) (decls : A.decl list) (s : site) (o : Ob.t) : A.expr option =
  let fns = Precond_infer.enum_fns [] decls in
  let at = at_span o.Ob.span s.stmt in
  let raw =
    match o.Ob.kind, at with
    | Ob.Precondition, Some (A.EApp (A.EVar f, args, _)) -> (
      let callee =
        List.find_map
          (fun ((_, (fd : A.fn_def)) as pf) ->
            match fd.A.fn_clauses with
            | [ fc ]
              when (Precond_infer.qualified_of pf = o.Ob.callee || last_seg (Precond_infer.qualified_of pf) = last_seg f.A.txt)
                   && List.length fc.A.fc_params = List.length args ->
              named_params fc
            | _ -> None)
          fns
      in
      match callee with
      | None -> None
      | Some ps ->
        let actuals = List.combine (List.map fst ps) args in
        let preds = List.filter_map (fun (n, t) -> Option.map (fun (b, p) -> (n, b, p)) (refined t)) ps in
        let pick =
          match List.filter (fun (_, _, p) -> text_of (span_of p) = Some o.Ob.predicate) preds with
          | [ x ] -> Some x
          | _ -> ( match preds with [ x ] -> Some x | _ -> None)
        in
        Option.map (fun (n, b, p) -> subst ((b, List.assoc n actuals) :: actuals) p) pick)
    | _ -> None
  in
  let rec inline k g =
    if k = 0 then g
    else
      let vs = List.filter (fun v -> List.mem_assoc v s.lets) (free_vars g) in
      if vs = [] then g else inline (k - 1) (subst (List.map (fun v -> (v, List.assoc v s.lets)) vs) g)
  in
  Option.map (inline 8) raw

let skeleton_of ~text_of ?(avoid : string list = []) (decls : A.decl list) (s : site) (o : Ob.t) : skeleton option =
  match goal_of ~text_of decls s o with
  | None -> None
  | Some g -> (
    let fd = snd s.fn in
    let fc = List.nth fd.A.fn_clauses s.clause in
    match named_params fc with
    | None -> None
    | Some ps ->
      let vs = List.sort_uniq compare (free_vars g) in
      (* A parameter some binder shadows at the call is not the name the goal reads. *)
      let once n = List.length (List.filter (( = ) n) s.scope) = 1 in
      let typed =
        List.filter_map (fun (n, t) -> match t with Some t when List.mem n vs && once n -> Some (n, t) | _ -> None) ps
      in
      if vs = [] || List.length typed <> List.length vs then None
      else
        let taken = avoid @ List.map (fun (_, (f : A.fn_def)) -> f.A.fn_name.A.txt) (Precond_infer.enum_fns [] decls) in
        let base = fd.A.fn_name.A.txt ^ "_lemma" in
        let rec fresh k = let n = if k = 1 then base else Printf.sprintf "%s_%d" base k in if List.mem n taken then fresh (k + 1) else n in
        Some { sk_name = fresh 1; sk_params = typed; sk_goal = g })

let skeleton_text (sk : skeleton) =
  let module F = March_format.Format in
  Printf.sprintf "@[lemma]\nfn %s(%s) : {Unit | %s} do\n  ()\nend" sk.sk_name
    (String.concat ", " (List.map (fun (n, t) -> n ^ " : " ^ F.fmt_ty t) sk.sk_params))
    (F.expr_inline sk.sk_goal)

let skeleton_call (sk : skeleton) = Printf.sprintf "%s(%s)" sk.sk_name (String.concat ", " (List.map fst sk.sk_params))
