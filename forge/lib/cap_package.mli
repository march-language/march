(** Per-package capability sets, and the diff between two versions of one.

    This is the piece the whole-binary audit structurally cannot provide.
    [forge cap inspect --deny] sees the UNION of a program's capabilities, so a
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

val probe_caps_support : toolchain_prefix:string -> (unit, string) result
(** [probe_caps_support ~toolchain_prefix] runs [march caps] on a trivial
    module, with [toolchain_prefix] ({!Toolchain.path_prefix}'s output, the
    same PATH [of_package]'s commands get) and no MARCH_LIB_PATH. [Ok ()] when
    the compiler answers with a caps JSON object; otherwise an [Error] naming
    the resolved [march], its [--version], the release that introduced
    [march caps], and what the probe printed.

    Exists because a toolchain that predates the subcommand takes [caps] as a
    file name and fails, so without it every dependency reports as not
    analyzable and nothing points at the compiler. *)

val compiler_identity : toolchain_prefix:string -> string
(** A digest identifying the compiler [march] resolves to under
    [toolchain_prefix]: its resolved path, the digest of the executable it
    resolves to, the global toolchain ([~/.march/current]) and MARCH_STDLIB.
    A cache keyed on it is invalidated by a new or different compiler. *)

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

