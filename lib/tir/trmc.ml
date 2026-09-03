(** TRMC (tail-recursion-modulo-cons) eligibility analysis — Phase 1.

    ANALYSIS ONLY: this module never rewrites the TIR.  It classifies every
    self-recursive call in the module so we can measure how much TRMC would
    actually buy before paying for the transformation (two new [Tir.expr]
    nodes and the RC integration).  See
    [specs/todos/2026-08-07-trmc-tail-recursion-modulo-cons.md] for the staged
    plan and [Lorenzen & Leijen, ICFP'22] §2.4.1 for the technique.

    A call is *modulo-cons* when it sits in tail position bound to a temporary
    whose sole use is as a field of a constructor allocation that is itself the
    tail expression:

      let t = self(args) in alloc Ctor(.., t, ..)      -- TRMC-eligible

    Such a function can be rewritten into destination-passing style, where the
    constructor is allocated *before* the recursive call with a hole in field
    [i], and the call — now a genuine tail call — fills it.  [Llvm_tco] then
    turns that tail call into a loop for free, which is what makes the whole
    transformation tractable.

    Run point: post-lower, pre-mono.  Later is too late — by [tir-perceus] the
    stdlib's inner [go] helpers are closures invoked via [ECallPtr] (Known_call
    does not devirtualize them), so self-recursion is no longer syntactically
    visible.  Earlier stages also mean one analysis per source function rather
    than one per monomorphic instantiation. *)

module StringSet = Set.Make (String)

(* ── Classification ──────────────────────────────────────────────────────── *)

(** How a single self-recursive call site is positioned. *)
type site =
  | Tail
      (** Already a tail call — [Llvm_tco] handles it; TRMC has nothing to do. *)
  | Modulo_cons of string * int
      (** Tail-position constructor application with the call in field [i] of
          the named constructor.  This is what TRMC would transform. *)
  | Other
      (** Any other position (a call argument, a scrutinee, a non-tail let RHS).
          v1 of the transformation cannot reach these. *)

type verdict =
  | Eligible      (** at least one modulo-cons site, and no [Other] sites *)
  | Mixed
      (** Some sites are transformable and some are not.  The classic case is a
          branching recursion like [Node(self(l), k, v, self(r))]: the last call
          on the path becomes the destination and the earlier one stays a real
          recursive call.  Still transformable, but the win is partial — the
          function keeps O(depth) stack for the non-destination calls. *)
  | Non_trmc      (** non-tail self-calls, none of them modulo-cons *)
  | Already_tail  (** every self-call is a tail call *)
  | No_recursion

type fn_report = {
  r_fn      : string;
  r_tail    : int;
  r_modcons : (string * int) list;  (** (constructor, hole index) per site *)
  r_other   : int;
}

let verdict_of (r : fn_report) : verdict =
  match r.r_modcons, r.r_other, r.r_tail with
  | [], 0, 0 -> No_recursion
  | [], 0, _ -> Already_tail
  | [], _, _ -> Non_trmc
  | _,  0, _ -> Eligible
  | _,  _, _ -> Mixed

let string_of_verdict = function
  | Eligible     -> "eligible"
  | Mixed        -> "mixed"
  | Non_trmc     -> "non-trmc"
  | Already_tail -> "already-tail"
  | No_recursion -> "no-recursion"

(* ── The modulo-cons shape ───────────────────────────────────────────────── *)

(** Does [v] occur exactly once in [atoms], and if so at which index?
    A hole must be a single field: a call appearing twice (e.g.
    [Node(self(l), self(r))]) is two separate recursive calls and cannot be a
    single destination. *)
let sole_atom_index (name : string) (atoms : Tir.atom list) : int option =
  let hits =
    List.filteri (fun _ a -> match a with
      | Tir.AVar v -> String.equal v.Tir.v_name name
      | _ -> false) atoms
  in
  match hits with
  | [_] ->
    let rec idx i = function
      | [] -> None
      | Tir.AVar v :: _ when String.equal v.Tir.v_name name -> Some i
      | _ :: rest -> idx (i + 1) rest
    in
    idx 0 atoms
  | _ -> None

