(** Dead code elimination pass.
    - Removes pure unused let bindings (converts impure ones to ESeq)
    - Removes top-level functions not reachable from main (with no entry point,
      seeds the entry module's own functions — see [root_names])
    Precondition: must run after Defun. ECallPtr post-Defun dispatches through
    apply-functions that are themselves reachable via EApp; running before Defun
    could eliminate lambda-lifted functions that ECallPtr would have reached. *)

module StringSet = Set.Make (String)

(** Collect all variable names free in an expression. *)
let rec free_vars : Tir.expr -> StringSet.t = function
  | Tir.EAtom (Tir.AVar v)     -> StringSet.singleton v.Tir.v_name
  | Tir.EAtom (Tir.ADefRef _) -> StringSet.empty  (* global ref — not a local binding *)
  | Tir.EAtom (Tir.ALit _)    -> StringSet.empty
  | Tir.EApp (f, args)      ->
    List.fold_left (fun s a -> StringSet.union s (free_atom a))
      (StringSet.singleton f.Tir.v_name) args
  | Tir.ECallPtr (f, args)  ->
    List.fold_left (fun s a -> StringSet.union s (free_atom a))
      (free_atom f) args
  | Tir.ELet (v, rhs, body) ->
    StringSet.union (free_vars rhs) (StringSet.remove v.Tir.v_name (free_vars body))
  | Tir.ELetRec (fns, body) ->
    let names = StringSet.of_list (List.map (fun fd -> fd.Tir.fn_name) fns) in
    let fn_free = List.fold_left (fun s fd ->
        StringSet.union s (StringSet.diff (free_vars fd.Tir.fn_body) names)
      ) StringSet.empty fns in
    StringSet.union fn_free (StringSet.diff (free_vars body) names)
  | Tir.ECase (a, branches, default) ->
    let bf = List.fold_left (fun s b ->
        let bound = StringSet.of_list (List.map (fun v -> v.Tir.v_name) b.Tir.br_vars) in
        StringSet.union s (StringSet.diff (free_vars b.Tir.br_body) bound)
      ) (free_atom a) branches in
    Option.fold ~none:bf ~some:(fun d -> StringSet.union bf (free_vars d)) default
  | Tir.ETuple atoms | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) ->
    List.fold_left (fun s a -> StringSet.union s (free_atom a)) StringSet.empty atoms
  | Tir.ERecord fields ->
    List.fold_left (fun s (_, a) -> StringSet.union s (free_atom a)) StringSet.empty fields
  | Tir.EField (a, _)        -> free_atom a
  | Tir.EUpdate (a, fields)  ->
    List.fold_left (fun s (_, v) -> StringSet.union s (free_atom v)) (free_atom a) fields
  | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a
  | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a -> free_atom a
  | Tir.EReuse (a, _, args)  ->
    List.fold_left (fun s v -> StringSet.union s (free_atom v)) (free_atom a) args
  | Tir.EAllocHole (_, args, _) ->
    List.fold_left (fun s v -> StringSet.union s (free_atom v)) StringSet.empty args
  | Tir.ESetField (o, _, v)  -> StringSet.union (free_atom o) (free_atom v)
  | Tir.ESeq (e1, e2)        -> StringSet.union (free_vars e1) (free_vars e2)

and free_atom : Tir.atom -> StringSet.t = function
  | Tir.AVar v    -> StringSet.singleton v.Tir.v_name
  | Tir.ADefRef _ -> StringSet.empty  (* global ref — not a local binding *)
  | Tir.ALit _    -> StringSet.empty

(** Collect all function names called from an expression.
    ECallPtr (indirect closure dispatch) is not tracked — post-Defun its targets
    are apply-functions already reachable via EApp from the closure constructor. *)
let rec called_fns : Tir.expr -> StringSet.t = function
  | Tir.EApp (f, _)         -> StringSet.singleton f.Tir.v_name
  | Tir.ELet (_, rhs, body) -> StringSet.union (called_fns rhs) (called_fns body)
  | Tir.ELetRec (fns, body) ->
    List.fold_left (fun s fd -> StringSet.union s (called_fns fd.Tir.fn_body))
      (called_fns body) fns
  | Tir.ECase (_, branches, default) ->
    let bf = List.fold_left (fun s b -> StringSet.union s (called_fns b.Tir.br_body))
               StringSet.empty branches in
    Option.fold ~none:bf ~some:(fun d -> StringSet.union bf (called_fns d)) default
  | Tir.ESeq (e1, e2)       -> StringSet.union (called_fns e1) (called_fns e2)
  | _                        -> StringSet.empty

