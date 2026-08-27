(** The builtin table, the LLVM preamble, and the extern-name mangling.

    Interface for {!Llvm_builtins}, added 2026-08-27 by the pass that gave the
    highest-churn compiler files one (see
    [specs/progress/2026-08-25-mli-interfaces-top-churn-files.md]).

    34 values were exported before this file existed; 22 still are.
    [Llvm_builtins] is not [include]d by anything, so hiding here is local and
    checkable.

    {2 What is hidden}

    Twelve values, all of them the private half of a public accessor.  The
    pattern repeats: a [Hashtbl] built once at module init, plus the function
    that reads it.  Only the function is anyone's business.

    - [is_builtin_fn_tbl], [builtin_ret_ty_tbl], [builtin_declare_sig_tbl],
      [mangle_extern_tbl] and [called_syms] — backing tables for
      [is_builtin_fn], [builtin_ret_ty], [mangle_extern],
      [reset_called_syms] and [called_c_symbols], which all stay;
    - [runtime_only_declares], [declare_text], [render_item], [render_items],
      [core_items], [native_actor_items] and [wasm_scheduler_stub_items] —
      the preamble construction kit behind {!emit_preamble}.

    [native_net_io_items] is the one [preamble_item] list that does escape
    ([llvm_emit_simd.ml] reads it), which is why the [preamble_item] type
    itself stays manifest rather than going private with its siblings.

    {2 What stays}

    [builtins] has 53 referencing files and [mangle_extern] 13; the tag
    constants are read by [llvm_toplevel.ml] and are a silent-miscompile
    hazard if they drift, so the whole family is kept together.
    [emit_preamble] is pinned by a byte-identical golden in
    [test/test_codegen.ml]. *)

type builtin = {
  march_name : string;
  c_name : string option;
  ret_ty : Tir.ty option;
  in_is_builtin : bool;
  declare_sig : string option;
}
val ordinary_ctor_tag_limit : int
val actor_message_tag_base : int
val actor_message_tag_limit : int
val collision_tag_base : int
val collision_tag_limit : int
val monitor_down_tag : int
val monitor_reason_normal_tag : int
val monitor_reason_killed_tag : int
val monitor_reason_crash_tag : int
val builtins : builtin list
type preamble_item =
    PComment of string
  | PDeclare of string
  | POther of string
  | PBlank
val native_net_io_items : preamble_item list
val emit_preamble :
  is_wasm:bool -> triple:string -> ?repl:bool -> Buffer.t -> unit
val is_builtin_fn : string -> bool
val builtin_ret_ty : string -> Tir.ty option
val builtin_boxed_generic_params_tbl : (string, int list) Hashtbl.t
val builtin_param_is_boxed_generic : string -> int -> bool
val builtin_param_llvm_tys : string -> string list option
val reset_called_syms : unit -> unit
val called_c_symbols : unit -> string list
val mangle_extern : string -> string
val c_symbol_of_march_name : string -> string
