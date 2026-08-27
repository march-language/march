(** The built-in world: the type constants, the capability tables, and the
    base environment every March module starts from.

    [include]d into [Typecheck] and [open]ed by [Typecheck_caps], so what stays
    here is what one of those two actually reads (plus what [typecheck.mli]
    re-exports). Thirteen of the thirty-nine values the band used to export are
    private to this file: the type constructors nothing outside builds
    ([t_list], [t_option], [t_pid], [t_vault] and the four dead [_t_*]
    duplicates), the interface-table constructors ([mk_builtin_iface],
    [mk_iface_method_scheme], [builtin_interfaces], [builtin_impls]) which
    exist only to feed [builtin_interface_bindings], and the [builtin_types] /
    [builtin_ctors] tables which exist only to feed [base_env]. *)

open Typecheck_types
open Typecheck_env

(** {1 Type constants} *)

val t_int : ty
val t_float : ty
val t_bool : ty
val t_string : ty
val t_unit : ty
val t_atom : ty
val t_result : ty -> ty -> ty

(** {1 Stdlib provenance}

    [stdlib_source_files] is set by the driver before checking; [span_is_stdlib]
    is the predicate the diagnostic filter reads off it. Mutating the ref after
    a check has started will not retroactively reclassify spans. *)

val stdlib_source_files : string list ref
val span_is_stdlib : Ast.span -> bool

(** {1 Capabilities} *)

val cap_strict_ceiling : bool ref
val builtin_cap_table : (string * string) list

(** [cap_subsumes broad narrow] — whether a grant of [broad] covers [narrow]. *)
val cap_subsumes : string -> string -> bool

val cap_path_of_names : Ast.name list -> string
val cap_paths_in_surface_ty : Ast.ty -> string list
val local_module_paths : env -> string list
val same_package_namespace : string -> string -> bool

(** {1 Builtin bindings and the base environment} *)

val locally_declared_names_of : Ast.decl list -> (string, unit) Hashtbl.t
val builtin_interface_bindings : (string * scheme) list
val builtin_bindings : (string * scheme) list
val prelude_collision_builtin_names : string list
val prelude_collision_iface_arities : (string * int) list
val noncallable_builtin_values : StringSet.t

(** [base_env ctx span_tys] is the environment a fresh module starts from. *)
val base_env : Err.ctx -> (Ast.span, ty) Hashtbl.t -> env
