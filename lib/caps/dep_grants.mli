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
(** The grant whose library root is the longest prefix of [file]'s real
    path ([None] under no root, and always [None] when no grants are
    active, without touching the file system).  Memoised per file name. *)

val digest : unit -> string option
(** A hex digest of the active grants, for cache keys; [None] when no grants
    are active. *)

val proven : (string, unit) Hashtbl.t
(** Granted-package functions whose transitive capability row the type
    checker proved within their package's grant (filled by the checker). *)
