(** Derive an OS sandbox profile from a capability set, and run a binary under
    it (specs/2026-08-03-forge-cap-audit-design.md §4.3, mechanism B).

    Externally imposed, so nothing inside the binary needs to be trusted: the
    caller supplies the policy, the kernel enforces it. A binary that
    under-claims its capabilities is killed (or gets an error) when it exceeds
    the policy, which is what makes under-claiming self-defeating.

    NOT every capability is enforceable. See {!enforceability} — the split was
    measured, not assumed, and the unenforceable ones are reported rather than
    silently treated as enforced. *)

type enforcement =
  | Enforced      (** the OS blocks this capability when not granted *)
  | Advisory of string
      (** cannot be enforced by this mechanism; the string says why *)

val enforceability : string -> enforcement
(** [enforceability cap] — whether denying [cap] is actually enforceable on
    this platform. *)

val advisory_caps : string list
(** Capabilities this platform cannot enforce, for reporting. *)

val profile_for : caps:string list -> binary:string -> string
(** [profile_for ~caps ~binary] builds an SBPL profile (macOS) granting only
    [caps]. [binary] is allowed to be exec'd and read — denying either
    prevents the process from starting at all. *)

val bwrap_args : caps:string list -> string list
(** Bubblewrap flags (Linux) for the same capability set. *)

val supported : bool
(** Whether external enforcement is available on this platform. *)

val run : caps:string list -> binary:string -> args:string list -> (int, string) result
(** Run [binary] under a profile derived from [caps]. Returns its exit code.
    [Error] if enforcement is unavailable — never silently runs unsandboxed. *)