(** Operational entry/root names preserved by top-level DCE. *)
let root_names ?(extra_root = fun _ -> false) ?(fail_open = true)
    (m : Tir.tir_module) : string list =
  let roots = ref StringSet.empty in
  let add name = roots := StringSet.add name !roots in
  let is_main_name name =
    name = "main"
    || let suffix = ".main" in
       let name_len = String.length name
       and suffix_len = String.length suffix in
       name_len >= suffix_len
       && String.sub name (name_len - suffix_len) suffix_len = suffix
  in
  List.iter
    (fun (fn : Tir.fn_def) ->
      if is_main_name fn.Tir.fn_name then add fn.Tir.fn_name;
      if fn.Tir.fn_name = Tir_names.setup_fn_name
         || fn.Tir.fn_name = Tir_names.setup_all_fn_name
         || Tir_names.is_migrate_fn_name fn.Tir.fn_name
      then add fn.Tir.fn_name)
    m.Tir.tm_fns;
  List.iter add m.Tir.tm_exports;
  List.iter (fun (name, _) -> add name) m.Tir.tm_tests;
  (* Caller-supplied roots, used ONLY when the module has no entry point of
     its own — see [prune_unreachable].  Applying them unconditionally is
     wrong: with a `main` present, reachability from `main` is exactly the
     right notion, and rooting the file's other functions resurrects code the
     program never runs.  Measured: doing so turned three previously clean
     programs into ceiling violations, all of them naming a stdlib module
     reached only from a user function that `main` never calls. *)
  if StringSet.is_empty !roots then
    List.iter
      (fun (fn : Tir.fn_def) ->
         if extra_root fn.Tir.fn_name then add fn.Tir.fn_name)
      m.Tir.tm_fns;
  (* Still nothing.  For CODEGEN, fail open and keep every function: emptying
     a library would be absurd.  For an ANALYSIS, [fail_open:false] says the
     opposite — a module with no entry point, no exports, no tests and no
     declarations of its own has no reachable code, so the honest answer is
     that it reaches nothing.  Failing open there does not make the analysis
     more conservative, it makes it wrong: the ceiling reported the whole
     prepended stdlib for a file containing a single `assert true`. *)
  if StringSet.is_empty !roots && fail_open then
    List.iter (fun (fn : Tir.fn_def) -> add fn.Tir.fn_name) m.Tir.tm_fns;
  StringSet.elements !roots

(** Transitive reachability from entry points.
    Uses [free_vars] (not [called_fns]) so that closure apply-function
    pointers stored in EAlloc args are also treated as references. *)
let reachable_fns ?(extra_root = fun _ -> false) ?(fail_open = true)
    (m : Tir.tir_module) : StringSet.t =
  let fn_map : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun fd -> Hashtbl.add fn_map fd.Tir.fn_name fd) m.Tir.tm_fns;
  let fn_names = StringSet.of_list (List.map (fun fd -> fd.Tir.fn_name) m.Tir.tm_fns) in
  let visited = ref StringSet.empty in
  let queue = Queue.create () in
  List.iter (fun name -> Queue.push name queue) (root_names ~extra_root ~fail_open m);
  while not (Queue.is_empty queue) do
    let name = Queue.pop queue in
    if not (StringSet.mem name !visited) then begin
      visited := StringSet.add name !visited;
      match Hashtbl.find_opt fn_map name with
      | None -> ()
      | Some fd ->
        (* Intersect all free variable names with known top-level function
           names — this covers both direct EApp calls and closure fn-ptr
           references stored in EAlloc args. *)
        let body_refs = free_vars fd.Tir.fn_body in
        let refs = StringSet.inter body_refs fn_names in
        StringSet.iter (fun callee -> Queue.push callee queue) refs;
        (* Collision-dispatch sentinels ([Mono] → [Llvm_dispatch]) are not TIR
           functions, so the intersection above drops them — but the
           module-qualified impl symbols they route to at LLVM time ARE real
           fn_defs that would otherwise look unreachable (nothing in the TIR
           call graph names them). Follow the [Dispatch_registry] rows so those
           impl bodies survive to link. Empty for any non-colliding program. *)
        StringSet.iter (fun name ->
          if Dispatch_registry.is_sentinel name then
            match Dispatch_registry.lookup name with
            | Some rows -> List.iter (fun (_, sym) -> Queue.push sym queue) rows
            | None -> ())
          body_refs
    end
  done;
  !visited

