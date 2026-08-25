(** AST → TIR lowering: orchestrator and public entry points.

    See [lower.ml]'s module doc for the full description of the pass and of the
    Wave-3 split into [Lower_state] / [Lower_types] / [Lower_match] /
    [Lower_decls] / [Lower_actor] / [Lower_tests].

    Historically this file re-exported nearly all of those five modules'
    surfaces bare, so external callers could keep writing [Lower.x]. In
    practice only the handful of values below are used from outside; the rest
    of the re-export block stays available to in-library callers under its
    defining module's own name ([Lower_state.fresh_name], [Lower_types.unknown_ty],
    [Lower_decls.lower_fn_def], …), which is where new code should reach for it.
    Anything genuinely needed from outside should be added here deliberately. *)

module Ast = March_ast.Ast
module Typecheck = March_typecheck.Typecheck

(** Re-exported from [Lower_state] with its definition visible, so callers can
    build and pattern-match an env without naming [Lower_state]. *)
type env = Lower_state.env = {
  type_map : (Ast.span, Typecheck.ty) Hashtbl.t option;
  current_module_aliases : (string, string) Hashtbl.t;
  mod_prefix : string;
  collision_set : (string, string list) Hashtbl.t;
}

val empty_env : env

(** {1 Entry point} *)

val lower_module :
  ?type_map:(Ast.span, Typecheck.ty) Hashtbl.t ->
  ?stdlib_context:Ast.decl list ->
  ?test_mode:bool ->
  ?hot_reload:bool -> Ast.module_ -> Tir.tir_module

(** {1 Piecewise lowering}

    The REPL JIT and the eval/JS pipelines lower fragments rather than whole
    modules, and need the type converters and the prelude ADTs directly. *)

val lower_ty : Ast.ty -> Tir.ty
val convert_ty : Typecheck.ty -> Tir.ty

val lower_type_def :
  Ast.name -> Ast.name list -> Ast.type_def -> Tir.type_def option

(** The compiler's always-injected prelude ADTs (Option/Result/List). *)
val builtin_type_defs : Tir.type_def list

val collect_type_names :
  prefix:string -> Tir.type_def list -> Ast.decl list -> Tir.type_def list

(** Interface-method dispatch table, consulted after lowering by [Mono] and by
    the JIT/JS drivers. *)
val get_iface_methods : unit -> (string, (string * string) list) Hashtbl.t

(** {1 Cross-run state}

    Lowering keeps module-level tables; a driver that lowers more than once in
    a process (REPL, test harness, snapshot runner) must be able to reset and
    to reach the accumulated definitions. *)

val reset_counter : unit -> unit
val _fns_ref : Tir.fn_def list ref ref
val _types_ref : Tir.type_def list ref ref
val _lowered_modules : (string, unit) Hashtbl.t ref

(** Forward reference to the lazy stdlib-module loader, installed by this
    module at load time. *)
val _ensure_module_lowered : (env -> string -> unit) ref

(** Alias-resolution state. [test/test_codegen.ml] drives these directly to
    reproduce the cross-module qualified-alias hijack (see that test's comment);
    a caller that resets them must reset all three together. *)

val _fn_param_types : (string, Tir.ty) Hashtbl.t
val _use_aliases : (string, string) Hashtbl.t ref
val _module_aliases : (string, string) Hashtbl.t ref
val with_current_module_fns : string list -> (unit -> 'a) -> 'a
val resolve_use_alias : env -> string -> string

(** {1 Re-exports kept only to stay compilable}

    These three have no caller anywhere — inside this module, elsewhere in
    [march_tir], or outside it. They are re-export bindings of
    [Lower_state]/[Lower_decls] values, and hiding them turns them into
    unused-value errors under the project's warnings-as-errors. Declaring them
    keeps this change to "add a file, touch no code"; deleting the three
    [let] lines in [lower.ml] and these three [val]s together is a separate,
    equally safe follow-up. *)

val nonexhaustive_panic : unit -> Tir.expr
val lower_fn_def : Lower_state.env -> Ast.fn_def -> Tir.fn_def
val rename_tir_vars : string -> string list -> Tir.fn_def -> Tir.fn_def
