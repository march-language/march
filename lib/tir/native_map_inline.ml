(** P10 Phase 2/2c — inline NativeArray.map closures.

    Runs once, after Opt (bin/main.ml) — needs Inline to have already
    flattened the [NativeArray.map_int]/[map_float] stdlib wrapper into its
    call site; at Defun time the closure allocation and the
    native_int_arr_map/native_float_arr_map call are still in two different
    function bodies. Handles two shapes, both keyed off the same
    eligibility bar: the closure is a fresh lambda used exactly once,
    precisely as the map call's 2nd argument.

    Phase 2 — non-capturing (EAlloc's arg list is the singleton
    [apply_fn_ptr], no captured free vars):

      let $clo = EAlloc(closure_ty, [apply_fn_ptr]) in
      ... EApp(native_int_arr_map/native_float_arr_map, [arr; AVar $clo]) ...

    Since the closure holds nothing, it's dropped outright and the call is
    rewritten to reference the apply fn directly, with llvm_emit.ml passing
    `null` for $clo (the apply body never reads it):

      EApp(__native_int_arr_map_inline/__native_float_arr_map_inline,
           [arr; AVar apply_fn])

    Phase 2c — capturing (EAlloc's arg list has one or more captured free
    vars after the fn ptr): the closure struct is a real, live value the
    apply body actually reads from, so nothing upstream is touched — no
    allocation dropped, no alias-copy lets or Perceus RC ops disturbed.
    Only the terminal call is rewritten in place, to a 3-arg form that
    keeps the closure pointer as a genuine 3rd argument instead of null:

      EApp(__native_int_arr_map_inline/__native_float_arr_map_inline,
           [arr; AVar apply_fn; AVar clo])

    Either way, llvm_emit.ml recognizes the synthetic names and emits a
    loop that calls the apply fn directly (same LLVM module -> inlinable),
    instead of going through the C runtime's opaque closure-pointer
    indirection (a different translation unit -> never inlinable, so never
    vectorizable). See specs/optimizations.md P10 for the vectorization
    story in each case (Phase 2 only benefits Int in practice — Float's
    per-element box/unbox call still blocks the vectorizer; Phase 2c's
    captured-var load is loop-invariant and typically gets hoisted once
    inlined, so the loop body is no worse off than Phase 2's).

    This is a narrow, conservative peephole either way: any shape it
    doesn't recognize (a closure stored in a variable and reused, one whose
    alias chain never resolves to a bare map call, ...) is left completely
    untouched and falls back to the existing, correct,
    closure-struct-and-indirect-call path. *)

let target_map_names = [ "native_int_arr_map"; "native_float_arr_map" ]

(* P10 Phase 2/2c's two-array counterpart (map2 added 2026-07-27 to unblock
   DataFrame.col_add_col). Same eligibility bar and inlining trick as the
   single-array case above -- a fresh, single-use closure whose apply fn is
   called directly instead of through the runtime's closure-pointer
   indirection -- just with 2 leading NativeArray args instead of 1 before
   the trailing closure arg, and a 2-param ($clo, a, b) apply fn instead of
   1-param. See [find_target_call2]/[subst_call2]/[find_target_call_var2]/
   [subst_call_capturing2] below and [Llvm_emit.emit_native_map2_inline_loop]. *)
let target_map2_names = [ "native_int_arr_map2"; "native_float_arr_map2" ]

let inline_name_of ~unboxed = function
  | "native_int_arr_map"   -> "__native_int_arr_map_inline"
  | "native_float_arr_map" -> if unboxed then "__native_float_arr_map_inline_unboxed"
                              else "__native_float_arr_map_inline"
  | "native_int_arr_map2"   -> "__native_int_arr_map2_inline"
  | "native_float_arr_map2" -> if unboxed then "__native_float_arr_map2_inline_unboxed"
                               else "__native_float_arr_map2_inline"
  | other -> other

