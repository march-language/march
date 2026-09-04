(** Escape Analysis — Pass 5.

    Stack-promotes heap allocations whose lifetimes are provably bounded
    to the current function's stack frame.  An EAlloc that does not escape
    is replaced with EStackAlloc, and dead RC ops on stack-allocated
    variables are removed.

    ── Promotion through a borrowed callee (2026-09-03) ──────────────────

    The verdict used to stop at every call boundary: passing a value as ANY
    argument of ANY call marked it escaping.  That is right for a callee that
    might keep the value, and wrong for one that only reads it — which is
    precisely the question [Borrow.infer_module] already answers.

    [Borrow]'s fixpoint calls a use OWNING when the value is returned, stored
    into a constructor / tuple / record, captured by an escaping closure,
    passed through an unknown callee ([ECallPtr]) or handed to an owned
    parameter of a known one; everything else (an [ECase] scrutinee, an
    [EField] source, an argument at another function's borrowed position) is
    BORROWING.  So [Borrow.is_borrowed bm f i] = "f neither consumes nor
    retains argument i" — exactly the property a stack cell needs from a
    callee, and the reason this pass can now see through such a call.

    ── Why the borrow verdict alone is not enough ────────────────────────

    [Borrow] answers an OWNERSHIP question ("who releases the reference"),
    which is strictly stronger than the one stack promotion needs ("can the
    pointer outlive the call").  Its [field_escape_owns] rule marks a
    parameter owned as soon as any field extracted from it is used in an
    owning position — including a scalar field handed to an ordinary builtin,
    because [is_borrowed] has no entry for `+`:

    {v
      pfn sum5(b : Big) : Int do
        match b do Big(a, c, d, e, f) -> a + c + d + e + f end
      end                                        -- inferred b:own
    v}

    That rule is load-bearing for ownership (an extracted HEAP field that
    escapes without an inc is an RC underflow), but it says nothing about
    where [b]'s POINTER went — it went nowhere.  Worse, being inferred owned
    is what makes Perceus emit a [dec_rc] on the parameter inside the callee,
    and a stack cell has [rc = 0] — so an owned callee does not merely fail to
    clear the value, it would free a stack address if promoted anyway.

    Measured over the 43 programs in [bench/]: taking the borrow verdict alone
    promotes NOTHING (0 stack cells, the same as before this extension); the
    retention answer below promotes 36 (in `array_numeric`, `dataframe_bench`,
    `rrb_bench`, `simd_map`, `simd_sum` and `string_parallel_scan`).

    So the verdict here is the disjunction of two answers:

    - [Borrow.is_borrowed] — the ownership fixpoint, as the design called for;
    - [may_retain] below — a purpose-built, narrower question: does the callee
      put the POINTER it received anywhere that outlives the call?  Storing it
      in a cell, returning it, capturing it in a closure, sending it through an
      unknown callee or an extern, or reference-counting/freeing it all count.
      Destructuring it, reading a field, and passing it on to a non-retaining
      local callee do not.  A field extracted from a stack cell is a copy: the
      cell's address never leaves, which is the whole property being proved.

    The first implies the second (an owning use in [Borrow]'s sense is always
    one of the retaining shapes), so the disjunction is really just the second
    — it is written as a disjunction so the design's stated criterion is
    visibly still honoured rather than quietly replaced.

    Three deliberate restrictions on the extension.  The first is about the
    VALUE; the other two are about who can be held to the contract:

    - **Never a closure struct** ([clo_candidates]).  A [$Clo_] cell handed to
      its own apply function is governed by a separate protocol:
      [Borrow.infer_module] PINS an apply function's [$clo] parameter owned,
      and [Perceus.insert_apply_fn_clo_drop] emits a [dec_rc $clo] inside the
      callee on the strength of that pin.  A stack cell's header says [rc = 0]
      ([Llvm_data.emit_stack_alloc] zeroes it), so that decrement underflows —
      and a capture-free closure is additionally something [Llvm_emit] already
      turns into ONE immortal global ([static_closure_ok]), which a stack cell
      would be a pessimisation of, not an improvement on.  Closure structs
      keep the pre-existing promotion rules (a dead binding may still be
      promoted); only clearing them THROUGH A CALL is excluded.

    - **March-defined callees only**.  [Borrow.is_borrowed]
      falls back to a hardcoded ABI table for C externs and runtime builtins,
      where "borrowed" is a DECLARATION about C code this pass cannot read.  A
      stack cell handed to C is a pointer whose header says [rc = 0]
      ([emit_stack_alloc] zeroes it), so a single stray [march_incrc] /
      [march_decrc] pair inside the C function would free a stack address.
      The fixpoint's verdict about a March function is derived from its body
      and carries no such risk.
    - **A borrow map must be supplied.**  It defaults to [Borrow.empty], under
      which [is_borrowed] answers false for every March function and the pass
      behaves exactly as it did before.  A caller that assembles its own pass
      list and does not pass one (the REPL) simply keeps the old, narrower
      verdict.  The map MUST be the one [Perceus] consumed — computed on the
      pre-Perceus module — because Perceus placed its RC ops against that
      answer; deriving a fresh one here, from a module that now carries those
      ops, could disagree with it. *)

module StringSet = Set.Make (String)

(* ── Helpers ──────────────────────────────────────────────────────────────── *)

let vars_of_atom : Tir.atom -> StringSet.t = function
  | Tir.AVar v -> StringSet.singleton v.Tir.v_name
  | Tir.ADefRef _ -> StringSet.empty  (* global/static ref, no local vars *)
  | Tir.ALit _ -> StringSet.empty

let vars_of_atoms (atoms : Tir.atom list) : StringSet.t =
  List.fold_left (fun s a -> StringSet.union s (vars_of_atom a))
    StringSet.empty atoms

(** Collect all variable names that appear in any atom position of [e].
    Used to conservatively mark captures in ELetRec inner functions. *)
let rec all_atom_vars (e : Tir.expr) : StringSet.t =
  match e with
  | Tir.EAtom a -> vars_of_atom a
  | Tir.EApp (f, args) ->
    StringSet.add f.Tir.v_name (vars_of_atoms args)
  | Tir.ECallPtr (a, args) ->
    StringSet.union (vars_of_atom a) (vars_of_atoms args)
  | Tir.ELet (_, e1, e2) ->
    StringSet.union (all_atom_vars e1) (all_atom_vars e2)
  | Tir.ELetRec (fns, body) ->
    List.fold_left (fun acc fn ->
      StringSet.union acc (all_atom_vars fn.Tir.fn_body)
    ) (all_atom_vars body) fns
  | Tir.ECase (a, branches, default) ->
    let from_a = vars_of_atom a in
    let from_branches =
      List.fold_left (fun acc br ->
        StringSet.union acc (all_atom_vars br.Tir.br_body)
      ) StringSet.empty branches
    in
    let from_default = match default with
      | Some d -> all_atom_vars d
      | None -> StringSet.empty
    in
    StringSet.union from_a (StringSet.union from_branches from_default)
  | Tir.ESeq (e1, e2) ->
    StringSet.union (all_atom_vars e1) (all_atom_vars e2)
  | Tir.ETuple atoms | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) ->
    vars_of_atoms atoms
  | Tir.ERecord fields ->
    vars_of_atoms (List.map snd fields)
  | Tir.EField (a, _) -> vars_of_atom a
  | Tir.EUpdate (a, fields) ->
    StringSet.union (vars_of_atom a) (vars_of_atoms (List.map snd fields))
  | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a
  | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a -> vars_of_atom a
  | Tir.EReuse (a, _, args) ->
    StringSet.union (vars_of_atom a) (vars_of_atoms args)
  | Tir.EAllocHole (tok, _, args, _) ->
    StringSet.union
      (match tok with Some a -> vars_of_atom a | None -> StringSet.empty)
      (vars_of_atoms args)
  | Tir.ESetField (o, _, v) ->
    StringSet.union (vars_of_atom o) (vars_of_atom v)

(* ── Phase 1: Collect EAlloc candidates ──────────────────────────────────── *)

(** True iff an [EAlloc ty] actually emits a heap cell.  A Newtype- or
    Niche-repr "alloc" emits NO cell at all — [llvm_emit.ml]'s EAlloc arm
    lowers it to a tagged/raw IMMEDIATE ((v<<1)|1 for a scalar payload,
    the raw pointer otherwise).  Stack-promoting such an alloc forces a
    boxed stack cell whose every consumer still decodes under the erased
    convention (an ECase on a Newtype untags the raw pointer → garbage =
    address>>1; slice-7 finding L7, `let c = R(22); match c ...` printed
    nondeterministic junk compiled).  Promotion of an erased alloc is also
    a strict pessimization even where it happens to be read back boxed —
    the unpromoted form is a register-sized immediate.

    The niche check mirrors llvm_emit's own EAlloc arm: [repr_of_ty] on a
    param-less ctor key returns [Boxed] for Option-shaped types, so the
    emitter guards separately with [is_niche_shaped] — as must we.  The
    ctor key is "TypeName.CtorName"; derive the type name the same way.

    [collision_set] (Task 2): must be threaded through to [Repr.repr_of_ty]/
    [Repr.is_niche_shaped] so a same-short-name colliding type is classified
    exactly as [llvm_emit.ml]'s EAlloc arm will classify it (forced Boxed).
    Without it, this function — using the default empty table — would
    classify a colliding niche-shaped type as "no heap cell" (Niche/Newtype)
    while codegen actually allocates a Boxed cell for it, so
    [collect_alloc_candidates] would mark its binding a stack-promotion
    candidate for a value that is really heap-allocated: an escape-analysis/
    codegen repr split, not merely a missed optimization. *)
let alloc_emits_heap_cell
    ?(collision_set : (string, string list) Hashtbl.t = Hashtbl.create 0)
    (type_defs : Tir.type_def list) (ty : Tir.ty) : bool =
  match ty with
  | Tir.TCon (ctor, _) ->
    let type_name = match String.rindex_opt ctor '.' with
      | Some i -> String.sub ctor 0 i
      | None -> ctor
    in
    (match Repr.repr_of_ty ~collision_set type_defs (Tir.TCon (type_name, [])) with
     | Repr.Newtype _ | Repr.Niche _ -> false
     (* Milestone 3: an unboxed aggregate's "alloc" is an [insertvalue] chain,
        no cell at all — the same reason Newtype/Niche return false here.
        Promoting one would force a boxed stack cell whose consumers all decode
        it as a struct value. *)
     | Repr.Unboxed _ -> false
     | Repr.Boxed -> not (Repr.is_niche_shaped ~collision_set type_defs type_name))
  | _ -> true

(** Names of variables bound to an [EAlloc] of a CLOSURE struct.  These are
    excluded from the through-a-call clearance — see the module doc's first
    restriction.  Same walk as [collect_alloc_candidates]. *)
let rec collect_clo_candidates (e : Tir.expr) : StringSet.t =
  match e with
  | Tir.ELet (v, Tir.EAlloc (Tir.TCon (c, _), _), body)
    when Tir_names.is_clo_struct c ->
    StringSet.add v.Tir.v_name (collect_clo_candidates body)
  | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) ->
    StringSet.union (collect_clo_candidates e1) (collect_clo_candidates e2)
  | Tir.ELetRec (_, body) -> collect_clo_candidates body
  | Tir.ECase (_, branches, default) ->
    let from_branches =
      List.fold_left (fun acc br ->
          StringSet.union acc (collect_clo_candidates br.Tir.br_body))
        StringSet.empty branches in
    (match default with
     | Some d -> StringSet.union from_branches (collect_clo_candidates d)
     | None -> from_branches)
  | _ -> StringSet.empty

