(** Portable closures at parallel boundaries.

    Design: specs/2026-10-07-portable-closures-design.md.

    A closure handed to a many-call parallel combinator ([List.pmap],
    [Parallel.preduce], [Task.async_stream], ...) runs on several tasks at
    once.  For ordinary March data that is already safe: values are
    immutable, [NativeArray.set] copies when the array is shared, Vault tables
    are behind reader/writer locks, reference counts are atomic, and a linear
    or affine value cannot be captured by any closure at all (the typechecker
    rejects it).  What is left is a native [resource] handle: it is
    reference-counted rather than linear, so a closure can capture it, and the
    C library behind it may not tolerate two threads calling into the same
    handle.  This pass rejects exactly that.

    It runs on TIR right after Defun, before [Hof_spec] clones higher-order
    functions per lambda: at that point every closure is an explicit
    [EAlloc] of a [$Clo_] struct whose argument atoms are its captures, each
    carrying its monomorphic type, so a generic function instantiated with a
    resource is caught too.

    Scope, chosen deliberately:
    - Only the MANY-CALL combinators.  [task_spawn] / [Task.async] run their
      closure once, and a task owning a handle it was given is a normal
      pattern; checking them would leave no way to hand a task a handle.
    - I/O inside the closure is allowed.  The parallelism docs recommend
      [List.pmap_n(urls, fn u -> http_get(u), 8)].
    - Compiled programs, [--check] and the LSP.  The interpreter runs tasks
      eagerly on one thread, so the hazard does not exist there.
    Known gaps: a closure that reaches a parallel position through a data
    structure (stored in a record, read back, then passed), returned from a
    call, or chosen by an [if]/[match] is not traced. *)

module SMap = Map.Make (String)
module SSet = Set.Make (String)

let base = Tir_names.strip_specialization_suffix

(** Combinator base name -> parameter positions whose closure runs on several
    tasks at once. *)
let seeds : (string * int list) list = [
  ("List.pmap", [ 1 ]);
  ("List.pmap_n", [ 1 ]);
  ("List.pfilter", [ 1 ]);
  ("List.preduce", [ 2 ]);
  ("Parallel.pmap", [ 1 ]);
  ("Parallel.pmap_n", [ 1 ]);
  ("Parallel.preduce", [ 2; 3 ]);
  ("Parallel.preduce_n", [ 2; 3 ]);
  ("Parallel.pcount", [ 1 ]);
  ("Parallel.pany", [ 1 ]);
  ("Parallel.pall", [ 1 ]);
  ("Task.async_stream", [ 1 ]);
  ("Task.async_stream_n", [ 1 ]);
]

(** Names of the user-facing combinator a parallel position ultimately reaches,
    for the diagnostic ("[wrapper], which passes it to [List.pmap]"). *)
type position = { via : string option; combinator : string }

let is_closure_ty = function
  | Tir.TFn _ -> true
  | Tir.TCon (n, _) -> Tir_names.is_clo_struct n
  | _ -> false

(** The combinator a call targets, matched on the whole name: [List.pmap] or
    a specialisation [List.pmap$<types>].  Not [Tir_names.strip_specialization_suffix],
    which looks for the [$] after the LAST dot, and a type suffix such as
    [List_Inner.Rec] has dots of its own. *)
let seed_of (callee : string) : (string * int list) option =
  List.find_opt (fun (s, _) ->
      String.equal callee s || String.starts_with ~prefix:(s ^ "$") callee)
    seeds

let display (callee : string) : string =
  match seed_of callee with Some (s, _) -> s | None -> base callee

(** Where a function receives a closure it may run in parallel: a parameter,
    or, for a lifted lambda's apply function, a captured free variable
    ([$clo.$fvK] is capture K of the closure allocation, counting from 1). *)
type slot = Param of int | Cap of int

(* ── Function-local facts ───────────────────────────────────────────────── *)

type locals = {
  closures : Tir.atom list SMap.t;
  (** v -> the capture atoms of the closure allocation bound to v (the apply
      function dropped); an alias [let k = g] maps k -> [g]. *)
  fv : int SMap.t;          (** v -> K when bound by [let v = $clo.$fvK] *)
  bound : SSet.t;           (** every name the function binds *)
}