(** Float-boxing Stage 4, Option B — the unboxed variant of an apply fn.

    [Tir_names.is_apply_fn] (the single predicate every box/unbox decision
    in [lib/tir/llvm_toplevel.ml]'s function-emission code keys off) is a
    pure name check: does the name contain the literal substring
    ["$apply$"]. It is not a structural/TIR-level marker — the lifted
    lambda's [fn_def] already carries its natural, concrete parameter and
    return types; boxing is purely a codegen-time decision applied because
    the name matches. So emitting the EXACT SAME [fn_def] under a
    differently-shaped name — one that does not contain ["$apply$"] — makes
    the existing, unmodified emission code treat it as an ordinary
    function: natural `double`/`i64` params and return, no
    march_alloc_float/march_unbox_float anywhere. This produces a second,
    unboxed entry point for the same lambda body with zero changes to
    [llvm_toplevel.ml].

    [apply_name] is always ["<fn>$apply$<uid>"] ([Tir_names.apply_fn_name]);
    splice out the "$apply$" marker itself (not just append past it — a
    name like "foo$apply$3U" would still CONTAIN "$apply$" as a substring
    and get boxed anyway). *)
let unboxed_name_of (apply_name : string) : string =
  let marker = "$apply$" in
  let mlen = String.length marker and nlen = String.length apply_name in
  let rec find i =
    if i + mlen > nlen then None
    else if String.sub apply_name i mlen = marker then Some i
    else find (i + 1)
  in
  match find 0 with
  | Some i ->
    String.sub apply_name 0 i ^ "$mapfast$" ^
    String.sub apply_name (i + mlen) (nlen - i - mlen)
  | None -> apply_name ^ "$mapfast$0"

(** True iff [fn]'s callback signature (every param after $clo, and the
    return type) is concretely Float — i.e. eligible for the unboxed
    variant. A [TVar] (unresolved generic) or any non-Float param/return
    means the boxed ptr ABI is still needed (either it's not Float at all,
    or its concrete type isn't known here). *)
let is_all_float_signature (fn : Tir.fn_def) : bool =
  fn.Tir.fn_ret_ty = Tir.TFloat
  && (match fn.Tir.fn_params with
      | _clo :: rest -> List.for_all (fun (p : Tir.var) -> p.Tir.v_ty = Tir.TFloat) rest
      | [] -> false)

(** If [target_name] is ["native_float_arr_map"] or ["native_float_arr_map2"]
    and the apply fn behind [apply_var] has an all-Float signature, synthesize
    its unboxed clone
    (pushing it onto [extra_fns] so [run] can add it to the module) and
    return a fresh [Tir.var] referencing it — same construction
    [Defun.lift_lambda] uses for the boxed fn-pointer atom (opaque
    [TPtr TUnit], never RC'd: a code address, not a heap value). Returns
    [None] for anything else (Int has no box to skip; a non-Float or
    still-generic signature keeps the boxed path). *)
let try_unboxed_variant (apply_fns : (string, Tir.fn_def) Hashtbl.t)
    (extra_fns : Tir.fn_def list ref) (target_name : string) (apply_var : Tir.var)
    : Tir.var option =
  if target_name <> "native_float_arr_map" && target_name <> "native_float_arr_map2" then None
  else
    match Hashtbl.find_opt apply_fns apply_var.Tir.v_name with
    | Some fn when is_all_float_signature fn ->
      let unboxed_name = unboxed_name_of fn.Tir.fn_name in
      if not (List.exists (fun f -> f.Tir.fn_name = unboxed_name) !extra_fns) then
        extra_fns := { fn with Tir.fn_name = unboxed_name } :: !extra_fns;
      Some { Tir.v_name = unboxed_name; v_ty = Tir.TPtr Tir.TUnit; v_lin = Tir.Unr }
    | _ -> None

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
  | Tir.EAlloc (_, args) | Tir.EStackAlloc (_, args)
  | Tir.EAllocHole (_, args, _) -> cas args
  | Tir.ESetField (o, _, v) -> ca o + ca v
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
    EApp(inline_name, [arr; AVar apply_var]). [apply_var] may be the
    original boxed apply fn, or (when [unboxed]) its unboxed clone from
    [try_unboxed_variant] — either way this just wires up the reference;
    the caller decides which one. *)
let rec subst_call ~unboxed (target_name : string) (v_name : string) (apply_var : Tir.var)
    (e : Tir.expr) : Tir.expr =
  let go = subst_call ~unboxed target_name v_name apply_var in
  match e with
  | Tir.EApp (f, [ arr; Tir.AVar v2 ])
    when v2.Tir.v_name = v_name && f.Tir.v_name = target_name ->
    Tir.EApp ({ f with Tir.v_name = inline_name_of ~unboxed target_name }, [ arr; Tir.AVar apply_var ])
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, go e1, go e2)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun fn -> { fn with Tir.fn_body = go fn.Tir.fn_body }) fns, go body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (br : Tir.branch) -> { br with Tir.br_body = go br.Tir.br_body }) brs,
               Option.map go def)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
  | other -> other

