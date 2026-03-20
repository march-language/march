(** Strongly-Connected Component detection for TIR function dependency graphs.

    Uses Tarjan's algorithm to find SCCs, then topologically sorts them
    (guaranteed acyclic at the SCC level).

    Returns SCCs in topological order: if SCC A's definitions reference
    definitions in SCC B, then B appears before A in the result list.
*)

open March_tir.Tir

(** A detected SCC.
    - [Single name]: one definition (possibly self-recursive).
    - [Group members]: two or more mutually-recursive definitions. *)
type scc =
  | Single of string
  | Group  of string list

(* ── Reference extraction ────────────────────────────────────────────────── *)

(** Collect the set of top-level function names referenced in an expression.
    Only captures names that appear as [EApp] function variable names or as
    [AVar] at the top level (a simple heuristic sufficient for TIR). *)
let rec refs_in_expr (known : string list) (e : expr) : string list =
  match e with
  | EAtom (AVar v)            -> if List.mem v.v_name known then [v.v_name] else []
  | EAtom (ADefRef did)       -> if List.mem did.did_name known then [did.did_name] else []
  | EAtom (ALit _)            -> []
  | EApp (fn_v, args)         ->
    let direct = if List.mem fn_v.v_name known then [fn_v.v_name] else [] in
    let from_args = List.concat_map (refs_in_atom known) args in
    direct @ from_args
  | ECallPtr (fn_a, args)     ->
    refs_in_atom known fn_a @ List.concat_map (refs_in_atom known) args
  | ELet (_, e1, e2)          -> refs_in_expr known e1 @ refs_in_expr known e2
  | ELetRec (fns, body)       ->
    List.concat_map (fun fd -> refs_in_expr known fd.fn_body) fns
    @ refs_in_expr known body
  | ECase (a, brs, def)       ->
    refs_in_atom known a
    @ List.concat_map (fun br -> refs_in_expr known br.br_body) brs
    @ Option.value ~default:[] (Option.map (refs_in_expr known) def)
  | ETuple atoms              -> List.concat_map (refs_in_atom known) atoms
  | ERecord fields            -> List.concat_map (fun (_, a) -> refs_in_atom known a) fields
  | EField (a, _)             -> refs_in_atom known a
  | EUpdate (a, fields)       ->
    refs_in_atom known a @ List.concat_map (fun (_, av) -> refs_in_atom known av) fields
  | EAlloc (_, args)
  | EStackAlloc (_, args)     -> List.concat_map (refs_in_atom known) args
  | EFree a | EIncRC a | EDecRC a -> refs_in_atom known a
  | EReuse (a, _, args)       ->
    refs_in_atom known a @ List.concat_map (refs_in_atom known) args
  | ESeq (e1, e2)             -> refs_in_expr known e1 @ refs_in_expr known e2

and refs_in_atom known = function
  | AVar v    -> if List.mem v.v_name known then [v.v_name] else []
  | ADefRef did -> if List.mem did.did_name known then [did.did_name] else []
  | ALit _    -> []

(** Direct dependencies of [fd.fn_name] within the set [known_names]. *)
let deps_of (known_names : string list) (fd : fn_def) : string list =
  let raw = refs_in_expr known_names fd.fn_body in
  (* Deduplicate; a fn may reference itself — keep self-refs *)
  List.sort_uniq String.compare raw

(* ── Tarjan's SCC algorithm ──────────────────────────────────────────────── *)

type node_state = {
  mutable index      : int;
  mutable low_link   : int;
  mutable on_stack   : bool;
}

let compute_sccs (fns : fn_def list) : scc list =
  let names = List.map (fun fd -> fd.fn_name) fns in
  let fn_map = Hashtbl.create (List.length fns) in
  List.iter (fun fd -> Hashtbl.replace fn_map fd.fn_name fd) fns;

  let state : (string, node_state) Hashtbl.t = Hashtbl.create (List.length fns) in
  let index_counter = ref 0 in
  let stack : string Stack.t = Stack.create () in
  (* Result: SCCs in reverse topological order — we'll reverse at the end *)
  let result : scc list ref = ref [] in

  let rec strongconnect name =
    let ns = { index = !index_counter; low_link = !index_counter; on_stack = true } in
    Hashtbl.replace state name ns;
    incr index_counter;
    Stack.push name stack;

    (* Visit successors *)
    let fd = Hashtbl.find fn_map name in
    let successors = deps_of names fd in
    List.iter (fun w ->
      match Hashtbl.find_opt state w with
      | None ->
        (* Not yet visited *)
        strongconnect w;
        let ns_w = Hashtbl.find state w in
        ns.low_link <- min ns.low_link ns_w.low_link
      | Some ns_w ->
        if ns_w.on_stack then
          ns.low_link <- min ns.low_link ns_w.index
    ) successors;

    (* If this node is the root of an SCC, pop the stack *)
    if ns.low_link = ns.index then begin
      let members = ref [] in
      let continue = ref true in
      while !continue do
        let w = Stack.pop stack in
        (Hashtbl.find state w).on_stack <- false;
        members := w :: !members;
        if String.equal w name then continue := false
      done;
      let scc = match !members with
        | [single] -> Single single
        | many     -> Group (List.sort String.compare many)
      in
      result := scc :: !result
    end
  in

  (* Run strongconnect for all unvisited nodes *)
  List.iter (fun fd ->
    if not (Hashtbl.mem state fd.fn_name) then
      strongconnect fd.fn_name
  ) fns;

  (* result is in reverse-topological order (roots last); reverse it so that
     definitions with no dependents come first (dependencies before dependents). *)
  List.rev !result
