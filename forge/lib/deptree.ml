(** Dependency tree rendering and reverse-path queries.

    Pure over an injected adjacency function [deps_of name] returning a node's
    direct dependency names. Used by `forge tree` and `forge why`. *)

(* Render an ASCII dependency tree rooted at [root]. A node already on the
   current path (a cycle) is marked "(*)" and not re-expanded. *)
let render_tree ~root ~deps_of =
  let out = ref [] in
  let emit line = out := line :: !out in
  emit root;
  let rec walk prefix name is_last path =
    let connector = if is_last then "└── " else "├── " in
    let seen = List.mem name path in
    emit (prefix ^ connector ^ name ^ (if seen then " (*)" else ""));
    if not seen then begin
      let children = deps_of name in
      let child_prefix = prefix ^ (if is_last then "    " else "│   ") in
      let n = List.length children in
      List.iteri (fun i c -> walk child_prefix c (i = n - 1) (name :: path)) children
    end
  in
  let children = deps_of root in
  let n = List.length children in
  List.iteri (fun i c -> walk "" c (i = n - 1) [ root ]) children;
  List.rev !out

(* All dependency paths from [root] to [target] (each path a name list,
   root-first). Cycles are not followed. *)
let why ~root ~deps_of ~target =
  let results = ref [] in
  let rec go path name =
    if name = target then results := List.rev (name :: path) :: !results
    else if List.mem name path then ()          (* cycle — stop *)
    else List.iter (go (name :: path)) (deps_of name)
  in
  go [] root;
  List.rev !results
