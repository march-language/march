(** Arithmetic and comparison codegen: the bodies of [Llvm_emit.emit_expr]'s
    `+ - * / %`, `== != < <= > >=` and `+. -. *. /.` arms.  See
    [llvm_emit_arith.ml].

    The arms themselves — position, guard, order — stay in [emit_expr]; only
    their bodies live here.  Call these only from the arm they were cut from. *)

(** LLVM opcode for an integer `+ - * / %`. *)
val int_arith_op : string -> string

(** LLVM `icmp` predicate for a March comparison operator. *)
val int_cmp_pred : string -> string

(** LLVM opcode for a float `+. -. *. /.`. *)
val float_arith_op : string -> string

(** Body of the `+ - * / %` arm ([is_int_arith] guard). *)
val emit_int_arith :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom -> Tir.atom -> string * string

(** Body of the `== != < <= > >=` arm ([is_int_cmp] guard). *)
val emit_int_cmp :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom -> Tir.atom -> string * string

(** Body of the `+. -. *. /.` arm ([is_float_arith] guard). *)
val emit_float_arith :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom -> Tir.atom -> string * string