(** Walk [e] and collect names of variables bound directly to an EAlloc that
    really allocates (see [alloc_emits_heap_cell]).
    Does not descend into ELetRec inner function bodies (separate scopes). *)
let rec collect_alloc_candidates
    ?(collision_set : (string, string list) Hashtbl.t = Hashtbl.create 0)
    (type_defs : Tir.type_def list)
    (e : Tir.expr) : StringSet.t =
  match e with
  | Tir.ELet (v, Tir.EAlloc (ty, _), body)
    when alloc_emits_heap_cell ~collision_set type_defs ty ->
    StringSet.add v.Tir.v_name (collect_alloc_candidates ~collision_set type_defs body)
  | Tir.ELet (_, e1, e2) ->
    StringSet.union (collect_alloc_candidates ~collision_set type_defs e1)
      (collect_alloc_candidates ~collision_set type_defs e2)
  | Tir.ELetRec (_, body) ->
    (* Inner fn bodies are separate scopes; only collect from the outer body *)
    collect_alloc_candidates ~collision_set type_defs body
  | Tir.ECase (_, branches, default) ->
    let from_branches =
      List.fold_left (fun acc br ->
        StringSet.union acc (collect_alloc_candidates ~collision_set type_defs br.Tir.br_body)
      ) StringSet.empty branches
    in
    let from_default = match default with
      | Some d -> collect_alloc_candidates ~collision_set type_defs d
      | None -> StringSet.empty
    in
    StringSet.union from_branches from_default
  | Tir.ESeq (e1, e2) ->
    StringSet.union (collect_alloc_candidates ~collision_set type_defs e1)
      (collect_alloc_candidates ~collision_set type_defs e2)
  | _ -> StringSet.empty

