(** The post-Lower TIR pipeline shared by the compiler driver and the LSP.

    Extracted mechanically from bin/main.ml (2026-09-03) and proven
    IR-identical with scripts/ir-oracle.sh.  Driver-only concerns that used
    to be interleaved with the passes (the policy audit, capability
    attribution / --cap-strict, phase snapshots, timings) are hooks so the
    driver keeps its exact behaviour while the LSP can run the SAME pass
    sequence and report the verdict the build will produce.  Order matters
    — see specs/features/compiler-pipeline.md "Pass-order note". *)

type result = {
  pre_opt : Tir.tir_module;
  (** Snapshot taken right after Escape, before [Opt.run]. *)
  final : Tir.tir_module;
  (** After [Native_map_inline]; ready for [Llvm_emit]. *)
  vectorize_diags : March_errors.Errors.diagnostic list;
  contract_diags : March_errors.Errors.diagnostic list;
  (** @[no_alloc] verdicts over [final]. *)
  allocating : (string, Alloc_contract.reason) Hashtbl.t;
  (** The transitive allocating set over [final], by TIR fn name — for the
      LSP lens / quick fix and --report-contracts. *)
  retaining : (string, Alloc_contract.retain) Hashtbl.t;
  (** The @[no_alloc(transient)] counterpart: functions that hand an
      allocation to something outliving the call. *)
  k_table : Kind.table;
  (** The per-type table the passes reasoned against, rebound to [final]'s
      type list — hand it to the emitter (specs/2026-09-10-type-kinds-design.md). *)
}

let island_suffixes = ["render"; "update"; "init"]

(** Escape hatch: [MARCH_NO_UNBOX=1] classifies every type Boxed, restoring the
    pre-Milestone-3 representation for bisection.  Read once per process. *)
let unboxing_env_disabled : bool Lazy.t =
  lazy (match Sys.getenv_opt "MARCH_NO_UNBOX" with
      | Some ("1" | "true" | "yes") -> true
      | _ -> false)