(** Same search as [find_target_call], but also returns the matched call's
    closure-argument [Tir.var] record (with its real TIR type) — the P10
    Phase 2c capturing-closure rewrite below needs the actual var, not just
    its name, to build a well-typed replacement atom. *)
let rec find_target_call_var (v_name : string) (e : Tir.expr) : (string * Tir.var) option =
  match e with
  | Tir.EApp (f, [ _; Tir.AVar v2 ])
    when v2.Tir.v_name = v_name && List.mem f.Tir.v_name target_map_names ->
    Some (f.Tir.v_name, v2)
  | Tir.ELet (_, e1, e2) ->
    (match find_target_call_var v_name e1 with Some _ as r -> r | None -> find_target_call_var v_name e2)
  | Tir.ELetRec (fns, body) ->
    (match List.find_map (fun fn -> find_target_call_var v_name fn.Tir.fn_body) fns with
     | Some _ as r -> r
     | None -> find_target_call_var v_name body)
  | Tir.ECase (_, brs, def) ->
    (match List.find_map (fun (br : Tir.branch) -> find_target_call_var v_name br.Tir.br_body) brs with
     | Some _ as r -> r
     | None -> (match def with Some e -> find_target_call_var v_name e | None -> None))
  | Tir.ESeq (e1, e2) ->
    (match find_target_call_var v_name e1 with Some _ as r -> r | None -> find_target_call_var v_name e2)
  | _ -> None

(** P10 Phase 2c — like [subst_call], but for a CAPTURING closure: replaces
    EApp(target_name, [arr; AVar v_name]) with a 3-arg inline call that also
    passes the real closure pointer [clo_var] through, instead of dropping
    it. Never touches anything else — the allocation, alias-copy lets, and
    any RC ops around them are the caller's problem to leave alone (and it
    does; see the capturing arm in [rewrite_expr]). *)
let rec subst_call_capturing ~unboxed (target_name : string) (v_name : string)
    (apply_var : Tir.var) (clo_var : Tir.var) (e : Tir.expr) : Tir.expr =
  let go = subst_call_capturing ~unboxed target_name v_name apply_var clo_var in
  match e with
  | Tir.EApp (f, [ arr; Tir.AVar v2 ])
    when v2.Tir.v_name = v_name && f.Tir.v_name = target_name ->
    Tir.EApp ({ f with Tir.v_name = inline_name_of ~unboxed target_name },
              [ arr; Tir.AVar apply_var; Tir.AVar clo_var ])
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, go e1, go e2)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun fn -> { fn with Tir.fn_body = go fn.Tir.fn_body }) fns, go body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (br : Tir.branch) -> { br with Tir.br_body = go br.Tir.br_body }) brs,
               Option.map go def)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
  | other -> other

(* ── map2 (two-array) counterparts of the four functions above ──────────
   Same searches/substitutions, just matching a 3-arg call
   EApp(f, [arr1; arr2; AVar v_name]) — the closure sits in the LAST
   position after two leading NativeArray args, instead of the 2nd of
   exactly two. *)

