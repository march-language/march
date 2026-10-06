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

(** The set of definition names a reference is checked against.  A hash set,
    not a list: it is the whole program's definitions (stdlib included), so a
    [List.mem] per reference made [deps_of] O(references x definitions), which
    measured ~4.4 s of a topology_app compile, cache hits included (2026-10-05). *)
type known = (string, unit) Hashtbl.t

let known_of_names (names : string list) : known =
  let t = Hashtbl.create (2 * List.length names + 1) in
  List.iter (fun n -> Hashtbl.replace t n ()) names;
  t

(** Collect the top-level function names referenced in an expression,
    prepended to [acc] (unordered, with duplicates).
    Only captures names that appear as [EApp] function variable names or as
    [AVar] at the top level (a simple heuristic sufficient for TIR). *)
let rec refs_in_expr (known : known) (acc : string list) (e : expr) : string list =
  let atoms acc l = List.fold_left (refs_in_atom known) acc l in
  match e with
  | EAtom a                   -> refs_in_atom known acc a
  | EApp (fn_v, args)         -> atoms (add_name known acc fn_v.v_name) args
  | ECallPtr (fn_a, args)     -> atoms (refs_in_atom known acc fn_a) args
  | ELet (_, e1, e2)
  | ESeq (e1, e2)             -> refs_in_expr known (refs_in_expr known acc e1) e2
  | ELetRec (fns, body)       ->
    let acc = List.fold_left (fun acc fd -> refs_in_expr known acc fd.fn_body) acc fns in
    refs_in_expr known acc body
  | ECase (a, brs, def)       ->
    let acc = refs_in_atom known acc a in
    let acc = List.fold_left (fun acc br -> refs_in_expr known acc br.br_body) acc brs in
    (match def with Some d -> refs_in_expr known acc d | None -> acc)
  | ETuple atoms'             -> atoms acc atoms'
  | ERecord fields            -> List.fold_left (fun acc (_, a) -> refs_in_atom known acc a) acc fields
  | EField (a, _)             -> refs_in_atom known acc a
  | EUpdate (a, fields)       ->
    List.fold_left (fun acc (_, av) -> refs_in_atom known acc av)
      (refs_in_atom known acc a) fields
  | EAlloc (_, args)
  | EStackAlloc (_, args)     -> atoms acc args
  | EFree a | EIncRC a | EDecRC a
  | EAtomicIncRC a | EAtomicDecRC a -> refs_in_atom known acc a
  | EReuse (a, _, args)       -> atoms (refs_in_atom known acc a) args
  | EAllocHole (tok, _, args, _) ->
    let acc = match tok with Some a -> refs_in_atom known acc a | None -> acc in
    atoms acc args
  | ESetField (o, _, v)       -> refs_in_atom known (refs_in_atom known acc o) v

and refs_in_atom known acc = function
  | AVar v      -> add_name known acc v.v_name
  | ADefRef did -> add_name known acc did.did_name
  | ALit _      -> acc

and add_name known acc n = if Hashtbl.mem known n then n :: acc else acc

(** Direct dependencies of [fd.fn_name] within the set [known]. *)
let deps_of (known : known) (fd : fn_def) : string list =
  let raw = refs_in_expr known [] fd.fn_body in
  (* Deduplicate; a fn may reference itself — keep self-refs *)
  List.sort_uniq String.compare raw

(* ── Tarjan's SCC algorithm ──────────────────────────────────────────────── *)

type node_state = {
  mutable index      : int;
  mutable low_link   : int;
  mutable on_stack   : bool;
}

let compute_sccs (fns : fn_def list) : scc list =
  let known = known_of_names (List.map (fun fd -> fd.fn_name) fns) in
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
    let successors = deps_of known fd in
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
