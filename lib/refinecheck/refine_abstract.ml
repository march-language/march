(* Abstract refinements: a refinement parameterised by a predicate.

   Design: specs/2026-09-20-abstract-refinements-design.md.  This module is
   PHASE 1 and is deliberately INERT with respect to every verdict: it decides
   which names in a signature are abstract refinements, reports the
   well-formedness errors of design §1, and hands the names to the
   predicate-vocabulary warning so a declared one is not reported as "not a
   measure".  Nothing here translates to SMT — an obligation over `p(_)` is
   still the `unreflectable-predicate` skip it was before, until phase 2 adds
   the encoding (design §2).

   Liquid Haskell spells this `filter :: (a -> Bool<p>) -> [a] -> [a<p>]`.
   March v1 spells it with today's grammar (both forms probed at 3cac5eaf5):

     fn filter(xs : List(a),
               keep : ({x : a | true}) -> {Bool | _ == p(x)})
             : List({a | p(_)})

   Three roles, from design §1:
   - DEFINER: an application inside the codomain refinement of an ARROW
     parameter, applied to that arrow's domain binder.  It is what fixes the
     predicate at a call site.
   - POSITIVE: an application inside the return type's element refinement,
     applied to that refinement's own binder.  The fact callers receive.
   - NEGATIVE: the same inside a parameter's element refinement.  An
     obligation on the caller.

   A name is a candidate iff it is applied to exactly one argument inside a
   refinement, is not recognized predicate vocabulary ([~is_known], supplied by
   [Refine_check] so this module stays below it and cannot see measures
   directly), and is not a value parameter of the same function.  Everything
   else about it is then CHECKED rather than assumed: the errors below are hard
   errors precisely because a signature is small and its author can see it, and
   a silent skip is what this whole feature exists to remove. *)

module A = March_ast.Ast
module Err = March_errors.Errors

type role = Definer | Positive | Negative

type occurrence = {
  occ_name : string;        (* the abstract refinement's name, e.g. "p" *)
  occ_role : role;
  occ_span : A.span;
  occ_arg : string;         (* the name it is applied to, "_" for the wildcard *)
  occ_binder : string;      (* the binder in scope at that occurrence *)
  occ_base : string;        (* rendered base type, for the same-sort rule *)
  (* Multi-arg design 2026-10-18 §5.1.  [occ_args]: every argument, in order
     ("$computed" for a computed one; one element for an arity-1 application,
     where it equals [occ_arg]).  [occ_scope]: for a DEFINER, the callback
     chain's domains as (binder, base), "_" for a domain with no binder; for a
     slot occurrence, every slot of the enclosing type application as
     (binder, base).  [occ_slot]: the index of the slot the occurrence sits in
     ([None] outside a type application's argument).  [occ_cont]: that
     application's constructor. *)
  occ_args : string list;
  occ_scope : (string * string) list;
  occ_slot : int option;
  occ_cont : string option;
}

(* A rendered key for the base type an occurrence sits at.  Deliberately
   syntactic: two occurrences at `a` agree, `a` and `Int` do not.  The design's
   rule 4 is about catching an author's mistake, not about unification. *)
let rec base_key (t : A.ty) : string =
  match t with
  | A.TyRefine (b, _, _) -> base_key b
  | A.TyCon ({ A.txt; _ }, []) -> txt
  | A.TyCon ({ A.txt; _ }, args) ->
    txt ^ "(" ^ String.concat "," (List.map base_key args) ^ ")"
  | A.TyVar { A.txt; _ } -> txt
  | A.TyArrow (a, b) -> base_key a ^ "->" ^ base_key b
  | A.TyTuple ts -> "(" ^ String.concat "," (List.map base_key ts) ^ ")"
  | A.TyRecord _ -> "{record}"
  | A.TyLinear (_, t) -> base_key t
  | A.TyChan _ -> "{chan}"
  | A.TyNat n -> string_of_int n
  | A.TyNatOp _ -> "{natop}"

let binder_of (b : A.name option) : string =
  match b with Some { A.txt; _ } -> txt | None -> "_"

(* Applications of a single argument inside a predicate, as (name, arg, span).
   The argument is classified only when it is a bare variable or `_`; anything
   else ([None]) is reported by rule 2, since an abstract refinement applied to
   a computed expression has no meaning this design gives it. *)
let rec applications (e : A.expr) : (string * string option * A.span) list =
  match e with
  | A.EApp (A.EVar { A.txt = f; _ }, [ arg ], span) ->
    let a =
      match arg with
      | A.EVar { A.txt; _ } -> Some txt
      | _ -> None
    in
    (f, a, span) :: applications arg
  | A.EApp (f, args, _) -> applications f @ List.concat_map applications args
  | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) ->
    List.concat_map applications es
  | A.EAnnot (e, _, _) -> applications e
  | _ -> []

(* Applications of ANY arity ≥ 1 (multi-arg design 2026-10-18 §5.1), as
   (name, arguments, span), each argument classified as [applications] does.
   Its arity-1 entries are exactly [applications]'s; the walk is the same. *)
let rec applications_n (e : A.expr) : (string * string option list * A.span) list =
  match e with
  | A.EApp (A.EVar { A.txt = f; _ }, (_ :: _ as args), span) ->
    let cls (arg : A.expr) = match arg with A.EVar { A.txt; _ } -> Some txt | _ -> None in
    (f, List.map cls args, span) :: List.concat_map applications_n args
  | A.EApp (f, args, _) -> applications_n f @ List.concat_map applications_n args
  | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) ->
    List.concat_map applications_n es
  | A.EAnnot (e, _, _) -> applications_n e
  | _ -> []

(* Nested application of a candidate inside another's argument (`p(q(_))`),
   rejected by rule 5.  Detected structurally rather than by the flattened
   list above, which cannot tell `p(q(_))` from two siblings.

   `not` is exempt (leftovers design 2026-10-18 §3.1): `!p(_)` and
   `not(p(_))` are the negation of `p` at the binder, a Boolean connective
   rather than an application of one predicate to another.  Its argument is
   still walked, so `not(p(q(_)))` is still rejected. *)
let rec nested_apps (e : A.expr) : (string * A.span) list =
  match e with
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ arg ], _) -> nested_apps arg
  | A.EApp (A.EVar _, [ arg ], _) ->
    (match arg with
     | A.EApp (A.EVar { A.txt = inner; _ }, [ _ ], span) -> [ (inner, span) ]
     | _ -> [])
    @ nested_apps arg
  | A.EApp (f, args, _) -> nested_apps f @ List.concat_map nested_apps args
  | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) ->
    List.concat_map nested_apps es
  | A.EAnnot (e, _, _) -> nested_apps e
  | _ -> []

