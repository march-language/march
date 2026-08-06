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
