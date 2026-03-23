(** Stream fusion / deforestation pass.

    Detects chains of pure list operations where intermediate lists are
    single-use, and replaces them with fused single-pass functions.

    Pipeline position: after monomorphization, before defunctionalization.
    At this point closures are still TFn (not yet struct-wrapped by defun),
    so purity of function arguments is tractable.

    Patterns fused:
      map(xs, f) |> fold(acc, g)              → $fused_mf_N(xs, f, acc, g)
      filter(xs, p) |> fold(acc, g)           → $fused_ff_N(xs, p, acc, g)
      map(xs, f) |> filter(t, p) |> fold(acc, g) → $fused_mff_N(xs, f, p, acc, g)

    Constraints enforced:
    - Both producer and consumer calls must be pure
    - Intermediate list variable must be used exactly once
    - Effectful operations (IO, tap>, send) are never fused
    - Multi-use intermediates are never fused

    Fusible producer names (base, before mono suffix):
      map, imap, list_map, fmap
      filter, ifilter, list_filter
      take, drop

    Fusible consumer names:
      fold, fold_left, foldl, ifold, fold_right, foldr, reduce *)

module StringSet = Set.Make(String)

(* ── Helpers ───────────────────────────────────────────────────────────── *)

let mk_var name ty = { Tir.v_name = name; Tir.v_ty = ty; Tir.v_lin = Tir.Unr }

let gensym_ctr = ref 0
let gensym prefix =
  incr gensym_ctr;
  Printf.sprintf "$fused_%s_%d" prefix !gensym_ctr

(** Atom type — uses TVar "_" as a fallback for unknown. *)
let ty_of_atom : Tir.atom -> Tir.ty = function
  | Tir.AVar v                              -> v.Tir.v_ty
  | Tir.ADefRef _                           -> Tir.TVar "_"
  | Tir.ALit (March_ast.Ast.LitInt _)    -> Tir.TInt
  | Tir.ALit (March_ast.Ast.LitFloat _)  -> Tir.TFloat
  | Tir.ALit (March_ast.Ast.LitBool _)   -> Tir.TBool
  | Tir.ALit (March_ast.Ast.LitString _) -> Tir.TString
  | Tir.ALit (March_ast.Ast.LitAtom _)   -> Tir.TVar "_"

(** True when type is TVar "_" (unknown / placeholder). *)
let is_unknown_ty = function Tir.TVar "_" -> true | _ -> false

(** Strip monomorphization suffix: "map$Int_Int" → "map". *)
let base_name (s : string) : string =
  match String.index_opt s '$' with
  | Some i -> String.sub s 0 i
  | None   -> s

(* ── List type analysis ───────────────────────────────────────────────── *)

(** True if the type definition looks like a singly-linked list:
    has exactly one nil constructor (0 args) and one cons constructor (2 args). *)
let type_def_is_list : Tir.type_def -> bool = function
  | Tir.TDVariant (_, ctors) ->
    let nils  = List.filter (fun (_, args) -> args = []) ctors in
    let conss = List.filter (fun (_, args) -> List.length args = 2) ctors in
    List.length nils = 1 && List.length conss = 1
  | _ -> false

(** True if [ty] names a list-like variant type in [types]. *)
let is_list_type (types : Tir.type_def list) (ty : Tir.ty) : bool =
  match ty with
  | Tir.TCon (name, _) ->
    List.exists (function
      | Tir.TDVariant (n, _) as td -> n = name && type_def_is_list td
      | _ -> false) types
  | _ -> false

(** Find (nil_ctor, cons_ctor) names for a list type named [name]. *)
let find_list_ctors (types : Tir.type_def list) (name : string)
    : (string * string) option =
  List.find_map (function
    | Tir.TDVariant (n, ctors) when n = name && type_def_is_list (Tir.TDVariant (n, ctors)) ->
      let nil_n  = fst (List.find (fun (_, args) -> args = []) ctors) in
      let cons_n = fst (List.find (fun (_, args) -> List.length args = 2) ctors) in
      Some (nil_n, cons_n)
    | _ -> None) types

(** Return the head element type of a list variant (first arg of cons ctor).
    Returns TVar "_" if unknown. *)
