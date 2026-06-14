(** File-change detection for `forge watch`.

    A [snapshot] maps watched file paths to their mtimes. The watch loop polls
    [snapshot_of] and reruns the chosen action whenever [changed] reports a
    difference (a file added, removed, or its mtime changed). *)

type snapshot = (string * float) list

(* Order-independent comparison: any added/removed path or changed mtime counts
   as a change (a `touch` triggers a rebuild, like make). Pure — unit-tested. *)
let changed ~prev ~cur =
  List.sort compare prev <> List.sort compare cur

(* Stat each path, dropping any that can't be stat'd (e.g. just deleted). *)
let snapshot_of paths =
  List.filter_map (fun p ->
    match (Unix.stat p).Unix.st_mtime with
    | m -> Some (p, m)
    | exception _ -> None) paths