(** [modulo_cons_target v k] is [Some (ctor, i)] when the continuation [k]
    consumes [v] exactly as field [i] of a tail-position [EAlloc].

    Intervening [ELet]s are permitted as long as they do not mention [v] — the
    value must flow untouched into the constructor, or the destination-passing
    rewrite would have to reorder effects around the hole. *)
let rec modulo_cons_target (v : string) (k : Tir.expr) : (string * int) option =
  match k with
  | Tir.EAlloc (Tir.TCon (ctor, _), atoms) ->
    Option.map (fun i -> (ctor, i)) (sole_atom_index v atoms)
  | Tir.ELet (bv, rhs, body)
    when not (String.equal bv.Tir.v_name v)
      && not (Perceus_liveness.name_free_in v rhs) ->
    modulo_cons_target v body
  | _ -> None

(* ── Walk ────────────────────────────────────────────────────────────────── *)

(** True if [name] is applied anywhere in [e].  Used to classify self-calls
    that the tail walk does not reach (they are [Other] by construction). *)
let rec calls_name (name : string) (e : Tir.expr) : bool =
  let atom_is a = match a with
    | Tir.AVar v -> String.equal v.Tir.v_name name
    | Tir.ADefRef d -> String.equal d.Tir.did_name name
    | Tir.ALit _ -> false
  in
  match e with
  | Tir.EApp (f, args) ->
    String.equal f.Tir.v_name name || List.exists atom_is args
  | Tir.ECallPtr (a, args) -> atom_is a || List.exists atom_is args
  | Tir.EAtom a -> atom_is a
  | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) ->
    calls_name name e1 || calls_name name e2
  | Tir.ELetRec (fns, body) ->
    List.exists (fun fd -> calls_name name fd.Tir.fn_body) fns
    || calls_name name body
  | Tir.ECase (a, branches, default) ->
    atom_is a
    || List.exists (fun br -> calls_name name br.Tir.br_body) branches
    || Option.fold ~none:false ~some:(calls_name name) default
  | Tir.ETuple atoms | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) ->
    List.exists atom_is atoms
  | Tir.ERecord fields -> List.exists (fun (_, a) -> atom_is a) fields
  | Tir.EUpdate (a, fields) ->
    atom_is a || List.exists (fun (_, a) -> atom_is a) fields
  | Tir.EField (a, _) | Tir.EFree a
  | Tir.EIncRC a | Tir.EDecRC a
  | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a -> atom_is a
  | Tir.EReuse (a, _, atoms) -> atom_is a || List.exists atom_is atoms
  | Tir.EAllocHole (tok, _, atoms, _) ->
    (match tok with Some a -> atom_is a | None -> false)
    || List.exists atom_is atoms
  | Tir.ESetField (o, _, v) -> atom_is o || atom_is v

(** Collect the self-call sites of [self] in [e].

    [in_tail] tracks whether [e] is in tail position of the enclosing function.
    Sub-expressions that are evaluated for their value (a let RHS, a call
    argument) are walked with [in_tail:false], so any self-call found there is
    [Other]. *)
