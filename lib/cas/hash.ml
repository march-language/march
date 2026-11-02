(** Compute sig_hash and impl_hash for TIR definitions. *)

open March_tir.Tir

type hashed_fn = {
  sig_hash  : string;   (** BLAKE3 hex of signature only *)
  impl_hash : string;   (** BLAKE3 hex of full impl (sig + body) *)
}

(** Hash a function definition.
    - sig_hash:  BLAKE3(canonical signature bytes)
    - impl_hash: BLAKE3(sig_hash_bytes ++ canonical impl bytes)
      The impl hash covers the full definition so that a body change
      always produces a new impl_hash while leaving sig_hash stable. *)
let hash_fn_def (fd : fn_def) : hashed_fn =
  let sig_bytes  = Serialize.serialize_fn_sig fd in
  let impl_bytes = Serialize.serialize_fn_def fd in
  let sig_hash   = Blake3.hash sig_bytes in
  (* impl_hash = BLAKE3(sig_hash_bytes ++ full impl bytes) *)
  let impl_hash  = Blake3.hash_concat [Bytes.of_string sig_hash; impl_bytes] in
  { sig_hash; impl_hash }

(* ── Hot-reload slot ABI hash ──────────────────────────────────────────────

   [sig_hash] above is the TYPE signature only.  That is the right identity
   for RPC admission (values are marshalled, so ownership never crosses a
   node), but not for a hot-reload dispatch slot: a running caller was
   compiled against the callee's parameter borrow modes as well
   ([Borrow.infer_module] is whole-program, and a mode is decided by the
   body, not the source signature).  A patch that turns a borrowed parameter
   owned releases a reference the caller still holds (use-after-free); the
   reverse leaks one per call (specs/progress/2026-10-13-hcr-borrow-mode-not-in-sig-hash.md).

   So a slot's published and manifest [sig_hash] is [hcr_sig_hash]: the type
   signature hash plus one character per parameter, the mode Perceus placed
   RC against.  Nothing else of the boundary convention varies per function:
   a return is always owned (+1 to the caller), a closure call always
   consumes its arguments, a Float crosses boxed and stays the caller's, and
   representation changes are type changes, already in [sig_hash].  Only
   built under --hot-reload, so no other build's IR changes. *)

(** One character per parameter: ['b'] borrowed, ['o'] owned; ["-"] when the
    borrow map has no row for the function (not inferred). *)
let modes_string (bm : March_tir.Borrow.borrow_map) (fn_name : string) : string =
  match March_tir.Borrow.StringMap.find_opt fn_name bm with
  | None -> "-"
  | Some modes -> String.init (Array.length modes) (fun i -> if modes.(i) then 'b' else 'o')

(** The slot ABI hash for a function whose type signature hashes to
    [sig_hash] and whose parameter modes are [modes] ([modes_string]).
    The tag versions the recipe; the HCR ABI id ([Hcr_abi.runtime_abi])
    was bumped when it was introduced, so a hash from this recipe is never
    compared with a type-only one from an older running build. *)
let hcr_sig_hash ~(sig_hash : string) ~(modes : string) : string =
  Blake3.hash_string ("march-hcr-slot-sig-v1\000" ^ sig_hash ^ "\000" ^ modes)

(** A work entry accepts values captured before the selected work epoch.
    Nominal names alone do not prove those values have the current layout.
    Include all reachable definitions, retaining constructor order (tag ABI). *)
let work_entry_sig_hash ~(type_defs : type_def list) (fd : fn_def) ~sig_hash =
  let defs = Hashtbl.create 32 in
  List.iter (fun td ->
    let name = match td with TDVariant (n, _) | TDRecord (n, _) | TDClosure (n, _) -> n in
    Hashtbl.replace defs name td) type_defs;
  let seen = Hashtbl.create 16 in
  let rec visit = function
    | TCon (name, args) ->
      List.iter visit args;
      (* Inferred adapter parameters can retain the leaf name [Env] while
         lowering qualifies its definition as [Back.Env]. If several owners
         match, include every candidate: ambiguity must never approve a
         captured layout that changed. *)
      let names = Hashtbl.to_seq_keys defs |> List.of_seq
          |> List.filter (fun candidate -> candidate = name
              || String.ends_with ~suffix:("." ^ name) candidate) in
      List.iter (fun name ->
        if not (Hashtbl.mem seen name) then begin
          Hashtbl.add seen name ();
          match Hashtbl.find defs name with
          | TDVariant (_, cs) -> List.iter (fun (_, ts) -> List.iter visit ts) cs
          | TDRecord (_, fs) -> List.iter (fun (_, t) -> visit t) fs
          | TDClosure (_, ts) -> List.iter visit ts
        end) names
    | TTuple ts -> List.iter visit ts
    | TRecord fs -> List.iter (fun (_, t) -> visit t) fs
    | TFn (ps, r) -> List.iter visit ps; visit r
    | TPtr t -> visit t
    | TInt | TFloat | TBool | TString | TUnit | TVar _ -> () in
  List.iter (fun p -> visit p.v_ty) fd.fn_params;
  visit fd.fn_ret_ty;
  let b = Buffer.create 128 in
  Serialize.buf_string b "march-work-entry-layout-v1";
  Serialize.buf_string b sig_hash;
  Hashtbl.to_seq_keys seen |> List.of_seq |> List.sort String.compare
  |> List.iter (fun name -> match Hashtbl.find_opt defs name with
    | None -> ()
    | Some td ->
      Serialize.buf_string b (Bytes.to_string (Serialize.serialize_type_def td));
      (match td with
       | TDVariant (_, cs) -> List.iter (fun (n, _) -> Serialize.buf_string b n) cs
       | TDRecord (_, fs) -> List.iter (fun (n, _) -> Serialize.buf_string b n) fs
       | TDClosure _ -> ()));
  Blake3.hash_string (Buffer.contents b)
