(** `~H` sigil codegen: the bodies of [Llvm_emit.emit_expr]'s
    `html_auto_escape` and `html_escape_ctx` arms.  See [llvm_emit_html.ml].

    The arms themselves — position, guard, order — stay in [emit_expr]; only
    their bodies live here.  Their ORDER is the design of this family (the
    [Html.Safe] fast path before the general escape; the literal-id escape
    before the dynamic-id one), which is why nothing was regrouped.  Call these
    only from the arm they were cut from. *)

(** Body of the `html_auto_escape` arm for an [Html.Safe] argument. *)
val emit_html_auto_escape_safe :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> string * string

(** Body of the general `html_auto_escape` arm. *)
val emit_html_auto_escape :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> string * string

(** Body of the `html_escape_ctx` arm for a compile-time escaper id. *)
val emit_html_escape_ctx_static :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> int -> Tir.atom -> string * string

(** Body of the `html_escape_ctx` arm for a runtime escaper id. *)
val emit_html_escape_ctx_dynamic :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> Tir.atom -> string * string