let sites_of (self : string) (body : Tir.expr) : site list =
  let acc = ref [] in
  let add s = acc := s :: !acc in
  (* A non-tail subtree: every self-call inside it is unreachable by TRMC. *)
  let scan_non_tail e = if calls_name self e then add Other in
  let rec go ~in_tail e =
    match e with
    (* let t = self(..) in <cont> — the modulo-cons shape lives here. *)
    | Tir.ELet (bv, Tir.EApp (f, args), k) when String.equal f.Tir.v_name self ->
      List.iter (fun a -> match a with
        | Tir.AVar v when String.equal v.Tir.v_name self -> add Other
        | _ -> ()) args;
      (* A site is only transformable if nothing later on this path is also a
         self-call.  For [Node(self(l), k, v, self(r))] the hole must be filled
         by the call that runs LAST, so [self(r)] becomes the destination and
         [self(l)] stays a real recursive call — exactly one destination per
         path.  Checking [k] for a further self-call is what enforces that. *)
      let transformable =
        in_tail && not (calls_name self k)
      in
      (match (if transformable then modulo_cons_target bv.Tir.v_name k else None) with
       | Some (ctor, i) -> add (Modulo_cons (ctor, i))
       | None -> add Other);
      go ~in_tail k
    | Tir.EApp (f, args) ->
      if String.equal f.Tir.v_name self then add (if in_tail then Tail else Other);
      List.iter (fun a -> match a with
        | Tir.AVar v when String.equal v.Tir.v_name self -> add Other
        | _ -> ()) args
    | Tir.ELet (_, rhs, body) -> go_rhs ~in_tail rhs; go ~in_tail body
    | Tir.ESeq (e1, e2) -> scan_non_tail e1; go ~in_tail e2
    | Tir.ECase (_, branches, default) ->
      List.iter (fun br -> go ~in_tail br.Tir.br_body) branches;
      Option.iter (go ~in_tail) default
    | Tir.ELetRec (fns, body) ->
      go_fns ~in_tail fns;
      go ~in_tail body
    | _ -> scan_non_tail e
  (* A let RHS is normally evaluated for its value, so self-calls inside it are
     [Other].  The exception is a JOIN POINT: [lower_match] hoists a match's
     fall-through into [ELetRec([jp], EAtom jp)] bound to a [$jp_clo] variable,
     and every fall-through site in the decision tree calls it indirectly.  A
     join-point body is therefore the match's CONTINUATION, not a value
     computation — its tail position is the enclosing expression's tail
     position.

     Treating it as a value computation is not conservative, it is simply
     wrong, and it showed up immediately: [List.last]'s third arm
     ([Cons(_, t) -> last(t)]) is a plain tail call that lowering places inside
     a join point, and the first version of this walk reported it as [Other].

     Approximation: this assumes every call site of the join point is itself in
     tail position, which holds for the fall-through join points [lower_match]
     generates but is not checked here.  Phase 2 must verify it per call site
     rather than inherit it. *)
  and go_rhs ~in_tail rhs =
    match rhs with
    | Tir.ELetRec (fns, _) -> go_fns ~in_tail fns
    | _ -> scan_non_tail rhs
  (* Join-point bodies inherit the enclosing tail position; every other nested
     definition is analysed under its own name by [analyze_module], and here
     contributes only [Other] sites for the enclosing [self]. *)
  and go_fns ~in_tail fns =
    List.iter (fun fd ->
      if fd.Tir.fn_kind = Tir.FnJoinPoint then go ~in_tail fd.Tir.fn_body
      else scan_non_tail fd.Tir.fn_body
    ) fns
  in
  go ~in_tail:true body;
  List.rev !acc

let report_of_fn (fn_name : string) (body : Tir.expr) : fn_report =
  let sites = sites_of fn_name body in
  List.fold_left (fun r s ->
    match s with
    | Tail -> { r with r_tail = r.r_tail + 1 }
    | Modulo_cons (c, i) -> { r with r_modcons = r.r_modcons @ [(c, i)] }
    | Other -> { r with r_other = r.r_other + 1 }
  ) { r_fn = fn_name; r_tail = 0; r_modcons = []; r_other = 0 } sites

(* ── Module-level analysis ───────────────────────────────────────────────── *)

(** Every function in the module, plus every [ELetRec]-bound nested function,
    each analysed against its own name.  Nested helpers matter: the stdlib's
    list producers put their whole loop in a nested [go]. *)
let rec nested_fns (e : Tir.expr) : Tir.fn_def list =
  match e with
  | Tir.ELetRec (fns, body) ->
    fns @ List.concat_map (fun fd -> nested_fns fd.Tir.fn_body) fns
    @ nested_fns body
  | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> nested_fns e1 @ nested_fns e2
  | Tir.ECase (_, branches, default) ->
    List.concat_map (fun br -> nested_fns br.Tir.br_body) branches
    @ Option.fold ~none:[] ~some:nested_fns default
  | _ -> []

