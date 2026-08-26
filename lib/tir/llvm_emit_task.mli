(** Task codegen: the bodies of [Llvm_emit.emit_expr]'s three non-trivial
    task/distribution builtin arms.  See [llvm_emit_task.ml].

    The arms themselves — position, guard, order — stay in [emit_expr]; only
    their bodies live here.  The other ~15 task arms are three to six lines
    each and stay inline.  Call these only from the arm they were cut from. *)

(** Body of the `task_await_unwrap` arm. *)
val emit_task_await_unwrap :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> string * string

(** Body of the `task_await` arm. *)
val emit_task_await :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> string * string

(** Body of the `remote_ref_hashes` arm: constant-folds (sig_hash, impl_hash)
    for a remote function reference. *)
val emit_remote_ref_hashes :
  Llvm_ctx.ctx -> Tir.atom -> Tir.atom -> string * string
