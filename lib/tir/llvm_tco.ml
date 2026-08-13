(** LLVM emission: tail-call-optimization analysis and the mutual-TCO
    combined-function emitter.

    Wave 3 Task 6 (chunk 2) split: moved verbatim out of [llvm_emit.ml] — same
    discipline as the Wave 3 Task 5 [Llvm_eq]/[Llvm_data]/[Llvm_case] split:
    whole-definition moves, no behavior change, fully-qualified references
    (no [open]).  [emit_mutual_tco_group] calls back into [emit_expr] (to
    emit each mutual-TCO group member's case body) — [emit_expr] stays in
    [llvm_emit.ml] per the brief ("the emit_expr arms stay"), so the
    mutual-recursion is de-cycled the same way [Llvm_case.emit_case] was in
    Task 5: [emit_expr] is threaded in as a labeled callback parameter.  1
    callback total (well under the >4 "BLOCKED" threshold).

    [is_trivial_dec_chain_returning] / [is_trivial_dec_chain] also move here
    (named explicitly in the brief, "moves as ONE" with the tail-call
    predicates) even though [llvm_emit.ml]'s [emit_expr] itself still calls
    them (the self-TCO and mutual-TCO Perceus-wrapped-call interception
    arms, B7/B8) — that is a one-directional forward reference
    ([llvm_emit.ml] depending on [Llvm_tco]), not a cycle: both predicates
    are pure structural recursion over [Tir.expr] with no dependency back on
    [emit_expr]/[emit_case]/anything else in [llvm_emit.ml]. *)

(** True if [e] is a cleanup operation: an RC op, or a call to a synthesized
    deep-drop function, which [Drop.run] substitutes for exactly such an op
    (see [Tir_names.is_drop_fn]).  Both are evaluated only for effect. *)
let is_cleanup_op (e : Tir.expr) : bool =
  match e with
  | Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _
  | Tir.EIncRC _ | Tir.EAtomicIncRC _ -> true
  | Tir.EApp (f, _) -> Tir_names.is_drop_fn f.Tir.v_name
  | _ -> false

(** The variable a cleanup op releases, when it is a simple variable — so the
    TCO back-edge emitters can ask "does this op target a forwarded argument?"
    uniformly across an RC op and the deep-drop call that may stand in for it. *)
let cleanup_target (e : Tir.expr) : string option =
  match e with
  | Tir.EDecRC (Tir.AVar v) | Tir.EAtomicDecRC (Tir.AVar v)
  | Tir.EIncRC (Tir.AVar v) | Tir.EAtomicIncRC (Tir.AVar v)
  | Tir.EFree (Tir.AVar v) -> Some v.Tir.v_name
  | Tir.EApp (f, [Tir.AVar v]) when Tir_names.is_drop_fn f.Tir.v_name ->
    Some v.Tir.v_name
  | _ -> None

(** True iff [body] is a "trivial cleanup chain" that performs only
    [EDecRC] / [EAtomicDecRC] / [EFree] operations and finally returns
    the binding named [tmp_name].

    Used to recognise the
        [ELet (tmp, EApp (f, args), ESeq (dec_v1, ESeq (dec_v2, EAtom tmp)))]
    shape that Perceus emits in the EApp case when wrapping a borrowed-arg
    last-use post-call DecRC around a NON-self call (see [perceus.ml] EApp
    handling).  Without this recognition the wrapped call is invisible to
    the tail-call analyses in the mutual-TCO section below — silently
    dropping mutual TCO and producing real stack overflows on long inputs.

    Single definition (Wave 3 Task 5, chunk 2): this predicate was
    previously duplicated — this copy (needed by emit_expr's Perceus-wrapped
    TCO cases) plus a byte-identical one at the top of the mutual-TCO
    analysis section, an OCaml forward-reference workaround carrying a
    "must stay identical" comment.  Both sets of callers live after this
    point in the file, so the duplicate was deleted and this is now the
    only copy. *)
let rec is_trivial_dec_chain_returning (tmp_name : string) (body : Tir.expr) : bool =
  match body with
  | Tir.EAtom (Tir.AVar v) -> String.equal v.Tir.v_name tmp_name
  | Tir.ESeq (op, rest) when is_cleanup_op op ->
    is_trivial_dec_chain_returning tmp_name rest
  | _ -> false

(* Sibling of is_trivial_dec_chain_returning for the no-temp ESeq shape:
   Perceus emits ESeq(EApp(self,args), dec_chain) — WITHOUT an ELet binding
   the call's result — when the tail call's result needs no further
   post-call field-level bookkeeping beyond decrementing/incrementing
   already-materialised local values (e.g. a wildcarded `Cons(_, t)` pattern
   decrements the local `t` after passing it on, since March's calling
   convention borrows arguments and the caller is responsible for releasing
   its own reference once the call returns). emit_expr's generic ESeq case
   relies on the "e2 is Dec/IncRC → propagate e1's value" rule (see ESeq
   below) to make e1's result the seq's value, but it also unconditionally
   clears tco_in_tail before emitting e1 — so a self-call here compiles as
   an ordinary (non-tail) call even though it is semantically a tail call.
   This predicate recognises that dec_chain consists solely of trivial
   RC bookkeeping, so the dedicated ESeq-TCO case below can intercept it
   and emit a back-edge instead. *)
let rec is_trivial_dec_chain (e : Tir.expr) : bool =
  match e with
  | _ when is_cleanup_op e -> true
  | Tir.ESeq (op, rest) when is_cleanup_op op -> is_trivial_dec_chain rest
  | _ -> false

(** Collect the locals in [expr] bound to a "dup" — [ELet (v, ESeq (EIncRC x,
    EAtom x), _)], the shape Perceus uses to materialise an owned local from a
    borrowed field (the `t` of a `Cons(_, t)` pattern, say).  Such a local
    carries a +1 whose matching half is the post-call DecRC the dec-chain
    emits.

    This is the discriminator the TCO back-edge emitters need.  Commit
    eafbd71a fixed a use-after-free by skipping every dec-chain RC op whose
    target is one of the forwarded tail-call arguments: under real recursion
    that DecRC fires only after the nested call fully returns, but the
    flattened loop runs it immediately before the same value is stored into
    the next iteration's parameter slot, freeing a freshly-allocated,
    uncompensated value one instruction before its reuse.  That reasoning
    holds only for an argument with no compensating IncRC.  A dup-bound
    argument's DecRC is not an early release — it is the closing half of a
    balanced pair, and skipping it strands the +1, leaking one cell (and its
    payload) per iteration.  eafbd71a anticipated this case and judged it to
    "survive by accident (a compensating IncRC keeps it alive)" — it does
    survive, but only by leaking the whole list.

    Emission-order-independent by construction: [emit_fn] runs this over the
    whole function body up front rather than accumulating during emission, so
    a dup binding is visible to the back-edge emitter no matter where the TIR
    puts it relative to the tail call. *)
let rec dup_bound_vars (expr : Tir.expr) : string list =
  let here = match expr with
    | Tir.ELet (v, Tir.ESeq (Tir.EIncRC (Tir.AVar a), Tir.EAtom (Tir.AVar b)), _)
      when String.equal a.Tir.v_name b.Tir.v_name -> [v.Tir.v_name]
    | _ -> []
  in
  let sub = match expr with
    | Tir.ELet (_, rhs, body) -> dup_bound_vars rhs @ dup_bound_vars body
    | Tir.ESeq (e1, e2) -> dup_bound_vars e1 @ dup_bound_vars e2
    | Tir.ECase (_, branches, default_opt) ->
      List.concat_map (fun br -> dup_bound_vars br.Tir.br_body) branches
      @ (match default_opt with Some d -> dup_bound_vars d | None -> [])
    | Tir.ELetRec (fns, body) ->
      List.concat_map (fun f -> dup_bound_vars f.Tir.fn_body) fns
      @ dup_bound_vars body
    | _ -> []
  in
  here @ sub

(* ── Mutual TCO: call graph analysis ────────────────────────────────── *)

(** Collect all function names that are called in TAIL position in [expr].
    Only traverses tail-position sub-expressions. *)
let rec tail_calls_in (expr : Tir.expr) : string list =
  match expr with
  | Tir.EApp (f, _) -> [f.Tir.v_name]
  | Tir.ELet (tmp_v, Tir.EApp (f, _), body)
    when is_trivial_dec_chain_returning tmp_v.Tir.v_name body ->
    (* Borrow-induced post-DecRC wrapper: the EApp is semantically the tail. *)
    [f.Tir.v_name]
  | Tir.ELet (_, _, body) -> tail_calls_in body
  | Tir.ESeq (_, e2) -> tail_calls_in e2
  | Tir.ECase (_, branches, default_opt) ->
    List.concat_map (fun br -> tail_calls_in br.Tir.br_body) branches
    @ (match default_opt with Some d -> tail_calls_in d | None -> [])
  | Tir.ELetRec (_, body) -> tail_calls_in body
  | _ -> []

(** True if [expr] contains a call to any member of [group] that is NOT in
    tail position.  [in_tail] tracks whether we are currently on a tail path.
    - ELet rhs is non-tail; body inherits [in_tail].
    - ESeq e1 is non-tail; e2 inherits [in_tail].
    - ECase arm bodies inherit [in_tail].
    - ELetRec inner fn bodies: calls there are relative to those fns, not the
      outer function, so we treat them as non-tail for outer-group purposes. *)
let rec has_non_tail_group_call (group : string list) ~(in_tail : bool)
    (expr : Tir.expr) : bool =
  match expr with
  | Tir.EApp (f, _) -> List.mem f.Tir.v_name group && not in_tail
  | Tir.ELet (tmp_v, Tir.EApp (f, _), body)
    when is_trivial_dec_chain_returning tmp_v.Tir.v_name body ->
    (* Borrow-induced post-DecRC wrapper: the EApp is semantically the tail
       call IFF this whole ELet is itself in tail position.  Body contains
       only DecRC/Free ops + the trailing EAtom — no further calls that
       could be non-tail on their own, so once we know the wrapped call is
       disqualifying we don't need to recurse into body.  Mirror the bare
       EApp arm above: a wrapped call to a group member is a non-tail group
       call whenever [in_tail] is false here (e.g. this ELet is the rhs of
       an outer ELet/ESeq).  Before this guard, the wrapped call was always
       treated as the tail call regardless of [in_tail], so a non-tail
       Perceus-wrapped group call could slip a mutual SCC through group
       formation, and the mutual-TCO emission then stranded the
       continuation in a dead block. *)
    (List.mem f.Tir.v_name group && not in_tail)
    || has_non_tail_group_call group ~in_tail body
  | Tir.ELet (_, rhs, body) ->
    has_non_tail_group_call group ~in_tail:false rhs
    || has_non_tail_group_call group ~in_tail body
  | Tir.ESeq (e1, e2) ->
    has_non_tail_group_call group ~in_tail:false e1
    || has_non_tail_group_call group ~in_tail e2
  | Tir.ECase (_, branches, default_opt) ->
    List.exists (fun br -> has_non_tail_group_call group ~in_tail br.Tir.br_body)
      branches
    || (match default_opt with
        | Some d -> has_non_tail_group_call group ~in_tail d
        | None -> false)
  | Tir.ELetRec (fns, body) ->
    (* Calls inside inner local functions are in those functions' own tail
       positions, not the outer function's.  Conservatively block mutual TCO
       if any inner fn non-tail-calls a group member (inner bodies are not the
       outer tail position regardless). *)
    List.exists (fun fn ->
      has_non_tail_group_call group ~in_tail:true fn.Tir.fn_body) fns
    || has_non_tail_group_call group ~in_tail body
  | _ -> false

(** Tarjan's SCC algorithm over the tail-call graph of [fns].
    Returns a list of SCCs, each SCC being a list of fn_names. *)
let tarjan_sccs (fns : Tir.fn_def list) : string list list =
  let fn_names = List.map (fun fn -> fn.Tir.fn_name) fns in
  (* tail-call adjacency: name -> [names tail-called within the module] *)
  let tail_adj = List.map (fun fn ->
    let tcs = tail_calls_in fn.Tir.fn_body in
    let within = List.sort_uniq String.compare
      (List.filter (fun n -> List.mem n fn_names) tcs) in
    (fn.Tir.fn_name, within)
  ) fns in
  let index_ctr = ref 0 in
  let stack     = ref [] in
  let on_stack  = Hashtbl.create 16 in
  let indices   = Hashtbl.create 16 in
  let lowlinks  = Hashtbl.create 16 in
  let sccs      = ref [] in
  let rec strongconnect v =
    let idx = !index_ctr in
    Hashtbl.replace indices  v idx;
    Hashtbl.replace lowlinks v idx;
    incr index_ctr;
    stack := v :: !stack;
    Hashtbl.replace on_stack v true;
    let neighbors = try List.assoc v tail_adj with Not_found -> [] in
    List.iter (fun w ->
      if not (Hashtbl.mem indices w) then begin
        strongconnect w;
        let vll = Hashtbl.find lowlinks v in
        let wll = Hashtbl.find lowlinks w in
        Hashtbl.replace lowlinks v (min vll wll)
      end else if Hashtbl.mem on_stack w then begin
        let vll = Hashtbl.find lowlinks v in
        let widx = Hashtbl.find indices w in
        Hashtbl.replace lowlinks v (min vll widx)
      end
    ) neighbors;
    if Hashtbl.find lowlinks v = Hashtbl.find indices v then begin
      let scc = ref [] in
      let go  = ref true in
      while !go do
        let w = List.hd !stack in
        stack := List.tl !stack;
        Hashtbl.remove on_stack w;
        scc := w :: !scc;
        if String.equal w v then go := false
      done;
      sccs := !scc :: !sccs
    end
  in
  List.iter (fun name ->
    if not (Hashtbl.mem indices name) then strongconnect name
  ) fn_names;
  !sccs

(** Given the full list of top-level functions, return groups of ≥ 2 functions
    that qualify for mutual TCO.  A group qualifies when:
    1. Its functions form a non-trivial SCC in the tail-call graph (size ≥ 2).
    2. No function in the group makes a non-tail call to any other group member.
    3. All functions in the group have the same LLVM return type (required for
       the shared loop to produce one result type). *)
let find_mutual_tco_groups (fns : Tir.fn_def list) : Tir.fn_def list list =
  let fn_map = List.map (fun fn -> (fn.Tir.fn_name, fn)) fns in
  let sccs = tarjan_sccs fns in
  List.filter_map (fun scc ->
    if List.length scc < 2 then None
    else begin
      let group_fns = List.filter_map (fun name ->
        try Some (List.assoc name fn_map) with Not_found -> None) scc in
      let group_names = List.map (fun fn -> fn.Tir.fn_name) group_fns in
      (* All cross-group calls must be tail calls *)
      let all_tail =
        List.for_all (fun fn ->
          not (has_non_tail_group_call group_names ~in_tail:true fn.Tir.fn_body)
        ) group_fns
      in
      (* All functions must have the same LLVM return type *)
      let ret_tys = List.map (fun fn -> Llvm_ctx.llvm_ret_ty fn.Tir.fn_ret_ty) group_fns in
      let all_same_ret = match ret_tys with
        | [] | [_] -> true
        | h :: t   -> List.for_all (String.equal h) t
      in
      if all_tail && all_same_ret then Some group_fns
      else None
    end
  ) sccs

(* ── Mutual TCO: combined function name ─────────────────────────────── *)

(** Stable mangled name for the combined function of a mutual-TCO group. *)
let mutual_tco_combined_name (group : Tir.fn_def list) : string =
  "__mutco_" ^
  String.concat "_" (List.map (fun fn -> Llvm_ctx.llvm_name fn.Tir.fn_name) group) ^
  "__"

(* ── TCO helper ──────────────────────────────────────────────────────── *)

(** Return true if [expr] contains a tail-position call to [fn_name].
    Only traverses sub-expressions that are in tail position:
    - ELet body (not rhs)
    - ESeq: second operand, or first operand when the first is a self-call
      followed only by RC cleanup (borrow inference may emit
      ESeq(EApp(self,...), EDecRC(arg)) — the EDecRC lands in dead code
      after TCO emits the back-edge, so it is safe to treat e1 as a tail call)
    - ECase branch bodies and default
    - ELetRec body
    A bare EApp whose callee name matches is a tail call. *)
let rec has_self_tail_call (fn_name : string) (expr : Tir.expr) : bool =
  match expr with
  | Tir.EApp (f, _) -> String.equal f.Tir.v_name fn_name
  | Tir.ELet (tmp_v, Tir.EApp (f, _), body)
    when String.equal f.Tir.v_name fn_name
         && is_trivial_dec_chain_returning tmp_v.Tir.v_name body ->
    (* Borrow-induced post-DecRC wrapper around a self call.  Recognise it
       so TCO sees the call.  (Self calls usually keep ESeq form via the
       is_self_call branch in perceus.ml, but the ELet form arises when the
       call is via an indirect alias.) *)
    true
  | Tir.ELet (_, _, body) -> has_self_tail_call fn_name body
  | Tir.ESeq (e1, e2) ->
    has_self_tail_call fn_name e2 ||
    has_self_tail_call fn_name e1
  | Tir.ECase (_, branches, default_opt) ->
    List.exists (fun br -> has_self_tail_call fn_name br.Tir.br_body) branches ||
    (match default_opt with Some d -> has_self_tail_call fn_name d | None -> false)
  | Tir.ELetRec (_, body) -> has_self_tail_call fn_name body
  | _ -> false

(* ── Mutual TCO: combined function emitter ───────────────────────────── *)

(** Emit the combined dispatch function and per-function wrapper stubs for
    [group].  After this call the caller must NOT emit any of the original
    [group] functions via [emit_fn] — the wrappers have been emitted here.

    Combined function layout:
      define RET @__mutco_f_g__(i64 %__tag__.arg,
                                Tf1 %f__p1.arg, ...,
                                Tg1 %g__p1.arg, ...) {
      entry:
        alloca tag_slot, param_slots ...
        br %mutual_loop
      mutual_loop:
        %tag = load tag_slot
        switch tag [ 0 -> case_f, 1 -> case_g, ... ]
      case_f:   ; f's body, mutual calls become: store tag+args → br loop
      case_g:   ; g's body, mutual calls become: store tag+args → br loop
      dead:
        unreachable
      }

    Wrapper for f:
      define RET @f(Tf1 %p1, ...) {
        %r = call RET @__mutco__(0, p1, ..., undef, ...)
        ret RET %r
      }

    [emit_expr] is threaded in as a labeled callback (de-cycling move, same
    pattern as [Llvm_case.emit_case] in Task 5): case bodies are [Tir.expr]
    and recurse into the top-level expression emitter, which stays in
    [llvm_emit.ml]. *)
let emit_mutual_tco_group ~emit_expr ctx (group : Tir.fn_def list) =
  (* Reset naming state for this combined function — same as emit_fn does at
     the top of each function, but here we do it once for the whole group so
     that local_names accumulates across all case bodies and never resets mid-
     function, which would produce duplicate %name.addr alloca definitions. *)
  Hashtbl.clear ctx.Llvm_ctx.local_names;
  Hashtbl.clear ctx.Llvm_ctx.var_slot;
  Hashtbl.clear ctx.Llvm_ctx.var_llvm_ty;
  let group_names = List.map (fun fn -> fn.Tir.fn_name) group in
  let combined    = mutual_tco_combined_name group in
  let ret_ty      = Llvm_ctx.llvm_ret_ty (List.hd group).Tir.fn_ret_ty in

  (* Assign integer dispatch tags in list order. *)
  let fn_tags = List.mapi (fun i fn -> (fn.Tir.fn_name, i)) group in

  (* Build a flat list of (fn_name, var, combined_slot_base) for ALL params.
     Each param slot is prefixed with the owning function's mangled name to
     avoid collisions between functions with identically-named parameters. *)
  let all_params : (string * Tir.var * string) list =
    List.concat_map (fun fn ->
      List.map (fun (v : Tir.var) ->
        let base = Llvm_ctx.llvm_name fn.Tir.fn_name ^ "__" ^ Llvm_ctx.llvm_name v.Tir.v_name in
        (fn.Tir.fn_name, v, base)
      ) fn.Tir.fn_params
    ) group
  in

  (* ── Emit the combined function definition ───────────────────────── *)
  let tag_param_str = "i64 %__tag__.arg" in
  let rest_params_str =
    if all_params = [] then ""
    else ", " ^ String.concat ", "
      (List.map (fun (_, (v : Tir.var), base) ->
        Printf.sprintf "%s %%%s.arg" (Llvm_ctx.llvm_param_ty ~type_defs:ctx.Llvm_ctx.type_defs ~collision_set:ctx.Llvm_ctx.collision_set v.Tir.v_ty) base
      ) all_params)
  in
  let mutco_vis = if ctx.Llvm_ctx.compile_so then "hidden " else "" in
  Buffer.add_string ctx.Llvm_ctx.buf
    (Printf.sprintf "\ndefine %s%s @%s(%s%s) {\nentry:\n"
       mutco_vis ret_ty (Llvm_ctx.llvm_name combined) tag_param_str rest_params_str);

  (* Alloca the dispatch tag slot. *)
  let tag_slot = "mutco_tag" in
  Llvm_ctx.emit ctx (Printf.sprintf "%%%s.addr = alloca i64" tag_slot);
  Llvm_ctx.emit ctx (Printf.sprintf "store i64 %%__tag__.arg, ptr %%%s.addr" tag_slot);

  (* Alloca each parameter slot and store the incoming arg.

     SIMD note: a vector-typed parameter threaded through a MUTUAL-recursion
     group keeps its uniform boxed `ptr` slot here (llvm_ty of the vector
     type), unlike emit_fn's self-TCO path which promotes it to a raw
     <N x T> register slot. That is correct, just unaccelerated: the group
     boxes/unboxes the vector on every call, exactly as it did before the
     self-TCO residency optimization landed. Recorded in
     docs/simd-vectorization.md's "Known limits"; no todo — pinned wontfix-
     until-demand, not gap-in-waiting: test/native/simd_mutual_tco.march
     (+ test/dune rule) asserts the boxed path still produces the correct
     numeric result, so a future change to the mutual-TCO slot strategy
     can't silently corrupt it. See the closeouts spec at
     specs/progress/2026-08-13-simd-closeouts-task3-mutual-tco-pin.md. *)
  let fn_param_slots : (string * (string * string * string) list) list =
    List.map (fun fn ->
      let slots = List.map (fun (v : Tir.var) ->
        let base = Llvm_ctx.llvm_name fn.Tir.fn_name ^ "__" ^ Llvm_ctx.llvm_name v.Tir.v_name in
        let ty   = Llvm_ctx.llvm_ty v.Tir.v_ty in
        Llvm_ctx.emit ctx (Printf.sprintf "%%%s.addr = alloca %s" base ty);
        Llvm_ctx.emit ctx (Printf.sprintf "store %s %%%s.arg, ptr %%%s.addr" ty base base);
        Hashtbl.replace ctx.Llvm_ctx.var_llvm_ty base ty;
        (v.Tir.v_name, base, ty)
      ) fn.Tir.fn_params in
      (fn.Tir.fn_name, slots)
    ) group
  in

  (* Jump to loop header. *)
  let loop_lbl = Llvm_ctx.fresh_block ctx "mutual_loop" in
  Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" loop_lbl);
  Llvm_ctx.emit_label ctx loop_lbl;

  (* Phase 4: decrement the reduction budget at every loop iteration, exactly
     as emit_fn's self-TCO path does at the top of tco_loop. A mutual-TCO
     group is never leaf (each member tail-calls another group member), so a
     pure mutually-recursive loop (e.g. is_even/is_odd) would otherwise never
     yield back to the scheduler and would monopolize its worker forever. *)
  Llvm_ctx.emit_reduction_check ctx;

  (* Snapshot the stack pointer at the top of each iteration — see
     tco_stack_save's doc comment for why this is required. Every case body's
     back-edge restores to this point before re-entering the loop header. *)
  let mutual_stack_save = Llvm_ctx.fresh ctx "mutco_sp.save" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = call ptr @llvm.stacksave()" mutual_stack_save);

  (* Load the dispatch tag and emit a switch. *)
  let tag_v    = Llvm_ctx.fresh ctx "mutco_tag_v" in
  let dead_lbl = Llvm_ctx.fresh_block ctx "mutco_dead" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = load i64, ptr %%%s.addr" tag_v tag_slot);

  let case_labels = List.map (fun fn ->
    let lbl = Llvm_ctx.fresh_block ctx ("mutco_case_" ^ Llvm_ctx.llvm_name fn.Tir.fn_name) in
    (fn, lbl)
  ) group in

  let switch_entries = String.concat " "
    (List.map2 (fun (fn, lbl) (_, tag_int) ->
      Printf.sprintf "i64 %d, label %%%s" tag_int lbl
      |> (fun s -> ignore fn; s)
    ) case_labels fn_tags)
  in
  Llvm_ctx.emit ctx (Printf.sprintf "switch i64 %s, label %%%s [ %s ]"
    tag_v dead_lbl switch_entries);

  (* Install mutual TCO context.  The EApp handler uses this to redirect
     tail calls to group members back to the loop header. *)
  ctx.Llvm_ctx.mutual_tco_group      <- group_names;
  ctx.Llvm_ctx.mutual_tco_tag_slot   <- tag_slot;
  ctx.Llvm_ctx.mutual_tco_loop_label <- loop_lbl;
  ctx.Llvm_ctx.mutual_tco_fn_params  <- fn_param_slots;
  ctx.Llvm_ctx.mutual_tco_fn_tags    <- fn_tags;
  ctx.Llvm_ctx.mutual_tco_stack_save <- mutual_stack_save;

  (* Emit each case body. *)
  List.iter (fun (fn, case_lbl) ->
    Llvm_ctx.emit_label ctx case_lbl;
    (* Reset per-case variable environment but NOT local_names: all case bodies
       live inside the same LLVM function, so alloca name uniquification must
       persist across case bodies to prevent duplicate %name.addr definitions. *)
    Hashtbl.clear ctx.Llvm_ctx.var_slot;
    Hashtbl.clear ctx.Llvm_ctx.var_llvm_ty;
    let fn_slots = List.assoc fn.Tir.fn_name fn_param_slots in
    List.iter (fun (vname, slot, ty) ->
      Hashtbl.replace ctx.Llvm_ctx.var_slot    vname slot;
      Hashtbl.replace ctx.Llvm_ctx.var_llvm_ty slot   ty
    ) fn_slots;
    (* Re-populate var_llvm_ty for all group slots (needed if a case body
       loads another group member's slot via a phi / load path). *)
    List.iter (fun (_, slots) ->
      List.iter (fun (_, slot, ty) ->
        Hashtbl.replace ctx.Llvm_ctx.var_llvm_ty slot ty
      ) slots
    ) fn_param_slots;
    ctx.Llvm_ctx.ret_ty <- fn.Tir.fn_ret_ty;
    let (body_ty, body_val) = emit_expr ctx fn.Tir.fn_body in
    if ret_ty = "void" then
      Llvm_ctx.emit_term ctx "ret void"
    else begin
      let final_val = Llvm_ctx.coerce ctx body_ty body_val ret_ty in
      Llvm_ctx.emit_term ctx (Printf.sprintf "ret %s %s" ret_ty final_val)
    end
  ) case_labels;

  (* Dead / unreachable default arm. *)
  Llvm_ctx.emit_label ctx dead_lbl;
  Llvm_ctx.emit ctx "unreachable";

  Buffer.add_string ctx.Llvm_ctx.buf "}\n";

  (* Clear mutual TCO context. *)
  ctx.Llvm_ctx.mutual_tco_group <- [];
  ctx.Llvm_ctx.mutual_tco_stack_save <- "";

  (* ── Emit wrapper functions ──────────────────────────────────────── *)
  (* Each original function name becomes a thin wrapper that sets the
     dispatch tag and calls the combined function. *)
  List.iter (fun fn ->
    let tag_int     = List.assoc fn.Tir.fn_name fn_tags in
    let fn_llvm     = Llvm_builtins.mangle_extern fn.Tir.fn_name in
    let params_str  = String.concat ", "
      (List.map (fun (v : Tir.var) ->
        Printf.sprintf "%s %%%s.arg" (Llvm_ctx.llvm_param_ty ~type_defs:ctx.Llvm_ctx.type_defs ~collision_set:ctx.Llvm_ctx.collision_set v.Tir.v_ty) (Llvm_ctx.llvm_name v.Tir.v_name)
      ) fn.Tir.fn_params)
    in
    let wrap_vis =
      let fname = fn.Tir.fn_name in
      let flen  = String.length fname in
      let ends_with sfx =
        let sl = String.length sfx in
        flen > sl && String.sub fname (flen - sl) sl = sfx
      in
      if ctx.Llvm_ctx.compile_so
         && not (Tir_names.is_actor_dispatch_fn fname)
         && not (ends_with "_migrate_state")
      then "hidden " else ""
    in
    Buffer.add_string ctx.Llvm_ctx.buf
      (Printf.sprintf "\ndefine %s%s @%s(%s) {\nentry:\n" wrap_vis ret_ty fn_llvm params_str);

    (* Build the call arguments: tag first, then ALL params of ALL group fns.
       For this function's own params, pass the incoming arg.
       For other functions' params, pass undef (they will not be read). *)
    let call_args =
      Printf.sprintf "i64 %d" tag_int ^
      (if all_params = [] then ""
       else ", " ^ String.concat ", "
         (List.map (fun (owner_fn, (v : Tir.var), base) ->
           let ty = Llvm_ctx.llvm_ty v.Tir.v_ty in
           if String.equal owner_fn fn.Tir.fn_name then
             Printf.sprintf "%s %%%s.arg" ty (Llvm_ctx.llvm_name v.Tir.v_name)
           else
             Printf.sprintf "%s undef" ty
           |> (fun s -> ignore base; s)
         ) all_params))
    in
    let result_v = Llvm_ctx.fresh ctx "mutco_wr" in
    if ret_ty = "void" then begin
      Llvm_ctx.emit ctx (Printf.sprintf "call void @%s(%s)" (Llvm_ctx.llvm_name combined) call_args);
      Llvm_ctx.emit_term ctx "ret void"
    end else begin
      Llvm_ctx.emit ctx (Printf.sprintf "%s = call %s @%s(%s)"
        result_v ret_ty (Llvm_ctx.llvm_name combined) call_args);
      Llvm_ctx.emit_term ctx (Printf.sprintf "ret %s %s" ret_ty result_v)
    end;
    Buffer.add_string ctx.Llvm_ctx.buf "}\n"
  ) group
