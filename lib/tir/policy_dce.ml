(** Policy-tag audit pass (Phase 3b).

    After monomorphization, walks every function whose parameter list
    includes a [Tagged(_, P)] parameter where [P] names a constraining
    policy, and reports any policy-violating operations.

    Policies:
      NoAlloc  — delegated to [Alloc_contract] on the final TIR (see below)
      NoPanic  — prohibits transitive calls to panic-surface builtins
      NoIO     — prohibits calls to IO-needful functions (tracked via tm_io_fns)

    Realtime implies all three. *)

module StringSet = Set.Make (String)

(* ── Policy table ────────────────────────────────────────────────────── *)

type policy_constraint = NoAlloc | NoPanic | NoIO

let policy_table : (string * policy_constraint list) list = [
  ("NoAlloc",  [NoAlloc]);
  ("NoPanic",  [NoPanic]);
  ("NoIO",     [NoIO]);
  ("Realtime", [NoAlloc; NoPanic; NoIO]);
]

(** Collect the policy constraints that apply to a function, based on
    its [Tagged(_, P)] parameters. Returns [] for non-tagged functions. *)
let policies_of_fn (fd : Tir.fn_def) : policy_constraint list =
  List.concat_map (fun (v : Tir.var) ->
    match v.v_ty with
    | Tir.TCon ("Tagged", [_; Tir.TCon (policy_name, [])]) ->
      (match List.assoc_opt policy_name policy_table with
       | Some cs -> cs
       | None    -> [])
    | _ -> []
  ) fd.Tir.fn_params

(* ── Structural fold ─────────────────────────────────────────────────── *)

(** [fold_expr f acc expr] applies [f acc expr] at every node in the
    expression tree, accumulating results. Visits the node itself first,
    then recurses into sub-expressions. *)
let rec fold_expr : ('a -> Tir.expr -> 'a) -> 'a -> Tir.expr -> 'a =
  fun f acc expr ->
  let acc = f acc expr in
  match expr with
  | Tir.ELet (_, rhs, body)       -> fold_expr f (fold_expr f acc rhs) body
  | Tir.ECase (_, branches, def)  ->
    let acc = List.fold_left (fun a b -> fold_expr f a b.Tir.br_body) acc branches in
    Option.fold ~none:acc ~some:(fold_expr f acc) def
  | Tir.ELetRec (fns, body)       ->
    let acc = List.fold_left (fun a fd -> fold_expr f a fd.Tir.fn_body) acc fns in
    fold_expr f acc body
  | Tir.ESeq (a, b)               -> fold_expr f (fold_expr f acc a) b
  | _ -> acc

(* ── Transitive panic analysis ───────────────────────────────────────── *)

(** Builtins that directly surface a panic/abort. *)
let direct_panic_builtins : StringSet.t = StringSet.of_list [
  "int_div"; "int_mod"; "int_div_euclid"; "int_mod_euclid";
  "/"; "%";
  "panic"; "panic_"; "todo_"; "unreachable_";
]

(** Returns the set of top-level function names that are transitively
    panicky: their body calls a direct panic builtin, or calls another
    panicky function. Uses the same fixpoint pattern as [Purity.impure_fns_of_module]. *)
let panicky_fns_of_module (m : Tir.tir_module) : StringSet.t =
  let calls_in_body fd =
    fold_expr (fun acc expr ->
      match expr with
      | Tir.EApp (f, _) -> StringSet.add f.Tir.v_name acc
      | _ -> acc
    ) StringSet.empty fd.Tir.fn_body
  in
  let rec fixpoint (panicky : StringSet.t) =
    let panicky' = List.fold_left (fun acc fd ->
      if StringSet.mem fd.Tir.fn_name acc then acc
      else
        let callees = calls_in_body fd in
        if not (StringSet.is_empty (StringSet.inter callees panicky))
        then StringSet.add fd.Tir.fn_name acc
        else acc
    ) panicky m.Tir.tm_fns in
    if StringSet.cardinal panicky' = StringSet.cardinal panicky
    then panicky'
    else fixpoint panicky'
  in
  fixpoint direct_panic_builtins

(* ── Transitive IO analysis ──────────────────────────────────────────── *)

(** Returns true if [f_name] belongs to an IO-needful module.
    Function names after mono look like "Http.get$String" or "HttpClient.run".
    We match by module-name prefix stored in [tm_io_fns]. *)
let fn_needs_io_direct (io_mods : StringSet.t) (f_name : string) : bool =
  StringSet.exists (fun mod_name ->
    let prefix = mod_name ^ "." in
    let plen = String.length prefix in
    String.length f_name >= plen && String.sub f_name 0 plen = prefix
  ) io_mods

(** Compute the transitive set of user-defined functions that require IO,
    seeded from functions whose names directly reference an IO module. *)
