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

(* Nested application of a candidate inside another's argument (`p(q(_))`),
   rejected by rule 5.  Detected structurally rather than by the flattened
   list above, which cannot tell `p(q(_))` from two siblings. *)
let rec nested_apps (e : A.expr) : (string * A.span) list =
  match e with
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

(* Walk one declared type, collecting occurrences at [role].

   [dom_binder] is the binder of the arrow domain whose codomain we are
   inside, so a definer's argument can be checked against it; it is [None]
   everywhere else. *)
let rec walk_ty ~(role : role) ?(dom_binder : string option)
    ?(dom_base : string option) (t : A.ty) (acc : occurrence list ref) : unit =
  match t with
  | A.TyRefine (base, binder, pred) ->
    let b = binder_of binder in
    List.iter
      (fun (f, arg, span) ->
        acc :=
          { occ_name = f;
            occ_role = role;
            occ_span = span;
            occ_arg = Option.value arg ~default:"$computed";
            occ_binder = (match dom_binder with Some d -> d | None -> b);
            (* A DEFINER sits on a `Bool` codomain but is ABOUT the callback's
               domain: `{Bool | _ == p(x)}` says what `p` means for an `x`.
               Recording `Bool` here made rule 4 fire on the canonical
               signature (`Bool` vs `a`), which is the whole feature. *)
            occ_base = (match dom_base with Some d -> d | None -> base_key base) }
          :: !acc)
      (applications pred);
    walk_ty ~role ?dom_binder ?dom_base base acc
  | A.TyCon (_, args) -> List.iter (fun a -> walk_ty ~role ?dom_binder ?dom_base a acc) args
  | A.TyArrow (dom, cod) ->
    (* The domain of an arrow parameter is where the callback RECEIVES values,
       so a refinement there is an obligation on the callee, not a definer;
       its own binder is what a codomain definer may name. *)
    let db = match dom with A.TyRefine (_, b, _) -> Some (binder_of b) | _ -> None in
    walk_ty ~role:(match role with Negative -> Positive | _ -> Negative) ?dom_binder ?dom_base dom acc;
    walk_ty ~role:Definer ?dom_binder:db ~dom_base:(base_key dom) cod acc
  | A.TyTuple ts -> List.iter (fun t -> walk_ty ~role ?dom_binder ?dom_base t acc) ts
  | A.TyRecord fs -> List.iter (fun (_, t) -> walk_ty ~role ?dom_binder ?dom_base t acc) fs
  | A.TyLinear (_, t) -> walk_ty ~role ?dom_binder ?dom_base t acc
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

(* Design §1's rules, as diagnostics.  Rules 2, 3 (no definer), 4 and 5 are
   hard errors; rule 3's other half (a definer nobody consumes) is a warning,
   because a vacuous refinement is useless rather than wrong. *)
let check (errctx : Err.ctx) ~(is_known : string -> bool) (fd : A.fn_def) : unit =
  let declared = collect ~is_known fd in
  List.iter
    (fun (name, occs) ->
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
            Err.error errctx ~span:o.occ_span
              (Printf.sprintf
                 "abstract refinement `%s` is applied to an expression. It may only be \
                  applied to the binder in scope (`%s`)."
                 name o.occ_binder)
          else if o.occ_arg <> o.occ_binder && o.occ_arg <> "_" then
            Err.error errctx ~span:o.occ_span
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
            Err.warning errctx ~span:o.occ_span
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
         Err.error errctx ~span:o.occ_span
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
        Err.error errctx ~span
          (Printf.sprintf
             "abstract refinement `%s` is applied inside another application. An abstract \
              refinement applies directly to the binder in scope."
             inner))
    nested
