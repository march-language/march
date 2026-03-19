(** Shared purity oracle.
    Conservative: returns [false] when uncertain.
    False negatives (treating pure as impure) are safe; false positives are not. *)

let impure_builtins = ["print"; "println"; "send"; "kill"; "march_print"; "march_println"]

let rec is_pure : Tir.expr -> bool = function
  | Tir.EAtom _                -> true
  | Tir.ETuple _               -> true
  | Tir.ERecord _              -> true
  | Tir.EField _               -> true
  | Tir.EAlloc _               -> true   (* allocation is pure, side-effect-free *)
  | Tir.EStackAlloc _          -> true
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EFree _ | Tir.EReuse _ -> true
  | Tir.EApp (f, _)            ->
    not (List.mem f.Tir.v_name impure_builtins)
  | Tir.ECallPtr _             -> false  (* indirect call — unknown target *)
  | Tir.ELet (_, rhs, body)    -> is_pure rhs && is_pure body
  | Tir.ELetRec (fns, body)    ->
    List.for_all (fun fd -> is_pure fd.Tir.fn_body) fns && is_pure body
  | Tir.ECase (_, branches, default) ->
    List.for_all (fun b -> is_pure b.Tir.br_body) branches
    && Option.fold ~none:true ~some:is_pure default
  | Tir.EUpdate _              -> true
  | Tir.ESeq (e1, e2)          -> is_pure e1 && is_pure e2
