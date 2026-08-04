(** Per-package capability sets, and the diff between two versions of one.

    This is the piece the whole-binary audit structurally cannot provide.
    [forge cap audit --deny] sees the UNION of a program's capabilities, so a
    dependency abusing a capability the application already holds is invisible
    to it — any web app holds [IO.Network] and [IO.FileRead], and a compromised
    dependency exfiltrating files adds no new capability to that union.

    The per-package delta does see it, and sees it at the moment a dependency
    enters the tree rather than after it runs. That is the xz / event-stream
    shape: a previously-pure library quietly growing an effect class. *)

type t = {
  name : string;
  caps : string list;  (** normalized, sorted *)
}

val of_package : root:string -> env_prefix:string -> (t, string) result
(** [of_package ~root ~env_prefix] computes the capability set of the package
    rooted at [root] by invoking [march caps] over all of its [.march] files.
    [env_prefix] is {!Cmd_build.lib_path_env}'s output — a complete shell
    assignment prefix, used verbatim as {!Cmd_build.check_all} does. Do not
    try to parse a value out of it: the first [=] belongs to [PATH].

    Whole-package, never per-file: most files in a real package reference
    sibling modules and fail standalone, and a union over the ones that happen
    to typecheck under-reports — the direction that certifies a package as
    needing LESS than it does. [Error] if the package cannot be analyzed, which
    callers must surface rather than treating as "no capabilities". *)

type change =
  | Gained of string list  (** capabilities the new version has and the old did not *)
  | Lost of string list
  | Unchanged

val diff : old_caps:string list -> new_caps:string list -> change list
(** Capability delta between two versions of a package. Uses lattice
    subsumption, not string equality: a version moving from [IO.NetConnect] to
    the broader [IO.Network] is a WIDENING and is reported as gained, while
    narrowing to a sub-capability is not. *)

val format_change : name:string -> old_version:string -> new_version:string ->
  change list -> string option
(** Human-readable summary, or [None] when nothing widened and nothing was
    lost. *)

val widens : change list -> bool
(** Whether any capability was gained — the condition an upgrade gate should
    require acknowledgement for. Losing a capability is safe and never gates. *)

val load_baseline : string -> (string * string list) list
(** Reviewed capability set per dependency, from [<root>/.forge/cap-baseline].
    Empty when no baseline has been recorded. *)

val save_baseline : string -> (string * string list) list -> unit
(** Record the current sets as reviewed. *)