let analyze_module (m : Tir.tir_module) : fn_report list =
  let all =
    List.concat_map (fun fn -> fn :: nested_fns fn.Tir.fn_body) m.Tir.tm_fns
  in
  List.filter_map (fun fn ->
    let r = report_of_fn fn.Tir.fn_name fn.Tir.fn_body in
    if verdict_of r = No_recursion then None else Some r
  ) all

(* ── Reporting ───────────────────────────────────────────────────────────── *)

(** Gated on [MARCH_TRMC_REPORT]; prints to stderr, one line per recursive
    function plus a summary.  Phase 1 has no other output and no effect on the
    compiled program. *)
let report (m : Tir.tir_module) : unit =
  if Sys.getenv_opt "MARCH_TRMC_REPORT" = None then ()
  else begin
    let reports = analyze_module m in
    let counts = Hashtbl.create 8 in
    List.iter (fun r ->
      let v = verdict_of r in
      let key = string_of_verdict v in
      Hashtbl.replace counts key (1 + Option.value ~default:0 (Hashtbl.find_opt counts key));
      let detail = match v with
        | Eligible | Mixed ->
          String.concat " " (List.map (fun (c, i) ->
            Printf.sprintf "%s@%d" c i) r.r_modcons)
        | _ -> ""
      in
      Printf.eprintf "TRMC\t%s\t%s\ttail=%d modcons=%d other=%d\t%s\n"
        (string_of_verdict v) r.r_fn r.r_tail (List.length r.r_modcons)
        r.r_other detail
    ) reports;
    Printf.eprintf "TRMCSUMMARY\tmodule=%s" m.Tir.tm_name;
    List.iter (fun k ->
      Printf.eprintf "\t%s=%d" k (Option.value ~default:0 (Hashtbl.find_opt counts k)))
      ["eligible"; "mixed"; "non-trmc"; "already-tail"];
    Printf.eprintf "\n%!"
  end

(* ── Phase 3: the destination-passing transformation ──────────────────────────

   For an [Eligible] function with exactly one modulo-cons site, build a helper
   whose recursive call is a genuine TAIL call, so [Llvm_tco] turns it into a
   loop:

     fn f(ps) = .. let t = f(as) in Ctor(.., t, ..) ..

   becomes

     fn f(ps)      = .. let c = allochole Ctor(.., _, ..) in f$dps(as, c); c ..
     fn f$dps(ps, dst) = .. let c = allochole Ctor(.., _, ..) in
                            dst.hole <- c;
                            f$dps(as, c)              <- tail call
                         .. and every OTHER tail expression E becomes
                            let r = E in dst.hole <- r

   [dst] is the parent CELL, not an interior pointer: the hole index is baked
   into the helper, which is sound because every iteration of a single-
   constructor loop writes the same field.  See the Phase 2 note in
   specs/todos/2026-08-07-trmc-tail-recursion-modulo-cons.md.

   GATED on [enabled] (set by --trmc, or by the legacy MARCH_TRMC env var) —
   this is a work-in-progress measurement vehicle, not yet a default pipeline
   stage. *)

let trmc_ctr = ref 0

let fresh_var (ty : Tir.ty) : Tir.var =
  incr trmc_ctr;
  { Tir.v_name = Printf.sprintf "$trmc%d" !trmc_ctr; v_ty = ty; v_lin = Tir.Unr }

(** The continuation of a modulo-cons call, when it is a DIRECT [EAlloc].

    v1 deliberately refuses intervening lets.  Those bindings are evaluated
    after the recursive call in the original but would have to move BEFORE it
    in destination-passing style, and while the eligibility check guarantees
    they do not read the call's result, it does not guarantee they are pure —
    so reordering them could move a side effect across the call. *)
let modcons_alloc (v : string) (k : Tir.expr)
    : (Tir.ty * Tir.atom list * int) option =
  match k with
  | Tir.EAlloc ((Tir.TCon _) as ty, atoms) ->
    (match sole_atom_index v atoms with
     | Some i ->
       let filled = List.filteri (fun j _ -> j <> i) atoms in
       Some (ty, filled, i)
     | None -> None)
  | _ -> None