let elem_ty_of_list (types : Tir.type_def list) (list_ty : Tir.ty) : Tir.ty =
  match list_ty with
  | Tir.TCon (name, _) ->
    (match List.find_map (function
       | Tir.TDVariant (n, ctors) when n = name ->
         List.find_map (fun (_, args) ->
           match args with hd :: _ -> Some hd | [] -> None) ctors
       | _ -> None) types with
     | Some t -> t
     | None   -> Tir.TVar "_")
  | _ -> Tir.TVar "_"

(* ── Use-count analysis ──────────────────────────────────────────────── *)

let rec use_count (n : string) : Tir.expr -> int = function
  | Tir.EAtom a              -> uca n a
  | Tir.EApp (f, args)       ->
    (if f.Tir.v_name = n then 1 else 0) +
    List.fold_left (fun s a -> s + uca n a) 0 args
  | Tir.ECallPtr (f, args)   ->
    uca n f + List.fold_left (fun s a -> s + uca n a) 0 args
  | Tir.ELet (_, rhs, body)  ->
    (* ANF uses fresh names per binding — no shadowing, simple raw count *)
    use_count n rhs + use_count n body
  | Tir.ELetRec (fns, body)  ->
    List.fold_left (fun s fd -> s + use_count n fd.Tir.fn_body) 0 fns
    + use_count n body
  | Tir.ECase (a, brs, def)  ->
    uca n a +
    List.fold_left (fun s b -> s + use_count n b.Tir.br_body) 0 brs +
    Option.fold ~none:0 ~some:(use_count n) def
  | Tir.ETuple atoms | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) ->
    List.fold_left (fun s a -> s + uca n a) 0 atoms
  | Tir.ERecord fs           ->
    List.fold_left (fun s (_, a) -> s + uca n a) 0 fs
  | Tir.EField (a, _) | Tir.EIncRC a | Tir.EDecRC a
  | Tir.EFree a | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a ->
    uca n a
  | Tir.EUpdate (a, fs)      ->
    uca n a + List.fold_left (fun s (_, a) -> s + uca n a) 0 fs
  | Tir.EReuse (a, _, atoms) ->
    uca n a + List.fold_left (fun s a -> s + uca n a) 0 atoms
  | Tir.ESeq (e1, e2)        -> use_count n e1 + use_count n e2

and uca (n : string) : Tir.atom -> int = function
  | Tir.AVar v -> if v.Tir.v_name = n then 1 else 0
  | _          -> 0

(* ── Fusible name classification ─────────────────────────────────────── *)

let map_names    = ["map"; "imap"; "list_map"; "fmap"]
let filter_names = ["filter"; "ifilter"; "list_filter"]
let fold_names   = ["fold"; "fold_left"; "foldl"; "ifold";
                    "fold_right"; "foldr"; "reduce"]
let producer_names = map_names @ filter_names @ ["take"; "drop"; "itake"; "idrop"]
let consumer_names = fold_names @ ["length"; "sum"; "count"]

let is_map    n = List.mem (base_name n) map_names
let is_filter n = List.mem (base_name n) filter_names
let is_fold   n = List.mem (base_name n) fold_names
let is_producer n = List.mem (base_name n) producer_names
let is_consumer n = List.mem (base_name n) consumer_names

(** Peel leading ELet bindings from [e] to find a terminal EApp.
    [wrap] accumulates the rebuild function for the peeled ELets.
    Returns [Some (wrap, fn_var, args)] when [e] ends in an EApp,
    [None] otherwise. *)
let rec extract_terminal_app
    (wrap : Tir.expr -> Tir.expr)
    : Tir.expr -> ((Tir.expr -> Tir.expr) * Tir.var * Tir.atom list) option
    = function
  | Tir.ELet (v, rhs, body) ->
    extract_terminal_app (fun inner -> wrap (Tir.ELet (v, rhs, inner))) body
  | Tir.EApp (fn_var, args) -> Some (wrap, fn_var, args)
  | _ -> None

(* ── Argument role detection ─────────────────────────────────────────── *)

(** Find the argument whose type is a list type. *)
let find_list_arg (types : Tir.type_def list) (args : Tir.atom list)
    : Tir.atom option =
  List.find_opt (fun a -> is_list_type types (ty_of_atom a)) args

(** Find arguments with a TFn type (closure / higher-order fn). *)
let find_fn_args (args : Tir.atom list) : Tir.atom list =
  List.filter (fun a -> match ty_of_atom a with Tir.TFn _ -> true | _ -> false) args

