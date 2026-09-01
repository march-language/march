(* Diagnosing WHY an obligation was not decided.

   Reached only from [Refine_call.check_call]'s fall-through, after the
   positive discharge has already failed — so nothing here is on the happy
   path and none of it costs a proved obligation anything.

   Everything in this file is syntactic over the built [Smt.vc].  The one
   diagnosis that costs solver time ([Partial_conjunct]) lives in
   [Refine_call] instead, because it needs [Refine.discharge] and the
   preamble, neither of which belongs in a pure analysis module. *)

module Smt = March_refine.Smt

(* Every symbol a term mentions, as [Const] names and [App] heads kept apart:
   a `Const` is a value the VC declares, an `App` head is a FUNCTION symbol
   that the preamble either axiomatised or did not. *)
let rec consts (t : Smt.term) : string list =
  match t with
  | Smt.Const n -> [ n ]
  | Smt.IntLit _ | Smt.BoolLit _ | Smt.FloatLit _ -> []
  | Smt.App (_, ts) -> List.concat_map consts ts
  | Smt.IsCtor (_, a) | Smt.Neg a | Smt.Not a -> consts a
  | Smt.MulLit (_, a) -> consts a
  | Smt.Add (a, b) | Smt.Sub (a, b) | Smt.Mul (a, b)
  | Smt.And (a, b) | Smt.Or (a, b) | Smt.Implies (a, b)
  | Smt.Eq (a, b) | Smt.Ne (a, b)
  | Smt.Lt (a, b) | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b)
  | Smt.FpEq (a, b) | Smt.FpLt (a, b) | Smt.FpLe (a, b)
  | Smt.FpGt (a, b) | Smt.FpGe (a, b) -> consts a @ consts b

let rec app_heads (t : Smt.term) : string list =
  match t with
  | Smt.Const _ | Smt.IntLit _ | Smt.BoolLit _ | Smt.FloatLit _ -> []
  | Smt.App (f, ts) -> f :: List.concat_map app_heads ts
  | Smt.IsCtor (_, a) | Smt.Neg a | Smt.Not a -> app_heads a
  | Smt.MulLit (_, a) -> app_heads a
  | Smt.Add (a, b) | Smt.Sub (a, b) | Smt.Mul (a, b)
  | Smt.And (a, b) | Smt.Or (a, b) | Smt.Implies (a, b)
  | Smt.Eq (a, b) | Smt.Ne (a, b)
  | Smt.Lt (a, b) | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b)
  | Smt.FpEq (a, b) | Smt.FpLt (a, b) | Smt.FpLe (a, b)
  | Smt.FpGt (a, b) | Smt.FpGe (a, b) -> app_heads a @ app_heads b

(* Function symbols the PREAMBLE — a raw SMT-LIB string assembled alongside
   [vc], not part of it — already declares and axiomatises: the string-length
   function, any measure name (the builtin `len` or a `@[measure]`-annotated
   one), a registered ADT constructor, or one of a constructor's own field
   selectors (named `<ctor>_<idx>`, see [Refine_resolve.make_field_resolver]).
   None of these appear in [vc.decls] — that list is VARIABLE declarations
   only — so checking [app_heads] against [vc.decls] alone would brand every
   one of them "opaque".  That would be wrong: the preamble gives each of
   them a meaning, the checker just could not connect a proof through it this
   time — which is exactly the false positive that fired on `$strlen` before
   this existed.

   [Refine_encode.is_measure] is NOT dead weight, even though a `len`
   application never reaches here as an [App] head — [measure_of_var]
   (refine_call.ml) flattens `len(_)` straight to `Const "len$x"`, so `"len"`
   itself can never be an [app_heads] entry.  But an AXIOMATISED user measure
   (`@[measure] fn size(t : Tree(a)) : Int do … end` over a declared ADT)
   reflects the OTHER way: [resolve_measure]'s axiom branch builds
   `App(m, [t])` — literally `App ("size", [...])` — because the solver needs
   the recursion equations, not a flat opaque constant.  Confirmed with a
   fixture (`get(t : Tree(a), i : {Int | _ >= 0 && _ < size(t)})` called
   unguarded): with [is_measure] removed here, "size" misfires
   `opaque-application`, the same class of false positive `$strlen` did.
   [ctor_field_sorts] does not cover it — that table holds CONSTRUCTOR names
   (`Leaf`, `Node`), not measure function names. See
   test/test_refinecheck.ml's "an axiomatised measure's own name is not
   opaque" for the pinned regression. *)
let known_head (f : string) : bool =
  f = Refine_encode.strlen_fn
  || Refine_encode.is_measure f
  || Hashtbl.mem Refine_encode.ctor_field_sorts f
  || Hashtbl.fold
       (fun ctor _ acc ->
         acc
         ||
         let prefix = ctor ^ "_" in
         let plen = String.length prefix in
         String.length f > plen
         && String.sub f 0 plen = prefix
         &&
         let suffix = String.sub f plen (String.length f - plen) in
         suffix <> "" && String.for_all (fun c -> c >= '0' && c <= '9') suffix)
       Refine_encode.ctor_field_names false

(* Ordered most-specific-first.  [subject_sym] must be the actual SMT symbol
   the subject reflected to IN THIS GOAL — e.g. `"len$ys"` for a
   `len`-measured `ys`, never the source argument's own spelling `"ys"` (see
   [Refine_call.mark_self], the only producer this module trusts).  [None]
   when the goal-building resolvers never pinned the subject to a single
   stable symbol (a record/ADT term, a non-variable actual, or a predicate
   that never references the binder at all) — there is no one name to search
   the assumptions for, so the unconstrained check below stays silent rather
   than guess. *)
let diagnose ~(subject_sym : string option) (vc : Smt.vc) : Obligation.reason option =
  let declared = List.map fst vc.Smt.decls in
  let goal_heads = List.sort_uniq compare (app_heads vc.Smt.goal) in
  match List.find_opt (fun f -> not (List.mem f declared) && not (known_head f)) goal_heads with
  | Some f -> Some (Obligation.Opaque_application f)
  | None ->
    (match subject_sym with
     | Some s
       when not
              (List.exists (fun a -> List.mem s (consts a)) vc.Smt.assumptions) ->
       Some (Obligation.Unconstrained_subject s)
     | _ -> None)
