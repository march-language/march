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

(** {1 Scope manifest}

    A compiled binary carries its DECLARED filesystem scopes in a manifest
    blob, [MARCHCAP\x01<u32 le length><json>], which forge's [Cap_binary]
    reads back so [forge cap run] can narrow its external sandbox to them.
    A declared scope is a claim, not a proof, and for enforcement a claim is
    enough. The sandbox blocks everything outside it, so a binary that
    under-states its scope only breaks itself. *)

val effective_scopes :
  decls:(string * string option) list -> string -> string list option
(** [effective_scopes ~decls klass] — the directories an OS-level class
    ([IO.FileRead] or [IO.FileWrite]) is narrowed to by [decls]. A
    declaration counts when its capability is an ancestor or a descendant of
    [klass], so [IO.FileSystem("/srv")] scopes both reads and writes. [None]
    (no narrowing) when no declaration is related, or when any related one is
    unscoped: one unrestricted grant means any path, so narrowing would be a
    lie. Scopes come back normalized, sorted and de-duplicated. *)

val manifest_json : (string * string option) list -> string option
(** [manifest_json decls] — the JSON body of the scope manifest,
    [{"v":1,"scopes":[{"cap":"IO.FileWrite","scope":"/srv"},
    {"cap":"IO","scope":null}]}]. Keeps only declarations related to a
    filesystem class, unscoped ones included, so the reader can see that an
    unrestricted grant overrides a scope. [None] when none of them carries a
    scope: an unscoped program gets no manifest, and its IR is unchanged. *)
