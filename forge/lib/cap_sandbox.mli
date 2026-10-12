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

val profile_for :
  ?scopes:(string * string option) list -> caps:string list -> binary:string ->
  unit -> string
(** [profile_for ?scopes ~caps ~binary ()] builds a DENY-DEFAULT SBPL profile (macOS)
    granting only [caps] plus the runtime baseline. Anything neither granted
    nor required to reach [main] is refused, including resources the
    capability lattice never modelled (IPC, IOKit, mach services). [binary]
    must stay readable or it cannot be mapped.

    [scopes] are the binary's declared path scopes ({!Cap_binary.scope_decls};
    default none). A held [IO.FileWrite] whose declarations are all scoped
    becomes [(allow file-write* (subpath ...))] per scope, resolved through
    symlinks on this machine, instead of a blanket write grant. Read scopes
    are not applied: [file-read*] is baseline here. *)

val bwrap_args :
  ?binary:string -> ?scopes:(string * string option) list ->
  caps:string list -> unit -> string list
(** Bubblewrap flags (Linux) for the same capability set. With [scopes], a
    held [IO.FileRead] scoped to directories gets the allow-list namespace
    plus a read-only bind of each scope, and a held [IO.FileWrite] scoped to
    directories gets a writable bind of each (over a read-only root when reads
    are unscoped). An unscoped write grant keeps [--dev-bind / /], and a read
    scope is then not enforceable; {!scope_notes} says so. *)

val resolve_scope : string -> string
(** Resolve a scope against this machine's filesystem: realpath of the
    longest existing prefix, remaining components re-appended. *)

val scope_notes :
  caps:string list -> scopes:(string * string option) list -> string list
(** One line per declared scope that narrows a held class, saying whether
    this backend enforces it. Printed by [forge cap run] before running. *)

val supported : bool
(** Whether external enforcement is available on this platform. *)

val run :
  ?scopes:(string * string option) list -> caps:string list -> binary:string ->
  args:string list -> unit -> (int, string) result
(** Run [binary] under a profile derived from [caps], narrowed by [scopes]. Returns its exit code.
    [Error] if enforcement is unavailable — never silently runs unsandboxed. *)
