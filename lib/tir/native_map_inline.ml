(** P10 Phase 2 — inline non-capturing NativeArray.map closures.

    Runs once, right after [Defun.defunctionalize].  Detects the specific
    shape defun always produces for [NativeArray.map_int]/[map_float] when
    the callback is a *fresh, non-capturing* lambda used nowhere else:

      let $clo = EAlloc(closure_ty, [apply_fn_ptr])   (* no captured fvs *)
      ... EApp(native_int_arr_map/native_float_arr_map, [arr; AVar $clo]) ...

    and rewrites it to a synthetic call that hands llvm_emit.ml the apply
    fn's name directly instead of the (now-dropped) closure allocation:

      EApp(__native_int_arr_map_inline/__native_float_arr_map_inline,
           [arr; AVar apply_fn])

    llvm_emit.ml recognizes the synthetic names and emits a loop that calls
    the apply fn directly (same LLVM module -> inlinable), instead of going
    through the C runtime's opaque closure-pointer indirection (a different
    translation unit -> never inlinable, so never vectorizable).  See
    specs/optimizations.md P10 for why this only benefits Int in practice
    (Float's per-element box/unbox call still blocks the vectorizer).

    This is a narrow, conservative peephole: any shape it doesn't recognize
    (a capturing closure, one stored in a variable and reused, a recursive
    lambda, ...) is left completely untouched and falls back to the existing,
    correct, closure-struct-and-indirect-call path. *)

let target_map_names = [ "native_int_arr_map"; "native_float_arr_map" ]

let inline_name_of = function
  | "native_int_arr_map"   -> "__native_int_arr_map_inline"
  | "native_float_arr_map" -> "__native_float_arr_map_inline"
  | other -> other

(** Count AVar occurrences of [name] in [e]. Does not descend into a scope
    that rebinds [name] (compiler-synthesized temp names never collide with
    themselves in practice, but this keeps the check honest). *)
let rec count_uses (name : string) (e : Tir.expr) : int =
  let ca a = match a with Tir.AVar v when v.Tir.v_name = name -> 1 | _ -> 0 in
  let cas args = List.fold_left (fun acc a -> acc + ca a) 0 args in
  match e with
  | Tir.EAtom a -> ca a
  | Tir.EApp (f, args) -> (if f.Tir.v_name = name then 1 else 0) + cas args
  | Tir.ECallPtr (f, args) -> ca f + cas args
  | Tir.ELet (v, e1, e2) ->
    count_uses name e1 + (if v.Tir.v_name = name then 0 else count_uses name e2)
  | Tir.ELetRec (fns, body) ->
    List.fold_left (fun acc fn -> acc + count_uses name fn.Tir.fn_body) 0 fns
    + count_uses name body
  | Tir.ECase (a, brs, def) ->
    ca a
    + List.fold_left (fun acc (br : Tir.branch) -> acc + count_uses name br.Tir.br_body) 0 brs
    + (match def with Some e -> count_uses name e | None -> 0)
  | Tir.ETuple atoms -> cas atoms
  | Tir.ERecord fields -> List.fold_left (fun acc (_, a) -> acc + ca a) 0 fields
  | Tir.EField (a, _) -> ca a
  | Tir.EUpdate (a, fields) -> ca a + List.fold_left (fun acc (_, a) -> acc + ca a) 0 fields
  | Tir.EAlloc (_, args) | Tir.EStackAlloc (_, args) -> cas args
  | Tir.EFree a -> ca a
  | Tir.EIncRC a | Tir.EAtomicIncRC a -> ca a
  | Tir.EDecRC a | Tir.EAtomicDecRC a -> ca a
  | Tir.EReuse (a, _, args) -> ca a + cas args
  | Tir.ESeq (e1, e2) -> count_uses name e1 + count_uses name e2

