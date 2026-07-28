module SSet = Set.Make (String)

type occurrence =
  | DirectCall of { caller : string; arity : int }
  | NonDirect

type summary = {
  mutable count : int;
  mutable sole : occurrence option;
}

let recursive_names successors =
  let indices : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let lowlinks : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let index = ref 0 in
  let stack = ref [] in
  let on_stack = ref SSet.empty in
  let recursive = ref SSet.empty in
  let rec strongconnect name =
    Hashtbl.add indices name !index;
    Hashtbl.add lowlinks name !index;
    incr index;
    stack := name :: !stack;
    on_stack := SSet.add name !on_stack;
    SSet.iter
      (fun successor ->
        if not (Hashtbl.mem indices successor) then begin
          strongconnect successor;
          Hashtbl.replace lowlinks name
            (min (Hashtbl.find lowlinks name)
               (Hashtbl.find lowlinks successor))
        end else if SSet.mem successor !on_stack then
          Hashtbl.replace lowlinks name
            (min (Hashtbl.find lowlinks name)
               (Hashtbl.find indices successor)))
      (Hashtbl.find successors name);
    if Hashtbl.find lowlinks name = Hashtbl.find indices name then begin
      let rec pop_component component =
        match !stack with
        | member :: rest ->
          stack := rest;
          on_stack := SSet.remove member !on_stack;
          let component = SSet.add member component in
          if String.equal member name then component
          else pop_component component
        | [] -> assert false
      in
      let component = pop_component SSet.empty in
      if SSet.cardinal component > 1
         || SSet.mem name (Hashtbl.find successors name) then
        recursive := SSet.union component !recursive
    end
  in
  Hashtbl.iter
    (fun name _ ->
      if not (Hashtbl.mem indices name) then strongconnect name)
    successors;
  !recursive

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
  let recursive = recursive_names successors in
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