let rec dce_expr ~impure_fns ~changed : Tir.expr -> Tir.expr = function
  | Tir.ELet (v, rhs, body) ->
    let rhs'  = dce_expr ~impure_fns ~changed rhs in
    let body' = dce_expr ~impure_fns ~changed body in
    let used  = StringSet.mem v.Tir.v_name (free_vars body') in
    if used then Tir.ELet (v, rhs', body')
    else if Purity.is_pure_ext impure_fns rhs' then begin
      changed := true; body'
    end else begin
      changed := true; Tir.ESeq (rhs', body')
    end
  | Tir.ECase (a, branches, default) ->
    Tir.ECase (a,
      List.map (fun b -> { b with Tir.br_body = dce_expr ~impure_fns ~changed b.Tir.br_body }) branches,
      Option.map (dce_expr ~impure_fns ~changed) default)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun fd -> { fd with Tir.fn_body = dce_expr ~impure_fns ~changed fd.Tir.fn_body }) fns,
                 dce_expr ~impure_fns ~changed body)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (dce_expr ~impure_fns ~changed e1, dce_expr ~impure_fns ~changed e2)
  | other -> other

(** Remove top-level functions unreachable from the entry points (main /
    tm_exports / tm_tests / setup / migrate stubs).  This is a LINKABILITY
    requirement, not an optimization: the injected prelude/http stack references
    externs (e.g. [_http_fetch]) that are not always linked, so an unreachable
    function that mentions one produces "undefined symbols" at link time.  It
    must therefore run before LLVM emit EVEN when the optimizer is disabled
    (--no-opt).  Idempotent: filtering an already-pruned module is a no-op, so
    it is safe to call both here and (transitively via [run]) inside [Opt.run]. *)
(* [extra_root] names additional roots, and exists for ANALYSIS consumers that
   read the pruned module to decide what a program uses.

   When a module has no `main`, no setup/migrate, no exports and no tests, it
   has no roots, and [root_names] fails OPEN — every function is a root, so
   nothing is pruned. For codegen that is the only safe answer. For an
   analysis it is silently wrong, and [Cap_attrib] paid for it: a main-less
   file using no capability at all drew SEVENTEEN `--cap-strict` ceiling
   violations, one per stdlib module holding an unreachable capability use
   (`Check` uses IO.Clock, `Socket` uses IO.NetConnect, `Process` uses
   IO.Process, …). Attribution found no non-transparent caller for any of
   them — correctly, since nothing called them — and fell back to naming the
   stdlib module. Measured 2026-08-07: of 110 programs failing --cap-strict in
   a 312-program sweep, 86 had no `main`.

   The honest root set for such a module is its own declared functions: its
   API surface is what a caller can reach. That set cannot be recovered from
   TIR names — [Lower] strips the entry file-module's prefix from its own
   declarations, and the PRELUDE's functions (`println`, `panic`, `debug`, …)
   are unprefixed too, so "no dot in the name" selects both. Verified: rooting
   every unprefixed function still charged the entry module IO.Console,
   IO.FileWrite and IO.NetConnect for a file whose only declaration was
   `fn helper(x) = x + 1`.

   So the caller supplies the predicate. bin/main.ml builds it from the
   DESUGARED AST, where a declaration's span still says which file it came
   from — the same stdlib-span filter [own_caps_of_this_module] uses. *)
let prune_unreachable ?(extra_root = fun _ -> false) ?(fail_open = true)
    (m : Tir.tir_module) : Tir.tir_module =
  let reachable = reachable_fns ~extra_root ~fail_open m in
  let fns = List.filter
      (fun fd -> StringSet.mem fd.Tir.fn_name reachable) m.Tir.tm_fns in
  { m with Tir.tm_fns = fns }

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  (* Step 1: remove dead let bindings within function bodies.
     Compute the transitive set of impure top-level functions first so we never
     drop a binding whose RHS calls (directly or indirectly) an impure builtin
     — e.g. [let _ = System.put_env(k, v)], which performs a [setenv]. *)
  let impure_fns = Purity.impure_fns_of_module m in
  let fns' = List.map (fun fd ->
    { fd with Tir.fn_body = dce_expr ~impure_fns ~changed fd.Tir.fn_body }
  ) m.Tir.tm_fns in
  (* Step 2: remove unreachable top-level functions *)
  let m1 = { m with Tir.tm_fns = fns' } in
  let m2 = prune_unreachable m1 in
  if List.compare_lengths m2.Tir.tm_fns m1.Tir.tm_fns < 0 then changed := true;
  m2
