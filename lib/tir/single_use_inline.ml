(** Single-use, impure-body inlining pass.

    Relocates a top-level function's body to its single call site — the
    complement of [Inline], which only handles syntactically *pure*
    candidates. Scope:
    - Impure-only: candidacy is gated on
      [not (Purity.is_pure fn.Tir.fn_body)] below. A syntactically pure
      function stays [Inline]'s responsibility (it can be duplicated freely
      across several call sites, so it doesn't need this pass's
      single-reference restriction). This pass exists because an impure body
      may only ever be relocated, never duplicated: duplicating it would
      duplicate its observable side effects, so it is only sound when there
      is exactly one call site to move it to.
    - Exhaustive reference counting: the eligibility test is "exactly one
      *total* free top-level reference in the whole artifact, and that
      occurrence is an arity-correct direct [EApp]". [scan_atom]/[scan_expr]
      below must visit every atom position in every body with no gaps —
      that's why [ADefRef], closure-stored atoms, [ECallPtr] targets, etc.
      all count via [NonDirect] rather than being skipped. A future new
      [Tir.expr]/[Tir.atom] constructor MUST be added to these scan
      functions too, or a real (uncounted) second reference would make the
      function wrongly look single-use.
    - This pass never deletes a function definition: [run] below rebuilds
      [tm_fns] with every [fn_def] intact and only rewrites [fn_body] at call
      sites, leaving deletion to DCE's independent reachability analysis.
      That is why an under-count in the reference scan above degrades to a
      *code-size* hazard rather than a soundness one: the original
      definition survives, so a missed second caller still reaches a whole,
      correct copy of the body — it just also gets a duplicate relocated
      into the (wrongly-believed) sole call site. Each dynamic call still
      executes exactly one copy of the body; nothing dangles and no
      side effect fires an extra time. This is the main reason the pass is
      forgiving of its own edge cases — but it is not a license to be sloppy
      in the scan, since silent code bloat is still a real defect.
    - Post-Perceus, "impure" is a very wide net. [Purity.is_pure] (used
      unparameterized here, i.e. with no known-impure user functions) treats
      any body containing [EIncRC]/[EDecRC]/[EFree]/[EReuse]/atomic-RC or an
      [ECallPtr] as impure — see `lib/tir/purity.ml`. Because this pass runs
      inside [Opt.run] strictly after Perceus (see below), essentially every
      non-trivial function body already carries RC ops by construction, so
      almost every candidate is "impure" in this sense and falls to this
      pass rather than to [Inline.run] (which requires purity). In practice
      this pass, not [Inline.run], does most of the single-call-site
      inlining once Perceus has run — despite the "impure-only" framing
      above sounding like a narrow carve-out. Keep that in mind when judging
      the blast radius of a change here: it is not a rarely-hit corner case.
    - Perceus must already have run. Ownership operations ([EIncRC],
      [EDecRC], [EFree], [EReuse], the atomic RC variants) are relocated
      verbatim, in their original order, alongside the body they annotate —
      soundness depends on those ops already being explicit in the TIR by
      the time this pass runs. Nothing here asserts that; the ordering is
      enforced only by [Opt.named_passes] running after
      [March_tir.Perceus.perceus] in the driver (see `bin/main.ml`, and the
      pass-order comment atop `lib/tir/opt.ml`). If that invocation order
      is ever changed — e.g. `Opt.run` moved ahead of `Perceus.perceus`, or
      a caller runs `Opt.run` standalone on pre-Perceus TIR — this pass
      would silently relocate a pre-RC body as if it carried real RC ops,
      miscompiling with no error at any stage. There is no cheap way to
      assert this locally (the pass has no reliable, zero-cost signal that
      RC insertion has or hasn't happened yet), so watch this ordering by
      hand when touching the pass list. *)

module SSet = Set.Make (String)

type occurrence =
  | DirectCall of { caller : string; arity : int }
  | NonDirect

type summary = {
  mutable count : int;
  mutable sole : occurrence option;
}

