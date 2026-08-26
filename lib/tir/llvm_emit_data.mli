(** Record/tuple codegen: the bodies of [Llvm_emit.emit_expr]'s record
    introspection builtins and of its [ETuple] / [ERecord] / [EField] /
    [EUpdate] arms.  See [llvm_emit_data.ml].

    The arms themselves — position, guard, order — stay in [emit_expr]; only
    their bodies live here.  Call these only from the arm they were cut from. *)

(** Body of the `record_keys` / `record_values` / `record_entries` arm. *)
val emit_record_walk :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom -> string * string

(** Body of the `record_get` arm. *)
val emit_record_get :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom -> Tir.atom -> string * string

(** Body of the `record_has_key` arm. *)
val emit_record_has_key :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> Tir.atom -> string * string

(** Body of the `record_put` arm. *)
val emit_record_put :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> Tir.atom -> Tir.atom -> string * string

(** Body of the `record_from_list` arm. *)
val emit_record_from_list :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> string * string

(** Body of the non-empty [ETuple] arm. *)
val emit_tuple :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom list -> string * string

(** Body of the [ERecord] arm. *)
val emit_record :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> (string * Tir.atom) list -> string * string

(** Body of the [EField] arm. *)
val emit_field :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> string -> string * string

(** Body of the [EUpdate] arm (record update). *)
val emit_update :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> (string * Tir.atom) list -> string * string