let io_fns_of_module (m : Tir.tir_module) : StringSet.t =
  let io_mods = StringSet.of_list m.Tir.tm_io_fns in
  if StringSet.is_empty io_mods then StringSet.empty
  else begin
    let calls_in_body fd =
      fold_expr (fun acc expr ->
        match expr with
        | Tir.EApp (f, _) -> StringSet.add f.Tir.v_name acc
        | _ -> acc
      ) StringSet.empty fd.Tir.fn_body
    in
    (* Seed: any user-defined fn whose name starts with an IO module prefix *)
    let seed = List.fold_left (fun acc fd ->
      if fn_needs_io_direct io_mods fd.Tir.fn_name
      then StringSet.add fd.Tir.fn_name acc
      else acc
    ) StringSet.empty m.Tir.tm_fns in
    let rec fixpoint (io_set : StringSet.t) =
      let io_set' = List.fold_left (fun acc fd ->
        if StringSet.mem fd.Tir.fn_name acc then acc
        else
          let callees = calls_in_body fd in
          if not (StringSet.is_empty (StringSet.inter callees io_set))
          then StringSet.add fd.Tir.fn_name acc
          else acc
      ) io_set m.Tir.tm_fns in
      if StringSet.cardinal io_set' = StringSet.cardinal io_set
      then io_set'
      else fixpoint io_set'
    in
    fixpoint seed
  end

(* ── Per-policy body checks ──────────────────────────────────────────── *)

(* The NoAlloc arm has no check here any more: it is decided by
   [Alloc_contract] on the FINAL TIR, after Perceus, Drop, Escape and the Opt
   loop, exactly like an @[no_alloc] contract.  This only widens what the
   policy accepts — a constructor Perceus reused in place, or a value Escape
   promoted to the stack, is no longer a violation — and it is the position
   from which "does this allocate?" can be answered honestly.  [Policy_dce]
   keeps its own position for NoPanic and NoIO, which are call-graph
   questions that do not depend on RC insertion. *)

(** Check NoPanic: returns Some error message if fn body calls a panicky function. *)
let check_nopanic (panicky : StringSet.t) (fd : Tir.fn_def) : string option =
  let violations : string list = fold_expr (fun acc expr ->
    match expr with
    | Tir.EApp (f, _) when StringSet.mem f.Tir.v_name panicky ->
      f.Tir.v_name :: acc
    | _ -> acc
  ) [] fd.Tir.fn_body in
  match violations with
  | [] -> None
  | callee :: _ ->
    Some (Printf.sprintf
      "function `%s` (specialized to a NoPanic policy) calls `%s`, which can panic.\n\
       Use a non-panicking alternative (e.g. `List.nth_opt` instead of `List.nth`,\n\
       `unwrap_or` instead of `unwrap`)."
      fd.Tir.fn_name callee)

(** Check NoIO: returns Some error message if fn body calls an IO-needful function. *)
let check_noio (io_fns : StringSet.t) (io_mods : StringSet.t) (fd : Tir.fn_def) : string option =
  let violations : string list = fold_expr (fun acc expr ->
    match expr with
    | Tir.EApp (f, _)
      when StringSet.mem f.Tir.v_name io_fns
        || fn_needs_io_direct io_mods f.Tir.v_name ->
      f.Tir.v_name :: acc
    | _ -> acc
  ) [] fd.Tir.fn_body in
  match violations with
  | [] -> None
  | callee :: _ ->
    Some (Printf.sprintf
      "function `%s` (specialized to a NoIO policy) calls `%s`, which requires Cap(IO).\n\
       IO is forbidden in NoIO / Realtime functions."
      fd.Tir.fn_name callee)

(* ── Entry point ─────────────────────────────────────────────────────── *)

(** [audit m] walks every function in [m] whose parameter list includes
    a [Tagged(_, P)] parameter where [P] names a constrained policy.
    Returns a list of [(fn_name, error_message)] violation reports.
    Returns [[]] if no violations are found. *)
let audit (m : Tir.tir_module) : (string * string) list =
  (* Pre-compute transitive sets once for the whole module. *)
  let panicky = panicky_fns_of_module m in
  let io_fns  = io_fns_of_module m in
  let io_mods = StringSet.of_list m.Tir.tm_io_fns in
  List.concat_map (fun fd ->
    let constraints = policies_of_fn fd in
    if constraints = [] then []
    else
      List.filter_map (fun c ->
        let msg_opt = match c with
          | NoAlloc -> None   (* see the note above: Alloc_contract decides *)
          | NoPanic -> check_nopanic panicky fd
          | NoIO    -> check_noio io_fns io_mods fd
        in
        Option.map (fun msg -> (fd.Tir.fn_name, msg)) msg_opt
      ) (List.sort_uniq compare constraints)
  ) m.Tir.tm_fns