let rewrite_expr ~changed candidates candidate_free_names resolve_name ~bound =
  let try_inline_call ~bound ~args ~call candidate_name =
    match Hashtbl.find_opt candidates candidate_name with
    | None -> call
    | Some fn ->
      let free_names =
        Option.value ~default:SSet.empty
          (Hashtbl.find_opt candidate_free_names candidate_name)
      in
      (* TIR uses names, rather than distinct local/global identifiers,
         for [AVar]. Inserting a callee free name beneath an equal
         caller-local binder would therefore capture it. Renaming only
         the callee's bound variables cannot repair that provenance
         loss, so conservatively retain this one call when scopes
         collide. This keeps the rejection local to the one-use pass
         instead of alpha-renaming unrelated caller bindings. *)
      if not (SSet.is_empty (SSet.inter bound free_names)) then call
      else
        match Inline.expand_call fn args with
        | None -> call
        | Some inlined ->
          changed := true;
          inlined
  in
  let rec rewrite ~bound = function
    | Tir.EApp (callee, args) as call ->
      if SSet.mem callee.Tir.v_name bound then call
      else
        (match resolve_name callee.Tir.v_name with
         | [candidate_name] ->
           try_inline_call ~bound ~args ~call candidate_name
         | [] | _ :: _ :: _ -> call)
    | Tir.ELet (var, rhs, body) ->
      Tir.ELet
        (var, rewrite ~bound rhs,
         rewrite ~bound:(SSet.add var.Tir.v_name bound) body)
    | Tir.ELetRec (fns, body) ->
      let bound =
        List.fold_left
          (fun names fn -> SSet.add fn.Tir.fn_name names)
          bound fns
      in
      Tir.ELetRec
        (List.map
           (fun fn ->
             let fn_bound =
               List.fold_left
                 (fun names param -> SSet.add param.Tir.v_name names)
                 bound fn.Tir.fn_params
             in
             { fn with Tir.fn_body = rewrite ~bound:fn_bound fn.Tir.fn_body })
           fns,
         rewrite ~bound body)
    | Tir.ECase (atom, branches, default) ->
      Tir.ECase
        (atom,
         List.map
           (fun branch ->
             let branch_bound =
               List.fold_left
                 (fun names var -> SSet.add var.Tir.v_name names)
                 bound branch.Tir.br_vars
             in
             { branch with
               Tir.br_body = rewrite ~bound:branch_bound branch.Tir.br_body })
           branches,
         Option.map (rewrite ~bound) default)
    | Tir.ESeq (first, second) ->
      Tir.ESeq (rewrite ~bound first, rewrite ~bound second)
    | other -> other
  in
  rewrite ~bound

