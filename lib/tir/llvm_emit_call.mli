(** Call codegen: the bodies of [Llvm_emit.emit_expr]'s general [EApp] arm and
    of its [ECallPtr] arms.  See [llvm_emit_call.ml].

    The arms themselves — position, guard, order — stay in [emit_expr]; only
    their bodies live here.  Call these only from the arm they were cut from. *)

(** Drop the call-scoped SIMD vector temp boxes collected for one call site. *)
val release_temp_boxes : Llvm_ctx.ctx -> string list ref -> unit

(** Return type of a function variable's type ([TFn] result, else itself). *)
val fn_ret_tir : Tir.ty -> Tir.ty

(** Body of the general [EApp] arm: the direct-call path for everything no
    earlier arm intercepted. *)
val emit_generic_app :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom list -> string * string

(** Body of the [ECallPtr]-to-a-`raises`-extern arm. *)
val emit_callptr_raises :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom list -> string * string

(** Body of the [ECallPtr]-to-a-`blocking`-extern arm. *)
val emit_callptr_blocking :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom list -> string * string

(** Body of the [ECallPtr]-to-an-unqualified-cross-module-function arm. *)
val emit_callptr_unqualified :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom list -> string * string

(** Body of the [ECallPtr]-with-no-local-alloca-slot arm: a direct call to the
    global function. *)
val emit_callptr_global :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom list -> string * string

(** Body of the generic [ECallPtr] arm: an indirect call dispatched through a
    closure struct. *)
val emit_callptr_closure :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> Tir.atom list -> string * string
