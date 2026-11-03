(** How a case arm takes over its scrutinee, decided from the arm's TIR
    alone: shared by codegen ([Llvm_case]'s case emitter) and the RC-balance
    verifier ([Tir_verify_rc]), which must agree on it exactly or the verifier
    judges a different ownership protocol than the one the binary runs.
    Moved verbatim from [Llvm_case] (where both were local helpers). *)

(* Helper: find the scrutinee's own EDecRC/EAtomicDecRC within a leading
   run of bare DecRC ops and return (v, rest) with the OTHER leading decs
   preserved in their original order around the extraction point.

   The scrutinee's dec is not always the literal head of the branch body:
   [add_cross_decrcs] in perceus.ml prepends OTHER cross-branch-dead
   variables' EDecRC/EAtomicDecRC ops in front of it whenever the branch
   also has, say, a closure parameter that's unused on this specific arm
   (e.g. Map.node_insert's HLeaf arm: `dec_rc eq; dec_rc node; ...` — the
   scrutinee `node`'s dec is SECOND, not first). A literal head-only match
   here silently falls through to the plain (unprotected) EDecRC codegen
   below, leaving extracted heap fields under-refcounted whenever the
   scrutinee is actually shared at that point — this was finding C1: a
   String map key's refcount under-counted this way, freed prematurely,
   surfacing as a use-after-free in march_hash_string when a later
   Map.keys/get_or traversal read it. Fixed 2026-07-11. *)
let strip_scrut_decrc scrut_name body =
  let rec go acc e =
    match e with
    | Tir.ESeq (((Tir.EDecRC (Tir.AVar v)) as op), rest)
    | Tir.ESeq (((Tir.EAtomicDecRC (Tir.AVar v)) as op), rest) ->
      if String.equal v.Tir.v_name scrut_name then
        Some (v, List.fold_left (fun inner o -> Tir.ESeq (o, inner)) rest acc)
      else
        go (op :: acc) rest
    (* [Drop] runs after Perceus and rewrites those prepended decs of
       OTHER variables into deep-drop calls ([dec_rc cfg] becomes
       [__drop$PoolConfig(cfg)]); it never rewrites the scrutinee's own dec
       (Drop.rewrite's [is_scrut_dec]).  Skip them like the bare decs they
       were, or the scrutinee's dec behind one compiles as a plain release
       with no shared-path dups -- finding C1 again: depot's
       Pool.handle_checkout `Cons(conn, rest)` arm, behind a dead [cfg]'s
       drop, moved [conn] and [rest] out of the still-shared idle list, and
       releasing the old pool state then freed the connection being handed
       to the caller. *)
    | Tir.ESeq ((Tir.EApp (f, [ Tir.AVar _ ]) as op), rest)
      when Tir_names.is_drop_fn f.Tir.v_name ->
      go (op :: acc) rest
    | _ -> None
  in
  go [] body


(* True iff [body] reuses the scrutinee's own storage via an
   [EReuse (AVar scrut_name, ...)] anywhere it could execute.

   This is the "reuse" counterpart of [strip_scrut_decrc].  When an arm both
   extracts heap fields (inherited from the scrutinee with NO dup) AND reuses
   the scrutinee box at the tail (the FBIP whole-cell-reuse pattern, e.g.
   [Bytes.slice]: [Bytes(xs) -> ... reuse b as Bytes(...)]), the box-level
   RC check lives at the EReuse site — which is too late.  The extracted
   fields were already moved into a consuming callee (e.g. list_drop, which
   FBIP-reuses xs's cons cells in place) UPSTREAM of the EReuse.  When the
   scrutinee is shared (RC > 1) the EReuse takes its dec+alloc-Llvm_ctx.fresh path and
   the original box survives, still pointing at those now-destroyed children
   → use-after-free in the caller (the [b len = 0] bug).

   The fix mirrors the leading-dec shared path: read the scrutinee RC at
   branch ENTRY (a non-consuming load — the EReuse still owns and consumes the
   box reference at the tail) and, on the shared path, IncRC each extracted
   heap field BEFORE the body consumes them.  RC(scrut box) is invariant
   between entry and the EReuse (the body consumes the CHILDREN, never the box
   header), so the entry check and the EReuse check observe the same value and
   stay consistent. *)
let rec body_reuses_scrut scrut_name e =
  match e with
  | Tir.EReuse (Tir.AVar v, _, _) -> String.equal v.Tir.v_name scrut_name
  (* TRMC's hole allocation with a reuse token is the same take-over-or-
     release as EReuse (Llvm_emit_alloc.emit_alloc_hole: rc = 1 reuses the
     cell, otherwise ONE box-level march_decrc and a fresh cell), so a
     shared scrutinee needs the same dup of its extracted fields. Without
     this arm the fields moved out of a SHARED cell with no increment: the
     tail passed on to the next iteration then looked unique and was reused
     in place, mutating a list someone else still held (an append whose
     first argument shares its tail -- Msgpack.encode of a Bin inside an
     Array, reused payload -- RC underflow / garbage). *)
  | Tir.EAllocHole (Some (Tir.AVar v), _, _, _) -> String.equal v.Tir.v_name scrut_name
  | Tir.ELet (v, e1, e2) ->
    body_reuses_scrut scrut_name e1
    || (not (String.equal v.Tir.v_name scrut_name)
        && body_reuses_scrut scrut_name e2)
  | Tir.ESeq (e1, e2) ->
    body_reuses_scrut scrut_name e1 || body_reuses_scrut scrut_name e2
  | Tir.ECase (_, branches, default) ->
    List.exists (fun br ->
      not (List.exists (fun bv ->
             String.equal bv.Tir.v_name scrut_name) br.Tir.br_vars)
      && body_reuses_scrut scrut_name br.Tir.br_body) branches
    || Option.fold ~none:false
         ~some:(body_reuses_scrut scrut_name) default
  | Tir.ELetRec (fns, body) ->
    not (List.exists (fun fn ->
           String.equal fn.Tir.fn_name scrut_name) fns)
    && body_reuses_scrut scrut_name body
  | _ -> false
