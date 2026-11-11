(** The capability checks that run on lowered TIR, shared by every mode
    (ocap phase 3, specs/plans/2026-11-10-ocap-p3-checks-plan.md): the module
    [needs] ceiling ({!March_tir.Cap_attrib} + {!March_caps.Cap_ceiling}) and
    host scopes on [IO.NetConnect] ({!March_tir.Net_scope.check}).

    The compile path calls {!host_scope_findings} and {!ceiling_findings} on
    the TIR it already has; every other mode calls {!check_program}, which
    lowers on demand.  Either way the findings are the same values, so a
    program gets the same verdict and the same diagnostic however it runs. *)

(** {1 Helpers shared with bin/main.ml} *)

val user_module_names : March_ast.Ast.decl list -> (string, unit) Hashtbl.t
(** Qualified names of the USER modules: a [DMod] whose span is a real file
    outside the stdlib root. *)

val stdlib_module_names : March_ast.Ast.decl list -> string list
(** The module names a batch of stdlib declarations defines. *)

val user_fn_names_of :
  stdlib_files:string list -> March_ast.Ast.module_ -> (string, unit) Hashtbl.t
(** The bare names of the functions the program's own files declare. *)

val tir_fn_stem : string -> string
(** A TIR function name with module prefix and mono suffix stripped. *)

val is_user_tir_fn :
  user_fns:(string, unit) Hashtbl.t -> stdlib_mods:string list -> string -> bool
(** Whether a TIR function is one the program's own files declare. *)

val cap_ceiling_module_spans :
  entry_owner:string -> entry_span:March_ast.Ast.span -> March_ast.Ast.decl list ->
  (string * March_ast.Ast.span) list * (string * bool) list
(** Each module's diagnostic span (first [needs] line, else its header) and
    whether that span is a header. *)

val cap_ceiling_fix_indent :
  src:string -> filename:string -> read_file:(string -> string) -> is_header:bool ->
  March_ast.Ast.span -> int
(** The column an inserted [needs] line for that module starts at. *)

(** {1 The checks} *)

type input = {
  desugared : March_ast.Ast.module_;  (** whole program, stdlib prepended *)
  stdlib_decls : March_ast.Ast.decl list;
  tc_env : March_typecheck.Typecheck.env;
  type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t;
  src : string;
  filename : string;
  read_file : string -> string;
  cap_strict : bool;  (** false under [--no-cap-strict]: no ceiling *)
}

type finding =
  | Diag of March_errors.Errors.diagnostic
  | Bare of string
      (** A violation with no span to point at, as the exact text the compile
          path prints (a file-less "-- CAPABILITY --" block). *)

type report = { findings : finding list; count : int }
(** [count] is the number of violations (several can share one finding). *)

val host_scope_findings : input -> March_tir.Tir.tir_module -> report
(** Over post-lower TIR (source names, literal arguments).  Empty when no
    module declares a host scope. *)

val cap_attribution : input -> pre_opt:March_tir.Tir.tir_module -> (string * string) list
(** [(capability, owner module)] over the pre-opt TIR, pruned to what the
    program reaches. *)

val ceiling_findings :
  input -> pre_opt:March_tir.Tir.tir_module -> attribution:(string * string) list ->
  report
(** Each module's attributed use against its own [needs].  Empty when
    [input.cap_strict] is false. *)

type outcome =
  | Checked of finding list
  | Unchecked of string  (** lowering failed; a one-line reason *)

val check_program : ?test_mode:bool -> opt:bool -> is_js:bool -> input -> outcome
(** Lowers [input.desugared] and runs both checks, stopping the post-lower
    pipeline at the compile path's pre-opt point.  Never raises for a program
    the compiler cannot lower: that is [Unchecked]. *)
