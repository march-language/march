(** Capability positions in surface ([Ast.ty]) syntax.

    Shared by the typechecker's [needs]-coverage checks and the desugarer's
    [derive Json] rejection so the two cannot drift apart.  Both functions are
    exhaustive over their constructor sets with no wildcard arm; see the
    implementation for why that is load-bearing rather than stylistic. *)

module Ast = March_ast.Ast

val caps_in_ty : Ast.ty -> string list
(** [caps_in_ty ty] returns every capability path named by a [Cap(X)] anywhere
    in [ty], left to right, duplicates retained.  A [Cap] applied to anything
    other than a bare nullary constructor contributes nothing. *)

val caps_in_type_def : Ast.type_def -> string list
(** [caps_in_type_def td] returns every capability path named in a type
    declaration's body: record field types, variant constructor arguments, or
    an alias right-hand side. *)

(** [mentions_tycon name ty]: does a type constructor called [name] occur
    anywhere in [ty]?  Same walk and exhaustiveness discipline as [caps_in_ty]. *)
val mentions_tycon : string -> Ast.ty -> bool

(** [type_def_mentions_tycon name td]: [mentions_tycon] over every position of
    a declaration body.  [derive Json] uses it to refuse a type with a [Pid]
    anywhere in it -- a local pid means nothing on another node. *)
val type_def_mentions_tycon : string -> Ast.type_def -> bool

(** The resource-handle types (ocap phase 2b): each spelling a program may
    write for a stdlib type that is or wraps a handle box, with the name a
    diagnostic shows for it.  The one list the [derive Json] refusal and the
    typed remote send's check both read. *)
val handle_type_spellings : (string * string) list

(** [handle_type_named n]: the displayed handle-type name when [n] spells one. *)
val handle_type_named : string -> string option

(** [handle_in_ty ?shadowed ty]: the first handle type named anywhere in
    [ty] (its displayed name and the written constructor), ignoring a
    constructor whose spelling is in [shadowed]. *)
val handle_in_ty : ?shadowed:string list -> Ast.ty -> (string * Ast.name) option