(** map2 counterpart of [find_target_call]. *)
let rec find_target_call2 (v_name : string) (e : Tir.expr) : string option =
  match e with
  | Tir.EApp (f, [ _; _; Tir.AVar v3 ])
    when v3.Tir.v_name = v_name && List.mem f.Tir.v_name target_map2_names ->
    Some f.Tir.v_name
  | Tir.ELet (_, e1, e2) ->
    (match find_target_call2 v_name e1 with Some _ as r -> r | None -> find_target_call2 v_name e2)
  | Tir.ELetRec (fns, body) ->
    (match List.find_map (fun fn -> find_target_call2 v_name fn.Tir.fn_body) fns with
     | Some _ as r -> r
     | None -> find_target_call2 v_name body)
  | Tir.ECase (_, brs, def) ->
    (match List.find_map (fun (br : Tir.branch) -> find_target_call2 v_name br.Tir.br_body) brs with
     | Some _ as r -> r
     | None -> (match def with Some e -> find_target_call2 v_name e | None -> None))
  | Tir.ESeq (e1, e2) ->
    (match find_target_call2 v_name e1 with Some _ as r -> r | None -> find_target_call2 v_name e2)
  | _ -> None

(** map2 counterpart of [subst_call]. *)
let rec subst_call2 ~unboxed (target_name : string) (v_name : string) (apply_var : Tir.var)
    (e : Tir.expr) : Tir.expr =
  let go = subst_call2 ~unboxed target_name v_name apply_var in
  match e with
  | Tir.EApp (f, [ arr1; arr2; Tir.AVar v3 ])
    when v3.Tir.v_name = v_name && f.Tir.v_name = target_name ->
    Tir.EApp ({ f with Tir.v_name = inline_name_of ~unboxed target_name }, [ arr1; arr2; Tir.AVar apply_var ])
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, go e1, go e2)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun fn -> { fn with Tir.fn_body = go fn.Tir.fn_body }) fns, go body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (br : Tir.branch) -> { br with Tir.br_body = go br.Tir.br_body }) brs,
               Option.map go def)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
  | other -> other

(** map2 counterpart of [find_target_call_var]. *)
let rec find_target_call_var2 (v_name : string) (e : Tir.expr) : (string * Tir.var) option =
  match e with
  | Tir.EApp (f, [ _; _; Tir.AVar v3 ])
    when v3.Tir.v_name = v_name && List.mem f.Tir.v_name target_map2_names ->
    Some (f.Tir.v_name, v3)
  | Tir.ELet (_, e1, e2) ->
    (match find_target_call_var2 v_name e1 with Some _ as r -> r | None -> find_target_call_var2 v_name e2)
  | Tir.ELetRec (fns, body) ->
    (match List.find_map (fun fn -> find_target_call_var2 v_name fn.Tir.fn_body) fns with
     | Some _ as r -> r
     | None -> find_target_call_var2 v_name body)
  | Tir.ECase (_, brs, def) ->
    (match List.find_map (fun (br : Tir.branch) -> find_target_call_var2 v_name br.Tir.br_body) brs with
     | Some _ as r -> r
     | None -> (match def with Some e -> find_target_call_var2 v_name e | None -> None))
  | Tir.ESeq (e1, e2) ->
    (match find_target_call_var2 v_name e1 with Some _ as r -> r | None -> find_target_call_var2 v_name e2)
  | _ -> None

(** map2 counterpart of [subst_call_capturing] — the rewritten call becomes
    4-arg (arr1, arr2, apply_var, clo_var) instead of 3. *)
let rec subst_call_capturing2 ~unboxed (target_name : string) (v_name : string)
    (apply_var : Tir.var) (clo_var : Tir.var) (e : Tir.expr) : Tir.expr =
  let go = subst_call_capturing2 ~unboxed target_name v_name apply_var clo_var in
  match e with
  | Tir.EApp (f, [ arr1; arr2; Tir.AVar v3 ])
    when v3.Tir.v_name = v_name && f.Tir.v_name = target_name ->
    Tir.EApp ({ f with Tir.v_name = inline_name_of ~unboxed target_name },
              [ arr1; arr2; Tir.AVar apply_var; Tir.AVar clo_var ])
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, go e1, go e2)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun fn -> { fn with Tir.fn_body = go fn.Tir.fn_body }) fns, go body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (br : Tir.branch) -> { br with Tir.br_body = go br.Tir.br_body }) brs,
               Option.map go def)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
  | other -> other

