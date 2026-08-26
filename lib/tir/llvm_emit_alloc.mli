(** Allocation codegen: the bodies of [Llvm_emit.emit_expr]'s [EAlloc],
    [EAllocHole], [EStackAlloc] and [EReuse] arms.  See [llvm_emit_alloc.ml].

    The arms themselves — position, guard, order — stay in [emit_expr]; only
    their bodies live here.  Call these only from the arm they were cut from. *)

(** Body of the capture-free-lambda [EAlloc] arm: a static immortal global
    closure rather than a heap allocation. *)
val emit_static_closure :
  Llvm_ctx.ctx -> string -> Tir.atom -> string * string

(** Body of the [EAlloc] constructor arm (the general heap allocation). *)
val emit_alloc_ctor :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> string -> Tir.ty list -> Tir.atom list -> string * string

(** Body of the non-constructor [EAlloc] arm (tuples / erased cells). *)
val emit_alloc_uniform :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) -> Llvm_ctx.ctx -> Tir.atom list -> string * string

(** Body of the [EAllocHole] constructor arm (TRMC hole allocation). *)
val emit_alloc_hole :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom option -> string -> Tir.atom list -> int ->
  string * string

(** Body of the [EStackAlloc] constructor arm. *)
val emit_stack_alloc_ctor :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> string -> Tir.atom list -> string * string

(** Body of the non-constructor [EStackAlloc] arm. *)
val emit_stack_alloc_uniform :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) -> Llvm_ctx.ctx -> Tir.atom list -> string * string

(** Body of the [EReuse] constructor arm: FBIP in-place reuse guarded on RC=1,
    falling back to a fresh allocation. *)
val emit_reuse_ctor :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> string -> Tir.atom list -> string * string

(** Body of the non-constructor [EReuse] arm. *)
val emit_reuse_uniform :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.atom -> Tir.ty -> Tir.atom list -> string * string
