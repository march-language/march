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
  | Tir.EAlloc (_, xs) | Tir.EStackAlloc (_, xs)
  | Tir.EAllocHole (_, xs, _) -> atoms_mention_any names xs
  | Tir.ESetField (o, _, v) ->
    atom_mentions_any names o || atom_mentions_any names v
  | Tir.ESeq (e1, e2) ->
    expr_mentions_any names e1 || expr_mentions_any names e2
  | Tir.EIncRC a | Tir.EDecRC a
  | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a
  | Tir.EFree a -> atom_mentions_any names a
  | Tir.EReuse (a, _, xs) ->
    atom_mentions_any names a || atoms_mention_any names xs

(* ── Variable renaming (Layer 1: alpha-merge) ───────────────────────────── *)

(* Fresh-name counter for floated binders.  The ["$jp"] prefix cannot collide
   with user identifiers or ANF temporaries (both reserve the [$] sigil for
   distinct synthetic names). *)
let jp_counter = ref 0
let fresh_name (base : string) : string =
  incr jp_counter;
  Printf.sprintf "$jp%d_%s" !jp_counter base

let rename_atom (from_name : string) (to_name : string) (a : Tir.atom) : Tir.atom =
  match a with
  | Tir.AVar v when v.Tir.v_name = from_name ->
    Tir.AVar { v with Tir.v_name = to_name }
  | _ -> a

(** Rename every [AVar] occurrence of [from_name] to [to_name] in [e].
    Used to substitute a per-arm head-let binder with the single floated
    binder.  Pre-Perceus only (no RC nodes carry independent ownership). *)
