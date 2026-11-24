(** Dependency grants (ocap phase 6): the grants file and package membership.

    A grant limits every function defined in a dependency's package to the
    capabilities written in the consumer's [forge.toml] (`grant = [...]`, in
    `needs` syntax).  forge writes the grants as a file and points the
    compiler at it with [MARCH_DEP_GRANTS]; [march --dep-grants FILE] does the
    same by hand, and wins over the variable.

    The file: UTF-8, one package per line, four tab-separated fields,
    {v <package>\t<lib root, absolute>\t<manifest>:<line>\t<scope text> v}
    A line starting with [#] is a comment and a blank line is skipped.  The
    scope text is the grant's strings joined with [", "]; [()] grants
    nothing.  A field holding a tab (a fifth field) or a carriage return is
    rejected.  The library root must be absolute and must exist; it is stored
    as its real path, with no trailing slash.

    With neither the flag nor the variable set nothing is loaded:
    [active ()] is [[]], [digest ()] is [None], and every pass that reads the
    grants is the identity.  A file with no entries means the same. *)

type grant = {
  g_pkg : string;  (** forge dep name, as written *)
  g_root : string;  (** real path of the library root, no trailing slash *)
  g_manifest : string;  (** the [forge.toml] path, as given *)
  g_line : int;  (** 1-based line of the dep's entry in [g_manifest] *)
  g_text : string;  (** canonical scope text, ["()"] for none *)
  g_entries : (March_ast.Ast.name list * string option) list;
      (** the entries, encoded as the parser encodes a `needs` line *)
  g_scoped : bool;  (** whether any entry carries a scope *)
}

val env_var : string
(** ["MARCH_DEP_GRANTS"]. *)

val load : ?flag:string -> unit -> (grant list, string * int option) result
(** Read the grants file named by [flag], else by [MARCH_DEP_GRANTS] (an
    empty value counts as unset), else none: [Ok []].  An error carries a
    message and the 1-based line of the grants file it is about ([None] when
    the file itself cannot be read).  Does not change [active]. *)

val parse_scope_text :
  string -> ((March_ast.Ast.name list * string option) list, string) result
(** Parse a grant's scope text with the real parser, as the body of
    [mod G__ do needs <text> end]; only a module whose sole content is that
    `needs` line is accepted.  ["()"] is [Ok []].  The entries' scopes are
    not judged here: the type checker runs [validate_cap_scopes] on them. *)

val set_active : grant list -> unit
(** Install the grants for this compilation.  Clears the membership memo and
    [proven]. *)

val active : unit -> grant list
(** The installed grants; [[]] means no grants (every pass is the identity). *)

val package_of_file : string -> grant option
(** The granted package [file] belongs to: the grant with the longest
    library root containing the file.  Decided twice, and the two must
    agree: by the file's real path, and by the location the loader found it
    at (each MARCH_LIB_PATH directory whose spelling contains the file's,
    taken at its real path, plus the rest of the file's spelling).  When they
    disagree (a file under a granted root that is a symlink to code outside
    it, a symlinked subdirectory, or the reverse) the file is recorded in
    {!conflicts} and the package of its spelled location is returned (else
    the real path's), so the grant still applies.  [None] under no root, and
    always [None] when no grants are active, without touching the file
    system.  Memoised per file name. *)

val impl_method_file : impl_file:string -> March_ast.Ast.span -> string
(** The file that decides an impl method's package: the method name's own
    file when it has a real one, else the impl's ([impl_file]).  A method
    written in the impl has its name in the impl's file; an interface
    default body the impl inherits ([Desugar.inject_defaults]) has the
    interface's method name, so it belongs to the package that declares the
    interface, not to the impl's; a derived method's name is synthetic
    ("<none>"), so it takes the impl's. *)

type conflict = {
  c_file : string;  (** the file as the loader named it *)
  c_real : string;  (** its real path *)
  c_logical : grant option;  (** the package its spelled location is in *)
  c_resolved : grant option;  (** the package its real path is in *)
}

val conflicts : unit -> conflict list
(** Every file [package_of_file] found on both sides of a granted root so
    far, by file name.  The type checker reports each as
    [dep_grant_invalid]. *)

val digest : unit -> string option
(** A hex digest of the active grants, for cache keys; [None] when no grants
    are active. *)

val proven : (string, unit) Hashtbl.t
(** Granted-package functions whose transitive capability row the type
    checker proved within their package's grant and which reach no call of
    an untraceable function value (filled by [Typecheck.check_dep_grants]).

    Keyed by the type checker's capability key, exactly as in its
    [fn_refs] / [fn_bound_points]: the module path (the entry module's
    name excluded: it is unwrapped) and the function's name joined by
    ["."], e.g. ["Weather.forecast"], ["Weather.Telemetry.ping"]; an impl
    method is ["<Mod>.<Iface>$<Ty>.<method>"], a module-level binding is
    keyed like a function of its name.  A lookup from a definition derives
    the key from the def's module path and its name. *)

val root_problem : grant -> string option
(** [Some why] when the grant's library root is neither one of the
    [MARCH_LIB_PATH] directories nor a parent of one (plan decision 2):
    such a grant would govern no code the build loads as a dependency. *)

(** What `march repl FILE` does with its entry under grants, from the exit
    status and the output of the `march --check FILE` child it runs first. *)
type preload_verdict = Load | Refuse of string

val preload_check_verdict : Unix.process_status -> string -> preload_verdict
(** [Refuse] when the output reports a grant diagnostic ([[dep_grant_...]]
    or [[dep_module_conflict]]), whatever the status.  Otherwise [Load] when
    the child exited 0, or exited 1 having printed at least one rendered
    diagnostic (an ordinary error in the entry, which the REPL reports
    itself when it loads the file).  Anything else fails closed: a child
    that crashed (an uncaught exception exits 2), was killed or stopped by a
    signal, or exited non-zero with no diagnostic it can recognise, never
    finished the grant checks, so the entry is not loaded unchecked. *)
