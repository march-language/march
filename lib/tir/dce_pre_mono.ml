(** Reachability prune before Mono.

    Lowering prepends the whole stdlib, and Mono seeds every monomorphic
    function, so Mono, Fusion and Defun used to process ~6,300 functions for a
    program that reaches a few dozen.  This pass keeps only what the roots
    reach.  It is a compile-time optimisation: the early DCE after Defun would
    drop the same functions anyway.  The one consumer that sits between Mono
    and that DCE, the policy audit run as the pipeline's [after_fusion] hook,
    reads every [Tagged(_, P)] function, and nothing calls one; those are
    pinned as roots (so is everything the allocation contract checks).

    Edges out of a reached function are every name its body MENTIONS (not only
    its free variables: Mono resolves names with its own, narrower notion of
    shadowing, so a let-bound local that shares a name with a top-level
    function must keep that function, exactly as it does without the prune),
    plus [Mono.implicit_callees] of each such name: the calls Mono mints that
    the TIR does not spell.  A missed implicit edge cannot go unnoticed: Mono
    raises on any resolution of a name in the removed set this pass returns.

    See specs/2026-11-24-stdlib-compile-floor-design.md. *)

module StringSet = Dce.StringSet

(** Every variable name the expression mentions, bound or free, including the
    bodies of nested functions. *)
let mentioned (e : Tir.expr) : StringSet.t =
  let acc = ref StringSet.empty in
  let add n = acc := StringSet.add n !acc in
  let atom = function
    | Tir.AVar v -> add v.Tir.v_name
    | Tir.ADefRef _ | Tir.ALit _ -> ()
  in
  let atoms = List.iter atom in
  let rec go = function
    | Tir.EAtom a -> atom a
    | Tir.EApp (f, args) -> add f.Tir.v_name; atoms args
    | Tir.ECallPtr (f, args) -> atom f; atoms args
    | Tir.ELet (_, rhs, body) -> go rhs; go body
    | Tir.ELetRec (fns, body) ->
      List.iter (fun (fd : Tir.fn_def) -> go fd.Tir.fn_body) fns; go body
    | Tir.ECase (a, branches, default) ->
      atom a;
      List.iter (fun b -> go b.Tir.br_body) branches;
      Option.iter go default
    | Tir.ETuple xs | Tir.EAlloc (_, xs) | Tir.EStackAlloc (_, xs) -> atoms xs
    | Tir.ERecord fields -> List.iter (fun (_, a) -> atom a) fields
    | Tir.EField (a, _) -> atom a
    | Tir.EUpdate (a, fields) -> atom a; List.iter (fun (_, x) -> atom x) fields
    | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a
    | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a -> atom a
    | Tir.EReuse (a, _, xs) -> atom a; atoms xs
    | Tir.EAllocHole (tok, _, xs, _) -> Option.iter atom tok; atoms xs
    | Tir.ESetField (o, _, x) -> atom o; atom x
    | Tir.ESeq (e1, e2) -> go e1; go e2
  in
  go e;
  !acc

let is_rpc_stub (n : string) : bool =
  let suffix = "__rpc_stub" in
  let nl = String.length n and sl = String.length suffix in
  nl > sl && String.sub n (nl - sl) sl = suffix

(** The edges out of [fd]: every name its body mentions or has free, and
    [Mono.implicit_callees] of each.  [k] sees a name once per occurrence
    in that set (a name and an implicit callee may repeat). *)
let iter_edges ~(iface_methods : (string, (string * string) list) Hashtbl.t)
    (fd : Tir.fn_def) (k : string -> unit) : unit =
  let refs = StringSet.union (mentioned fd.Tir.fn_body) (Dce.free_vars fd.Tir.fn_body) in
  StringSet.iter (fun r ->
      k r;
      List.iter k (Mono.implicit_callees ~iface_methods r))
    refs

