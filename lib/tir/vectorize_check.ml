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

(* ── Marker scanning (post-mark, pre-strip) ──────────────────────────── *)

(** Revision note: an earlier version of this module matched @[vectorize]
    functions to TIR [fn_def]s by name — walking [Ast.decl]s for the
    attribute, then looking up each TIR fn whose name (stripped of any
    "$..." monomorphization suffix) matched. Review found that unsound in
    two confirmed ways: (1) the "$"-strip collided with Defun's own
    "<fn>$apply$<uid>" lifted-lambda naming, so an unrelated stdlib lambda
    sharing a user fn's name could spuriously fail the check; (2) the
    check ran post-Opt/inlining, so a small annotated wrapper that the
    optimizer inlined into its caller no longer existed as a distinct
    [Tir.fn_def] by the time the check ran — the exact "reuse gate"
    violation this feature exists to catch was silently missed. Both are
    now structurally impossible: [Vectorize_mark.mark] does the
    name-matching immediately after [Lower.lower_module] (the one point
    where TIR names are still exactly source names), and stamps a
    sentinel *call* into the matched fn's body instead of relying on the
    fn's own identity surviving to this point. Mono's duplication and
    Opt's inlining both preserve body contents, so the sentinel — and
    with it, the (source name, severity, span) triple — rides along into
    wherever the body ends up, and this module scans for sentinels
    instead of matching by name. *)

let marker_severity : string -> severity option = function
  | "__vectorize_marker_hard" -> Some Hard
  | "__vectorize_marker_soft" -> Some Soft
  | _ -> None

let marker_shape (f : Tir.var) (args : Tir.atom list) : (string * severity * March_ast.Ast.span) option =
  match marker_severity f.Tir.v_name, args with
  | Some sev,
    [ Tir.ALit (March_ast.Ast.LitString file);
      Tir.ALit (March_ast.Ast.LitInt start_line);
      Tir.ALit (March_ast.Ast.LitInt start_col);
      Tir.ALit (March_ast.Ast.LitInt end_line);
      Tir.ALit (March_ast.Ast.LitInt end_col);
      Tir.ALit (March_ast.Ast.LitString name) ] ->
    Some (name, sev, { March_ast.Ast.file; start_line; start_col; end_line; end_col })
  | _ -> None

(** Every sentinel call anywhere in [e], as (source_name, severity, span).
    Does not stop at the first one — see [combine_markers]'s doc comment
    on the rare case where more than one turns up in the same body. *)
let rec find_markers (e : Tir.expr) : (string * severity * March_ast.Ast.span) list =
  let go = find_markers in
  match e with
  | Tir.EApp (f, args) ->
    (match marker_shape f args with Some m -> [ m ] | None -> [])
  | Tir.ELet (_, e1, e2) -> go e1 @ go e2
  | Tir.ELetRec (fns, body) ->
    List.concat_map (fun fn -> go fn.Tir.fn_body) fns @ go body
  | Tir.ECase (_, brs, def) ->
    List.concat_map (fun (br : Tir.branch) -> go br.Tir.br_body) brs
    @ (match def with Some e -> go e | None -> [])
  | Tir.ESeq (e1, e2) -> go e1 @ go e2
  | _ -> []

(** Strip every sentinel call out of [e] once its payload has been read —
    sentinels are compiler-internal and must never reach LLVM emission
    (there is no @__vectorize_marker_* symbol to link against). [mark]
    only ever installs one as an [ESeq] head directly in a fn's body, but
    every sentinel found is defensively replaced wherever it sits (not
    just that shape), so nothing downstream chokes even if some future
    pass moved it somewhere unexpected. *)
let rec strip_markers (e : Tir.expr) : Tir.expr =
  let go = strip_markers in
  match e with
  | Tir.EApp (f, args) when marker_shape f args <> None ->
    Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt 0))
  | Tir.ESeq (Tir.EApp (f, args), rest) when marker_shape f args <> None -> go rest
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, go e1, go e2)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun fn -> { fn with Tir.fn_body = go fn.Tir.fn_body }) fns, go body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (br : Tir.branch) -> { br with Tir.br_body = go br.Tir.br_body }) brs,
               Option.map go def)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
  | other -> other

(** Combine multiple sentinels found in the same function body into one
    effective (name, severity, span) to report against: severity is Hard
    if ANY sentinel present is Hard (never silently downgrade); name is
    every sentinel's source name, comma-joined; span is the first
    sentinel's (arbitrary but deterministic — precise attribution isn't
    possible once bodies have merged). The overwhelmingly common case is
    exactly one sentinel (the fn was never inlined, or exactly one
    annotated fn got inlined into this body) and this is a no-op
    passthrough; more than one only arises when two SEPARATELY annotated
    functions both got inlined into the very same caller, which cannot be
    cleanly attributed call-by-call — a documented limitation, not a
    silent misattribution (it still fires, just against a joined name). *)
let combine_markers (markers : (string * severity * March_ast.Ast.span) list)
  : string * severity * March_ast.Ast.span =
  let name = String.concat "`, `" (List.map (fun (n, _, _) -> n) markers) in
  let severity = if List.exists (fun (_, s, _) -> s = Hard) markers then Hard else Soft in
  let (_, _, span) = List.hd markers in
  (name, severity, span)

(** Entry point. Walks every function body for sentinel calls [mark]
    installed earlier in the pipeline, runs [check_fn] against whichever
    body a sentinel ended up in, and returns the TIR with every sentinel
    stripped back out. A function with no sentinels is untouched and
    never walked for eligibility at all. *)
let check (ctx : March_errors.Errors.ctx) (m : Tir.tir_module) : Tir.tir_module =
  let apply_fns = Native_map_inline.apply_fn_table m in
  let new_fns = List.map (fun (fd : Tir.fn_def) ->
      match find_markers fd.Tir.fn_body with
      | [] -> fd
      | markers ->
        let (name, severity, span) = combine_markers markers in
        check_fn ctx apply_fns ~severity ~span { fd with Tir.fn_name = name };
        { fd with Tir.fn_body = strip_markers fd.Tir.fn_body })
    m.Tir.tm_fns
  in
  { m with Tir.tm_fns = new_fns }
