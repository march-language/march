(** P1 — Let-floating past ECase.

    When the same [let x = rhs in …] binding appears at the start of EVERY
    branch of an ECase, and the RHS does not mention any pattern-bound
    variable from that branch, the binding can be hoisted above the ECase:

      ECase(a, [
        {T1; [v1]; ELet(x, rhs, body1)};
        {T2; [v2]; ELet(x, rhs, body2)};
      ], default)
      →
      ELet(x, rhs,
        ECase(a, [
          {T1; [v1]; body1};
          {T2; [v2]; body2};
        ], default))

    Safety conditions:
    1. The variable name [x] is the same across all branches.
    2. The RHS expression [rhs] is structurally equal across all branches.
    3. The RHS does not mention any pattern-bound variable [vi] in that branch.
    4. The variable [x] is not itself pattern-bound in any branch.
    5. The default branch, if present, also starts with [let x = rhs].

    We run this as a fixpoint (repeat until no change) so chains of common
    lets are all floated in a single call to [run]. *)

(* ── Structural equality ────────────────────────────────────────────────── *)

let lit_eq (l1 : March_ast.Ast.literal) (l2 : March_ast.Ast.literal) : bool =
  match l1, l2 with
  | March_ast.Ast.LitInt a,    March_ast.Ast.LitInt b    -> a = b
  | March_ast.Ast.LitFloat a,  March_ast.Ast.LitFloat b  -> a = b
  | March_ast.Ast.LitBool a,   March_ast.Ast.LitBool b   -> a = b
  | March_ast.Ast.LitString a, March_ast.Ast.LitString b -> a = b
  | March_ast.Ast.LitAtom a,   March_ast.Ast.LitAtom b   -> a = b
  | _ -> false

let atom_eq (a : Tir.atom) (b : Tir.atom) : bool =
  match a, b with
  | Tir.ALit la,   Tir.ALit lb   -> lit_eq la lb
  | Tir.AVar va,   Tir.AVar vb   -> va.Tir.v_name = vb.Tir.v_name
  | Tir.ADefRef da, Tir.ADefRef db -> da.Tir.did_hash = db.Tir.did_hash
  | _ -> false

let atoms_eq (xs : Tir.atom list) (ys : Tir.atom list) : bool =
  List.length xs = List.length ys && List.for_all2 atom_eq xs ys

let rec expr_eq (e1 : Tir.expr) (e2 : Tir.expr) : bool =
  match e1, e2 with
  | Tir.EAtom a1,      Tir.EAtom a2      -> atom_eq a1 a2
  | Tir.EApp (f1, xs), Tir.EApp (f2, ys) ->
    f1.Tir.v_name = f2.Tir.v_name && atoms_eq xs ys
  | Tir.ECallPtr (f1, xs), Tir.ECallPtr (f2, ys) ->
    atom_eq f1 f2 && atoms_eq xs ys
  | Tir.ELet (v1, r1, b1), Tir.ELet (v2, r2, b2) ->
    v1.Tir.v_name = v2.Tir.v_name && expr_eq r1 r2 && expr_eq b1 b2
  | Tir.ETuple xs,  Tir.ETuple ys  -> atoms_eq xs ys
  | Tir.ERecord fs1, Tir.ERecord fs2 ->
    List.length fs1 = List.length fs2 &&
    List.for_all2 (fun (n1,a1) (n2,a2) -> n1 = n2 && atom_eq a1 a2) fs1 fs2
  | Tir.EField (a1, f1), Tir.EField (a2, f2) ->
    atom_eq a1 a2 && f1 = f2
  | Tir.EUpdate (r1, fs1), Tir.EUpdate (r2, fs2) ->
    atom_eq r1 r2 &&
    List.length fs1 = List.length fs2 &&
    List.for_all2 (fun (n1,a1) (n2,a2) -> n1 = n2 && atom_eq a1 a2) fs1 fs2
  | Tir.EAlloc (t1, xs), Tir.EAlloc (t2, ys) ->
    t1 = t2 && atoms_eq xs ys
  | Tir.ESeq (a1, b1), Tir.ESeq (a2, b2) ->
    expr_eq a1 a2 && expr_eq b1 b2
  | Tir.EIncRC a1,       Tir.EIncRC a2       -> atom_eq a1 a2
  | Tir.EDecRC a1,       Tir.EDecRC a2       -> atom_eq a1 a2
  | Tir.EAtomicIncRC a1, Tir.EAtomicIncRC a2 -> atom_eq a1 a2
  | Tir.EAtomicDecRC a1, Tir.EAtomicDecRC a2 -> atom_eq a1 a2
  | Tir.EFree a1,        Tir.EFree a2        -> atom_eq a1 a2
  | Tir.EStackAlloc (t1, xs), Tir.EStackAlloc (t2, ys) ->
    t1 = t2 && atoms_eq xs ys
  | Tir.EReuse (a1, t1, xs), Tir.EReuse (a2, t2, ys) ->
    atom_eq a1 a2 && t1 = t2 && atoms_eq xs ys
  | _ -> false