(** Rewrite the tail positions of a helper body so every result is WRITTEN into
    [dst]'s hole instead of returned. *)
let rec returnify ~(self : string) ~(dps : Tir.var) ~(dst : Tir.var)
    ~(hole : int) ~(ret_ty : Tir.ty) (e : Tir.expr) : Tir.expr =
  let store_tail tail =
    let r = fresh_var ret_ty in
    Tir.ELet (r, tail, Tir.ESetField (Tir.AVar dst, hole, Tir.AVar r))
  in
  let recur = returnify ~self ~dps ~dst ~hole ~ret_ty in
  match e with
  | Tir.ELet (bv, Tir.EApp (f, args), k)
    when String.equal f.Tir.v_name self && not (calls_name self k) ->
    (match modcons_alloc bv.Tir.v_name k with
     | Some (alloc_ty, filled, i) ->
       let c = fresh_var alloc_ty in
       Tir.ELet (c, Tir.EAllocHole (None, alloc_ty, filled, i),
         Tir.ESeq (Tir.ESetField (Tir.AVar dst, hole, Tir.AVar c),
                   Tir.EApp (dps, args @ [Tir.AVar c])))
     | None -> store_tail e)
  | Tir.ELet (bv, rhs, k) -> Tir.ELet (bv, rhs, recur k)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (e1, recur e2)
  | Tir.ECase (a, branches, default) ->
    Tir.ECase (a,
      List.map (fun br -> { br with Tir.br_body = recur br.Tir.br_body }) branches,
      Option.map recur default)
  | _ -> store_tail e

(** Rewrite the ORIGINAL function: allocate the cell, hand it to the helper,
    return it. *)
let rec seed_entry ~(self : string) ~(dps : Tir.var) (e : Tir.expr) : Tir.expr =
  let recur = seed_entry ~self ~dps in
  match e with
  | Tir.ELet (bv, Tir.EApp (f, args), k)
    when String.equal f.Tir.v_name self && not (calls_name self k) ->
    (match modcons_alloc bv.Tir.v_name k with
     | Some (alloc_ty, filled, i) ->
       let c = fresh_var alloc_ty in
       Tir.ELet (c, Tir.EAllocHole (None, alloc_ty, filled, i),
         Tir.ESeq (Tir.EApp (dps, args @ [Tir.AVar c]),
                   Tir.EAtom (Tir.AVar c)))
     | None -> e)
  | Tir.ELet (bv, rhs, k) -> Tir.ELet (bv, rhs, recur k)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (e1, recur e2)
  | Tir.ECase (a, branches, default) ->
    Tir.ECase (a,
      List.map (fun br -> { br with Tir.br_body = recur br.Tir.br_body }) branches,
      Option.map recur default)
  | _ -> e

(** True when [ty] names a type that can cross an actor boundary, and so must
    never be rewritten: the hole-fill is a plain non-atomic store, safe only
    while the cell is thread-local.

    The two halves are checked DIFFERENTLY, deliberately:

    - The actor-STRUCT half is structural — [Repr.is_actor_struct_type] confirms
      field 0 is literally ["$d_dispatch"], a name [lower_actor.ml] alone can
      construct (no surface March identifier may start with [$]).  A name-suffix
      guess here previously false-positived on a user type called [Tree_Actor];
      in [llvm_emit.ml]'s [EReuse] arm that was outright unsound (it skipped the
      refcount check shared-value FBIP safety depends on), which is why
      [Repr.is_actor_struct_type] exists at all.  Here the same false positive
      is merely conservative — an over-approximation only DECLINES a rewrite —
      but a user type named [Tree_Actor] silently lost TRMC for no reason, so it
      is worth checking properly now that the structural predicate is available.

    - The actor-MESSAGE half is still the ["_Msg"] name suffix
      ([Tir_names.is_actor_msg_name]).  There is no structural predicate for a
      message variant, and the failure direction is safe: a user type named
      [Foo_Msg] over-approximates to "crosses a boundary" and loses TRMC, which
      costs an optimization and never correctness.  Do not copy this suffix test
      to a site where a false positive would SKIP a safety check. *)