let run ~changed (module_ : Tir.tir_module) : Tir.tir_module =
  let top_names =
    SSet.of_list
      (List.map (fun fn -> fn.Tir.fn_name) module_.Tir.tm_fns)
  in
  let extern_names =
    SSet.of_list
      (List.map
         (fun extern_ -> extern_.Tir.ed_march_name)
         module_.Tir.tm_externs)
  in
  let aliases : (string, SSet.t) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun fn ->
      match String.rindex_opt fn.Tir.fn_name '.' with
      | Some dot when not (Tir_names.is_iface_mangled fn.Tir.fn_name) ->
        let bare =
          String.sub fn.Tir.fn_name (dot + 1)
            (String.length fn.Tir.fn_name - dot - 1)
        in
        let targets =
          Option.value ~default:SSet.empty (Hashtbl.find_opt aliases bare)
        in
        Hashtbl.replace aliases bare (SSet.add fn.Tir.fn_name targets)
      | Some _ | None -> ())
    module_.Tir.tm_fns;
  let resolve_name name =
    if SSet.mem name extern_names then []
    else if SSet.mem name top_names then [name]
    else
      match Hashtbl.find_opt aliases name with
      | Some targets -> SSet.elements targets
      | None -> []
  in
  let summaries : (string, summary) Hashtbl.t = Hashtbl.create 16 in
  let successors : (string, SSet.t) Hashtbl.t = Hashtbl.create 16 in
  let free_names : (string, SSet.t) Hashtbl.t = Hashtbl.create 16 in
  SSet.iter
    (fun name ->
      Hashtbl.add summaries name { count = 0; sole = None };
      Hashtbl.add successors name SSet.empty;
      Hashtbl.add free_names name SSet.empty)
    top_names;
  let record name occurrence =
    match Hashtbl.find_opt summaries name with
    | None -> ()
    | Some summary ->
      summary.count <- summary.count + 1;
      summary.sole <-
        if summary.count = 1 then Some occurrence else None
  in
  let record_free caller name =
    Hashtbl.replace free_names caller
      (SSet.add name (Hashtbl.find free_names caller))
  in
  let record_resolved occurrence targets =
    match targets with
    | [] -> ()
    | [target] -> record target occurrence
    | targets -> List.iter (fun target -> record target NonDirect) targets
  in
  let scan_atom ~caller ~bound occurrence = function
    | Tir.AVar var when not (SSet.mem var.Tir.v_name bound) ->
      record_free caller var.Tir.v_name;
      record_resolved occurrence (resolve_name var.Tir.v_name)
    | Tir.ADefRef def
      when SSet.mem def.Tir.did_name top_names ->
      record def.Tir.did_name occurrence
    | Tir.AVar _ | Tir.ADefRef _ | Tir.ALit _ -> ()
  in
  let rec scan_expr ~caller ~bound = function
    | Tir.EAtom atom -> scan_atom ~caller ~bound NonDirect atom
    | Tir.EApp (callee, args) ->
      let callee_is_free = not (SSet.mem callee.Tir.v_name bound) in
      if callee_is_free then begin
        record_free caller callee.Tir.v_name;
        let targets = resolve_name callee.Tir.v_name in
        List.iter
          (fun target ->
            Hashtbl.replace successors caller
              (SSet.add target (Hashtbl.find successors caller)))
          targets;
        record_resolved
          (DirectCall { caller; arity = List.length args })
          targets;
        if Dispatch_registry.is_sentinel callee.Tir.v_name then
          match Dispatch_registry.lookup callee.Tir.v_name with
          | Some rows ->
            List.iter
              (fun (_, target) ->
                record_resolved NonDirect (resolve_name target))
              rows
          | None -> ()
      end;
      List.iter (scan_atom ~caller ~bound NonDirect) args
    | Tir.ECallPtr (callee, args) ->
      scan_atom ~caller ~bound NonDirect callee;
      List.iter (scan_atom ~caller ~bound NonDirect) args
    | Tir.ELet (var, rhs, body) ->
      scan_expr ~caller ~bound rhs;
      scan_expr ~caller ~bound:(SSet.add var.Tir.v_name bound) body
    | Tir.ELetRec (fns, body) ->
      let recursive_bound =
        List.fold_left
          (fun names fn -> SSet.add fn.Tir.fn_name names)
          bound fns
      in
      List.iter
        (fun fn ->
          let fn_bound =
            List.fold_left
              (fun names param -> SSet.add param.Tir.v_name names)
              recursive_bound fn.Tir.fn_params
          in
          scan_expr ~caller ~bound:fn_bound fn.Tir.fn_body)
        fns;
      scan_expr ~caller ~bound:recursive_bound body
    | Tir.ECase (atom, branches, default) ->
      scan_atom ~caller ~bound NonDirect atom;
      List.iter
        (fun branch ->
          let branch_bound =
            List.fold_left
              (fun names var -> SSet.add var.Tir.v_name names)
              bound branch.Tir.br_vars
          in
          scan_expr ~caller ~bound:branch_bound branch.Tir.br_body)
        branches;
      Option.iter (scan_expr ~caller ~bound) default
    | Tir.ETuple atoms
    | Tir.EAlloc (_, atoms)
    | Tir.EStackAlloc (_, atoms) ->
      List.iter (scan_atom ~caller ~bound NonDirect) atoms
    | Tir.ERecord fields ->
      List.iter
        (fun (_, atom) -> scan_atom ~caller ~bound NonDirect atom)
        fields
    | Tir.EField (atom, _) ->
      scan_atom ~caller ~bound NonDirect atom
    | Tir.EUpdate (atom, fields) ->
      scan_atom ~caller ~bound NonDirect atom;
      List.iter
        (fun (_, value) -> scan_atom ~caller ~bound NonDirect value)
        fields
    | Tir.EFree atom
    | Tir.EIncRC atom
    | Tir.EDecRC atom
    | Tir.EAtomicIncRC atom
    | Tir.EAtomicDecRC atom ->
      scan_atom ~caller ~bound NonDirect atom
    | Tir.EReuse (reuse, _, args) ->
      scan_atom ~caller ~bound NonDirect reuse;
      List.iter (scan_atom ~caller ~bound NonDirect) args
    | Tir.ESeq (first, second) ->
      scan_expr ~caller ~bound first;
      scan_expr ~caller ~bound second
  in
  List.iter
    (fun fn ->
      let bound =
        SSet.of_list (List.map (fun param -> param.Tir.v_name) fn.Tir.fn_params)
      in
      scan_expr ~caller:fn.Tir.fn_name ~bound fn.Tir.fn_body)
    module_.Tir.tm_fns;
  let roots = SSet.of_list (Dce.root_names module_) in
  let recursive = Inline.recursive_names_in_graph successors in
  let candidates : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun fn ->
      let summary = Hashtbl.find summaries fn.Tir.fn_name in
      let sole_direct_call =
        match summary.sole with
        | Some (DirectCall { arity; _ }) ->
          arity = List.length fn.Tir.fn_params
        | Some NonDirect | None -> false
      in
      if not (Purity.is_pure fn.Tir.fn_body)
         && Inline.node_count fn.Tir.fn_body <= Inline.inline_size_threshold
         && summary.count = 1
         && sole_direct_call
         && not (SSet.mem fn.Tir.fn_name recursive)
         && not (SSet.mem fn.Tir.fn_name roots)
         && not (Inline.is_reloadable_name fn.Tir.fn_name)
      then Hashtbl.add candidates fn.Tir.fn_name fn)
    module_.Tir.tm_fns;
  { module_ with
    Tir.tm_fns =
      List.map
        (fun fn ->
          let bound =
            SSet.of_list
              (List.map (fun param -> param.Tir.v_name) fn.Tir.fn_params)
          in
          { fn with
            Tir.fn_body =
              rewrite_expr ~changed candidates free_names resolve_name
                ~bound fn.Tir.fn_body })
        module_.Tir.tm_fns }