let rec strip_seq = function Tir.ESeq (_, e) -> strip_seq e | e -> e

let locals_of (fn : Tir.fn_def) : locals =
  let closures = ref SMap.empty and fv = ref SMap.empty in
  let bound = ref (SSet.of_list (List.map (fun (p : Tir.var) -> p.Tir.v_name) fn.Tir.fn_params)) in
  let bind n = bound := SSet.add n !bound in
  let rec go (e : Tir.expr) =
    match e with
    | Tir.ELet (v, rhs, rest) ->
      bind v.Tir.v_name;
      (match strip_seq rhs with
       | Tir.EAlloc (Tir.TCon (n, _), _ :: caps) when Tir_names.is_clo_struct n ->
         closures := SMap.add v.Tir.v_name caps !closures
       | Tir.EAtom (Tir.AVar _ as a) -> closures := SMap.add v.Tir.v_name [ a ] !closures
       | Tir.EField (_, f) when Tir_names.is_fv_field f ->
         fv := SMap.add v.Tir.v_name (Tir_names.fv_field_index f) !fv
       | _ -> ());
      go rhs; go rest
    | Tir.ECase (_, brs, def) ->
      List.iter (fun (b : Tir.branch) ->
          List.iter (fun (v : Tir.var) -> bind v.Tir.v_name) b.Tir.br_vars;
          go b.Tir.br_body)
        brs;
      Option.iter go def
    | Tir.ELetRec (fns, rest) ->
      List.iter (fun (f : Tir.fn_def) ->
          bind f.Tir.fn_name;
          List.iter (fun (p : Tir.var) -> bind p.Tir.v_name) f.Tir.fn_params;
          go f.Tir.fn_body)
        fns;
      go rest
    | Tir.ESeq (a, b) -> go a; go b
    | _ -> ()
  in
  go fn.Tir.fn_body;
  { closures = !closures; fv = !fv; bound = !bound }

