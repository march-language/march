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
    Known gap: a closure that reaches a parallel position through a data
    structure (stored in a record, read back, then passed) is not traced. *)

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

(* ── Local closure allocations ──────────────────────────────────────────── *)

(** Inside one function body: variable name -> the capture atoms of the
    closure allocation it is bound to (the first [EAlloc] argument is the
    apply function and is dropped). *)
let local_closures (body : Tir.expr) : Tir.atom list SMap.t =
  let rec go acc (e : Tir.expr) =
    match e with
    | Tir.ELet (v, (Tir.EAlloc (Tir.TCon (n, _), _ :: caps)), rest)
      when Tir_names.is_clo_struct n ->
      go (SMap.add v.Tir.v_name caps acc) rest
    | Tir.ELet (_, rhs, rest) -> go (go acc rhs) rest
    | Tir.ECase (_, brs, def) ->
      let acc = List.fold_left (fun a (b : Tir.branch) -> go a b.Tir.br_body) acc brs in
      (match def with Some d -> go acc d | None -> acc)
    | Tir.ELetRec (fns, rest) ->
      go (List.fold_left (fun a (f : Tir.fn_def) -> go a f.Tir.fn_body) acc fns) rest
    | Tir.ESeq (a, b) -> go (go acc a) b
    | _ -> acc
  in
  go SMap.empty body

(** Every call in [body], with its argument atoms. *)
let calls (body : Tir.expr) : (string * Tir.atom list) list =
  let rec go acc (e : Tir.expr) =
    match e with
    | Tir.EApp (f, args) -> (f.Tir.v_name, args) :: acc
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

(** The closure-typed parameters of [fn] that an atom reaches, directly or as
    a capture (transitively) of a locally allocated closure. *)
let params_reached (fn : Tir.fn_def) (locals : Tir.atom list SMap.t) (a : Tir.atom) : int list =
  let index = List.mapi (fun i (p : Tir.var) -> (p.Tir.v_name, i)) fn.Tir.fn_params in
  let rec go seen acc = function
    | Tir.AVar v ->
      let n = v.Tir.v_name in
      if SSet.mem n seen then acc
      else
        let seen = SSet.add n seen in
        let acc = match List.assoc_opt n index with
          | Some i when is_closure_ty v.Tir.v_ty -> i :: acc
          | _ -> acc in
        (match SMap.find_opt n locals with
         | Some caps -> List.fold_left (go seen) acc caps
         | None -> acc)
    | _ -> acc
  in
  List.sort_uniq compare (go SSet.empty [] a)

(* ── Which (function, parameter) pairs are parallel ─────────────────────── *)

(** Fixpoint: a function parameter is a parallel position when the function
    passes it (or a closure capturing it) to a parallel position. *)
let parallel_positions (m : Tir.tir_module) : (string * int, position) Hashtbl.t =
  let pos : (string * int, position) Hashtbl.t = Hashtbl.create 64 in
  let lookup callee j =
    match Hashtbl.find_opt pos (callee, j) with
    | Some p -> Some p
    | None ->
      (match List.assoc_opt (base callee) seeds with
       | Some js when List.mem j js -> Some { via = None; combinator = base callee }
       | _ -> None)
  in
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter (fun (fn : Tir.fn_def) ->
        let locals = local_closures fn.Tir.fn_body in
        List.iter (fun (callee, args) ->
            List.iteri (fun j a ->
                match lookup callee j with
                | None -> ()
                | Some p ->
                  List.iter (fun i ->
                      if not (Hashtbl.mem pos (fn.Tir.fn_name, i)) then begin
                        Hashtbl.replace pos (fn.Tir.fn_name, i)
                          { via = Some (base callee); combinator = p.combinator };
                        changed := true
                      end)
                    (params_reached fn locals a))
              args)
          (calls fn.Tir.fn_body))
      m.Tir.tm_fns
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

(** Resource-carrying captures of the closure an atom denotes (through nested
    closure allocations in the same function).  A top-level function or
    extern named in a capture slot is code, not a value the closure holds;
    a zero-argument one is typed by its result (`acc_new : Acc`), so it must
    be skipped by name, not by type. *)
let resource_captures k_table globals locals (a : Tir.atom) : (string * Tir.ty) list =
  let rec go seen acc = function
    | Tir.AVar v ->
      let n = v.Tir.v_name in
      if SSet.mem n seen then acc
      else
        let seen = SSet.add n seen in
        (match SMap.find_opt n locals with
         | Some caps -> List.fold_left (go seen) acc caps
         | None ->
           if SSet.mem n globals
           || (Kind.of_ty k_table v.Tir.v_ty).Kind.resource_free then acc
           else (n, v.Tir.v_ty) :: acc)
    | _ -> acc
  in
  List.rev (go SSet.empty [] a)

let violations ~(k_table : Kind.table) (m : Tir.tir_module) : violation list =
  let pos = parallel_positions m in
  let lookup callee j =
    match Hashtbl.find_opt pos (callee, j) with
    | Some p -> Some p
    | None ->
      (match List.assoc_opt (base callee) seeds with
       | Some js when List.mem j js -> Some { via = None; combinator = base callee }
       | _ -> None)
  in
  let globals =
    SSet.of_list
      (List.map (fun (f : Tir.fn_def) -> f.Tir.fn_name) m.Tir.tm_fns
       @ List.map (fun (e : Tir.extern_decl) -> e.Tir.ed_march_name) m.Tir.tm_externs) in
  List.concat_map (fun (fn : Tir.fn_def) ->
      let locals = local_closures fn.Tir.fn_body in
      List.concat_map (fun (callee, args) ->
          List.concat (List.mapi (fun j a ->
              match lookup callee j, a with
              | Some p, Tir.AVar v when SMap.mem v.Tir.v_name locals ->
                List.map (fun (c, ty) ->
                    { v_fn = fn.Tir.fn_name; v_callee = base callee; v_position = p;
                      v_capture = c; v_capture_ty = ty })
                  (resource_captures k_table globals locals a)
              | _ -> [])
              args))
        (calls fn.Tir.fn_body))
    m.Tir.tm_fns

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
        | Tir.ELet (_, Tir.EAlloc (Tir.TCon (n, _), Tir.ADefRef d :: _), rest)
          when Tir_names.is_clo_struct n -> go (SMap.add d.Tir.did_name fn.Tir.fn_name acc) rest
        | Tir.ELet (_, Tir.EAlloc (Tir.TCon (n, _), Tir.AVar d :: _), rest)
          when Tir_names.is_clo_struct n -> go (SMap.add d.Tir.v_name fn.Tir.fn_name acc) rest
        | Tir.ELet (_, rhs, rest) -> go (go acc rhs) rest
        | Tir.ECase (_, brs, def) ->
          let acc = List.fold_left (fun a (b : Tir.branch) -> go a b.Tir.br_body) acc brs in
          (match def with Some d -> go acc d | None -> acc)
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