(* ── Free-variable check ────────────────────────────────────────────────── *)

let atom_mentions_any (names : string list) (a : Tir.atom) : bool =
  match a with
  | Tir.AVar v -> List.mem v.Tir.v_name names
  | _ -> false

let atoms_mention_any ns xs = List.exists (atom_mentions_any ns) xs

(** Returns true if [e] mentions any name in [names] (free or bound).
    Conservative: we treat bound names as potential mentions too, so we
    never float a binding whose RHS shadows a pattern variable. *)
let rec expr_mentions_any (names : string list) (e : Tir.expr) : bool =
  match e with
  | Tir.EAtom a -> atom_mentions_any names a
  | Tir.EApp (f, xs) ->
    List.mem f.Tir.v_name names || atoms_mention_any names xs
  | Tir.ECallPtr (f, xs) ->
    atom_mentions_any names f || atoms_mention_any names xs
  | Tir.ELet (v, rhs, body) ->
    List.mem v.Tir.v_name names
    || expr_mentions_any names rhs
    || expr_mentions_any names body
  | Tir.ELetRec (fns, body) ->
    List.exists (fun fn -> expr_mentions_any names fn.Tir.fn_body) fns
    || expr_mentions_any names body
  | Tir.ECase (a, brs, def) ->
    atom_mentions_any names a
    || List.exists (fun br ->
        List.exists (fun v -> List.mem v.Tir.v_name names) br.Tir.br_vars
        || expr_mentions_any names br.Tir.br_body) brs
    || (match def with Some d -> expr_mentions_any names d | None -> false)
  | Tir.ETuple xs -> atoms_mention_any names xs
  | Tir.ERecord fs -> List.exists (fun (_, a) -> atom_mentions_any names a) fs
  | Tir.EField (a, _) -> atom_mentions_any names a
  | Tir.EUpdate (a, fs) ->
    atom_mentions_any names a
    || List.exists (fun (_, av) -> atom_mentions_any names av) fs
  | Tir.EAlloc (_, xs) | Tir.EStackAlloc (_, xs) -> atoms_mention_any names xs
  | Tir.ESeq (e1, e2) ->
    expr_mentions_any names e1 || expr_mentions_any names e2
  | Tir.EIncRC a | Tir.EDecRC a
  | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a
  | Tir.EFree a -> atom_mentions_any names a
  | Tir.EReuse (a, _, xs) ->
    atom_mentions_any names a || atoms_mention_any names xs

(* ── Core transform ─────────────────────────────────────────────────────── *)

(** Try to peel one common leading [let x = rhs in …] from all branches.
    Returns [(x, rhs, branches_with_body_only, default_body_only)] on
    success, or [None] when no common leading let exists. *)
