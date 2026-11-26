(** Capture sets (ocap phase 8a, specs/2026-11-11-ocap-capture-checking-design.md
    §3): a finite set of scopes in the [needs] scope language, an upper bound on
    what a function value can do when called.  This module is the scope part
    only; set variables live in the capture pass ([Capture_solve]), and tracked
    names arrive with phase 8b.

    [unknown] is one extra element above every set, [full] included: the
    answer for a value the capture pass does not model.  It is never smaller
    than the truth. *)

type scope = { kind : string; arg : string option }
(** A capability path ("IO.FileRead") and its scope in the parser's [needs]
    encoding ([Scope_expr.entry]'s string), [None] when unscoped. *)

type t

val empty : t
val full : t
(** [IO]: any authority. *)

val unknown : t

type name = { label : string; id : int }
(** A tracked name (design §3, ocap phase 8b): the scoped handle one use of a
    function with a `scoped` callback parameter hands out.  [label] is the
    source name it prints as; [id] tells two handles with one label apart. *)

val of_name : name -> t
val names : t -> name list
(** Sorted by id.  Kept beside [unknown] too: a value the pass does not follow
    can still be known to hold a scoped handle. *)

val without_names : t -> t

val unknown_origin : t
(** [unknown], marked as a value whose origin the pass does not know (a
    function value read from a table opened by name): calling it with a scoped
    handle is an escape.  The mark travels like a name and is never printed,
    listed by [names] or compared by [covers]. *)

val has_unknown_origin : t -> bool
val of_scopes : scope list -> t
val of_entries : Scope_expr.entry list -> t
val scopes : t -> scope list
(** Sorted; [[]] for [unknown]. *)

val is_unknown : t -> bool
val is_empty : t -> bool
val equal : t -> t -> bool
val union : t -> t -> t

val scope_covers : scope -> scope -> bool
(** [scope_covers a b]: everything [b] permits, [a] permits. *)

val covers : sup:t -> t -> bool
(** No scope covers a tracked name, [full] and [unknown] included: only a set
    that holds the name does. *)

val narrow : t -> by:t -> t
(** An upper bound of the intersection, exact when one side is unscoped or
    covers the other.  An element [by] covers is kept; an unscoped element is
    replaced by the entries of [by] beneath or above its kind (taking their
    scope); an element with no related entry in [by] is dropped; a scoped
    element that covers every related entry of [by] is replaced by them;
    any other scoped element [by] relates to is kept whole.  [unknown] is
    never narrowed, and narrowing by [unknown] or [full] changes nothing.
    Tracked names are never narrowed. *)

val admits : t -> kind:string -> target:string -> cwd:string -> bool
(** Whether a run-time operation is inside the set: the judgement of
    [Authority.admits] (stdlib/authority.march), as
    test/test_authority_differential.ml states it in OCaml.  A path target
    and a relative path scope are resolved against [cwd]; a network target
    is [host:port]; a path scope on a host is not judged here. *)

val scope_to_string : scope -> string
val to_string : t -> string
(** [needs] syntax, entries joined by [", "]; [""] when empty, ["?"] for
    [unknown]; tracked names follow the scopes, by label. *)