let rec rename_expr (from_name : string) (to_name : string) (e : Tir.expr)
    : Tir.expr =
  let ra = rename_atom from_name to_name in
  let re = rename_expr from_name to_name in
  let rv (v : Tir.var) =
    if v.Tir.v_name = from_name then { v with Tir.v_name = to_name } else v in
  match e with
  | Tir.EAtom a -> Tir.EAtom (ra a)
  | Tir.EApp (f, xs) -> Tir.EApp (rv f, List.map ra xs)
  | Tir.ECallPtr (f, xs) -> Tir.ECallPtr (ra f, List.map ra xs)
  | Tir.ELet (v, rhs, body) ->
    (* A binder re-using [from_name] shadows it: stop renaming in the body. *)
    let body' = if v.Tir.v_name = from_name then body else re body in
    Tir.ELet (v, re rhs, body')
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec
      (List.map (fun fn -> { fn with Tir.fn_body = re fn.Tir.fn_body }) fns,
       re body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (ra a,
      List.map (fun br ->
        (* A pattern var named [from_name] shadows it in this arm. *)
        if List.exists (fun v -> v.Tir.v_name = from_name) br.Tir.br_vars
        then br
        else { br with Tir.br_body = re br.Tir.br_body }) brs,
      Option.map re def)
  | Tir.ETuple xs -> Tir.ETuple (List.map ra xs)
  | Tir.ERecord fs -> Tir.ERecord (List.map (fun (n, a) -> (n, ra a)) fs)
  | Tir.EField (a, f) -> Tir.EField (ra a, f)
  | Tir.EUpdate (a, fs) ->
    Tir.EUpdate (ra a, List.map (fun (n, av) -> (n, ra av)) fs)
  | Tir.EAlloc (t, xs) -> Tir.EAlloc (t, List.map ra xs)
  | Tir.EStackAlloc (t, xs) -> Tir.EStackAlloc (t, List.map ra xs)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (re e1, re e2)
  | Tir.EIncRC a -> Tir.EIncRC (ra a)
  | Tir.EDecRC a -> Tir.EDecRC (ra a)
  | Tir.EAtomicIncRC a -> Tir.EAtomicIncRC (ra a)
  | Tir.EAtomicDecRC a -> Tir.EAtomicDecRC (ra a)
  | Tir.EFree a -> Tir.EFree (ra a)
  | Tir.EReuse (a, t, xs) -> Tir.EReuse (ra a, t, List.map ra xs)
  | Tir.EAllocHole (t, xs, hole) -> Tir.EAllocHole (t, List.map ra xs, hole)
  | Tir.ESetField (o, i, v) -> Tir.ESetField (ra o, i, ra v)

(* ── Core transform ─────────────────────────────────────────────────────── *)

(** Try to peel one common leading [let x = rhs in …] from all branches.
    Returns [(x, rhs, branches_with_body_only, default_body_only)] on
    success, or [None] when no common leading let exists.

    When [~rename] is true (Layer 1, pre-Perceus), branches may bind the
    common RHS under DIFFERENT names: a single fresh binder is floated and each
    arm body has its own binder substituted for it.  When false (the in-loop
    post-Perceus pass) binder names must already match — substitution post-RC
    is unsafe, so we stay conservative. *)
let peel_common_let
    ?(rename = false)
    ~(scrut : Tir.atom)
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
       (* (1) All branch leading-lets must have an equal RHS.  Without [rename]
          the binder names must also match (post-Perceus safety). *)
       let all_match = List.for_all (function
         | Some (v, rhs, _) ->
           expr_eq rhs rhs0 && (rename || v.Tir.v_name = v0.Tir.v_name)
         | None -> false) rest_opts
       in
       if not all_match then None
       else begin
         (* (2) The RHS must not mention any pattern-bound variable in any
            branch, NOR the scrutinee itself.

            The scrutinee half is not a refinement of the first: floating a
            let that reads the scrutinee moves it ABOVE the [ECase] that
            destructures the scrutinee — harmless for a pure read, fatal for
            anything that invalidates it.  Drop.ml's synthesized drop is
            exactly that shape:

              case x of Rec(xs, _) -> let freed = march_decrc_freed(x) in
                                      case freed of True -> drop(xs)

            Every arm starts with the same let, so this peeled it out and the
            emitted code freed the box and THEN read its tag and fields:

              %cr47  = call i64 @march_decrc_freed(ptr %ld46)   ; frees x
              %tag51 = load i32, ptr %tgp50                     ; reads x
              %fv53  = load ptr,  ptr %fp52                     ; reads x

            — a use-after-free on every container released without being
            destructured (segfault on macOS's allocator, silent corruption on
            glibc).  Refusing the hoist whenever the RHS mentions the
            scrutinee is deliberately conservative: losing the hoist of a
            genuinely pure read costs an optimization, and telling pure from
            invalidating apart needs effect information this pass lacks. *)
         let scrut_names =
           match scrut with Tir.AVar v -> [ v.Tir.v_name ] | _ -> [] in
         let rhs_safe =
           not (expr_mentions_any scrut_names rhs0)
           && List.for_all (fun br ->
             let br_var_names = List.map (fun v -> v.Tir.v_name) br.Tir.br_vars in
             not (expr_mentions_any br_var_names rhs0)
           ) branches in
         if not rhs_safe then None
         else begin
           (* The floated binder: a fresh name under [rename] (cannot collide,
              so each arm body is substituted onto it), else [v0] verbatim. *)
           let floated_var =
             if rename
             then { v0 with Tir.v_name = fresh_name v0.Tir.v_name }
             else v0
           in
           let float_name = floated_var.Tir.v_name in
           (* (3) The floated variable name must not be pattern-bound in any
              branch.  Always holds under [rename] (fresh name). *)
           let name_safe = rename || List.for_all (fun br ->
             not (List.exists (fun v -> v.Tir.v_name = float_name) br.Tir.br_vars)
           ) branches in
           if not name_safe then None
           else begin
             (* Strip the leading let from one branch, renaming its own binder
                onto [floated_var] when names differ. *)
             let strip_branch br =
               match leading_let br with
               | Some (v, _, body) ->
                 let body' =
                   if v.Tir.v_name = float_name then body
                   else rename_expr v.Tir.v_name float_name body
                 in
                 { br with Tir.br_body = body' }
               | None -> assert false
             in
             (* (4) Default branch must also start with an equal let (if present). *)
             let default_body_opt =
               match default with
               | None -> Some None  (* no default → OK, return None body *)
               | Some (Tir.ELet (v, rhs, body))
                 when expr_eq rhs rhs0 && (rename || v.Tir.v_name = float_name) ->
                 let body' =
                   if v.Tir.v_name = float_name then body
                   else rename_expr v.Tir.v_name float_name body
                 in
                 Some (Some body')
               | Some _ -> None  (* default doesn't match → can't float *)
             in
             match default_body_opt with
             | None -> None
             | Some new_default ->
               let new_branches = List.map strip_branch branches in
               Some (floated_var, rhs0, new_branches, new_default)
           end
         end
       end)

(** One pass: float common lets above ECases throughout an expression. *)
let rec float_expr ?(rename = false) (changed : bool ref) (e : Tir.expr)
    : Tir.expr =
  let recur = float_expr ~rename changed in
  match e with
  | Tir.ECase (a, branches, default) ->
    (* Recurse into branches first. *)
    let branches' = List.map (fun br ->
      { br with Tir.br_body = recur br.Tir.br_body }) branches in
    let default' = Option.map recur default in
    (* Now try to peel a common leading let from the (post-recursion) branches. *)
    (match peel_common_let ~rename ~scrut:a branches' default' with
     | None -> Tir.ECase (a, branches', default')
     | Some (v, rhs, new_branches, new_default) ->
       changed := true;
       (* Wrap the result in the floated let, then recurse to catch chains. *)
       let new_case = Tir.ECase (a, new_branches, new_default) in
       recur (Tir.ELet (v, rhs, new_case)))
  | Tir.ELet (v, rhs, body) ->
    Tir.ELet (v, recur rhs, recur body)
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fn ->
      { fn with Tir.fn_body = recur fn.Tir.fn_body }) fns in
    Tir.ELetRec (fns', recur body)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (recur e1, recur e2)
  (* Leaf expressions — no sub-expressions to recurse into. *)
  | Tir.EAtom _ | Tir.EApp _ | Tir.ECallPtr _ | Tir.ETuple _ | Tir.ERecord _
  | Tir.EField _ | Tir.EUpdate _ | Tir.EAlloc _ | Tir.EStackAlloc _
  | Tir.EFree _ | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _
  | Tir.EAtomicDecRC _ | Tir.EReuse _
  | Tir.EAllocHole _ | Tir.ESetField _ ->
    e

let float_fn ?(rename = false) (changed : bool ref) (fn : Tir.fn_def)
    : Tir.fn_def =
  { fn with Tir.fn_body = float_expr ~rename changed fn.Tir.fn_body }

(** Run let-floating on a TIR module.  Returns the transformed module.
    The [changed] ref is set to true if any transformation fired.

    This is the conservative variant (binder names must match) run inside the
    post-Perceus opt loop. *)
let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map (float_fn changed) m.Tir.tm_fns }

(** P1 Layer 1: pre-Perceus alpha-merge.  Floats common leading lets even when
    arms bind the shared RHS under different (fresh ANF) names, substituting
    each arm's binder for a single floated one.  Safe only on RC-free TIR, so
    it must run BEFORE [Perceus.perceus].  Loops internally until stable. *)
let run_pre ~changed (m : Tir.tir_module) : Tir.tir_module =
  let rec fixpoint m =
    let local = ref false in
    let m' = { m with Tir.tm_fns =
                 List.map (float_fn ~rename:true local) m.Tir.tm_fns } in
    if !local then (changed := true; fixpoint m') else m'
  in
  fixpoint m