(** The worklist shared by [prune] and lazy lowering
    ([Lower.lower_module ~lazy_bodies]), which must agree edge for edge: lazy
    lowering lowers exactly the stdlib bodies this walk can reach.

    From [roots], visit each name once; for each of its definitions
    ([defs n], every one when a name is defined twice) follow [iter_edges]
    to every name [known] holds, plus the names [extra] gives for that
    definition.  Returns the visited set (roots included, defined or not). *)
let walk ~(iface_methods : (string, (string * string) list) Hashtbl.t)
    ~(known : string -> bool) ~(defs : string -> Tir.fn_def list)
    ?(extra : Tir.fn_def -> string list = fun _ -> [])
    (roots : string list) : (string, unit) Hashtbl.t =
  let visited : (string, unit) Hashtbl.t = Hashtbl.create 256 in
  let queue = Queue.create () in
  List.iter (fun n -> Queue.push n queue) roots;
  let push r = if known r then Queue.push r queue in
  while not (Queue.is_empty queue) do
    let name = Queue.pop queue in
    if not (Hashtbl.mem visited name) then begin
      Hashtbl.replace visited name ();
      List.iter (fun (fd : Tir.fn_def) ->
          iter_edges ~iface_methods fd push;
          List.iter push (extra fd))
        (defs name)
    end
  done;
  visited

(** Whether [fd] is a stdlib fn lazy lowering left unlowered (its body calls
    [Tir_names.unlowered_marker]; a pass may have put code in front). *)
let is_unlowered (fd : Tir.fn_def) : bool =
  StringSet.mem Tir_names.unlowered_marker (mentioned fd.Tir.fn_body)

let prune ?(iface_methods = Hashtbl.create 0) ~(extra_roots : string list)
    ~(fail_open : bool) (m : Tir.tir_module)
  : Tir.tir_module * (string, unit) Hashtbl.t =
  (* [Hashtbl.add], not [replace]: two functions can share a name before Mono,
     and a reached name follows the edges of every one of them. *)
  let by_name : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 4096 in
  List.iter (fun (fd : Tir.fn_def) -> Hashtbl.add by_name fd.Tir.fn_name fd)
    m.Tir.tm_fns;
  let wanted = Hashtbl.create 16 in
  List.iter (fun n -> Hashtbl.replace wanted n ())
    (extra_roots @ Dce.remote_ref_targets m);
  let pins = List.filter_map (fun (fd : Tir.fn_def) ->
      let n = fd.Tir.fn_name in
      if Hashtbl.mem wanted n || is_rpc_stub n
         || Policy_dce.policies_of_fn fd <> []
      then Some n else None) m.Tir.tm_fns in
  let roots =
    Dce.root_names ~fail_open
      { m with Tir.tm_exports = m.Tir.tm_exports @ pins } in
  (* Tripwire: a reached fn whose body lazy lowering never lowered is a root
     or an edge [Lower.lower_module ~lazy_bodies] missed.  Refuse loudly
     rather than compile a program missing a function.  An unreached stub
     lands in the removed set, so Mono's [pruned_lookup] covers a name Mono
     mints itself. *)
  let defs name =
    let ds = Hashtbl.find_all by_name name in
    List.iter (fun (fd : Tir.fn_def) ->
        if is_unlowered fd then
          failwith (Printf.sprintf
            "internal error: the pre-mono prune reached %s, a standard-library \
             function whose body lazy lowering did not lower; rerun with \
             --disable-pass lazy-lower and report it" name))
      ds;
    ds
  in
  let visited =
    walk ~iface_methods ~known:(Hashtbl.mem by_name) ~defs roots in
  let removed : (string, unit) Hashtbl.t = Hashtbl.create 4096 in
  let fns = List.filter (fun (fd : Tir.fn_def) ->
      Hashtbl.mem visited fd.Tir.fn_name
      || (Hashtbl.replace removed fd.Tir.fn_name (); false))
      m.Tir.tm_fns in
  ({ m with Tir.tm_fns = fns }, removed)