let run ?(snap = fun _ _ -> ()) ?opt_snap ?(stamp = fun _ -> ())
    ?(after_fusion = fun _ -> ()) ?(before_perceus = fun ~k_table:_ _ -> ())
    ?(before_opt = fun _ -> ()) ?(extra_roots = [])
    ?(wasm_island = false) ?(is_js = false) ?(hot_reload = None)
    ?iface_methods ?(decls = []) ~opt ~trmc (tir : Tir.tir_module) : result =
  (* TRMC eligibility analysis (gated on MARCH_TRMC_REPORT).  Must run here:
     by tir-perceus the stdlib's nested `go` helpers are closures invoked via
     ECallPtr, so self-recursion is no longer syntactically visible. *)
  Trmc.report tir;
  (* The same analysis feeds the @[no_alloc] --trmc hint: which annotated
     functions TRMC would transform.  Taken on the pre-transform TIR, by the
     pre-Mono name the contract is keyed on. *)
  let trmc_eligible =
    let contracts = List.filter (fun d -> d.Alloc_contract.d_form <> None) decls in
    if contracts = [] then (fun _ -> false)
    else begin
      let eligible = Hashtbl.create 16 in
      List.iter (fun r ->
          if Trmc.verdict_of r = Trmc.Eligible then
            Hashtbl.replace eligible r.Trmc.r_fn ())
        (Trmc.analyze_module tir);
      fun n -> Hashtbl.mem eligible n
    end
  in
  (* Annotated functions must survive DCE so their own (optimised) bodies
     can be judged even when every caller inlined them. *)
  let extra_roots =
    extra_roots
    @ List.filter_map (fun d ->
        match d.Alloc_contract.d_form with
        | Some (Alloc_contract.Hard | Alloc_contract.Warn
               | Alloc_contract.Transient) -> Some d.Alloc_contract.d_name
        | _ -> None) decls
  in
  let tir = Trmc.transform_module ~enabled:trmc tir in
  (* For WASM island targets, mark render/update/init as exported.
     Set exports BEFORE monomorphization so the functions get mono'd. *)
  let tir =
    if not wasm_island then tir
    else begin
      let exports = List.filter_map (fun (fn : Tir.fn_def) ->
          let n = fn.Tir.fn_name in
          if List.exists (fun suffix ->
              n = suffix ||
              (String.length n > String.length suffix + 1 &&
               String.sub n (String.length n - String.length suffix - 1)
                 (String.length suffix + 1) = ("." ^ suffix))
            ) island_suffixes
          then Some n else None
        ) tir.Tir.tm_fns in
      { tir with Tir.tm_exports = exports }
    end
  in
  let tir = Mono.monomorphize ?iface_methods tir in
  snap "tir-mono" tir;
  stamp "mono";
  (* After mono, update tm_exports to use monomorphized names *)
  let tir =
    if tir.Tir.tm_exports <> [] then begin
      let matches_suffix name suffix =
        let base = match String.index_opt name '$' with
          | Some i -> String.sub name 0 i
          | None -> name
        in
        base = suffix ||
        (String.length base > String.length suffix + 1 &&
         String.sub base (String.length base - String.length suffix - 1)
           (String.length suffix + 1) = ("." ^ suffix))
      in
      let exports = List.filter_map (fun (fn : Tir.fn_def) ->
          let n = fn.Tir.fn_name in
          if List.exists (matches_suffix n) island_suffixes
          then Some n else None
        ) tir.Tir.tm_fns in
      { tir with Tir.tm_exports = exports }
    end else tir
  in
  (* Pin __rpc_stub functions so the DCE pass keeps them (and their callees)
     alive.  Without this, private stubs never called from March code are
     dropped before the CAS hash and LLVM emit steps can see them. *)
  let tir =
    let stub_suffix = "__rpc_stub" in
    let slen = String.length stub_suffix in
    let stubs = List.filter_map (fun (fn : Tir.fn_def) ->
        let n = fn.Tir.fn_name in
        let nl = String.length n in
        if nl > slen && String.sub n (nl - slen) slen = stub_suffix
        then Some n else None
      ) tir.Tir.tm_fns in
    if stubs = [] then tir
    else { tir with Tir.tm_exports = tir.Tir.tm_exports @ stubs }
  in
  let tir = if opt then Fusion.run ~changed:(ref false) tir else tir in
  snap "tir-fusion" tir;
  stamp "fusion";
  after_fusion tir;
  let tir = Defun.defunctionalize tir in
  snap "tir-defun" tir;
  stamp "defun";
  (* The per-type table is decided here — after Mono (which instantiates
     generic variants) and Defun (which adds the closure structs), so the
     decision is made on the type list the remaining passes see, and BEFORE
     the first pass that consults it.  Borrow, Perceus, Drop, Escape and
     Alloc_contract all receive THIS table; [Kind.rebind] at the end of this
     function re-keys the same decision to the final type list for the
     emitter.  The JS backend gets a table with nothing unboxed. *)
  let k0 =
    let collision_set = Collision_set.compute tir.Tir.tm_types in
    Kind.build ~externs:tir.Tir.tm_externs
      ~unboxing:(not is_js && not (Lazy.force unboxing_env_disabled))
      ~collision_set tir.Tir.tm_types
  in
  (* Known-call pass: run before Perceus so apply functions are still pure
     and eligible for inlining in the subsequent Opt fixed-point loop.  See
     the [is_apply_fn] guard in [Perceus]'s EApp post_dec_vars for why the
     closure-apply ABI must not get a caller-side post-call EDecRC. *)
  let tir = if opt then Known_call.run ~changed:(ref false) tir else tir in
  snap "tir-known-call" tir;
  (* Beta-ADT: reduce case-of-known-constructor before Perceus so that the
     EAlloc is DCE'd before RC insertion. *)
  let tir = if opt then Beta_adt.run ~changed:(ref false) tir else tir in
  snap "tir-beta-adt-pre" tir;
  (* P1 Layer 1: alpha-merge let-floating on RC-free TIR.  Must run BEFORE
     Perceus so RC is inserted once for the hoisted binding. *)
  let tir = if opt then Join_points.run_pre ~changed:(ref false) tir else tir in
  snap "tir-join-points-pre" tir;
  (* Pre-Perceus simplify: folds that are only sound before RC insertion. *)
  let tir = if opt then Simplify.run ~pre_perceus:true ~changed:(ref false) tir else tir in
  snap "tir-simplify-pre" tir;
  before_perceus ~k_table:k0 tir;
  (* Computed ONCE here and shared: [Perceus] places its RC ops against this
     answer, and [Escape]'s promotion-through-a-borrowed-callee verdict has to
     be taken against the SAME one — re-deriving it after RC insertion could
     disagree.  See [Escape]'s module doc. *)
  let borrow_map = Borrow.infer_module ~k_table:k0 tir in
  let tir = Perceus.perceus ~k_table:k0 ~borrow_map tir in
  snap "tir-perceus" tir;
  stamp "perceus";
  (* Deep-drop synthesis (lib/tir/drop.ml).  Skipped for the JS target, whose
     runtime is GC'd and ignores RC ops entirely. *)
  let tir = if is_js then tir else Drop.run ~k_table:k0 tir in
  snap "tir-drop" tir;
  stamp "drop";
  let tir = Escape.escape_analysis ~k_table:k0 ~borrow_map tir in
  snap "tir-escape" tir;
  stamp "escape";
  let pre_opt = tir in
  before_opt pre_opt;
  (* Extra DCE roots, given by pre-Mono name: expand to every clone whose
     specialization-stripped name matches, then pin them via tm_exports so
     the DCE inside [Opt.run] cannot prune them.  A rooted function's BODY is
     optimised exactly as it would be otherwise; only reachability differs. *)
  (* A Tagged(_, NoAlloc) function is never CALLED — Tagged is a phantom type
     with no value constructor — so DCE would drop it before the check could
     judge it.  Root it like an annotated one. *)
  let extra_roots =
    extra_roots
    @ List.filter_map (fun (fn : Tir.fn_def) ->
        if Alloc_contract.has_noalloc_policy fn then Some fn.Tir.fn_name else None)
      tir.Tir.tm_fns
  in
  let tir =
    if extra_roots = [] then tir
    else begin
      let wanted = Hashtbl.create 16 in
      List.iter (fun n -> Hashtbl.replace wanted n ()) extra_roots;
      let roots = List.filter_map (fun (fn : Tir.fn_def) ->
          let n = fn.Tir.fn_name in
          if Hashtbl.mem wanted n
             || Hashtbl.mem wanted (Tir_names.strip_specialization_suffix n)
          then Some n else None) tir.Tir.tm_fns in
      if roots = [] then tir
      else { tir with Tir.tm_exports = tir.Tir.tm_exports @ roots }
    end
  in
  (* The driver records Opt's per-pass snapshots through a different observer
     than the top-level stages (phases only, never MARCH_DUMP_TXT); default to
     [snap] for callers that don't care. *)
  let opt_snap = match opt_snap with Some f -> f | None -> snap in
  let tir = if opt then Opt.run ~snap:opt_snap ~hot_reload tir else tir in
  (* Prune functions unreachable from the entry points BEFORE LLVM emit, even
     when the optimizer is disabled: a linkability requirement, not an
     optimization (see the comment at this call's original site). *)
  let tir = Dce.prune_unreachable tir in
  (* @[vectorize]/@[vectorize(warn)]: verify against the SAME pre-rewrite TIR
     shape Native_map_inline.run is about to consume.  [check]'s return value
     MUST be used going forward — it has every Vectorize_mark sentinel
     stripped back out. *)
  let (tir, vectorize_diags) =
    if is_js then (tir, [])
    else
      let ctx = March_errors.Errors.create () in
      let tir' = Vectorize_check.check ctx tir in
      (tir', March_errors.Errors.sorted ctx)
  in
  (* P10 Phase 2: inline non-capturing NativeArray.map closures.  Native/wasm
     only — Js_emit has no codegen arm for the synthetic call. *)
  let tir = if is_js then tir else Native_map_inline.run tir in
  snap "tir-native-map-inline" tir;
  (* When opt is disabled there are no per-pass snaps; still emit one overall. *)
  if not opt then snap "tir-opt" tir;
  stamp "opt";
  (* @[no_alloc]: the last pass before emission, on the exact TIR Llvm_emit
     will consume. *)
  (* Hand the emitter exactly this decision: the same unboxed set the passes
     reasoned against, re-keyed to the final type list ([Kind.rebind]). *)
  let k_table = Kind.rebind k0 tir.Tir.tm_types in
  let allocating = Alloc_contract.allocating_fns ~k_table ~decls tir in
  let retaining = Alloc_contract.retaining_fns ~k_table ~decls tir in
  let contract_diags =
    Alloc_contract.check ~decls ~allocating ~retaining ~opt ~trmc ~trmc_eligible tir in
  { pre_opt; final = tir; vectorize_diags; contract_diags; allocating; retaining; k_table }
