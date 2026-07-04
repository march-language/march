(** Capability hierarchy for `needs` / `Cap` checking.

    Shared between the typechecker's body-scan (Phase 2, [March_typecheck.Typecheck])
    and the refinement checker's capability-inference hints
    ([March_refinecheck.Cap_infer]) — both need the identical subsumption rule,
    so the hierarchy lives here as a single source of truth. *)

(** [hierarchy] — each entry is [(cap_path, parent_path option)].
    Paths are dot-joined strings, e.g. ["IO.FileRead"].
    FFI caps like ["LibC"] are valid but not in this table — they are
    their own roots and have no subtyping relationship. *)
val hierarchy : (string * string option) list

(** [cap_ancestors cap] returns [cap] and all its ancestors, most-specific first.
    E.g., ["IO.FileRead"] -> [["IO.FileRead"; "IO.FileSystem"; "IO"]].
    FFI caps not in the table return just themselves. *)
val cap_ancestors : string -> string list

(** [cap_subsumes parent child] — true if [parent] is an ancestor of (or equal
    to) [child]. E.g., [cap_subsumes "IO" "IO.FileRead" = true]. *)
val cap_subsumes : string -> string -> bool

(** [normalize caps] drops any cap in [caps] that is already subsumed by
    another cap in the list (e.g. ["IO"; "IO.FileRead"] -> ["IO"]).  Preserves
    the relative order of the caps that remain. *)
val normalize : string list -> string list