(* fn_name -> fn_def, restricted to apply wrappers (FnApply) taking either
   ($clo, one original param) -- map's unary callback -- or ($clo, two
   original params) -- map2's binary callback, e.g. `fn (a, b) -> a + b`.
   Arity compatibility with the actual call site (map vs map2) is enforced
   separately by which target-call shape [rewrite_expr] finds; a 3-param
   entry here simply never matches the 2-arg map call shape and vice versa. *)
let apply_fn_table (m : Tir.tir_module) : (string, Tir.fn_def) Hashtbl.t =
  let t = Hashtbl.create 16 in
  List.iter (fun fn ->
      if fn.Tir.fn_kind = Tir.FnApply
      && (List.length fn.Tir.fn_params = 2 || List.length fn.Tir.fn_params = 3) then
        Hashtbl.replace t fn.Tir.fn_name fn)
    m.Tir.tm_fns;
  t

(* Cprop deliberately never propagates closure-typed copies (see
   Cprop.avar_env's TFn exclusion — ECallPtr dispatch is name-sensitive in
   llvm_emit), so a closure allocation used exactly once still reaches this
   pass through one or more transparent `let f = clo in ...` copies rather
   than being referenced directly.  Walk past a chain of those before doing
   the eligibility check, so [effective_name] is the name actually used at
   the call site.

   Perceus also frequently inserts an unrelated RC op (e.g. `inc_rc arr;`
   for some OTHER live variable, not the closure) as an `ESeq` between the
   alloc and the alias-let — e.g. when the array being mapped is used again
   later, such as in a self-recursive loop that both maps `arr` and passes
   `arr` on to its own tail call.  See past it too, but only when it does
   not itself mention [name]: an RC op on the closure var being tracked
   (rather than some other var) would mean our "used exactly once" analysis
   can't just skip over it, so bail out of peeling in that case instead of
   risking a miscount. Every wrapper we peel is returned (in original
   order) so the caller can re-wrap the rewritten body in the same
   `ESeq`s — dropping or reordering one would be an RC correctness bug
   (UAF / premature free), not just a missed optimization. *)
let rec strip_alias_chain (name : string) (e : Tir.expr) : string * Tir.expr list * Tir.expr =
  match e with
  | Tir.ELet (v2, Tir.EAtom (Tir.AVar v3), cont) when v3.Tir.v_name = name ->
    strip_alias_chain v2.Tir.v_name cont
  | Tir.ESeq (other, cont) when count_uses name other = 0 ->
    let (final_name, wrappers, final_e) = strip_alias_chain name cont in
    (final_name, other :: wrappers, final_e)
  | _ -> (name, [], e)

