(** Phase 6: Cache-hit fast path for the March compilation pipeline.

    After TIR lowering, definitions are grouped into SCCs, hashed, and
    checked against the CAS. Cache hits skip mono → defun → llvm entirely.

    Key types:
    - [hashed_scc]: an SCC paired with its pre-computed content hashes.
    - [hash_module]: processes a [tir_module], builds SCCs and hashes all defs.
    - [compile_scc]: looks up a cached artifact; on miss, calls the injected
      [~compile] function and stores the result.
*)

open March_tir.Tir

(* ── hashed_scc ─────────────────────────────────────────────────────────── *)

(** A hashed SCC.  Carries the SCC structure (Single/Group of names) plus
    the per-definition hashed_defs and the representative impl_hash used
    as the CAS key. *)
type hashed_scc =
  | HSingle of {
      hs_hdef    : Cas.hashed_def;   (** the single function's hashed def *)
    }
  | HGroup of {
      hg_hash : string;              (** group hash = BLAKE3(all member bytes) *)
      hg_hdefs : Cas.hashed_def list;(** individual members with own hashes *)
    }

(** The CAS key for a hashed_scc: impl_hash for Single, group hash for Group. *)
let scc_impl_hash = function
  | HSingle { hs_hdef } -> hs_hdef.Cas.hd_impl_hash
  | HGroup  { hg_hash; _ } -> hg_hash

(* ── type-reference extraction (for the type-layout Merkle fold) ─────────── *)

(* Collect the named-type constructors (TCon names) reachable within a type. *)
let rec add_tycons_of_ty acc (t : ty) : string list =
  match t with
  | TCon (n, args) -> List.fold_left add_tycons_of_ty (n :: acc) args
  | TTuple ts       -> List.fold_left add_tycons_of_ty acc ts
  | TRecord fs      -> List.fold_left (fun a (_, t) -> add_tycons_of_ty a t) acc fs
  | TFn (ps, r)     -> add_tycons_of_ty (List.fold_left add_tycons_of_ty acc ps) r
  | TPtr t          -> add_tycons_of_ty acc t
  | TInt | TFloat | TBool | TString | TUnit | TVar _ -> acc

let add_tycons_of_var acc (v : var) = add_tycons_of_ty acc v.v_ty
let add_tycons_of_atom acc = function
  | AVar v -> add_tycons_of_var acc v
  | ADefRef _ | ALit _ -> acc

(* All TCon names a definition mentions — in its signature AND its body
   (let-bound var types, constructor allocs, case-bound vars, …). Body usage
   matters: a fn that builds/matches a type is layout-sensitive to it even when
   the type never appears in its signature. *)
let rec add_tycons_of_expr acc (e : expr) : string list =
  match e with
  | EAtom a            -> add_tycons_of_atom acc a
  | EApp (v, args)     -> List.fold_left add_tycons_of_atom (add_tycons_of_var acc v) args
  | ECallPtr (f, args) -> List.fold_left add_tycons_of_atom (add_tycons_of_atom acc f) args
  | ELet (v, e1, e2)   -> add_tycons_of_expr (add_tycons_of_expr (add_tycons_of_var acc v) e1) e2
  | ELetRec (fns, body) ->
    add_tycons_of_expr (List.fold_left add_tycons_of_fn acc fns) body
  | ECase (a, brs, def) ->
    let acc = add_tycons_of_atom acc a in
    let acc = List.fold_left (fun a br ->
      add_tycons_of_expr (List.fold_left add_tycons_of_var a br.br_vars) br.br_body) acc brs in
    (match def with Some e -> add_tycons_of_expr acc e | None -> acc)
  | ETuple atoms       -> List.fold_left add_tycons_of_atom acc atoms
  | ERecord fields     -> List.fold_left (fun a (_, at) -> add_tycons_of_atom a at) acc fields
  | EField (a, _)      -> add_tycons_of_atom acc a
  | EUpdate (a, fields) ->
    List.fold_left (fun acc (_, av) -> add_tycons_of_atom acc av) (add_tycons_of_atom acc a) fields
  | EAlloc (ty, args) | EStackAlloc (ty, args) ->
    List.fold_left add_tycons_of_atom (add_tycons_of_ty acc ty) args
  | EReuse (a, ty, args) ->
    List.fold_left add_tycons_of_atom (add_tycons_of_ty (add_tycons_of_atom acc a) ty) args
  | EFree a | EIncRC a | EDecRC a | EAtomicIncRC a | EAtomicDecRC a -> add_tycons_of_atom acc a
  | ESeq (e1, e2)      -> add_tycons_of_expr (add_tycons_of_expr acc e1) e2

and add_tycons_of_fn acc (fd : fn_def) : string list =
  let acc = List.fold_left add_tycons_of_var acc fd.fn_params in
  add_tycons_of_expr (add_tycons_of_ty acc fd.fn_ret_ty) fd.fn_body

let name_of_type_def = function
  | TDVariant (n, _) | TDRecord (n, _) | TDClosure (n, _) -> n

(* Named types this type definition directly references. *)
let tycons_of_type_def acc = function
  | TDVariant (_, ctors) ->
    List.fold_left (fun a (_, tys) -> List.fold_left add_tycons_of_ty a tys) acc ctors
  | TDRecord (_, fields) ->
    List.fold_left (fun a (_, t) -> add_tycons_of_ty a t) acc fields
  | TDClosure (_, tys) -> List.fold_left add_tycons_of_ty acc tys

(* ── hash_module ────────────────────────────────────────────────────────── *)

(** Compute hashes for all SCCs in a [tir_module].
    Returns SCCs in topological order (dependencies before dependents).

    [impl_hash] is a true Merkle root: a definition's hash folds in the
    [impl_hash]es of every callee resolved in an EARLIER SCC. Because SCCs
    are returned dependencies-first, a change to any transitive dependency
    propagates into the hash of everything that (directly or indirectly)
    calls it — closing the cross-SCC stale-cache hole where an inlined
    callee's body change left the caller's hash unchanged.

    Intra-SCC references (self-recursion, and the members of a mutually-
    recursive [Group]) are NOT folded: a [Single] cannot depend on its own
    not-yet-computed hash, and a [Group]'s members are already covered
    collectively by the group hash, which spans all their bodies.

    The fold also covers TYPE layout: a definition's hash folds in the base
    hashes of every named type it transitively references (via [tm_types]).
    A record/variant layout change therefore propagates into every definition
    that uses the type — directly or through another type — because TIR
    references types by name, so without this a layout change would leave the
    user's serialized bytes (and hash) unchanged while its GEP offsets moved.
    Types defined outside this module (stdlib, deps) have no base hash here and
    are simply not folded, mirroring the cross-SCC callee rule. *)
let hash_module (m : tir_module) : hashed_scc list =
  let sccs = Scc.compute_sccs m.tm_fns in
  (* Build a name → fn_def lookup table *)
  let fn_table = Hashtbl.create (List.length m.tm_fns) in
  List.iter (fun fd -> Hashtbl.replace fn_table fd.fn_name fd) m.tm_fns;
  let all_names = List.map (fun fd -> fd.fn_name) m.tm_fns in
  (* name → impl_hash, populated as each SCC is processed (earlier SCCs only). *)
  let resolved : (string, string) Hashtbl.t =
    Hashtbl.create (List.length m.tm_fns) in
  (* Per-type base hash (own definition) and direct type→type references. *)
  let type_base : (string, string) Hashtbl.t =
    Hashtbl.create (List.length m.tm_types) in
  let type_refs : (string, string list) Hashtbl.t =
    Hashtbl.create (List.length m.tm_types) in
  List.iter (fun td ->
    let name = name_of_type_def td in
    Hashtbl.replace type_base name (Blake3.hash (Serialize.serialize_type_def td));
    Hashtbl.replace type_refs name
      (List.sort_uniq String.compare (tycons_of_type_def [] td))
  ) m.tm_types;
  (* Base hashes of all types transitively reachable from [start] (cycle-safe). *)
  let type_closure_hashes (start : string list) : string list =
    let seen : (string, unit) Hashtbl.t = Hashtbl.create 16 in
    let rec go = function
      | [] -> ()
      | n :: rest when Hashtbl.mem seen n -> go rest
      | n :: rest ->
        Hashtbl.replace seen n ();
        let next = Option.value ~default:[] (Hashtbl.find_opt type_refs n) in
        go (next @ rest)
    in
    go start;
    Hashtbl.fold (fun n () acc ->
      match Hashtbl.find_opt type_base n with Some h -> h :: acc | None -> acc)
      seen []
  in
  (* Merkle hash: base impl_hash of [fd], then fold the (sorted) impl_hashes of
     its already-resolved callees together with the base hashes of every type
     it transitively references. *)
  let merkle_hash_fn (fd : fn_def) : Hash.hashed_fn =
    let base = Hash.hash_fn_def fd in
    let dep_hashes =
      Scc.deps_of all_names fd
      |> List.filter_map (fun n -> Hashtbl.find_opt resolved n)
    in
    let type_hashes = type_closure_hashes (add_tycons_of_fn [] fd) in
    match List.sort String.compare (dep_hashes @ type_hashes) with
    | [] -> base
    | folded ->
      let impl_hash =
        Blake3.hash_string (String.concat "" (base.Hash.impl_hash :: folded))
      in
      { base with Hash.impl_hash }
  in
  List.map (fun scc ->
    match scc with
    | Scc.Single name ->
      let fd = Hashtbl.find fn_table name in
      let h  = merkle_hash_fn fd in
      Hashtbl.replace resolved name h.Hash.impl_hash;
      let hdef : Cas.hashed_def = {
        Cas.hd_sig_hash  = h.Hash.sig_hash;
        Cas.hd_impl_hash = h.Hash.impl_hash;
        Cas.hd_def       = Cas.FnDef fd;
      } in
      HSingle { hs_hdef = hdef }
    | Scc.Group members ->
      (* Sort by name, hash each (folding cross-group deps), derive group hash *)
      let sorted = List.sort String.compare members in
      let hdefs = List.map (fun name ->
        let fd = Hashtbl.find fn_table name in
        let h  = merkle_hash_fn fd in
        { Cas.hd_sig_hash  = h.Hash.sig_hash;
          Cas.hd_impl_hash = h.Hash.impl_hash;
          Cas.hd_def       = Cas.FnDef fd; }
      ) sorted in
      (* Publish member hashes only after the whole group is hashed, so
         intra-group references are excluded from the fold. *)
      List.iter2 (fun name hd -> Hashtbl.replace resolved name hd.Cas.hd_impl_hash)
        sorted hdefs;
      (* Group hash: BLAKE3 of all individual impl_hashes concatenated *)
      let group_hash = Blake3.hash_string
        (String.concat "" (List.map (fun hd -> hd.Cas.hd_impl_hash) hdefs)) in
      HGroup { hg_hash = group_hash; hg_hdefs = hdefs }
  ) sccs

(* ── compile_scc ────────────────────────────────────────────────────────── *)

(** Compile a single hashed SCC, with CAS cache-hit fast path.

    [~compile] is the actual compiler (mono → defun → llvm) injected by the
    caller. It receives the [hashed_scc] and returns an artifact path.

    On cache hit: returns the stored artifact path, [~compile] is NOT called.
    On cache miss: calls [~compile], stores the result, returns the path. *)
let compile_scc
    (store : Cas.t)
    ~(target : string)
    ~(flags  : string list)
    ~(compile : hashed_scc -> string)
    (h_scc : hashed_scc)
  : string =
  let impl_hash = scc_impl_hash h_scc in
  let ch = Cas.compilation_hash impl_hash ~target ~flags in
  match Cas.lookup_artifact store ch with
  | Some artifact_path -> artifact_path
  | None ->
    let artifact_path = compile h_scc in
    (* Store def(s) in the CAS *)
    (match h_scc with
     | HSingle { hs_hdef }     -> Cas.store_def store hs_hdef
     | HGroup  { hg_hdefs; _ } -> List.iter (Cas.store_def store) hg_hdefs);
    Cas.store_artifact store ch artifact_path;
    artifact_path