(* ── Callee retention analysis ───────────────────────────────────────────── *)

(** Does parameter [i] of local function [f] put the POINTER it receives
    somewhere that outlives the call?  See the module doc for why this exists
    alongside [Borrow.is_borrowed] and how the two differ.

    A least fixpoint over the call graph: start with nothing retained and
    propagate retention until stable.  The retaining shapes, and the argument
    for each:

    - [EAtom (AVar p)] — returned to the caller;
    - [EAlloc] / [EStackAlloc] / [ETuple] / [ERecord] / [EUpdate] /
      [EAllocHole] / [ESetField] — stored into something with its own
      lifetime.  A closure capture is an [EAlloc] of a [$Clo_] struct and is
      caught by the same arm;
    - [ECallPtr] in either position — an unknown callee;
    - [EApp] to anything NOT defined in this module (an extern, a runtime
      builtin such as [send], [task_spawn] or a [Vault] operation) — this pass
      cannot read that code;
    - [EApp] to a local function at a parameter this analysis already marks
      retaining;
    - [EIncRC] / [EAtomicIncRC] — someone is taking a longer-lived reference;
    - [EDecRC] / [EAtomicDecRC] / [EFree] — worse than retention: a stack cell
      has [rc = 0] ([Llvm_data.emit_stack_alloc] zeroes the header), so a
      decrement would underflow and hand a stack address to [free].

    - an [EReuse] token — [Llvm_emit_alloc]'s arm reads the cell's refcount and
      decrements it on the shared path, which is the rc = 0 hazard again.

    Non-retaining, and each is the point of the analysis: an [ECase] scrutinee
    and an [EField] source.  A field read out of the cell is a COPY; where that
    copy then goes is a question about the FIELD's lifetime, not about the
    cell's address. *)
let may_retain_table (m : Tir.tir_module) : (string, bool array) Hashtbl.t =
  let local = Hashtbl.create (List.length m.Tir.tm_fns) in
  List.iter (fun (fd : Tir.fn_def) -> Hashtbl.replace local fd.Tir.fn_name ())
    m.Tir.tm_fns;
  let tbl = Hashtbl.create (List.length m.Tir.tm_fns) in
  List.iter (fun (fd : Tir.fn_def) ->
      Hashtbl.replace tbl fd.Tir.fn_name
        (Array.make (List.length fd.Tir.fn_params) false))
    m.Tir.tm_fns;
  let retains_param f i =
    match Hashtbl.find_opt tbl f with
    | Some a -> i < Array.length a && a.(i)
    (* Not defined here: an extern or a runtime builtin.  Conservatively
       retaining — see the module doc's first restriction. *)
    | None -> true
  in
  (* [names]: the tracked variable and every pure alias of it in scope. *)
  let rec retained (names : StringSet.t) (e : Tir.expr) : bool =
    let hits a = match a with
      | Tir.AVar v -> StringSet.mem v.Tir.v_name names
      | _ -> false in
    let any = List.exists hits in
    match e with
    | Tir.EAtom a -> hits a
    | Tir.EAlloc (_, args) | Tir.EStackAlloc (_, args) | Tir.ETuple args -> any args
    | Tir.ERecord fields -> any (List.map snd fields)
    | Tir.EUpdate (base, fields) -> hits base || any (List.map snd fields)
    | Tir.EAllocHole (tok, _, args, _) ->
      (match tok with Some a -> hits a | None -> false) || any args
    | Tir.ESetField (o, _, v) -> hits o || hits v
    | Tir.ECallPtr (a, args) -> hits a || any args
    | Tir.EApp (f, args) ->
      let fname = f.Tir.v_name in
      StringSet.mem fname names
      || list_any_idx (fun i a -> hits a && retains_param fname i) args
    | Tir.EIncRC a | Tir.EAtomicIncRC a
    | Tir.EDecRC a | Tir.EAtomicDecRC a | Tir.EFree a -> hits a
    | Tir.EField (a, _) -> ignore a; false
    (* The REUSE TOKEN is not a read: [Llvm_emit_alloc]'s EReuse arm checks the
       cell's refcount and, on the shared path, decrements it and allocates a
       fresh one.  A stack cell's header says rc = 0, so that decrement would
       underflow and free a stack address — the same reason the RC ops below
       count. *)
    | Tir.EReuse (tok, _, args) -> hits tok || any args
    (* A pure alias carries the same pointer forward; track it too. *)
    | Tir.ELet (v, Tir.EAtom (Tir.AVar src), body)
      when StringSet.mem src.Tir.v_name names ->
      retained (StringSet.add v.Tir.v_name names) body
    | Tir.ELet (v, e1, e2) ->
      retained names e1
      || retained (StringSet.remove v.Tir.v_name names) e2
    | Tir.ELetRec (fns, body) ->
      retained names body
      || List.exists (fun fn ->
          let shadowed =
            List.exists (fun p -> StringSet.mem p.Tir.v_name names) fn.Tir.fn_params in
          not shadowed && retained names fn.Tir.fn_body) fns
    | Tir.ECase (_, branches, default) ->
      List.exists (fun br ->
          let bound =
            List.fold_left (fun acc (bv : Tir.var) -> StringSet.remove bv.Tir.v_name acc)
              names br.Tir.br_vars in
          retained bound br.Tir.br_body) branches
      || (match default with Some d -> retained names d | None -> false)
    | Tir.ESeq (e1, e2) -> retained names e1 || retained names e2
  and list_any_idx f xs =
    let rec go i = function
      | [] -> false
      | x :: t -> if f i x then true else go (i + 1) t
    in go 0 xs
  in
  let rec fix () =
    let changed = ref false in
    List.iter (fun (fd : Tir.fn_def) ->
        match Hashtbl.find_opt tbl fd.Tir.fn_name with
        | None -> ()
        | Some modes ->
          List.iteri (fun i (p : Tir.var) ->
              if not modes.(i)
              && retained (StringSet.singleton p.Tir.v_name) fd.Tir.fn_body
              then begin modes.(i) <- true; changed := true end)
            fd.Tir.fn_params)
      m.Tir.tm_fns;
    if !changed then fix ()
  in
  ignore local;
  fix ();
  tbl

(** True iff [f] is defined in this module and provably does not retain the
    pointer passed at parameter [i]. *)
let callee_cannot_retain (tbl : (string, bool array) Hashtbl.t)
    (f : string) (i : int) : bool =
  match Hashtbl.find_opt tbl f with
  | Some a -> i < Array.length a && not a.(i)
  | None -> false

(* ── Phase 2: Escape check ────────────────────────────────────────────────── *)

(** Returns the subset of [candidates] that appear in escaping atom positions
    within [e].

    [borrow_map] / [retain_tbl]: see the module doc.  An [EApp] argument on a
    callee defined in this module is NOT an escaping position when either
    answer clears it. *)
let rec escaping_vars ?(borrow_map = Borrow.empty)
    ?(retain_tbl : (string, bool array) Hashtbl.t = Hashtbl.create 0)
    ?(clo_candidates = StringSet.empty)
    (e : Tir.expr) (candidates : StringSet.t) : StringSet.t =
  let escaping_vars ?(borrow_map = borrow_map) ?(retain_tbl = retain_tbl)
      ?(clo_candidates = clo_candidates) e c =
    escaping_vars ~borrow_map ~retain_tbl ~clo_candidates e c in
  let candidate_atom a =
    match a with
    | Tir.AVar v when StringSet.mem v.Tir.v_name candidates ->
      StringSet.singleton v.Tir.v_name
    | _ -> StringSet.empty
  in
  let candidate_atoms atoms =
    List.fold_left (fun acc a -> StringSet.union acc (candidate_atom a))
      StringSet.empty atoms
  in
  match e with
  (* Tail atom return — escapes *)
  | Tir.EAtom a -> candidate_atom a

  (* Passed as a function call argument — escapes UNLESS the callee is a
     March function this module defines and the borrow fixpoint proved that
     parameter borrowed (see the module doc). *)
  | Tir.EApp (f, args) ->
    (* f is a var, not an atom; check if it's a candidate (used as closure) *)
    let fn_esc =
      if StringSet.mem f.Tir.v_name candidates
      then StringSet.singleton f.Tir.v_name
      else StringSet.empty
    in
    let callee = f.Tir.v_name in
    let callee_is_local = Hashtbl.mem retain_tbl callee in
    let arg_esc =
      List.fold_left (fun (i, acc) a ->
          let is_clo = match a with
            | Tir.AVar v -> StringSet.mem v.Tir.v_name clo_candidates
            | _ -> false in
          let cleared =
            callee_is_local && not is_clo
            && (Borrow.is_borrowed borrow_map callee i
                || callee_cannot_retain retain_tbl callee i)
          in
          let acc =
            if cleared then acc else StringSet.union acc (candidate_atom a) in
          (i + 1, acc))
        (0, StringSet.empty) args
      |> snd
    in
    StringSet.union fn_esc arg_esc

  | Tir.ECallPtr (a, args) ->
    (* a may be a closure — check both the fn ptr and all args *)
    StringSet.union (candidate_atom a) (candidate_atoms args)

  (* Stored into a heap allocation — escapes *)
  | Tir.EAlloc (_, args) -> candidate_atoms args

  (* Stored into stack alloc args (conservative; treat like EAlloc) *)
  | Tir.EStackAlloc (_, args) -> candidate_atoms args

  (* Stored via FBIP reuse: the reuse token (first atom) does NOT escape;
     the constructor args do *)
  | Tir.EReuse (_, _, args) -> candidate_atoms args

  (* Stored in a tuple — escapes *)
  | Tir.ETuple atoms -> candidate_atoms atoms

  (* Stored in a record — escapes *)
  | Tir.ERecord fields -> candidate_atoms (List.map snd fields)

  (* Stored in a functional update's new field values — escapes *)
  | Tir.EUpdate (_, fields) -> candidate_atoms (List.map snd fields)

  (* ELet: check RHS (which may itself be a tail atom, call, etc.) and body *)
  | Tir.ELet (_, e1, e2) ->
    StringSet.union (escaping_vars e1 candidates) (escaping_vars e2 candidates)

  (* ELetRec: conservatively mark all candidates mentioned in inner fn bodies
     as escaping (they are captured free variables) *)
  | Tir.ELetRec (fns, body) ->
    let from_fns =
      List.fold_left (fun acc fn ->
        let all_in_fn = all_atom_vars fn.Tir.fn_body in
        StringSet.union acc (StringSet.inter all_in_fn candidates)
      ) StringSet.empty fns
    in
    StringSet.union from_fns (escaping_vars body candidates)

  | Tir.ECase (_, branches, default) ->
    let from_branches =
      List.fold_left (fun acc br ->
        StringSet.union acc (escaping_vars br.Tir.br_body candidates)
      ) StringSet.empty branches
    in
    let from_default = match default with
      | Some d -> escaping_vars d candidates
      | None -> StringSet.empty
    in
    (* Note: the scrutinee atom is NOT an escaping position per spec *)
    StringSet.union from_branches from_default

  | Tir.ESeq (e1, e2) ->
    StringSet.union (escaping_vars e1 candidates) (escaping_vars e2 candidates)

  (* Non-escaping positions: ECase scrutinee (handled above), EField,
     EIncRC, EDecRC, EFree, EReuse first position, atomic RC ops *)
  | Tir.EField _ | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EFree _
  | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _ ->
    StringSet.empty

  (* TRMC.  Both are ESCAPING positions: EAllocHole stores its operands into
     a heap cell, and ESetField stores into one whose lifetime this analysis
     cannot see.  A stack-promoted value written through either would dangle
     once the frame returns, so nothing here may be stack-allocated. *)
  | Tir.EAllocHole (_, _, args, _) -> candidate_atoms args
  | Tir.ESetField (o, _, v) ->
    StringSet.union (candidate_atoms [o]) (candidate_atoms [v])

(** Returns the subset of [candidates] for which EIncRC appears anywhere in [e].
    Such variables have multiple live references — not safe to stack-promote. *)
let rec has_incrc_for (e : Tir.expr) (candidates : StringSet.t) : StringSet.t =
  match e with
  | Tir.EIncRC (Tir.AVar v) when StringSet.mem v.Tir.v_name candidates ->
    StringSet.singleton v.Tir.v_name
  | Tir.EAtomicIncRC (Tir.AVar v) when StringSet.mem v.Tir.v_name candidates ->
    StringSet.singleton v.Tir.v_name
  | Tir.ELet (_, e1, e2) ->
    StringSet.union (has_incrc_for e1 candidates) (has_incrc_for e2 candidates)
  | Tir.ELetRec (fns, body) ->
    let from_fns =
      List.fold_left (fun acc fn ->
        StringSet.union acc (has_incrc_for fn.Tir.fn_body candidates)
      ) StringSet.empty fns
    in
    StringSet.union from_fns (has_incrc_for body candidates)
  | Tir.ECase (_, branches, default) ->
    let from_branches =
      List.fold_left (fun acc br ->
        StringSet.union acc (has_incrc_for br.Tir.br_body candidates)
      ) StringSet.empty branches
    in
    let from_default = match default with
      | Some d -> has_incrc_for d candidates
      | None -> StringSet.empty
    in
    StringSet.union from_branches from_default
  | Tir.ESeq (e1, e2) ->
    StringSet.union (has_incrc_for e1 candidates) (has_incrc_for e2 candidates)
  | _ -> StringSet.empty

(* ── Phase 3: Transform ───────────────────────────────────────────────────── *)

(** A unit no-op expression — used to replace dead RC ops. *)
let unit_expr : Tir.expr = Tir.ETuple []

(** Rewrite [e] applying stack-promotion for [promotable] variables. *)
let rec promote_expr (e : Tir.expr) (promotable : StringSet.t) : Tir.expr =
  match e with
  (* Rewrite A: promote EAlloc to EStackAlloc *)
  | Tir.ELet (v, Tir.EAlloc (ty, args), body)
    when StringSet.mem v.Tir.v_name promotable ->
    Tir.ELet (v, Tir.EStackAlloc (ty, args), promote_expr body promotable)

  (* Rewrite B: eliminate dead RC ops on stack variables in ESeq position *)
  | Tir.ESeq (Tir.EDecRC (Tir.AVar v), rest)
    when StringSet.mem v.Tir.v_name promotable ->
    promote_expr rest promotable
  | Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v), rest)
    when StringSet.mem v.Tir.v_name promotable ->
    promote_expr rest promotable
  | Tir.ESeq (Tir.EFree (Tir.AVar v), rest)
    when StringSet.mem v.Tir.v_name promotable ->
    promote_expr rest promotable

  (* Standalone EDecRC/EFree/EAtomicDecRC on promotable var — replace with unit no-op *)
  | Tir.EDecRC (Tir.AVar v) when StringSet.mem v.Tir.v_name promotable ->
    unit_expr
  | Tir.EAtomicDecRC (Tir.AVar v) when StringSet.mem v.Tir.v_name promotable ->
    unit_expr
  | Tir.EFree (Tir.AVar v) when StringSet.mem v.Tir.v_name promotable ->
    unit_expr

  (* Recurse into compound expressions *)
  | Tir.ELet (v, e1, e2) ->
    Tir.ELet (v, promote_expr e1 promotable, promote_expr e2 promotable)
  | Tir.ELetRec (fns, body) ->
    (* Inner fn bodies are separate scopes; don't apply outer promotable set *)
    Tir.ELetRec (fns, promote_expr body promotable)
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun br ->
      { br with Tir.br_body = promote_expr br.Tir.br_body promotable }
    ) branches in
    let default' = Option.map (fun d -> promote_expr d promotable) default in
    Tir.ECase (a, branches', default')
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (promote_expr e1 promotable, promote_expr e2 promotable)

  (* Leaf forms — nothing to rewrite *)
  | Tir.EAtom _ | Tir.EApp _ | Tir.ECallPtr _
  | Tir.ETuple _ | Tir.ERecord _ | Tir.EField _ | Tir.EUpdate _
  | Tir.EAlloc _ | Tir.EStackAlloc _ | Tir.EFree _ | Tir.EIncRC _
  | Tir.EDecRC _ | Tir.EReuse _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _
  | Tir.EAllocHole _ | Tir.ESetField _ ->
    e

(* ── Per-function entry ───────────────────────────────────────────────────── *)

let escape_fn
    ?(collision_set : (string, string list) Hashtbl.t = Hashtbl.create 0)
    ?(borrow_map = Borrow.empty)
    ?(retain_tbl : (string, bool array) Hashtbl.t = Hashtbl.create 0)
    (type_defs : Tir.type_def list) (fn : Tir.fn_def) : Tir.fn_def =
  let body = fn.Tir.fn_body in
  (* Phase 1: collect EAlloc-bound variables (Boxed-repr allocs only) *)
  let candidates = collect_alloc_candidates ~collision_set type_defs body in
  if StringSet.is_empty candidates then fn
  else begin
    (* Phase 2: compute promotable set *)
    let clo_candidates = collect_clo_candidates body in
    let escaping =
      escaping_vars ~borrow_map ~retain_tbl ~clo_candidates body candidates in
    let with_incrc = has_incrc_for body candidates in
    let non_promotable = StringSet.union escaping with_incrc in
    let promotable = StringSet.diff candidates non_promotable in
    if StringSet.is_empty promotable then fn
    else
      (* Phase 3: transform *)
      let body' = promote_expr body promotable in
      { fn with Tir.fn_body = body' }
  end

(* ── Module entry point ───────────────────────────────────────────────────── *)

let escape_analysis ?(borrow_map = Borrow.empty) (m : Tir.tir_module)
  : Tir.tir_module =
  (* Milestone 3: this pass must not offer an unboxed aggregate for stack
     promotion — it has no cell to promote and [Llvm_emit_alloc] rejects an
     [EStackAlloc] of one outright.  [Contract_pipeline] has normally already
     registered; [ensure_unboxed_types] makes a caller that assembles its own
     pass list (the LSP's older path, tests, [Repl_jit] with unboxing forced
     off) agree with the emitter rather than run against an empty table. *)
  Repr.ensure_unboxed_types
    ~collision_set:(Collision_set.compute m.Tir.tm_types) m.Tir.tm_types;
  (* Computed once per module from its own [tm_types] — mirrors
     [Llvm_ctx.make_ctx]'s [collision_set] derivation (Task 1), so escape
     analysis's Boxed/Niche/Newtype classification of a same-short-name
     colliding type always agrees with what codegen will actually emit for
     it, even though this pass runs standalone (no [ctx] in scope; see
     [alloc_emits_heap_cell]'s doc comment for why that agreement matters). *)
  let collision_set = Collision_set.compute m.Tir.tm_types in
  (* Callees whose borrow verdict is derived from a body this module contains
     — never a C extern or a runtime builtin, whose entry in
     [Borrow.extern_borrow_table] is a declaration rather than an inference.
     See the module doc. *)
  let retain_tbl = may_retain_table m in
  { m with Tir.tm_fns =
      List.map (escape_fn ~collision_set ~borrow_map ~retain_tbl m.Tir.tm_types)
        m.Tir.tm_fns }