(** Find the map-builtin name at the single occurrence of [v_name] as the
    2nd argument of a target call, if that's where it is. *)
let rec find_target_call (v_name : string) (e : Tir.expr) : string option =
  match e with
  | Tir.EApp (f, [ _; Tir.AVar v2 ])
    when v2.Tir.v_name = v_name && List.mem f.Tir.v_name target_map_names ->
    Some f.Tir.v_name
  | Tir.ELet (_, e1, e2) ->
    (match find_target_call v_name e1 with Some _ as r -> r | None -> find_target_call v_name e2)
  | Tir.ELetRec (fns, body) ->
    (match List.find_map (fun fn -> find_target_call v_name fn.Tir.fn_body) fns with
     | Some _ as r -> r
     | None -> find_target_call v_name body)
  | Tir.ECase (_, brs, def) ->
    (match List.find_map (fun (br : Tir.branch) -> find_target_call v_name br.Tir.br_body) brs with
     | Some _ as r -> r
     | None -> (match def with Some e -> find_target_call v_name e | None -> None))
  | Tir.ESeq (e1, e2) ->
    (match find_target_call v_name e1 with Some _ as r -> r | None -> find_target_call v_name e2)
  | _ -> None

(** Replace the single EApp(target_name, [arr; AVar v_name]) node with
    EApp(inline_name, [arr; AVar apply_var]). *)
let rec subst_call (target_name : string) (v_name : string) (apply_var : Tir.var)
    (e : Tir.expr) : Tir.expr =
  let go = subst_call target_name v_name apply_var in
  match e with
  | Tir.EApp (f, [ arr; Tir.AVar v2 ])
    when v2.Tir.v_name = v_name && f.Tir.v_name = target_name ->
    Tir.EApp ({ f with Tir.v_name = inline_name_of target_name }, [ arr; Tir.AVar apply_var ])
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, go e1, go e2)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun fn -> { fn with Tir.fn_body = go fn.Tir.fn_body }) fns, go body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (br : Tir.branch) -> { br with Tir.br_body = go br.Tir.br_body }) brs,
               Option.map go def)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
  | other -> other

(* fn_name -> fn_def, restricted to apply wrappers (FnApply) that take
   exactly ($clo, one original param) -- i.e. a unary, non-recursive-shaped
   lambda.  map's callback is always unary. *)
let apply_fn_table (m : Tir.tir_module) : (string, Tir.fn_def) Hashtbl.t =
  let t = Hashtbl.create 16 in
  List.iter (fun fn ->
      if fn.Tir.fn_kind = Tir.FnApply && List.length fn.Tir.fn_params = 2 then
        Hashtbl.replace t fn.Tir.fn_name fn)
    m.Tir.tm_fns;
  t

(* Cprop deliberately never propagates closure-typed copies (see
   Cprop.avar_env's TFn exclusion — ECallPtr dispatch is name-sensitive in
   llvm_emit), so a closure allocation used exactly once still reaches this
   pass through one or more transparent `let f = clo in ...` copies rather
   than being referenced directly.  Walk past a chain of those before doing
   the eligibility check, so [effective_name] is the name actually used at
   the call site. *)
let rec strip_alias_chain (name : string) (e : Tir.expr) : string * Tir.expr =
  match e with
  | Tir.ELet (v2, Tir.EAtom (Tir.AVar v3), cont) when v3.Tir.v_name = name ->
    strip_alias_chain v2.Tir.v_name cont
  | _ -> (name, e)

let rec rewrite_expr (apply_fns : (string, Tir.fn_def) Hashtbl.t) (e : Tir.expr) : Tir.expr =
  match e with
  | Tir.ELet (v, (Tir.EAlloc (Tir.TCon (_clo_name, []), [ Tir.AVar apply_var ]) as alloc_e), rest) ->
    let (effective_name, inner) = strip_alias_chain v.Tir.v_name rest in
    let inner' = rewrite_expr apply_fns inner in
    let eligible =
      Hashtbl.mem apply_fns apply_var.Tir.v_name
      && count_uses effective_name inner' = 1
    in
    if not eligible then Tir.ELet (v, alloc_e, rewrite_expr apply_fns rest)
    else
      (match find_target_call effective_name inner' with
       | Some target_name -> subst_call target_name effective_name apply_var inner'
       | None -> Tir.ELet (v, alloc_e, rewrite_expr apply_fns rest))
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, rewrite_expr apply_fns e1, rewrite_expr apply_fns e2)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun fn -> { fn with Tir.fn_body = rewrite_expr apply_fns fn.Tir.fn_body }) fns,
                 rewrite_expr apply_fns body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (br : Tir.branch) -> { br with Tir.br_body = rewrite_expr apply_fns br.Tir.br_body }) brs,
               Option.map (rewrite_expr apply_fns) def)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (rewrite_expr apply_fns e1, rewrite_expr apply_fns e2)
  | other -> other

let run (m : Tir.tir_module) : Tir.tir_module =
  let apply_fns = apply_fn_table m in
  { m with
    Tir.tm_fns = List.map (fun fn -> { fn with Tir.fn_body = rewrite_expr apply_fns fn.Tir.fn_body }) m.Tir.tm_fns
  }