(** Find arguments that are neither a list nor a TFn (i.e. scalars / accumulators). *)
let find_scalar_args (types : Tir.type_def list) (args : Tir.atom list)
    : Tir.atom list =
  List.filter (fun a ->
    let ty = ty_of_atom a in
    not (is_list_type types ty) &&
    not (match ty with Tir.TFn _ -> true | _ -> false)) args

(* ── Fused function generators ──────────────────────────────────────── *)

(** Generate a map+fold fused function.
    Equivalent to: fold_left(combine, acc, map(transform, xs))

    fn $fused_mf_N(xs, transform, acc, combine) :=
      match xs
      | nil_ctor       → acc
      | cons_ctor(h,t) →
          let fh   = transform(h)
          let acc' = combine(acc, fh)
          $fused_mf_N(t, transform, acc', combine) *)
let gen_map_fold
    ~nil_ctor ~cons_ctor
    ~list_ty ~elem_ty ~mapped_ty ~acc_ty
    : Tir.fn_def =
  let fn_name = gensym "mf" in
  let xs   = mk_var "xs"   list_ty in
  let xf   = mk_var "f"    (Tir.TFn ([elem_ty],             mapped_ty)) in
  let acc  = mk_var "acc"  acc_ty in
  let xg   = mk_var "g"    (Tir.TFn ([acc_ty; mapped_ty],   acc_ty)) in
  let h    = mk_var "h"    elem_ty in
  let t    = mk_var "t"    list_ty in
  let fh   = mk_var "fh"   mapped_ty in
  let acc' = mk_var "acc'" acc_ty in
  let self = mk_var fn_name
    (Tir.TFn ([list_ty; xf.Tir.v_ty; acc_ty; xg.Tir.v_ty], acc_ty)) in
  let body =
    Tir.ECase (Tir.AVar xs, [
      { Tir.br_tag = nil_ctor;  br_vars = [];
        br_body = Tir.EAtom (Tir.AVar acc) };
      { Tir.br_tag = cons_ctor; br_vars = [h; t];
        br_body =
          Tir.ELet (fh,   Tir.EApp (xf, [Tir.AVar h]),
          Tir.ELet (acc', Tir.EApp (xg, [Tir.AVar acc; Tir.AVar fh]),
          Tir.EApp (self, [Tir.AVar t; Tir.AVar xf;
                           Tir.AVar acc'; Tir.AVar xg]))) };
    ], None)
  in
  { Tir.fn_name; fn_params = [xs; xf; acc; xg]; fn_ret_ty = acc_ty; fn_body = body }

(** Generate a filter+fold fused function.
    Equivalent to: fold_left(combine, acc, filter(pred, xs))

    fn $fused_ff_N(xs, pred, acc, combine) :=
      match xs
      | nil_ctor       → acc
      | cons_ctor(h,t) →
          match pred(h)
          | True  → $fused_ff_N(t, pred, combine(acc, h), combine)
          | False → $fused_ff_N(t, pred, acc, combine) *)
let gen_filter_fold
    ~nil_ctor ~cons_ctor
    ~list_ty ~elem_ty ~acc_ty
    : Tir.fn_def =
  let fn_name = gensym "ff" in
  let xs   = mk_var "xs"   list_ty in
  let xp   = mk_var "p"    (Tir.TFn ([elem_ty],           Tir.TBool)) in
  let acc  = mk_var "acc"  acc_ty in
  let xg   = mk_var "g"    (Tir.TFn ([acc_ty; elem_ty],   acc_ty)) in
  let h    = mk_var "h"    elem_ty in
  let t    = mk_var "t"    list_ty in
  let ph   = mk_var "ph"   Tir.TBool in
  let acc' = mk_var "acc'" acc_ty in
  let self = mk_var fn_name
    (Tir.TFn ([list_ty; xp.Tir.v_ty; acc_ty; xg.Tir.v_ty], acc_ty)) in
  let body =
    Tir.ECase (Tir.AVar xs, [
      { Tir.br_tag = nil_ctor;  br_vars = [];
        br_body = Tir.EAtom (Tir.AVar acc) };
      { Tir.br_tag = cons_ctor; br_vars = [h; t];
        br_body =
          Tir.ELet (ph, Tir.EApp (xp, [Tir.AVar h]),
          Tir.ECase (Tir.AVar ph, [
            { Tir.br_tag = "True";  br_vars = [];
              br_body =
                Tir.ELet (acc', Tir.EApp (xg, [Tir.AVar acc; Tir.AVar h]),
                Tir.EApp (self, [Tir.AVar t; Tir.AVar xp;
                                 Tir.AVar acc'; Tir.AVar xg])) };
            { Tir.br_tag = "False"; br_vars = [];
              br_body =
                Tir.EApp (self, [Tir.AVar t; Tir.AVar xp;
                                 Tir.AVar acc; Tir.AVar xg]) };
          ], None)) };
    ], None)
  in
  { Tir.fn_name; fn_params = [xs; xp; acc; xg]; fn_ret_ty = acc_ty; fn_body = body }

(** Generate a map+filter+fold fused function.
    Equivalent to: fold_left(combine, acc, filter(pred, map(transform, xs)))

    fn $fused_mff_N(xs, transform, pred, acc, combine) :=
      match xs
      | nil_ctor       → acc
      | cons_ctor(h,t) →
          let fh = transform(h)
          match pred(fh)
          | True  → $fused_mff_N(t, transform, pred, combine(acc, fh), combine)
          | False → $fused_mff_N(t, transform, pred, acc, combine) *)
let gen_map_filter_fold
    ~nil_ctor ~cons_ctor
    ~list_ty ~elem_ty ~mapped_ty ~acc_ty
    : Tir.fn_def =
  let fn_name = gensym "mff" in
  let xs   = mk_var "xs"   list_ty in
  let xf   = mk_var "f"    (Tir.TFn ([elem_ty],             mapped_ty)) in
  let xp   = mk_var "p"    (Tir.TFn ([mapped_ty],           Tir.TBool)) in
  let acc  = mk_var "acc"  acc_ty in
  let xg   = mk_var "g"    (Tir.TFn ([acc_ty; mapped_ty],   acc_ty)) in
  let h    = mk_var "h"    elem_ty in
  let t    = mk_var "t"    list_ty in
  let fh   = mk_var "fh"   mapped_ty in
  let ph   = mk_var "ph"   Tir.TBool in
  let acc' = mk_var "acc'" acc_ty in
  let self = mk_var fn_name
    (Tir.TFn ([list_ty; xf.Tir.v_ty; xp.Tir.v_ty; acc_ty; xg.Tir.v_ty], acc_ty)) in
  let body =
    Tir.ECase (Tir.AVar xs, [
      { Tir.br_tag = nil_ctor;  br_vars = [];
        br_body = Tir.EAtom (Tir.AVar acc) };
      { Tir.br_tag = cons_ctor; br_vars = [h; t];
        br_body =
          Tir.ELet (fh, Tir.EApp (xf, [Tir.AVar h]),
          Tir.ELet (ph, Tir.EApp (xp, [Tir.AVar fh]),
          Tir.ECase (Tir.AVar ph, [
            { Tir.br_tag = "True";  br_vars = [];
              br_body =
                Tir.ELet (acc', Tir.EApp (xg, [Tir.AVar acc; Tir.AVar fh]),
                Tir.EApp (self, [Tir.AVar t; Tir.AVar xf; Tir.AVar xp;
                                 Tir.AVar acc'; Tir.AVar xg])) };
            { Tir.br_tag = "False"; br_vars = [];
              br_body =
                Tir.EApp (self, [Tir.AVar t; Tir.AVar xf; Tir.AVar xp;
                                 Tir.AVar acc; Tir.AVar xg]) };
          ], None))) };
    ], None)
  in
  { Tir.fn_name;
    fn_params  = [xs; xf; xp; acc; xg];
    fn_ret_ty  = acc_ty;
    fn_body    = body }

(* ── Fusion attempt helpers ──────────────────────────────────────────── *)

(** For a producer call [EApp(fn_var, prod_args)] that produces [prod_var]
    (a list), and a consumer call [EApp(cons_fn, cons_args)] that consumes
    [prod_var], attempt to fuse them.

    Returns [(fused_call_expr, new_fn_def)] on success, None otherwise. *)
let try_fuse_2step
    (types    : Tir.type_def list)
    (prod_fn  : string)
    (prod_args: Tir.atom list)
    (prod_ty  : Tir.ty)        (* type of intermediate list *)
    (tmp_name : string)        (* name of the intermediate variable *)
    (cons_fn  : string)
    (cons_args: Tir.atom list)
    (cons_ty  : Tir.ty)        (* result type after consumer *)
    : (Tir.expr * Tir.fn_def) option =
  (* Guard: both must be known fusible and pure *)
  if not (is_producer prod_fn && is_consumer cons_fn) then None
  else if not (Purity.is_pure (Tir.EApp (mk_var prod_fn (Tir.TVar "_"), prod_args))) then None
  else if not (Purity.is_pure (Tir.EApp (mk_var cons_fn (Tir.TVar "_"), cons_args))) then None
  else
  (* Find list ctor names *)
  let ty_name = match prod_ty with Tir.TCon (n, _) -> Some n | _ -> None in
  match Option.bind ty_name (find_list_ctors types) with
  | None -> None
  | Some (nil_ctor, cons_ctor) ->
  let elem_ty = elem_ty_of_list types prod_ty in
  (* Strip the intermediate list arg from the consumer args to get the
     "other" args: accumulator(s) and combine function(s). *)
  let cons_other = List.filter (fun a ->
    match a with
    | Tir.AVar v when v.Tir.v_name = tmp_name -> false
    | _ -> true) cons_args in
  (* The list input to the producer (other than function args). *)
  let list_input = find_list_arg types prod_args in
  match list_input with
  | None -> None
  | Some xs_atom ->
  (* Case 1: map ∘ fold *)
  if is_map prod_fn && is_fold cons_fn then begin
    let fn_args_prod   = find_fn_args prod_args in
    let scalar_args    = find_scalar_args types cons_other in
    let fn_args_cons   = find_fn_args cons_other in
    match fn_args_prod, scalar_args, fn_args_cons with
    | [transform], [acc_atom], [combine] ->
      let mapped_ty = (match ty_of_atom transform with
        | Tir.TFn (_, r) -> r | _ -> Tir.TVar "_") in
      let acc_ty    = if is_unknown_ty cons_ty then ty_of_atom acc_atom else cons_ty in
      if is_unknown_ty elem_ty || is_unknown_ty mapped_ty || is_unknown_ty acc_ty
      then None
      else begin
        let fd = gen_map_fold ~nil_ctor ~cons_ctor
            ~list_ty:prod_ty ~elem_ty ~mapped_ty ~acc_ty in
        let call_var = mk_var fd.Tir.fn_name
            (Tir.TFn ([prod_ty; ty_of_atom transform;
                       acc_ty; ty_of_atom combine], acc_ty)) in
        let fused = Tir.EApp (call_var,
            [xs_atom; transform; acc_atom; combine]) in
        Some (fused, fd)
      end
    | _ -> None
  end
  (* Case 2: filter ∘ fold *)
  else if is_filter prod_fn && is_fold cons_fn then begin
    let fn_args_prod = find_fn_args prod_args in
    let scalar_args  = find_scalar_args types cons_other in
    let fn_args_cons = find_fn_args cons_other in
    match fn_args_prod, scalar_args, fn_args_cons with
    | [pred], [acc_atom], [combine] ->
      let acc_ty = if is_unknown_ty cons_ty then ty_of_atom acc_atom else cons_ty in
      if is_unknown_ty elem_ty || is_unknown_ty acc_ty
      then None
      else begin
        let fd = gen_filter_fold ~nil_ctor ~cons_ctor
            ~list_ty:prod_ty ~elem_ty ~acc_ty in
        let call_var = mk_var fd.Tir.fn_name
            (Tir.TFn ([prod_ty; ty_of_atom pred;
                       acc_ty; ty_of_atom combine], acc_ty)) in
        let fused = Tir.EApp (call_var,
            [xs_atom; pred; acc_atom; combine]) in
        Some (fused, fd)
      end
    | _ -> None
  end
  else None

(** Attempt a 3-step map→filter→fold fusion.
    Pattern:
      let t1 = map(xs, f)      [t1 single-use]
      let t2 = filter(t1, p)   [t2 single-use]
      let r  = fold(t2, acc, g)
    →  let r = $fused_mff_N(xs, f, p, acc, g) *)
let try_fuse_3step
    (types   : Tir.type_def list)
    (map_fn  : string)
    (map_args: Tir.atom list)
    (map_ty  : Tir.ty)
    (t1_name : string)        (* intermediate after map *)
    (flt_fn  : string)
    (flt_args: Tir.atom list)
    (t2_name : string)        (* intermediate after filter *)
    (fold_fn : string)
    (fold_args: Tir.atom list)
    (result_ty: Tir.ty)
    : (Tir.expr * Tir.fn_def) option =
  if not (is_map map_fn && is_filter flt_fn && is_fold fold_fn) then None
  else if not (Purity.is_pure (Tir.EApp (mk_var map_fn (Tir.TVar "_"), map_args))) then None
  else if not (Purity.is_pure (Tir.EApp (mk_var flt_fn (Tir.TVar "_"), flt_args))) then None
  else if not (Purity.is_pure (Tir.EApp (mk_var fold_fn (Tir.TVar "_"), fold_args))) then None
  else
  let ty_name = match map_ty with Tir.TCon (n, _) -> Some n | _ -> None in
  match Option.bind ty_name (find_list_ctors types) with
  | None -> None
  | Some (nil_ctor, cons_ctor) ->
  let elem_ty = elem_ty_of_list types map_ty in
  (* Original list input and transform fn from the map call *)
  let list_input    = find_list_arg types map_args in
  let fn_args_map   = find_fn_args map_args in
  (* Predicate from the filter call *)
  let fn_args_flt   = find_fn_args flt_args in
  (* acc and combine from the fold call, excluding the filter result *)
  let fold_other    = List.filter (fun a ->
    match a with
    | Tir.AVar v when v.Tir.v_name = t2_name -> false
    | _ -> true) fold_args in
  let scalar_fold   = find_scalar_args types fold_other in
  let fn_args_fold  = find_fn_args fold_other in
  (* Also check that t1 only appears in the filter call (single-use in the
     remaining body is guaranteed by the caller, but double-check here) *)
  ignore t1_name;
  match list_input, fn_args_map, fn_args_flt, scalar_fold, fn_args_fold with
  | Some xs_atom, [transform], [pred], [acc_atom], [combine] ->
    let mapped_ty = (match ty_of_atom transform with
      | Tir.TFn (_, r) -> r | _ -> Tir.TVar "_") in
    let acc_ty = if is_unknown_ty result_ty then ty_of_atom acc_atom else result_ty in
    if is_unknown_ty elem_ty || is_unknown_ty mapped_ty || is_unknown_ty acc_ty
    then None
    else begin
      let fd = gen_map_filter_fold ~nil_ctor ~cons_ctor
          ~list_ty:map_ty ~elem_ty ~mapped_ty ~acc_ty in
      let call_var = mk_var fd.Tir.fn_name
          (Tir.TFn ([map_ty; ty_of_atom transform; ty_of_atom pred;
                     acc_ty; ty_of_atom combine], acc_ty)) in
      let fused = Tir.EApp (call_var,
          [xs_atom; transform; pred; acc_atom; combine]) in
      Some (fused, fd)
    end
  | _ -> None

(* ── Expression rewriter ─────────────────────────────────────────────── *)

let rec fuse_expr
    (types       : Tir.type_def list)
    (new_fns_acc : Tir.fn_def list ref)
    ~(changed    : bool ref)
    (e           : Tir.expr)
    : Tir.expr =
  match e with
  (* ── Flatten nested ELet RHSes for list-typed bindings ────────────── *)
  (* Lambda arguments are pre-bound in ANF, producing:                   *)
  (*   ELet(ys, ELet(lam, ra, EApp(imap,[xs,lam])), body)                *)
  (* Float the inner binding outward so the producer EApp becomes the    *)
  (* direct RHS, enabling the producer pattern to match.                 *)
  | Tir.ELet (v, Tir.ELet (a, ra, inner), body)
    when is_list_type types v.Tir.v_ty ->
    fuse_expr types new_fns_acc ~changed
      (Tir.ELet (a, ra, Tir.ELet (v, inner, body)))

  (* ── 2-step or 3-step chain starting with a map ─────────────────── *)
  | Tir.ELet (t1, Tir.EApp (map_fn, map_args), body1)
    when is_map map_fn.Tir.v_name
      && is_list_type types t1.Tir.v_ty
      && Purity.is_pure (Tir.EApp (map_fn, map_args))
      && use_count t1.Tir.v_name body1 = 1 ->
    (* Skip past any intervening non-list bindings (e.g. lambdas) in body1
       to find the filter step for a 3-step chain.
       The filter binding RHS may have nested ELets (lambda pre-binding);
       use extract_terminal_app to find the filter EApp inside. *)
    let rec find_filter wrap2 = function
      | Tir.ELet (t2, rhs2, body2) when is_list_type types t2.Tir.v_ty ->
        (match extract_terminal_app (fun x -> x) rhs2 with
         | Some (rhs2_prefix, flt_fn, flt_args)
           when is_filter flt_fn.Tir.v_name
             && List.exists (fun a -> uca t1.Tir.v_name a = 1) flt_args
             && Purity.is_pure (Tir.EApp (flt_fn, flt_args))
             && use_count t2.Tir.v_name body2 = 1 ->
           (* Found the filter step — now look for fold *)
           let rec find_fold wrap3 = function
             | Tir.ELet (result, Tir.EApp (fold_fn, fold_args), rest)
               when is_fold fold_fn.Tir.v_name
                 && List.exists (fun a -> uca t2.Tir.v_name a = 1) fold_args ->
               (match try_fuse_3step types
                        map_fn.Tir.v_name map_args t1.Tir.v_ty
                        t1.Tir.v_name
                        flt_fn.Tir.v_name flt_args
                        t2.Tir.v_name
                        fold_fn.Tir.v_name fold_args result.Tir.v_ty with
                | Some (fused, fd) ->
                  changed := true;
                  new_fns_acc := fd :: !new_fns_acc;
                  let inner = fuse_expr types new_fns_acc ~changed
                      (Tir.ELet (result, fused, rest)) in
                  Some (wrap2 (rhs2_prefix (wrap3 inner)))
                | None -> None)
             (* Terminal fold — fold is the last expression in the body *)
             | Tir.EApp (fold_fn, fold_args)
               when is_fold fold_fn.Tir.v_name
                 && List.exists (fun a -> uca t2.Tir.v_name a = 1) fold_args ->
               (match try_fuse_3step types
                        map_fn.Tir.v_name map_args t1.Tir.v_ty
                        t1.Tir.v_name
                        flt_fn.Tir.v_name flt_args
                        t2.Tir.v_name
                        fold_fn.Tir.v_name fold_args (Tir.TVar "_") with
                | Some (fused, fd) ->
                  changed := true;
                  new_fns_acc := fd :: !new_fns_acc;
                  Some (wrap2 (rhs2_prefix
                    (wrap3 (fuse_expr types new_fns_acc ~changed fused))))
                | None -> None)
             | Tir.ELet (v, rhs, body')
               when not (is_list_type types v.Tir.v_ty) ->
               find_fold (fun i -> wrap3 (Tir.ELet (v, rhs, i))) body'
             | _ -> None
           in
           find_fold (fun x -> x) body2
         | _ -> None)
      | Tir.ELet (v, rhs, body')
        when not (is_list_type types v.Tir.v_ty) ->
        find_filter (fun i -> wrap2 (Tir.ELet (v, rhs, i))) body'
      | _ -> None
    in
    (match find_filter (fun x -> x) body1 with
     | Some result_expr -> result_expr
     | None ->
       (* No 3-step; try 2-step *)
       try_fuse_2step_let types new_fns_acc ~changed
         t1 map_fn.Tir.v_name map_args body1)

  (* ── 2-step: producer → consumer ─────────────────────────────────── *)
  | Tir.ELet (tmp, Tir.EApp (prod_fn, prod_args), body)
    when is_producer prod_fn.Tir.v_name
      && is_list_type types tmp.Tir.v_ty
      && Purity.is_pure (Tir.EApp (prod_fn, prod_args))
      && use_count tmp.Tir.v_name body = 1 ->
    try_fuse_2step_let types new_fns_acc ~changed
      tmp prod_fn.Tir.v_name prod_args body

  (* ── Recursive descent ────────────────────────────────────────────── *)
  | Tir.ELet (v, rhs, body) ->
    Tir.ELet (v,
      fuse_expr types new_fns_acc ~changed rhs,
      fuse_expr types new_fns_acc ~changed body)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (
      List.map (fun fd ->
        { fd with Tir.fn_body =
            fuse_expr types new_fns_acc ~changed fd.Tir.fn_body }) fns,
      fuse_expr types new_fns_acc ~changed body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a,
      List.map (fun b ->
        { b with Tir.br_body =
            fuse_expr types new_fns_acc ~changed b.Tir.br_body }) brs,
      Option.map (fuse_expr types new_fns_acc ~changed) def)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (fuse_expr types new_fns_acc ~changed e1,
              fuse_expr types new_fns_acc ~changed e2)
  | other -> other

(** Search through a body expression for the single consumer use of [tmp],
    skipping over intervening pure non-list ELet bindings (e.g. lambda
    captures, scalar temporaries).

    [wrap] re-applies accumulated skipped bindings around the final result.

    Returns [Some new_body] when fusion succeeds, [None] otherwise. *)
and search_consumer
    (types       : Tir.type_def list)
    (new_fns_acc : Tir.fn_def list ref)
    ~(changed    : bool ref)
    (tmp         : Tir.var)
    (prod_fn     : string)
    (prod_args   : Tir.atom list)
    (wrap        : Tir.expr -> Tir.expr)
    (body        : Tir.expr)
    : Tir.expr option =
  match body with
  (* ── Consumer in a let binding: let r = fold(...) in rest ─────── *)
  | Tir.ELet (result, Tir.EApp (cons_fn, cons_args), rest)
    when is_consumer cons_fn.Tir.v_name
      && List.exists (fun a -> uca tmp.Tir.v_name a = 1) cons_args ->
    (match try_fuse_2step types
             prod_fn prod_args tmp.Tir.v_ty tmp.Tir.v_name
             cons_fn.Tir.v_name cons_args result.Tir.v_ty with
     | Some (fused, fd) ->
       changed := true;
       new_fns_acc := fd :: !new_fns_acc;
       let inner = fuse_expr types new_fns_acc ~changed
           (Tir.ELet (result, fused, rest)) in
       Some (wrap inner)
     | None -> None)
  (* ── Terminal consumer: fold(...) as the final expression ─────── *)
  | Tir.EApp (cons_fn, cons_args)
    when is_consumer cons_fn.Tir.v_name
      && List.exists (fun a -> uca tmp.Tir.v_name a = 1) cons_args ->
    (* Result type is unknown at this site; try_fuse_2step infers from args *)
    (match try_fuse_2step types
             prod_fn prod_args tmp.Tir.v_ty tmp.Tir.v_name
             cons_fn.Tir.v_name cons_args (Tir.TVar "_") with
     | Some (fused, fd) ->
       changed := true;
       new_fns_acc := fd :: !new_fns_acc;
       Some (wrap (fuse_expr types new_fns_acc ~changed fused))
     | None -> None)
  (* ── Skip intervening pure non-list bindings (e.g. lambdas) ──── *)
  | Tir.ELet (v, rhs, body')
    when not (is_list_type types v.Tir.v_ty) ->
    let wrap' inner = wrap (Tir.ELet (v, rhs, inner)) in
    search_consumer types new_fns_acc ~changed tmp prod_fn prod_args wrap' body'
  (* ── No matching consumer found ──────────────────────────────── *)
  | _ -> None

(** Handle the 2-step producer→consumer ELet pattern. *)
and try_fuse_2step_let
    (types       : Tir.type_def list)
    (new_fns_acc : Tir.fn_def list ref)
    ~(changed    : bool ref)
    (tmp         : Tir.var)
    (prod_fn     : string)
    (prod_args   : Tir.atom list)
    (body        : Tir.expr)
    : Tir.expr =
  match search_consumer types new_fns_acc ~changed tmp prod_fn prod_args
          (fun x -> x) body with
  | Some new_body -> new_body
  | None ->
    Tir.ELet (tmp, Tir.EApp (mk_var prod_fn tmp.Tir.v_ty, prod_args),
      fuse_expr types new_fns_acc ~changed body)

(* ── Module-level pass ───────────────────────────────────────────────── *)

let run ~(changed : bool ref) (m : Tir.tir_module) : Tir.tir_module =
  let new_fns_acc = ref [] in
  let fns' = List.map (fun fd ->
    { fd with Tir.fn_body =
        fuse_expr m.Tir.tm_types new_fns_acc ~changed fd.Tir.fn_body }
  ) m.Tir.tm_fns in
  { m with Tir.tm_fns = List.rev !new_fns_acc @ fns' }