(* A SLOT PREDICATE (leftovers design §3.2): does [e] apply the abstract
   refinements [ps] only as `p(binder)` (or `p(_)`), and only under `&&`, `||`
   and `not`?  The parts that do not mention [ps] are left to the caller (they
   are ordinary vocabulary over the binder, translated or not as any
   refinement is).  `p(_) == false`, `if … p(_) …`, `p` under any other
   operator: [false], so a call site declines rather than guessing what the
   shape means. *)
let rec slot_mentions_only_applied (ps : string list) (binder : string) (e : A.expr) : bool =
  let rec mentions (e : A.expr) =
    match e with
    | A.EVar { A.txt; _ } -> List.mem txt ps
    | A.EApp (f, args, _) -> mentions f || List.exists mentions args
    | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) -> List.exists mentions es
    | A.EAnnot (e, _, _) | A.EField (e, _, _) -> mentions e
    | A.EBlock (es, _) -> List.exists mentions es
    | A.EIf (c, t, f, _) -> mentions c || mentions t || mentions f
    | A.EMatch (s, bs, _) ->
      mentions s || List.exists (fun (b : A.branch) -> mentions b.A.branch_body) bs
    | A.ELam _ -> true (* conservative: never looked inside *)
    | _ -> false
  in
  match e with
  | A.EApp (A.EVar { A.txt = p; _ }, [ A.EVar { A.txt = v; _ } ], _) when List.mem p ps ->
    v = binder || v = "_"
  | A.EApp (A.EVar { A.txt = ("&&" | "||"); _ }, [ a; b ], _) ->
    slot_mentions_only_applied ps binder a && slot_mentions_only_applied ps binder b
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) -> slot_mentions_only_applied ps binder a
  | A.EAnnot (e', _, _) -> slot_mentions_only_applied ps binder e'
  | _ -> not (mentions e)

(* [subst_abstract p (y, q) s]: every application `p(v)` in [s] replaced by
   [q] with [y := v] (leftovers design §3.2, `inst`).  [subst] is the
   simultaneous substitution [Refine_scope.subst_params] (passed in: this
   module sits below it).  Only the shapes [slot_mentions_only_applied]
   admits reach here, so an application is always to a bare variable. *)
let rec subst_abstract ~(subst : (string * A.expr) list -> A.expr -> A.expr) (p : string)
    ((y, q) : string * A.expr) (s : A.expr) : A.expr =
  let go = subst_abstract ~subst p (y, q) in
  match s with
  | A.EApp (A.EVar { A.txt; _ }, [ (A.EVar _ as v) ], _) when txt = p -> subst [ (y, v) ] q
  | A.EApp (f, args, sp) -> A.EApp (go f, List.map go args, sp)
  | A.ETuple (es, sp) -> A.ETuple (List.map go es, sp)
  | A.ECon (c, es, sp) -> A.ECon (c, List.map go es, sp)
  | A.EAtom (a, es, sp) -> A.EAtom (a, List.map go es, sp)
  | A.EAnnot (e, t, sp) -> A.EAnnot (go e, t, sp)
  | e -> e

(* The arity-n [subst_abstract]: every `p(a1, …, an)` replaced by [q] with
   [ys := as] (simultaneously, [subst]).  An application of [p] at another
   arity is left alone (W5 makes it unreachable from a well-formed
   signature). *)
let rec subst_abstract_n ~(subst : (string * A.expr) list -> A.expr -> A.expr) (p : string)
    ((ys, q) : string list * A.expr) (s : A.expr) : A.expr =
  let go = subst_abstract_n ~subst p (ys, q) in
  match s with
  | A.EApp (A.EVar { A.txt; _ }, args, _) when txt = p && List.length args = List.length ys ->
    subst (List.combine ys args) q
  | A.EApp (f, args, sp) -> A.EApp (go f, List.map go args, sp)
  | A.ETuple (es, sp) -> A.ETuple (List.map go es, sp)
  | A.ECon (c, es, sp) -> A.ECon (c, List.map go es, sp)
  | A.EAtom (a, es, sp) -> A.EAtom (a, List.map go es, sp)
  | A.EAnnot (e, t, sp) -> A.EAnnot (go e, t, sp)
  | e -> e

(* Walk one declared type, collecting occurrences at [role].

   [dom_binder] is the binder of the arrow domain whose codomain we are
   inside, so a definer's argument can be checked against it; it is [None]
   everywhere else.

   [chain] (multi-arg design §5.1): the domains of the callback CHAIN whose
   final codomain we are inside, as (binder, base), so a definer records the
   whole binder list (`D1 -> … -> Dn -> C`); the per-arrow [dom_binder] is
   its last element.  [app]: the enclosing type application's slots and the
   index of the slot being walked, for an occurrence directly in a slot's
   refinement (W2's sibling binders). *)
let rec walk_ty ~(role : role) ?(dom_binder : string option)
    ?(dom_base : string option) ?(chain : (string * string) list = [])
    ?(app : (string * (string * string) list * int) option) (t : A.ty)
    (acc : occurrence list ref) : unit =
  match t with
  | A.TyRefine (base, binder, pred) ->
    let b = binder_of binder in
    List.iter
      (fun (f, args, span) ->
        let arg_strs = List.map (fun a -> Option.value a ~default:"$computed") args in
        let n = List.length args in
        (* An application of several arguments is a DEFINER only on a chain
           of at least two domains: a tuple domain `((x, y)) -> {Bool | _ ==
           p(x, y)}` is ONE argument and defines nothing new (§1.1, s4), so it
           is left exactly as it was — no occurrence at all. *)
        let ident = String.length f > 0 && (match f.[0] with 'a' .. 'z' | '_' -> true | _ -> false) in
        if n >= 2 && not ident then ()
        else if role = Definer && n >= 2 && List.length chain < 2 then ()
        else
          acc :=
            { occ_name = f;
              occ_role = role;
              occ_span = span;
              occ_arg =
                (if n = 1 then List.hd arg_strs else String.concat ", " arg_strs);
              occ_binder =
                (match role, n with
                 | Definer, n when n >= 2 -> String.concat ", " (List.map fst chain)
                 | _ -> (match dom_binder with Some d -> d | None -> b));
              (* A DEFINER sits on a `Bool` codomain but is ABOUT the callback's
                 domain: `{Bool | _ == p(x)}` says what `p` means for an `x`.
                 Recording `Bool` here made rule 4 fire on the canonical
                 signature (`Bool` vs `a`), which is the whole feature. *)
              occ_base = (match dom_base with Some d -> d | None -> base_key base);
              occ_args = arg_strs;
              occ_scope =
                (match role, app with
                 | Definer, _ -> chain
                 | _, Some (_, slots, _) -> slots
                 | _, None -> []);
              occ_slot = (match role, app with Definer, _ -> None | _, Some (_, _, i) -> Some i | _ -> None);
              occ_cont = (match role, app with Definer, _ -> None | _, Some (c, _, _) -> Some c | _ -> None) }
            :: !acc)
      (List.filter (fun (_, args, _) -> args <> []) (applications_n pred));
    walk_ty ~role ?dom_binder ?dom_base ~chain base acc
  | A.TyCon ({ A.txt = c; _ }, args) ->
    let slot_of (t : A.ty) =
      match t with
      | A.TyRefine (b, binder, _) -> (binder_of binder, base_key b)
      | t -> ("_", base_key t)
    in
    let slots = List.map slot_of args in
    List.iteri
      (fun i a -> walk_ty ~role ?dom_binder ?dom_base ~app:(c, slots, i) a acc)
      args
  | A.TyArrow (dom, cod) ->
    (* The domain of an arrow parameter is where the callback RECEIVES values,
       so a refinement there is an obligation on the callee, not a definer;
       its own binder is what a codomain definer may name. *)
    let db = match dom with A.TyRefine (_, b, _) -> Some (binder_of b) | _ -> None in
    let link = (Option.value db ~default:"_", base_key dom) in
    let chain' = (if role = Definer then chain else []) @ [ link ] in
    walk_ty ~role:(match role with Negative -> Positive | _ -> Negative) ?dom_binder ?dom_base dom acc;
    walk_ty ~role:Definer ?dom_binder:db ~dom_base:(base_key dom) ~chain:chain' cod acc
  | A.TyTuple ts -> List.iter (fun t -> walk_ty ~role ?dom_binder ?dom_base t acc) ts
  | A.TyRecord fs -> List.iter (fun (_, t) -> walk_ty ~role ?dom_binder ?dom_base t acc) fs
  | A.TyLinear (_, t) -> walk_ty ~role ?dom_binder ?dom_base ~chain t acc
  | A.TyChan _ | A.TyVar _ | A.TyNat _ | A.TyNatOp _ -> ()

(* Every declared type of [fd]: each clause's parameter annotations, then the
   return type.  A parameter is Negative (the caller supplies it), the return
   Positive (the caller receives it); [walk_ty] flips at each arrow. *)
let signature_occurrences (fd : A.fn_def) : occurrence list =
  let acc = ref [] in
  List.iter
    (fun (c : A.fn_clause) ->
      List.iter
        (function
          | A.FPNamed p | A.FPDefault (p, _) ->
            Option.iter (fun t -> walk_ty ~role:Negative t acc) p.A.param_ty
          | A.FPPat _ -> ())
        c.A.fc_params)
    fd.A.fn_clauses;
  Option.iter (fun t -> walk_ty ~role:Positive t acc) fd.A.fn_ret_ty;
  List.rev !acc

let value_params (fd : A.fn_def) : string list =
  List.concat_map
    (fun (c : A.fn_clause) ->
      List.filter_map
        (function
          | A.FPNamed p | A.FPDefault (p, _) -> Some p.A.param_name.A.txt
          | A.FPPat _ -> None)
        c.A.fc_params)
    fd.A.fn_clauses

(* The abstract refinements [fd]'s signature declares, with their occurrences.
   [is_known] is [Refine_check.known_predicate_fn]: anything it recognizes is
   ordinary vocabulary (a measure, `len`, a set operation) and never a
   candidate. *)
let collect ~(is_known : string -> bool) (fd : A.fn_def) :
    (string * occurrence list) list =
  let params = value_params fd in
  let occs =
    List.filter
      (fun o -> (not (is_known o.occ_name)) && not (List.mem o.occ_name params))
      (signature_occurrences fd)
  in
  let names = List.sort_uniq compare (List.map (fun o -> o.occ_name) occs) in
  (* A name is abstract only if this signature DEFINES it — a callback codomain
     `{Bool | _ == p(x)}`.  Without a definer there is nothing to instantiate
     and no reason to read `bogus_fn(_)` as anything but what it has always
     been: a predicate calling a name the checker does not know, which
     [Refine_check.warn_predicate_expr] warns about.  Requiring the definer is
     what keeps this phase inert: dropping it silently swallowed that warning
     for every typo in a refinement (caught by probe a7). *)
  List.filter_map
    (fun n ->
      let os = List.filter (fun o -> o.occ_name = n) occs in
      if List.exists (fun o -> o.occ_role = Definer) os then Some (n, os) else None)
    names

let names ~(is_known : string -> bool) (fd : A.fn_def) : string list =
  List.map fst (collect ~is_known fd)

(* Is [occs] (one name's occurrences) about an arity-n abstract refinement
   (multi-arg design §1.4): some application of several arguments, or a
   definer under a callback chain of several domains?  Such a name is checked
   by W1-W5 ([check_nary]) instead of the arity-1 rules 2 and 4, which read a
   single argument against a single binder. *)
let is_nary (occs : occurrence list) : bool =
  List.exists
    (fun o -> List.length o.occ_args >= 2 || (o.occ_role = Definer && List.length o.occ_scope >= 2))
    occs

(* The number of arguments [p]'s definer applies it to (§5.1), or [None] when
   [p] is not an abstract refinement of [fd]. *)
let arity_of ~(is_known : string -> bool) (fd : A.fn_def) (p : string) : int option =
  match List.assoc_opt p (collect ~is_known fd) with
  | None -> None
  | Some occs ->
    List.find_map (fun o -> if o.occ_role = Definer then Some (List.length o.occ_args) else None) occs

let is_container_base (b : string) : bool = String.contains b '('

(* W1-W5 for one name of arity n (multi-arg design §1.4), hard errors
   [abstract_refinement_misuse].  [entry_shaped c s] is
   [Refine_encode.entry_shaped] (passed in: this module sits below it). *)
let check_nary (errctx : Err.ctx) ~(entry_shaped : name_of:(int -> string) -> string -> int list -> (unit, string) result)
    (name : string) (occs : occurrence list) : unit =
  let misuse span msg = Err.error ~code:Err.Code.abstract_refinement_misuse errctx ~span msg in
  let definers = List.filter (fun o -> o.occ_role = Definer) occs in
  let consumers = List.filter (fun o -> o.occ_role <> Definer) occs in
  let arity o = List.length o.occ_args in
  (* W1: the definer applies [p] to exactly the chain's binders, each once,
     in chain order (decision D3). *)
  let w1_bad =
    List.filter
      (fun o ->
        let binders = List.map fst o.occ_scope in
        let n = List.length binders in
        let named = List.for_all (fun b -> b <> "_") binders in
        let fix =
          if named then Printf.sprintf "write `%s(%s)`" name (String.concat ", " binders)
          else
            Printf.sprintf
              "name every argument of the callback (`({x : %s | true}) -> …`) and apply `%s` to \
               all %d of them, in order"
              (match o.occ_scope with (_, b) :: _ -> b | [] -> "a") name n
        in
        if arity o <> n then begin
          misuse o.occ_span
            (Printf.sprintf "abstract refinement `%s` is applied to %d of the callback's %d arguments; %s."
               name (arity o) n fix);
          true
        end
        else if (not named) || o.occ_args <> binders then begin
          misuse o.occ_span
            (Printf.sprintf
               "abstract refinement `%s` must be applied to the callback's arguments, each once, \
                in order; %s."
               name fix);
          true
        end
        else false)
      definers
  in
  match List.sort_uniq compare (List.map arity definers) with
  | _ :: _ :: _ as ns ->
    (* W5: one name, one arity. *)
    misuse (List.hd definers).occ_span
      (Printf.sprintf
         "abstract refinement `%s` is used with %s arguments. One abstract refinement has one \
          arity: define it by one callback."
         name (String.concat " and " (List.map string_of_int ns)))
  | [ n ] when w1_bad = [] ->
    let d = List.hd definers in
    let dbinders = List.map fst d.occ_scope and dbases = List.map snd d.occ_scope in
    List.iter
      (fun o ->
        let k = arity o in
        (* The long form of the occurrence a single slot should have been. *)
        let fix () =
          let c = Option.value o.occ_cont ~default:"C" in
          let slots = if o.occ_scope = [] then List.map (fun b -> ("_", b)) dbases else o.occ_scope in
          let bs = List.mapi (fun i b -> if b = "_" then Printf.sprintf "x%d" i else b) dbinders in
          let shown =
            List.mapi
              (fun i (_, base) ->
                if i < n - 1 then Printf.sprintf "{%s : %s | true}" (List.nth bs i) base
                else if i = n - 1 then
                  Printf.sprintf "{%s : %s | %s(%s)}" (List.nth bs i) base name (String.concat ", " bs)
                else base)
              slots
          in
          Printf.sprintf "%s(%s)" c (String.concat ", " shown)
        in
        (* The sugar for the same (§1.2, phase 3): mark every slot `p`
           relates, in slot order ([expand_markers] reads it back as the long
           form). *)
        let sugar () =
          let c, slots =
            match o.occ_cont with
            | Some c when List.length o.occ_scope >= n -> (c, o.occ_scope)
            | _ -> ("T", List.map (fun b -> ("_", b)) dbases)
          in
          Printf.sprintf "%s(%s)" c
            (String.concat ", "
               (List.mapi (fun i (_, base) -> if i < n then Printf.sprintf "%s[%s]" base name else base) slots))
        in
        (* An application with fewer slots than [p] relates cannot hold the
           relation at all (`List(Int[p])` under `Int -> Int -> Bool[p]`). *)
        let too_few () =
          match o.occ_cont with
          | Some c when List.length o.occ_scope < n ->
            Printf.sprintf " (`%s` has %d type argument%s)" c (List.length o.occ_scope)
              (if List.length o.occ_scope = 1 then "" else "s")
          | _ -> ""
        in
        if k = 1 && n >= 2 then
          (* W2: a single slot cannot carry a relation.  A marked slot `v[p]`
             reaches here when its application marks a number of slots other
             than n ([expand_markers] leaves those as written). *)
          misuse o.occ_span
            (Printf.sprintf
               "abstract refinement `%s` takes %d arguments, so it relates %d slots of one type \
                application, not one slot%s: mark every slot it relates, `%s`."
               name n n (too_few ()) (sugar ()))
        else if k <> n then
          misuse o.occ_span
            (Printf.sprintf
               "abstract refinement `%s` is used with %d and %d arguments. One abstract \
                refinement has one arity: apply it to %d sibling binders."
               name (min k n) (max k n) n)
        else if n >= 2 then begin
          let w2 () =
            misuse o.occ_span
              (Printf.sprintf
                 "abstract refinement `%s` relates the slots of one type application: its \
                  arguments must be %d distinct binders of sibling slots, as in `%s`."
                 name n (fix ()))
          in
          match o.occ_slot with
          | None -> w2 ()
          | Some i ->
            let slots = o.occ_scope in
            let resolve a =
              if a = "_" || a = fst (List.nth slots i) then Some i
              else
                match List.filter (fun (_, (b, _)) -> b = a) (List.mapi (fun j s -> (j, s)) slots) with
                | [ (j, _) ] -> Some j
                | _ -> None
            in
            let idxs = List.map resolve o.occ_args in
            if List.exists Option.is_none idxs
               || List.length (List.sort_uniq compare idxs) <> List.length idxs
            then w2 ()
            else
              let idxs = List.map Option.get idxs in
              match List.find_opt (fun j -> is_container_base (snd (List.nth slots j))) idxs with
              | Some j ->
                misuse o.occ_span
                  (Printf.sprintf
                     "abstract refinement `%s` relates scalar slots (a type variable, Int, Bool, \
                      String, Float or a record), and `%s` is a nested container."
                     name (snd (List.nth slots j)))
              | None ->
                (* W3: each position at one base. *)
                let mism =
                  List.find_opt
                    (fun (pos, j) -> List.nth_opt dbases pos <> Some (snd (List.nth slots j)))
                    (List.mapi (fun pos j -> (pos, j)) idxs)
                in
                (match mism with
                 | Some (pos, j) ->
                   misuse o.occ_span
                     (Printf.sprintf
                        "argument %d of `%s` is used at more than one type (`%s`, `%s`). Each \
                         argument of an abstract refinement has one type: the callback's domain \
                         and the slot it relates must agree."
                        (pos + 1) name
                        (Option.value ~default:"?" (List.nth_opt dbases pos))
                        (snd (List.nth slots j)))
                 | None ->
                   (* W4: the container is entry-shaped for the related slots. *)
                   (match o.occ_cont with
                    | Some c ->
                      let name_of j = fst (List.nth slots j) in
                      (match entry_shaped ~name_of c (List.sort_uniq compare idxs) with
                       | Ok () -> ()
                       | Error why ->
                         misuse o.occ_span
                           (Printf.sprintf "abstract refinement `%s` relates slots of `%s`, but %s." name c why))
                    | None -> ()))
        end)
      consumers;
    if consumers = [] then
      List.iter
        (fun o ->
          Err.warning ~code:Err.Code.abstract_refinement_unused errctx ~span:o.occ_span
            (Printf.sprintf
               "abstract refinement `%s` is defined by this callback but never used in the \
                signature, so it states nothing. Use it as a relation between sibling slots of \
                the return, e.g. `%s`."
               name
               (let bs = List.mapi (fun i b -> if b = "_" then Printf.sprintf "x%d" i else b) dbinders in
                let shown =
                  List.mapi
                    (fun i base ->
                      if i < n - 1 then Printf.sprintf "{%s : %s | true}" (List.nth bs i) base
                      else Printf.sprintf "{%s : %s | %s(%s)}" (List.nth bs i) base name (String.concat ", " bs))
                    dbases
                in
                Printf.sprintf "T(%s)" (String.concat ", " shown))))
        definers
  | _ -> ()

(* Design §1's rules, as diagnostics.  Rules 2, 3 (no definer), 4 and 5 are
   hard errors; rule 3's other half (a definer nobody consumes) is a warning,
   because a vacuous refinement is useless rather than wrong.  A name of
   arity n ([is_nary]) is checked by [check_nary] instead. *)
let check ?(entry_shaped = fun ~name_of:_ _ _ -> Ok ()) (errctx : Err.ctx) ~(is_known : string -> bool)
    (fd : A.fn_def) : unit =
  let declared = collect ~is_known fd in
  List.iter
    (fun (name, occs) ->
      if is_nary occs then check_nary errctx ~entry_shaped name occs else
      let definers = List.filter (fun o -> o.occ_role = Definer) occs in
      let positives = List.filter (fun o -> o.occ_role = Positive) occs in
      (* A NEGATIVE occurrence (an obligation on the caller) is a use too: the
         signature says something with it.  Only a definer with no consumer at
         all is vacuous. *)
      let consumers = List.filter (fun o -> o.occ_role <> Definer) occs in
      let malformed =
        List.exists
          (fun o -> o.occ_arg <> o.occ_binder && o.occ_arg <> "_")
          occs
      in
      (* Rule 2: applied to the binder in scope, not to something else. *)
      List.iter
        (fun o ->
          if o.occ_arg = "$computed" then
            Err.error ~code:Err.Code.abstract_refinement_misuse errctx ~span:o.occ_span
              (Printf.sprintf
                 "abstract refinement `%s` is applied to an expression. It may only be \
                  applied to the binder in scope (`%s`)."
                 name o.occ_binder)
          else if o.occ_arg <> o.occ_binder && o.occ_arg <> "_" then
            Err.error ~code:Err.Code.abstract_refinement_misuse errctx ~span:o.occ_span
              (Printf.sprintf
                 "abstract refinement `%s` is applied to `%s`, which is not the binder in \
                  scope here (`%s`). An abstract refinement applies to the value the \
                  refinement is about: write `%s(%s)`."
                 name o.occ_arg o.occ_binder name o.occ_binder))
        occs;
      (* Rule 3: a promise nobody can instantiate is an error; a definer
         nobody consumes is a vacuous signature, which is a warning. *)
      ignore positives;
      (* Design §1 rule 3's other half — a name promised in the return with no
         definer — is NOT an error here: without a definer the name is not an
         abstract refinement at all (see [collect]), and it keeps the ordinary
         "not a measure, so this refinement is not checked" warning it has
         always had.  Making it an error would turn existing accepted programs
         into rejected ones, which phase 1 must not do. *)
      if definers <> [] && consumers = [] && not malformed then
        List.iter
          (fun o ->
            Err.warning ~code:Err.Code.abstract_refinement_unused errctx ~span:o.occ_span
              (Printf.sprintf
                 "abstract refinement `%s` is defined by this callback but never used in \
                  the signature, so it states nothing. Use it as an element refinement, \
                  e.g. `: List({a | %s(_)})`."
                 name name))
          definers;
      (* Rule 4: one sort per name. *)
      (match List.sort_uniq compare (List.map (fun o -> o.occ_base) occs) with
       | _ :: _ :: _ as bases ->
         let o = List.hd occs in
         Err.error ~code:Err.Code.abstract_refinement_misuse errctx ~span:o.occ_span
           (Printf.sprintf
              "abstract refinement `%s` is used at more than one type (%s). One abstract \
               refinement stands for one predicate, over one type."
              name (String.concat ", " (List.map (fun b -> "`" ^ b ^ "`") bases)))
       | _ -> ()))
    declared;
  (* Rule 5, over the same signature: `p(q(_))` has no meaning here. *)
  let nested =
    let acc = ref [] in
    let walk t =
      let rec go (t : A.ty) =
        match t with
        | A.TyRefine (b, _, pred) -> acc := nested_apps pred @ !acc; go b
        | A.TyCon (_, args) -> List.iter go args
        | A.TyArrow (a, b) -> go a; go b
        | A.TyTuple ts -> List.iter go ts
        | A.TyRecord fs -> List.iter (fun (_, t) -> go t) fs
        | A.TyLinear (_, t) -> go t
        | A.TyChan _ | A.TyVar _ | A.TyNat _ | A.TyNatOp _ -> ()
      in
      go t
    in
    List.iter
      (fun (c : A.fn_clause) ->
        List.iter
          (function
            | A.FPNamed p | A.FPDefault (p, _) -> Option.iter walk p.A.param_ty
            | A.FPPat _ -> ())
          c.A.fc_params)
      fd.A.fn_clauses;
    Option.iter walk fd.A.fn_ret_ty;
    !acc
  in
  let declared_names = List.map fst declared in
  List.iter
    (fun (inner, span) ->
      if List.mem inner declared_names then
        Err.error ~code:Err.Code.abstract_refinement_misuse errctx ~span
          (Printf.sprintf
             "abstract refinement `%s` is applied inside another application. An abstract \
              refinement applies directly to the binder in scope."
             inner))
    nested

(* Which parameter's type DEFINES abstract refinement [p] (holds its Definer
   occurrence)?  Counted over the first clause's parameters, patterns
   included, so the index lines up with a call's argument list. *)
let definer_index ~(is_known : string -> bool) (fd : A.fn_def) (p : string) : int option =
  if not (List.mem p (names ~is_known fd)) then None
  else
    match fd.A.fn_clauses with
    | [] -> None
    | c :: _ ->
      let defines (fp : A.fn_param) =
        match fp with
        | A.FPNamed prm | A.FPDefault (prm, _) ->
          let acc = ref [] in
          Option.iter (fun t -> walk_ty ~role:Negative t acc) prm.A.param_ty;
          List.exists (fun o -> o.occ_name = p && o.occ_role = Definer) !acc
        | A.FPPat _ -> false
      in
      let rec find i = function
        | [] -> None
        | fp :: rest -> if defines fp then Some i else find (i + 1) rest
      in
      find 0 c.A.fc_params

(* The element type [p] is applied at in the RETURN (its first Positive
   occurrence's base), e.g. "a" for `List({a | p(_)})`. *)
let positive_base ~(is_known : string -> bool) (fd : A.fn_def) (p : string) : string option =
  match List.assoc_opt p (collect ~is_known fd) with
  | None -> None
  | Some occs ->
    List.find_map (fun o -> if o.occ_role = Positive then Some o.occ_base else None) occs

(* The element type at each position [p] relates in the RETURN (§5.1): for an
   arity-1 [p] [positive_base]'s one base; for an arity-n [p] the base of the
   slot each argument of its first Positive occurrence names. *)
let positive_bases ~(is_known : string -> bool) (fd : A.fn_def) (p : string) : string list option =
  match List.assoc_opt p (collect ~is_known fd) with
  | None -> None
  | Some occs ->
    List.find_map
      (fun o ->
        if o.occ_role <> Positive then None
        else
          match o.occ_args, o.occ_slot with
          | [ _ ], _ -> Some [ o.occ_base ]
          | args, Some i ->
            let slots = o.occ_scope in
            let base a =
              if a = "_" || a = fst (List.nth slots i) then Some (snd (List.nth slots i))
              else List.find_map (fun (b, t) -> if b = a then Some t else None) slots
            in
            let bs = List.map base args in
            if List.for_all Option.is_some bs then Some (List.map Option.get bs) else None
          | _, None -> None)
      occs

(* ── The occurrence sugar `T(k[p], v[p])` (multi-arg design 2026-10-18 §1.2,
   §9 phase 3) ─────────────────────────────────────────────────────────────
   A pre-pass over every function's declared types, run before [Refine_check]
   builds any table, so every later reader sees only the long form.

   For an abstract refinement [p] of arity n ≥ 2 (its definer, the chain
   `k -> v -> Bool[p]` the parser builds, applies it to n binders), the slots
   of ONE type application marked `T[p]` (the parser's `{_ : T | p(_)}`) are
   the relation's slots, in slot order.  When exactly n are marked they become
   `T({$s0 : k | true}, {$s1 : v | p($s0, $s1)})`: every marked slot binds a
   fresh name and the last carries the relation.  Any other count is left as
   written, and [check_nary] reports each marked slot as W2's single-slot
   error, whose fix is this sugar.  An arity-1 [p] is never touched:
   `Map(k[p], v[p])` keeps its two unary facts.

   The arity is read with [is_known = fun _ -> false]: no table exists yet.
   A name the checker knows (a measure) is a candidate here only when a
   well-formed chain definer applies it, and the expansion then spells out
   exactly what the markers already meant. *)
let marker_of (t : A.ty) : (A.ty * string * A.span) option =
  match t with
  | A.TyRefine (b, Some { A.txt = "_"; _ }, A.EApp (A.EVar { A.txt = p; _ }, [ A.EVar { A.txt = "_"; _ } ], sp)) ->
    Some (b, p, sp)
  | _ -> None

let nary_arities (fd : A.fn_def) : (string * int) list =
  List.filter_map
    (fun (p, occs) ->
      List.find_map
        (fun o ->
          let n = List.length o.occ_args in
          if o.occ_role = Definer && n >= 2 && o.occ_args = List.map fst o.occ_scope then Some (p, n)
          else None)
        occs)
    (collect ~is_known:(fun _ -> false) fd)

let expand_markers_fn (fd : A.fn_def) : A.fn_def =
  match nary_arities fd with
  | [] -> fd
  | ar ->
    let ctr = ref 0 in
    let rec ty (t : A.ty) : A.ty =
      match t with
      | A.TyCon (c, args) ->
        let args = List.map ty args in
        let marked p = List.filter_map (fun a -> match marker_of a with Some (_, q, _) when q = p -> Some () | _ -> None) args in
        let args =
          List.fold_left
            (fun args (p, n) ->
              if List.length (marked p) <> n then args
              else begin
                let names = List.init n (fun i -> Printf.sprintf "$s%d" (!ctr + i)) in
                ctr := !ctr + n;
                let k = ref 0 in
                List.map
                  (fun a ->
                    match marker_of a with
                    | Some (b, q, sp) when q = p ->
                      let i = !k in
                      incr k;
                      let nm = { A.txt = List.nth names i; A.span = sp } in
                      let pred =
                        if i < n - 1 then A.ELit (A.LitBool true, sp)
                        else
                          A.EApp
                            ( A.EVar { A.txt = p; A.span = sp }
                            , List.map (fun x -> A.EVar { A.txt = x; A.span = sp }) names
                            , sp )
                      in
                      A.TyRefine (b, Some nm, pred)
                    | _ -> a)
                  args
              end)
            args ar
        in
        A.TyCon (c, args)
      | A.TyRefine (b, n, e) -> A.TyRefine (ty b, n, e)
      | A.TyArrow (a, b) -> A.TyArrow (ty a, ty b)
      | A.TyTuple ts -> A.TyTuple (List.map ty ts)
      | A.TyRecord fs -> A.TyRecord (List.map (fun (n, t) -> (n, ty t)) fs)
      | A.TyLinear (l, t) -> A.TyLinear (l, ty t)
      | A.TyChan _ | A.TyVar _ | A.TyNat _ | A.TyNatOp _ -> t
    in
    let param (p : A.param) = { p with A.param_ty = Option.map ty p.A.param_ty } in
    { fd with
      A.fn_clauses =
        List.map
          (fun (c : A.fn_clause) ->
            { c with
              A.fc_params =
                List.map
                  (function
                    | A.FPNamed p -> A.FPNamed (param p)
                    | A.FPDefault (p, e) -> A.FPDefault (param p, e)
                    | A.FPPat _ as fp -> fp)
                  c.A.fc_params })
          fd.A.fn_clauses;
      A.fn_ret_ty = Option.map ty fd.A.fn_ret_ty }

(* Physically the same decl wherever nothing was expanded, so a module with no
   arity-n definer is handed on untouched. *)
let rec expand_markers (decls : A.decl list) : A.decl list =
  List.map
    (fun (d : A.decl) ->
      match d with
      | A.DFn (fd, sp) ->
        let fd' = expand_markers_fn fd in
        if fd' == fd then d else A.DFn (fd', sp)
      | A.DMod (n, v, ds, sp) ->
        let ds' = expand_markers ds in
        if List.for_all2 ( == ) ds ds' then d else A.DMod (n, v, ds', sp)
      | d -> d)
    decls
