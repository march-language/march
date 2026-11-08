(** Logical binders reuse the AST's lexical lambda representation. The private
    head cannot be spelled in March source and must never reach runtime code. *)
open Ast

type kind = Forall | Exists
type domain = Range of expr * expr | Elements of expr
type t = { kind : kind; binder : name; domain : domain; body : expr; span : span }

let symbol kind domain =
  "$bounded_" ^ (match kind with Forall -> "forall" | Exists -> "exists")
  ^ (match domain with Range _ -> "_range" | Elements _ -> "_set")

let make q =
  let args = match q.domain with Range (lo, hi) -> [lo; hi] | Elements s -> [s] in
  let p = {param_name = q.binder; param_ty = None; param_lin = Unrestricted} in
  EApp (EVar {txt = symbol q.kind q.domain; span = q.span},
        args @ [ELam ([p], q.body, q.span)], q.span)

let view = function
  | EApp (EVar {txt = ("$bounded_forall_range" | "$bounded_exists_range") as txt; _},
          [lo; hi; ELam ([p], body, _)], span) ->
    Some {kind = (if txt = "$bounded_forall_range" then Forall else Exists);
          binder = p.param_name; domain = Range (lo, hi); body; span}
  | EApp (EVar {txt = ("$bounded_forall_set" | "$bounded_exists_set") as txt; _},
          [s; ELam ([p], body, _)], span) ->
    Some {kind = (if txt = "$bounded_forall_set" then Forall else Exists);
          binder = p.param_name; domain = Elements s; body; span}
  | _ -> None

let map_domain f = function
  | Range (lo, hi) -> Range (f lo, f hi)
  | Elements s -> Elements (f s)

let domain_exprs = function Range (lo, hi) -> [lo; hi] | Elements s -> [s]

let is_symbol = function
  | "$bounded_forall_range" | "$bounded_exists_range"
  | "$bounded_forall_set" | "$bounded_exists_set" -> true
  | _ -> false

(** All names, including bound names, for deterministic alpha-renaming of
    logical predicates. This is deliberately broader than free names. *)
let rec names = function
  | EVar n -> [n.txt]
  | EApp (f, args, _) -> names f @ List.concat_map names args
  | ELam (ps, body, _) -> List.map (fun p -> p.param_name.txt) ps @ names body
  | ECon (_, es, _) | ETuple (es, _) -> List.concat_map names es
  | EField (e, _, _) | EAnnot (e, _, _) | ERefineMsg (e, _, _) -> names e
  | EIf (c, a, b, _) -> names c @ names a @ names b
  | _ -> []

(** Conservative: may [x] occur in [e]?  True for any form [names] does not
    model, so a caller that refuses on [true] never misses an occurrence. *)
let rec may_mention x = function
  | EVar n -> n.txt = x
  | ELit _ -> false
  | EApp (f, args, _) -> may_mention x f || List.exists (may_mention x) args
  | ELam (ps, body, _) -> List.exists (fun p -> p.param_name.txt = x) ps || may_mention x body
  | ECon (_, es, _) | ETuple (es, _) -> List.exists (may_mention x) es
  | EField (e, _, _) | EAnnot (e, _, _) | ERefineMsg (e, _, _) -> may_mention x e
  | EIf (c, a, b, _) -> may_mention x c || may_mention x a || may_mention x b
  | _ -> true

let rec has_exists e =
  match view e with
  | Some q -> q.kind = Exists || has_exists q.body || List.exists has_exists (domain_exprs q.domain)
  | None -> match e with
    | EApp (f, args, _) -> has_exists f || List.exists has_exists args
    | ELam (_, b, _) | EAnnot (b, _, _) | ERefineMsg (b, _, _) -> has_exists b
    | _ -> false

let witness_hint e =
  if has_exists e then
    "; give a witness by naming a candidate in a proof block and asserting both its bound and the instantiated predicate"
  else ""

let rec contains e =
  match view e with
  | Some _ -> true
  | None -> match e with
    | EApp (f, args, _) -> contains f || List.exists contains args
    | ELam (_, b, _) | EAnnot (b, _, _) | ERefineMsg (b, _, _) -> contains b
    | EIf (c, a, b, _) -> contains c || contains a || contains b
    | _ -> false
