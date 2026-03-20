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

(* ── hash_module ────────────────────────────────────────────────────────── *)

(** Compute hashes for all SCCs in a [tir_module].
    Returns SCCs in topological order (dependencies before dependents). *)
let hash_module (m : tir_module) : hashed_scc list =
  let sccs = Scc.compute_sccs m.tm_fns in
  (* Build a name → fn_def lookup table *)
  let fn_table = Hashtbl.create (List.length m.tm_fns) in
  List.iter (fun fd -> Hashtbl.replace fn_table fd.fn_name fd) m.tm_fns;
  List.map (fun scc ->
    match scc with
    | Scc.Single name ->
      let fd = Hashtbl.find fn_table name in
      let h  = Hash.hash_fn_def fd in
      let hdef : Cas.hashed_def = {
        Cas.hd_sig_hash  = h.Hash.sig_hash;
        Cas.hd_impl_hash = h.Hash.impl_hash;
        Cas.hd_def       = Cas.FnDef fd;
      } in
      HSingle { hs_hdef = hdef }
    | Scc.Group members ->
      (* Sort by name, hash each, then derive group hash *)
      let sorted = List.sort String.compare members in
      let hdefs = List.map (fun name ->
        let fd = Hashtbl.find fn_table name in
        let h  = Hash.hash_fn_def fd in
        { Cas.hd_sig_hash  = h.Hash.sig_hash;
          Cas.hd_impl_hash = h.Hash.impl_hash;
          Cas.hd_def       = Cas.FnDef fd; }
      ) sorted in
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