let peel_common_let
    (branches : Tir.branch list)
    (default  : Tir.expr option)
    : (Tir.var * Tir.expr * Tir.branch list * Tir.expr option) option =
  (* Extract the leading let from a branch body (if any). *)
  let leading_let br =
    match br.Tir.br_body with
    | Tir.ELet (v, rhs, body) -> Some (v, rhs, body)
    | _ -> None
  in
  (* All branches must start with a let. *)
  match List.map leading_let branches with
  | [] -> None
  | first_opt :: rest_opts ->
    (match first_opt with
     | None -> None
     | Some (v0, rhs0, _) ->
       (* (1) All branch leading-lets must have the same var name and RHS. *)
       let all_match = List.for_all (function
         | Some (v, rhs, _) -> v.Tir.v_name = v0.Tir.v_name && expr_eq rhs rhs0
         | None -> false) rest_opts
       in
       if not all_match then None
       else begin
         (* (2) The RHS must not mention any pattern-bound variable in any branch. *)
         let rhs_safe = List.for_all (fun br ->
           let br_var_names = List.map (fun v -> v.Tir.v_name) br.Tir.br_vars in
           not (expr_mentions_any br_var_names rhs0)
         ) branches in
         if not rhs_safe then None
         else begin
           (* (3) The floated variable name must not be pattern-bound in any branch. *)
           let name_safe = List.for_all (fun br ->
             not (List.exists (fun v -> v.Tir.v_name = v0.Tir.v_name) br.Tir.br_vars)
           ) branches in
           if not name_safe then None
           else begin
             (* (4) Default branch must also start with the same let (if present). *)
             let default_body_opt =
               match default with
               | None -> Some None  (* no default → OK, return None body *)
               | Some def_expr ->
                 match def_expr with
                 | Tir.ELet (v, rhs, body)
                   when v.Tir.v_name = v0.Tir.v_name && expr_eq rhs rhs0 ->
                   Some (Some body)
                 | _ -> None  (* default doesn't match → can't float *)
             in
             match default_body_opt with
             | None -> None
             | Some new_default ->
               let new_branches = List.map2 (fun br -> function
                 | Some (_, _, body) -> { br with Tir.br_body = body }
                 | None -> assert false
               ) branches (List.map leading_let branches) in
               Some (v0, rhs0, new_branches, new_default)
           end
         end
       end)

(** One pass: float common lets above ECases throughout an expression. *)
let rec float_expr (changed : bool ref) (e : Tir.expr) : Tir.expr =
  match e with
  | Tir.ECase (a, branches, default) ->
    (* Recurse into branches first. *)
    let branches' = List.map (fun br ->
      { br with Tir.br_body = float_expr changed br.Tir.br_body }) branches in
    let default' = Option.map (float_expr changed) default in
    (* Now try to peel a common leading let from the (post-recursion) branches. *)
    (match peel_common_let branches' default' with
     | None -> Tir.ECase (a, branches', default')
     | Some (v, rhs, new_branches, new_default) ->
       changed := true;
       (* Wrap the result in the floated let, then recurse to catch chains. *)
       let new_case = Tir.ECase (a, new_branches, new_default) in
       float_expr changed (Tir.ELet (v, rhs, new_case)))
  | Tir.ELet (v, rhs, body) ->
    Tir.ELet (v, float_expr changed rhs, float_expr changed body)
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fn ->
      { fn with Tir.fn_body = float_expr changed fn.Tir.fn_body }) fns in
    Tir.ELetRec (fns', float_expr changed body)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (float_expr changed e1, float_expr changed e2)
  (* Leaf expressions — no sub-expressions to recurse into. *)
  | Tir.EAtom _ | Tir.EApp _ | Tir.ECallPtr _ | Tir.ETuple _ | Tir.ERecord _
  | Tir.EField _ | Tir.EUpdate _ | Tir.EAlloc _ | Tir.EStackAlloc _
  | Tir.EFree _ | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _
  | Tir.EAtomicDecRC _ | Tir.EReuse _ ->
    e

let float_fn (changed : bool ref) (fn : Tir.fn_def) : Tir.fn_def =
  { fn with Tir.fn_body = float_expr changed fn.Tir.fn_body }

(** Run let-floating on a TIR module.  Returns the transformed module.
    The [changed] ref is set to true if any transformation fired.
    Runs as a fixpoint internally: repeats until stable. *)
let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map (float_fn changed) m.Tir.tm_fns }
