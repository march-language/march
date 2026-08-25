(** Desugaring: the AST-to-AST pass between parsing and typechecking.

    It lowers surface conveniences onto the core AST — pipes, multi-head
    function definitions into a single [EMatch] clause, [let?] propagation,
    string/HTML interpolation, [derive]/[satisfy] expansion, interface default
    methods, and module-reference qualification.  Everything it emits is
    ordinary AST; nothing downstream needs to know a desugaring happened.

    The exported surface below is deliberately small.  The bulk of this module
    is single-purpose helpers for one of those expansions; if you need one from
    outside, widen this file on purpose rather than by reflex. *)

module Err = March_errors.Errors

(** {1 Entry point} *)

val desugar_module :
  ?errors:Err.ctx ->
  ?is_entry:bool -> March_ast.Ast.module_ -> March_ast.Ast.module_

(** {1 Sub-entry points}

    Used by consumers that hold something smaller than a module: the REPL and
    LSP desugar a bare expression, and the driver re-runs individual stages. *)

val desugar_expr : March_ast.Ast.expr -> March_ast.Ast.expr
val desugar_ty : March_ast.Ast.ty -> March_ast.Ast.ty
val desugar_decl : March_ast.Ast.decl -> March_ast.Ast.decl

val inject_defaults :
  (string * March_ast.Ast.interface_def) list ->
  March_ast.Ast.decl -> March_ast.Ast.decl

(** {1 Module qualification} *)

val make_qualifier :
  string ->
  string list -> string list -> March_ast.Ast.expr -> March_ast.Ast.expr

val qualify_module_refs :
  ?entry_prefix:string -> March_ast.Ast.decl list -> March_ast.Ast.decl list

val collect_direct_names :
  externs:bool -> March_ast.Ast.decl list -> string list

(** {1 Misc. helpers with outside callers} *)

(** Normalises a refinement predicate's qualifier chain; used by refinecheck. *)
val flatten_pred_quals : March_ast.Ast.expr -> March_ast.Ast.expr

(** Rewrites spans to fresh synthetic ones, so derived/injected code cannot be
    mistaken for user source by diagnostics. *)
val respan_ty : March_ast.Ast.ty -> March_ast.Ast.ty

val check_main_signature : Err.ctx -> March_ast.Ast.decl list -> unit
