(** Path scopes on filesystem capabilities.

    A scope narrows a capability to a directory subtree:
    [needs IO.FileRead("/etc/myapp")]. [None] means unscoped — any path — which
    is what every capability declared without a scope means, so existing code
    keeps its current meaning.

    Deliberately separate from {!Cap_lattice}: ten modules consume capabilities
    as bare strings, including the C lattice table code-genned by
    [emit_c_table.ml]. Encoding a scope into the string would match no
    hierarchy entry and break them silently, so scopes travel alongside the
    string rather than inside it. *)

val normalize : string -> string
(** Lexically normalize a path: collapse repeated separators, resolve [.] and
    [..], strip a trailing separator. [normalize "/etc/ssl/../shadow"] is
    ["/shadow"], which is what stops a [..] escaping a scope.

    Lexical only — no filesystem access. The build machine's filesystem is not
    the deployment machine's, so symlinks are NOT resolved here. Landlock
    resolves at the inode level, so the runtime half is unaffected. *)

val is_absolute : string -> bool
(** Whether a path starts at the root. A relative scope is rejected by the
    caller: it would denote different directories depending on the working
    directory at run time. *)

val within : scope:string -> string -> bool
(** [within ~scope p] — is [p] the scope directory itself, or beneath it?
    Both sides are normalized first. Compares whole path segments, so
    [within ~scope:"/etc" "/etcpasswd"] is [false] — a prefix match on raw
    characters would wrongly accept it. *)

val scope_subsumes : string option -> string option -> bool
(** [scope_subsumes a b] — does scope [a] permit everything scope [b] does?
    [None] (unscoped) subsumes everything, including [None]. A scope never
    subsumes [None]: narrowing to a directory grants strictly less. *)

val is_scopable : string -> bool
(** Whether a capability accepts a scope at all. Only filesystem capabilities
    do; a scope elsewhere is rejected rather than ignored, because an ignored
    scope reads as enforcement that is not there. *)