(** Every place [body] hands an atom to a (function, slot): the arguments of
    a call, and the captures of a closure allocation ([alloc $Clo(apply, c1,
    …)] hands cK to [apply]'s [Cap K]). *)
let uses (body : Tir.expr) : (string * slot * Tir.atom) list =
  let rec go acc (e : Tir.expr) =
    match e with
    | Tir.EApp (f, args) ->
      List.rev_append (List.mapi (fun j a -> (f.Tir.v_name, Param j, a)) args) acc
    | Tir.EAlloc (Tir.TCon (n, _), apply :: caps) when Tir_names.is_clo_struct n ->
      (match apply with
       | Tir.ADefRef d ->
         List.rev_append (List.mapi (fun k a -> (d.Tir.did_name, Cap (k + 1), a)) caps) acc
       | Tir.AVar v ->
         List.rev_append (List.mapi (fun k a -> (v.Tir.v_name, Cap (k + 1), a)) caps) acc
       | _ -> acc)
    | Tir.ELet (_, rhs, rest) -> go (go acc rhs) rest
    | Tir.ECase (_, brs, def) ->
      let acc = List.fold_left (fun a (b : Tir.branch) -> go a b.Tir.br_body) acc brs in
      (match def with Some d -> go acc d | None -> acc)
    | Tir.ELetRec (fns, rest) ->
      go (List.fold_left (fun a (f : Tir.fn_def) -> go a f.Tir.fn_body) acc fns) rest
    | Tir.ESeq (a, b) -> go (go acc a) b
    | _ -> acc
  in
  List.rev (go [] body)

(** The slots of [fn] that an atom reaches: a closure-typed parameter or
    captured free variable, directly, through an alias, or as a capture
    (transitively) of a locally allocated closure. *)
let slots_reached (fn : Tir.fn_def) (l : locals) (a : Tir.atom) : slot list =
  let index = List.mapi (fun i (p : Tir.var) -> (p.Tir.v_name, i)) fn.Tir.fn_params in
  let rec go seen acc = function
    | Tir.AVar v ->
      let n = v.Tir.v_name in
      if SSet.mem n seen then acc
      else
        let seen = SSet.add n seen in
        let closure = is_closure_ty v.Tir.v_ty in
        let acc = match List.assoc_opt n index with
          | Some i when closure -> Param i :: acc
          | _ -> acc in
        let acc = match SMap.find_opt n l.fv with
          | Some k when closure -> Cap k :: acc
          | _ -> acc in
        (match SMap.find_opt n l.closures with
         | Some caps -> List.fold_left (go seen) acc caps
         | None -> acc)
    | _ -> acc
  in
  List.sort_uniq compare (go SSet.empty [] a)

(* ── Which (function, slot) pairs are parallel ──────────────────────────── *)

type fn_facts = { f_fn : Tir.fn_def; f_locals : locals; f_uses : (string * slot * Tir.atom) list }

let facts (m : Tir.tir_module) : fn_facts list =
  List.map (fun (fn : Tir.fn_def) ->
      { f_fn = fn; f_locals = locals_of fn; f_uses = uses fn.Tir.fn_body })
    m.Tir.tm_fns

let lookup pos callee slot =
  match Hashtbl.find_opt pos (callee, slot) with
  | Some p -> Some p
  | None ->
    (match slot, seed_of callee with
     | Param j, Some (s, js) when List.mem j js -> Some { via = None; combinator = s }
     | _ -> None)

(** Fixpoint: a slot of a function is parallel when the function hands it (or
    a closure capturing it) to a parallel slot. *)
let parallel_positions (fs : fn_facts list) : (string * slot, position) Hashtbl.t =
  let pos : (string * slot, position) Hashtbl.t = Hashtbl.create 64 in
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter (fun f ->
        List.iter (fun (callee, slot, a) ->
            match lookup pos callee slot with
            | None -> ()
            | Some p ->
              List.iter (fun s ->
                  let key = (f.f_fn.Tir.fn_name, s) in
                  if not (Hashtbl.mem pos key) then begin
                    Hashtbl.replace pos key { via = Some (display callee); combinator = p.combinator };
                    changed := true
                  end)
                (slots_reached f.f_fn f.f_locals a))
          f.f_uses)
      fs
  done;
  pos

(* ── The check ──────────────────────────────────────────────────────────── *)

type violation = {
  v_fn : string;            (** TIR function containing the call *)
  v_callee : string;        (** what the closure was passed to *)
  v_position : position;
  v_capture : string;       (** the captured variable *)
  v_capture_ty : Tir.ty;
}

(** Resource-carrying captures of the closure an atom denotes (through
    aliases and nested closure allocations in the same function).  A
    top-level function or extern named in a capture slot is code, not a value
    the closure holds; a zero-argument one is typed by its result
    (`acc_new : Acc`), so it is skipped by name, but only when the function
    does not bind that name itself (a parameter `handle : Acc` shadowing a
    top-level `handle()` is a value). *)
let resource_captures k_table globals (l : locals) (a : Tir.atom) : (string * Tir.ty) list =
  let rec go seen acc = function
    | Tir.AVar v ->
      let n = v.Tir.v_name in
      if SSet.mem n seen then acc
      else
        let seen = SSet.add n seen in
        (match SMap.find_opt n l.closures with
         | Some caps -> List.fold_left (go seen) acc caps
         | None ->
           if (SSet.mem n globals && not (SSet.mem n l.bound))
           || (Kind.of_ty k_table v.Tir.v_ty).Kind.resource_free then acc
           else (n, v.Tir.v_ty) :: acc)
    | _ -> acc
  in
  List.rev (go SSet.empty [] a)

let violations ~(k_table : Kind.table) (m : Tir.tir_module) : violation list =
  let fs = facts m in
  let pos = parallel_positions fs in
  let globals =
    SSet.of_list
      (List.map (fun (f : Tir.fn_def) -> f.Tir.fn_name) m.Tir.tm_fns
       @ List.map (fun (e : Tir.extern_decl) -> e.Tir.ed_march_name) m.Tir.tm_externs) in
  List.concat_map (fun f ->
      List.concat_map (fun (callee, slot, a) ->
          match lookup pos callee slot, a with
          | Some p, Tir.AVar v when SMap.mem v.Tir.v_name f.f_locals.closures ->
            (* A closure captured by a lambda that runs it in parallel: say
               where it ends up, not the lambda's lifted name. *)
            let callee, p = match slot with
              | Param _ -> display callee, p
              | Cap _ -> p.combinator, { p with via = None } in
            List.map (fun (c, ty) ->
                { v_fn = f.f_fn.Tir.fn_name; v_callee = callee; v_position = p;
                  v_capture = c; v_capture_ty = ty })
              (resource_captures k_table globals f.f_locals a)
          | _ -> [])
        f.f_uses)
    fs

(* ── Naming what was captured ─────────────────────────────────────────── *)

(** The first native resource type reachable from [ty] (same walk and same
    stopping rules as [Kind.resource_free]), for the diagnostic. *)
let first_resource (k_table : Kind.table) (ty : Tir.ty) : string option =
  let visited = Hashtbl.create 8 in
  let rec go (ty : Tir.ty) : string option =
    match ty with
    | Tir.TCon (n, params) when Kind.is_resource_name k_table n -> ignore params; Some n
    | Tir.TCon (n, params) ->
      (match List.find_map go params with
       | Some r -> Some r
       | None ->
         let d = Kind.declaration_of k_table n in
         if Hashtbl.mem visited d then None
         else begin
           Hashtbl.replace visited d ();
           List.find_map (function
               | Tir.TDVariant (q, ctors) when String.equal q d ->
                 List.find_map (fun (_, fs) -> List.find_map go fs) ctors
               | Tir.TDRecord (q, fs) when String.equal q d ->
                 List.find_map (fun (_, f) -> go f) fs
               | Tir.TDClosure (q, fs) when String.equal q d -> List.find_map go fs
               | _ -> None)
             (Kind.type_defs k_table)
         end)
    | Tir.TTuple ts -> List.find_map go ts
    | Tir.TRecord fs -> List.find_map (fun (_, f) -> go f) fs
    | Tir.TPtr inner -> go inner
    | _ -> None
  in
  go ty

(** A type as the user wrote it: short constructor names, no TIR syntax. *)
let rec show (ty : Tir.ty) : string =
  match ty with
  | Tir.TInt -> "Int" | Tir.TFloat -> "Float" | Tir.TBool -> "Bool"
  | Tir.TString -> "String" | Tir.TUnit -> "()"
  | Tir.TCon (n, []) -> Collision_set.short_name n
  | Tir.TCon (n, args) ->
    Collision_set.short_name n ^ "(" ^ String.concat ", " (List.map show args) ^ ")"
  | Tir.TTuple ts -> "(" ^ String.concat ", " (List.map show ts) ^ ")"
  | Tir.TRecord fs ->
    "{ " ^ String.concat ", " (List.map (fun (f, t) -> f ^ " : " ^ show t) fs) ^ " }"
  | Tir.TFn (args, ret) -> "(" ^ String.concat ", " (List.map show args) ^ ") -> " ^ show ret
  | Tir.TPtr t -> show t
  | Tir.TVar v -> v

(* ── --check gate ────────────────────────────────────────────────────────── *)

(** Whether the program declares a native [resource] anywhere (any module
    depth).  [--check] lowers to TIR only for programs that could violate
    this rule or carry a @[no_alloc] obligation; no eagerly loaded stdlib
    module declares a resource, so an ordinary program stays a list scan. *)
let rec declares_resource_in (decls : March_ast.Ast.decl list) : bool =
  List.exists (function
      | March_ast.Ast.DType (_, _, _, March_ast.Ast.TDVariant [], _) -> true
      | March_ast.Ast.DMod (_, _, inner, _) -> declares_resource_in inner
      | _ -> false)
    decls

let declares_resource (m : March_ast.Ast.module_) : bool =
  declares_resource_in m.March_ast.Ast.mod_decls

(* ── Diagnostics ────────────────────────────────────────────────────────── *)

(** A lifted lambda's apply function -> the function that allocates its
    closure, so a violation inside a lambda is reported at the named
    function the user wrote. *)
let lambda_parents (m : Tir.tir_module) : string SMap.t =
  List.fold_left (fun acc (fn : Tir.fn_def) ->
      let rec go acc (e : Tir.expr) =
        match e with
        | Tir.EAlloc (Tir.TCon (n, _), Tir.ADefRef d :: _) when Tir_names.is_clo_struct n ->
          SMap.add d.Tir.did_name fn.Tir.fn_name acc
        | Tir.EAlloc (Tir.TCon (n, _), Tir.AVar d :: _) when Tir_names.is_clo_struct n ->
          SMap.add d.Tir.v_name fn.Tir.fn_name acc
        | Tir.ELet (_, rhs, rest) -> go (go acc rhs) rest
        | Tir.ECase (_, brs, def) ->
          let acc = List.fold_left (fun a (b : Tir.branch) -> go a b.Tir.br_body) acc brs in
          (match def with Some d -> go acc d | None -> acc)
        | Tir.ELetRec (fns, rest) ->
          go (List.fold_left (fun a (f : Tir.fn_def) -> go a f.Tir.fn_body) acc fns) rest
        | Tir.ESeq (a, b) -> go (go acc a) b
        | _ -> acc
      in
      go acc fn.Tir.fn_body)
    SMap.empty m.Tir.tm_fns

let user_name (n : string) : string =
  (* "$x$12" / "x$3" -> "x": drop specialization and fresh-name suffixes *)
  let n = base n in
  match String.index_opt n '$' with
  | Some 0 -> n
  | Some i -> String.sub n 0 i
  | None -> n

let check ~(k_table : Kind.table) ~(decls : Alloc_contract.decl_info list)
    (m : Tir.tir_module) : March_errors.Errors.diagnostic list =
  let vs = violations ~k_table m in
  if vs = [] then []
  else begin
    let parents = lambda_parents m in
    let rec named f depth =
      let b = base f in
      match List.find_opt (fun (d : Alloc_contract.decl_info) -> d.Alloc_contract.d_name = b) decls with
      | Some d -> Some d
      | None ->
        if depth > 16 then None
        else match SMap.find_opt f parents with
          | Some p -> named p (depth + 1)
          | None -> None
    in
    let seen = Hashtbl.create 8 in
    List.filter_map (fun v ->
        let key = (v.v_fn, v.v_callee, v.v_capture) in
        if Hashtbl.mem seen key then None
        else begin
          Hashtbl.replace seen key ();
          let decl = named v.v_fn 0 in
          let span = match decl with
            | Some d -> d.Alloc_contract.d_name_span
            | None -> March_ast.Ast.dummy_span in
          let fn_label = match decl with
            | Some d -> user_name d.Alloc_contract.d_name
            | None -> user_name v.v_fn in
          let cap = user_name v.v_capture in
          let resource = match first_resource k_table v.v_capture_ty with
            | Some r -> Collision_set.short_name r
            | None -> show v.v_capture_ty in
          let what =
            match v.v_capture_ty with
            | Tir.TCon (n, _) when Kind.is_resource_name k_table n ->
              Printf.sprintf "`%s` is a native resource handle (`%s`)" cap resource
            | ty ->
              Printf.sprintf "`%s` is a `%s`, which holds a native resource handle (`%s`)"
                cap (show ty) resource in
          let runs = match v.v_position.via with
            | None -> Printf.sprintf "`%s`, which runs it on several tasks at once" v.v_callee
            | Some _ ->
              Printf.sprintf "`%s`, which runs it on several tasks at once through `%s`"
                v.v_callee v.v_position.combinator in
          let msg = Printf.sprintf
              "`%s` passes a closure that captures `%s` to %s.\n\
               %s, and nothing guarantees the native library behind it is safe \
               to call from more than one thread."
              fn_label cap runs what in
          Some (Alloc_contract.diag ~severity:March_errors.Errors.Error ~span
                  ~code:March_errors.Code.portable_capture
                  ~notes:[ Printf.sprintf
                             "help: create the handle inside the closure, so each task \
                              gets its own, or use the sequential version of `%s`."
                             v.v_position.combinator ]
                  msg)
        end)
      vs
  end
