(* =================================================================
   Capability hierarchy for needs / Cap checking.
   Each entry: (cap_path, parent_path option).
   Paths are dot-joined strings, e.g. "IO.FileRead".
   FFI caps like "LibC" are valid but not in this table — they are
   their own roots and have no subtyping relationship.

   Shared between March_typecheck.Typecheck (body-scan Phase 2) and
   March_refinecheck.Cap_infer (capability-inference hints) — both need
   the identical subsumption rule, so it lives here as a single source
   of truth (factored out in Phase5C-A.1; previously duplicated verbatim
   in both files).
   ================================================================= *)

let hierarchy : (string * string option) list = [
  ("IO",            None);
  ("IO.Console",    Some "IO");
  ("IO.FileSystem", Some "IO");
  ("IO.FileRead",   Some "IO.FileSystem");
  ("IO.FileWrite",  Some "IO.FileSystem");
  ("IO.Network",    Some "IO");
  ("IO.NetConnect", Some "IO.Network");
  ("IO.NetListen",  Some "IO.Network");
  ("IO.Process",    Some "IO");
  ("IO.Clock",      Some "IO");
  ("IO.Random",     Some "IO");
  ("IO.Database",   Some "IO.NetConnect");
  ("IO.Spawn",      Some "IO");
  ("IO.Mut",        Some "IO");
  ("IO.Telemetry",  Some "IO");
  ("IO.NetConnect.TLS", Some "IO.NetConnect");
  ("IO.Foreign",         Some "IO");
  ("IO.Foreign.Blocking", Some "IO.Foreign");
]

(** [cap_ancestors cap] returns [cap] and all its ancestors, most-specific first.
    E.g., "IO.FileRead" → ["IO.FileRead"; "IO.FileSystem"; "IO"].
    FFI caps not in the table return just themselves. *)
let cap_ancestors cap =
  let rec go c acc =
    let acc' = c :: acc in
    match List.assoc_opt c hierarchy with
    | Some (Some parent) -> go parent acc'
    | _ -> acc'
  in
  List.rev (go cap [])

(** [cap_subsumes parent child] — true if [parent] is an ancestor of (or equal to) [child].
    E.g., cap_subsumes "IO" "IO.FileRead" = true. *)
let cap_subsumes parent child =
  List.mem parent (cap_ancestors child)

(** [normalize caps] drops any cap subsumed by another cap already in the
    list, preserving the relative order of the caps that remain.  E.g.
    ["IO"; "IO.FileRead"] -> ["IO"]; ["IO.FileRead"; "IO"] -> ["IO"]. *)
let normalize caps =
  List.filter (fun c ->
    not (List.exists (fun other -> other <> c && cap_subsumes other c) caps)
  ) caps
