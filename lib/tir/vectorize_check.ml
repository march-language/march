(** @[vectorize] / @[vectorize(warn)] — turns the silent eligibility
    heuristics [Native_map_inline] applies for NativeArray.map/map2
    closures into a checked compile-time contract.

    Deliberately reuses [Native_map_inline]'s own matching helpers
    (count_uses, strip_alias_chain, find_target_call*, apply_fn_table,
    is_all_float_signature) rather than re-deriving a second notion of
    "eligible" — the two must never be able to disagree about whether a
    given callback vectorizes. Must run on the TIR *before*
    [Native_map_inline.run] rewrites the very shape this inspects (see
    bin/main.ml's placement, Task 3). *)

(** [Hard] = @[vectorize] (compile error). [Soft] = @[vectorize(warn)]
    (non-fatal warning). Distinct from [March_errors.Errors.severity] so
    the mapping to Error/Warning stays a single explicit step below. *)
type severity = Hard | Soft

let errors_severity : severity -> March_errors.Errors.severity = function
  | Hard -> March_errors.Errors.Error
  | Soft -> March_errors.Errors.Warning

(** Attribute string (as stored in [Ast.fn_def.fn_attrs]) -> [severity],
    or [None] if this function isn't annotated with either variant. *)
let attr_severity (attrs : string list) : severity option =
  if List.mem "vectorize" attrs then Some Hard
  else if List.mem "vectorize:warn" attrs then Some Soft
  else None

(* ── Messages ─────────────────────────────────────────────────────────── *)

let display_name = function
  | "native_int_arr_map"    -> "map_int"
  | "native_float_arr_map"  -> "map_float"
  | "native_int_arr_map2"   -> "map2_int"
  | "native_float_arr_map2" -> "map2_float"
  | other -> other

let is_map2_target name =
  name = "native_int_arr_map2" || name = "native_float_arr_map2"

let is_float_target name =
  name = "native_float_arr_map" || name = "native_float_arr_map2"

let reuse_example target =
  let d = display_name target in
  if is_map2_target target then
    Printf.sprintf "NativeArray.%s(a, b, fn (x, y) -> x +. y)" d
  else
    Printf.sprintf "NativeArray.%s(arr, fn x -> x *. 2.0)" d

let reuse_diag ~span ~severity ~fn_name ~target : March_errors.Errors.diagnostic =
  let d = display_name target in
  { March_errors.Errors.severity = errors_severity severity; span;
    message = Printf.sprintf
        "`%s` cannot vectorize \xe2\x80\x94 this callback isn't safe to inline\n\n\
         I can only turn NativeArray.%s into a real SIMD loop when its\n\
         callback is used exactly once, passed straight in as the call's\n\
         argument. That's what lets me inline it in place of the\n\
         closure-pointer call.\n\n\
         Here, the callback passed to `%s` is used more than once (or\n\
         stored and called separately elsewhere), so I can't safely\n\
         inline it \xe2\x80\x94 falling back would silently produce a scalar\n\
         loop, not the fast path you asked for."
        fn_name d d;
    labels = []; code = None; fix = None;
    notes = [ Printf.sprintf
        "Hint: pass a fresh, single-use lambda directly to the call:\n    %s"
        (reuse_example target) ] }

let generic_diag ~span ~severity ~fn_name ~target : March_errors.Errors.diagnostic =
  let d = display_name target in
  { March_errors.Errors.severity = errors_severity severity; span;
    message = Printf.sprintf
        "`%s` cannot vectorize \xe2\x80\x94 callback type is still generic\n\n\
         NativeArray needs a concrete Float signature to drop the\n\
         per-element box/unbox and hand the loop to LLVM's vectorizer\n\
         as-is."
        fn_name;
    labels = []; code = None; fix = None;
    notes = [ Printf.sprintf
        "Hint: give the callback passed to `%s` a concrete Float\n\
         signature, e.g. `fn (x: Float) -> x *. 2.0`, instead of leaving\n\
         it generic. (see docs/simd-vectorization.md \"%s\")"
        d d ] }

let misuse_diag ~span ~fn_name : March_errors.Errors.diagnostic =
  { March_errors.Errors.severity = March_errors.Errors.Error; span;
    message = Printf.sprintf
        "`%s` is marked @[vectorize] but calls no NativeArray.map/map2 \
         function"
        fn_name;
    labels = []; code = None; fix = None;
    notes = [ "Hint: remove the attribute, or check the NativeArray call \
               you meant to guard is actually present in this function's \
               body." ] }

(* ── Gate evaluation ──────────────────────────────────────────────────── *)

type gate_failure = ReuseFail of string | GenericFail of string

(** One call site's verdict, given the closure's use-count within the
    subtree the map/map2 call was found in. Mirrors
    [Native_map_inline]'s two gates exactly (see module doc above): reuse
    first (applies to Int and Float), then — Float targets only —
    the concrete-signature gate. *)
let eval_site
    (apply_fns : (string, Tir.fn_def) Hashtbl.t)
    (apply_var : Tir.var) (target_name : string) ~(use_count : int)
  : gate_failure option =
  let reuse_ok = Hashtbl.mem apply_fns apply_var.Tir.v_name && use_count = 1 in
  if not reuse_ok then Some (ReuseFail target_name)
  else if is_float_target target_name
       && not (Native_map_inline.is_all_float_signature
                 (Hashtbl.find apply_fns apply_var.Tir.v_name))
  then Some (GenericFail target_name)
  else None

(** Walk [e] collecting (a) every gate failure found and (b) how many
    NativeArray.map/map2 call sites were found at all (used to detect the
    "@[vectorize] on a fn with nothing to check" misuse case). Purely a
    read: unlike [Native_map_inline.rewrite_expr], nothing here is
    rewritten. Structurally mirrors that function's two ELet-alloc arms
    (non-capturing / capturing) plus its generic recursion cases. *)
let rec collect_call_sites
    (apply_fns : (string, Tir.fn_def) Hashtbl.t) (e : Tir.expr)
  : gate_failure list * int =
  let combine (f1, n1) (f2, n2) = (f1 @ f2, n1 + n2) in
  match e with
  | Tir.ELet (v, Tir.EAlloc (Tir.TCon (_, []), [ Tir.AVar apply_var ]), rest) ->
    let (effective_name, _wrappers, inner) =
      Native_map_inline.strip_alias_chain v.Tir.v_name rest in
    let sub = collect_call_sites apply_fns inner in
    let target =
      match Native_map_inline.find_target_call effective_name inner with
      | Some t -> Some t
      | None -> Native_map_inline.find_target_call2 effective_name inner
    in
    (match target with
     | None -> sub
     | Some target_name ->
       let use_count = Native_map_inline.count_uses effective_name inner in
       let fail = eval_site apply_fns apply_var target_name ~use_count in
       let (sub_fails, sub_found) = sub in
       ((match fail with Some f -> f :: sub_fails | None -> sub_fails),
        sub_found + 1))
  | Tir.ELet (v, Tir.EAlloc (Tir.TCon (_, []), Tir.AVar apply_var :: (_ :: _)), rest) ->
    let (effective_name, _wrappers, inner) =
      Native_map_inline.strip_alias_chain v.Tir.v_name rest in
    let sub = collect_call_sites apply_fns rest in
    let target =
      match Native_map_inline.find_target_call_var effective_name rest with
      | Some (t, _clo_var) -> Some t
      | None ->
        (match Native_map_inline.find_target_call_var2 effective_name rest with
         | Some (t, _clo_var) -> Some t
         | None -> None)
    in
    (match target with
     | None -> sub
     | Some target_name ->
       let use_count = Native_map_inline.count_uses effective_name inner in
       let fail = eval_site apply_fns apply_var target_name ~use_count in
       let (sub_fails, sub_found) = sub in
       ((match fail with Some f -> f :: sub_fails | None -> sub_fails),
        sub_found + 1))
  | Tir.ELet (_, e1, e2) ->
    combine (collect_call_sites apply_fns e1) (collect_call_sites apply_fns e2)
  | Tir.ELetRec (fns, body) ->
    List.fold_left (fun acc fn -> combine acc (collect_call_sites apply_fns fn.Tir.fn_body))
      (collect_call_sites apply_fns body) fns
  | Tir.ECase (_, brs, def) ->
    let branches = List.fold_left (fun acc (br : Tir.branch) ->
        combine acc (collect_call_sites apply_fns br.Tir.br_body)) ([], 0) brs in
    (match def with
     | Some e -> combine branches (collect_call_sites apply_fns e)
     | None -> branches)
  | Tir.ESeq (e1, e2) ->
    combine (collect_call_sites apply_fns e1) (collect_call_sites apply_fns e2)
  | _ -> ([], 0)

(** Check one already-matched annotated function (its attribute has
    already been resolved to [severity] and [span] by the caller).
    Exposed directly (not just via [check]) so tests can hand-build a
    minimal [Tir.fn_def] + apply-fn table instead of round-tripping
    through source + full monomorphization to hit a specific gate. *)
let check_fn
    (ctx : March_errors.Errors.ctx)
    (apply_fns : (string, Tir.fn_def) Hashtbl.t)
    ~(severity : severity) ~(span : March_ast.Ast.span) (fd : Tir.fn_def)
  : unit =
  let (failures, found) = collect_call_sites apply_fns fd.Tir.fn_body in
  if found = 0 then March_errors.Errors.report ctx (misuse_diag ~span ~fn_name:fd.Tir.fn_name)
  else
    List.iter (fun failure ->
        let diag = match failure with
          | ReuseFail target -> reuse_diag ~span ~severity ~fn_name:fd.Tir.fn_name ~target
          | GenericFail target -> generic_diag ~span ~severity ~fn_name:fd.Tir.fn_name ~target
        in
        March_errors.Errors.report ctx diag)
      failures

(* ── AST attribute collection + TIR dispatch ─────────────────────────── *)

(** Every top-level [DFn] anywhere in [decls] (recursing into nested
    [DMod]s, since sibling/stdlib modules appear that way in the AST the
    compile pipeline hands to [Lower.lower_module]) whose [fn_attrs]
    names a @[vectorize] variant, keyed by its *source* name. *)
let rec collect_attrs (decls : March_ast.Ast.decl list)
  : (string * (severity * March_ast.Ast.span)) list =
  List.concat_map (function
      | March_ast.Ast.DFn (def, span) ->
        (match attr_severity def.March_ast.Ast.fn_attrs with
         | Some sev -> [ (def.March_ast.Ast.fn_name.March_ast.Ast.txt, (sev, span)) ]
         | None -> [])
      | March_ast.Ast.DMod (_, _, inner, _) -> collect_attrs inner
      | _ -> [])
    decls

(** Monomorphization suffixes a name with "$..." (e.g. "scale$Float") but
    always keeps the original source name as the prefix before the first
    "$" (see e.g. bin/main.ml's WASM-island-export matching, which relies
    on the same convention). A generic annotated fn may be monomorphized
    into several concrete instantiations; each is checked independently
    below — intentional, not a limitation: a generic wrapper can
    vectorize for one call site's type and fail to for another's. *)
let base_name (name : string) : string =
  match String.index_opt name '$' with
  | Some i -> String.sub name 0 i
  | None -> name

(** Entry point. Walks [ast] for @[vectorize]/@[vectorize(warn)]
    functions and checks every TIR instantiation ([m.tm_fns]) whose base
    name matches. A no-op (does not even build the apply-fn table) when
    nothing in [ast] carries the attribute. *)
let check (ctx : March_errors.Errors.ctx) (ast : March_ast.Ast.module_) (m : Tir.tir_module) : unit =
  let attrs = collect_attrs ast.March_ast.Ast.mod_decls in
  if attrs <> [] then begin
    let apply_fns = Native_map_inline.apply_fn_table m in
    List.iter (fun (fd : Tir.fn_def) ->
        match List.assoc_opt (base_name fd.Tir.fn_name) attrs with
        | Some (severity, span) -> check_fn ctx apply_fns ~severity ~span fd
        | None -> ())
      m.Tir.tm_fns
  end
