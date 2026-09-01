(** The capability checker: what a module declares it [needs], and whether the
    code inside it stays within that grant.

    This module is [include]d into [Typecheck] at the position its band used to
    occupy, so everything below is re-exported there — but [typecheck.mli] is
    the wall that decides what actually leaves the library. Four of the
    fifteen values the band used to export ([cap_annots_in_expr],
    [path_arg_builtins], [literal_path_uses], [cap_in_solved_ty]) are reached
    from nowhere outside this file and are now private to it.

    [check_module_needs] is the entry point: given a module's [needs]
    declaration it walks the module's decls and reports every use that escapes
    the grant. The [check_*_sites] trio are narrower single-purpose passes over
    the same environment, and the [fn_*_capability_closures] accessors expose
    the per-function capability sets the walk computes — the LSP and the
    capability-audit tooling read those. *)

open Typecheck_types
open Typecheck_env

val is_migrate_fn_name : string -> bool

val check_module_needs :
  env -> Ast.name -> cap_qname_prefix:string -> Ast.decl list -> unit

(** Single-purpose capability passes, each run once per [check_module]. *)

val check_cap_narrow_sites : env -> unit
val check_json_cap_sites : env -> unit
val check_cap_dict_decls : env -> unit
val check_cap_impl_sites : env -> unit
val check_mint_cap_sites : env -> unit

(** Per-function capability sets, as computed by the walk above. [own] is what
    a function's own body demands; the [transitive] pair adds everything its
    callees demand. The [_tbl] forms are the underlying hashtables. *)

val fn_capability_rows_tbl :
  ?with_rows:bool -> env -> (string, March_caps.Cap_rows.row) Hashtbl.t

val fn_transitive_capability_closures_tbl :
  env -> (string, string list) Hashtbl.t

val fn_capability_closures : env -> (string * string list) list
val fn_own_capability_closures : env -> (string * string list) list
val fn_transitive_capability_closures : env -> (string * string list) list
val declared_cap_scopes : env -> (string * string option) list