let crosses_actor_boundary (type_defs : Tir.type_def list) (ty : Tir.ty) : bool =
  match ty with
  | Tir.TCon (name, _) ->
    Tir_names.is_actor_msg_name name || Repr.is_actor_struct_type type_defs name
  | _ -> false

(** [Some (f', f_dps)] when [fn] is transformable.

    [on_decline] receives the reason whenever the answer is [None] and the
    function looked transformable to the ANALYSIS.  It exists so the report in
    [transform_module] can name the specific refusal without re-deriving this
    ladder — two copies of it would drift, and a skip line that says only
    "eligible" tells you a gap exists but not which one. *)
let transform_fn ?(on_decline = fun (_ : string) -> ())
      (type_defs : Tir.type_def list)
      (fn : Tir.fn_def) : (Tir.fn_def * Tir.fn_def) option =
  let r = report_of_fn fn.Tir.fn_name fn.Tir.fn_body in
  let decline reason = on_decline reason; None in
  if crosses_actor_boundary type_defs fn.Tir.fn_ret_ty then
    decline "actor-boundary-return"
  else
  match verdict_of r, r.r_modcons with
  | Eligible, [ (_ctor, hole) ] ->
    let dps_name = fn.Tir.fn_name ^ "$dps" in
    let dst = { Tir.v_name = "$dst"; v_ty = fn.Tir.fn_ret_ty; v_lin = Tir.Unr } in
    let dps_ty =
      Tir.TFn (List.map (fun (p : Tir.var) -> p.Tir.v_ty)
                 (fn.Tir.fn_params @ [dst]), Tir.TUnit)
    in
    let dps = { Tir.v_name = dps_name; v_ty = dps_ty; v_lin = Tir.Unr } in
    let helper =
      { Tir.fn_name = dps_name;
        fn_params = fn.Tir.fn_params @ [dst];
        fn_ret_ty = Tir.TUnit;
        fn_body = returnify ~self:fn.Tir.fn_name ~dps ~dst ~hole
                    ~ret_ty:fn.Tir.fn_ret_ty fn.Tir.fn_body;
        fn_kind = Tir.FnNormal }
    in
    let entry =
      { fn with Tir.fn_body = seed_entry ~self:fn.Tir.fn_name ~dps fn.Tir.fn_body }
    in
    Some (entry, helper)
  | Eligible, sites -> decline (Printf.sprintf "multi-site(%d)" (List.length sites))
  | Mixed, _ -> decline "mixed"
  | _ -> None

(** Whether the destination-passing transform runs.  A [ref] rather than an
    env-var read so the driver owns the decision and a CLI flag can set it;
    [bin/main.ml] is the only writer.  Default OFF until the default flips
    (see specs/plans/2026-08-10-trmc-on-by-default.md Task 10). *)
let enabled : bool ref = ref false

(** Apply TRMC across a module.  Gated on [enabled] (see [--trmc]). *)
let transform_module ?(enabled = !enabled) (m : Tir.tir_module) : Tir.tir_module =
  if not enabled then m
  else begin
    let report = Sys.getenv_opt "MARCH_TRMC_REPORT" <> None in
    let out = List.concat_map (fun fn ->
      (* No silent caps: a function the ANALYSIS considers transformable but
         the TRANSFORM declines is a coverage gap, and it must be visible in
         the report rather than inferred from a missing TRMCXFORM line.  The
         reason comes from transform_fn itself so the two cannot drift. *)
      let on_decline reason =
        if report then begin
          let r = report_of_fn fn.Tir.fn_name fn.Tir.fn_body in
          Printf.eprintf "TRMCSKIP\t%s\t%s\t%s\tmodcons=%d other=%d\n%!"
            fn.Tir.fn_name reason (string_of_verdict (verdict_of r))
            (List.length r.r_modcons) r.r_other
        end
      in
      match transform_fn ~on_decline m.Tir.tm_types fn with
      | Some (entry, helper) ->
        if report then
          Printf.eprintf "TRMCXFORM\t%s -> %s\n%!" fn.Tir.fn_name helper.Tir.fn_name;
        [entry; helper]
      | None -> [fn]
    ) m.Tir.tm_fns in
    { m with Tir.tm_fns = out }
  end