let rec rewrite_expr (apply_fns : (string, Tir.fn_def) Hashtbl.t)
    (extra_fns : Tir.fn_def list ref) (e : Tir.expr) : Tir.expr =
  let rewrite_expr = rewrite_expr apply_fns extra_fns in
  match e with
  | Tir.ELet (v, (Tir.EAlloc (Tir.TCon (_clo_name, []), [ Tir.AVar apply_var ]) as alloc_e), rest) ->
    let (effective_name, wrappers, inner) = strip_alias_chain v.Tir.v_name rest in
    let inner' = rewrite_expr inner in
    let eligible =
      Hashtbl.mem apply_fns apply_var.Tir.v_name
      && count_uses effective_name inner' = 1
    in
    if not eligible then Tir.ELet (v, alloc_e, rewrite_expr rest)
    else
      (* Float-boxing Stage 4, Option B: an all-Float callback (no
         captures here, so nothing to check besides the signature) gets
         an unboxed clone instead of the boxed apply_var — see
         [try_unboxed_variant]. Anything else (Int, or a still-generic
         signature) keeps the existing boxed reference. Shared between the
         map and map2 shapes below since eligibility only depends on the
         apply fn itself, not which call matched. *)
      let unboxed_pair target_name =
        match try_unboxed_variant apply_fns extra_fns target_name apply_var with
        | Some v -> (true, v)
        | None -> (false, apply_var)
      in
      (match find_target_call effective_name inner' with
       | Some target_name ->
         let (unboxed, call_var) = unboxed_pair target_name in
         let substituted = subst_call ~unboxed target_name effective_name call_var inner' in
         List.fold_right (fun w acc -> Tir.ESeq (rewrite_expr w, acc)) wrappers substituted
       | None ->
         match find_target_call2 effective_name inner' with
         | Some target_name ->
           let (unboxed, call_var) = unboxed_pair target_name in
           let substituted = subst_call2 ~unboxed target_name effective_name call_var inner' in
           List.fold_right (fun w acc -> Tir.ESeq (rewrite_expr w, acc)) wrappers substituted
         | None -> Tir.ELet (v, alloc_e, rewrite_expr rest))
  (* P10 Phase 2c — a CAPTURING closure (one or more free vars, so the
     EAlloc's arg list is [apply_fn_ptr; fv0; fv1; ...] rather than the
     singleton list above): the closure struct is a real, live value that
     genuinely needs to exist at the call site (the apply body loads its
     free vars from it), so — unlike the non-capturing case — nothing
     upstream is stripped. Only the terminal call itself is rewritten, in
     place, to pass the closure pointer through as a real 3rd argument.
     Same eligibility bar as above (closure used exactly once, precisely as
     the map call's 2nd arg): a closure reused elsewhere, or one whose
     alias chain never reaches a bare map call, is left completely alone,
     same fallback as ever. *)
  | Tir.ELet (v, (Tir.EAlloc (Tir.TCon (_clo_name, []), Tir.AVar apply_var :: (_ :: _)) as alloc_e), rest) ->
    let rest' = rewrite_expr rest in
    let (effective_name, _wrappers, inner) = strip_alias_chain v.Tir.v_name rest' in
    (* Count on [inner] (the tree with the alias-copy let(s) already peeled
       off), NOT on [rest'] directly: count_uses's ELet case treats a
       rebinding of the tracked name as "stop counting — this is a distinct
       shadowed variable now", which is exactly wrong when the "rebinding"
       in question is [effective_name]'s OWN alias-let sitting at the head
       of [rest'] — that would zero out the real use further down before
       ever reaching it. [inner] has already had that alias-let stripped
       (by the same [strip_alias_chain] call above), so no such node
       remains to trip the guard. *)
    let eligible =
      Hashtbl.mem apply_fns apply_var.Tir.v_name
      && count_uses effective_name inner = 1
    in
    if not eligible then Tir.ELet (v, alloc_e, rest')
    else
      (* Same Option B treatment as the non-capturing arm above; the
         closure pointer itself ([clo_var]) is unaffected either way —
         captured free vars are stored/loaded at their own concrete
         type in the closure struct already (never boxed), regardless
         of which apply-fn variant reads them. *)
      let unboxed_pair target_name =
        match try_unboxed_variant apply_fns extra_fns target_name apply_var with
        | Some v -> (true, v)
        | None -> (false, apply_var)
      in
      (match find_target_call_var effective_name rest' with
       | Some (target_name, clo_var) ->
         let (unboxed, call_var) = unboxed_pair target_name in
         Tir.ELet (v, alloc_e, subst_call_capturing ~unboxed target_name effective_name call_var clo_var rest')
       | None ->
         match find_target_call_var2 effective_name rest' with
         | Some (target_name, clo_var) ->
           let (unboxed, call_var) = unboxed_pair target_name in
           Tir.ELet (v, alloc_e, subst_call_capturing2 ~unboxed target_name effective_name call_var clo_var rest')
         | None -> Tir.ELet (v, alloc_e, rest'))
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, rewrite_expr e1, rewrite_expr e2)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun fn -> { fn with Tir.fn_body = rewrite_expr fn.Tir.fn_body }) fns,
                 rewrite_expr body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (br : Tir.branch) -> { br with Tir.br_body = rewrite_expr br.Tir.br_body }) brs,
               Option.map rewrite_expr def)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (rewrite_expr e1, rewrite_expr e2)
  | other -> other

let run (m : Tir.tir_module) : Tir.tir_module =
  let apply_fns = apply_fn_table m in
  let extra_fns = ref [] in
  let new_fns = List.map (fun fn -> { fn with Tir.fn_body = rewrite_expr apply_fns extra_fns fn.Tir.fn_body }) m.Tir.tm_fns in
  { m with Tir.tm_fns = new_fns @ !extra_fns }
