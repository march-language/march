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
   this existed. *)
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

(* Ordered most-specific-first.  [subject_sym] is the SMT symbol the checked
   ACTUAL reflected to, or [None] when the actual is not a bare symbol (an
   arbitrary expression has no single name to report as unconstrained). *)
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
