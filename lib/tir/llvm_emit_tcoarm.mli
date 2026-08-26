(** TCO back-edge codegen: the bodies of [Llvm_emit.emit_expr]'s four
    Perceus-wrapped tail-call interception arms, plus the closure
    free-variable load arm that sits with them.  See [llvm_emit_tcoarm.ml].

    The arms themselves — position, guard, order — stay in [emit_expr]; only
    their bodies live here.  These arms sit ABOVE most builtin arms and that
    precedence is load-bearing, so nothing was regrouped.  [Llvm_tco] holds the
    tail-call ANALYSIS the guards run; this module holds only the emission that
    follows it.  Call these only from the arm they were cut from. *)

type emit_atom_fn = Llvm_ctx.ctx -> Tir.atom -> string * string
type emit_expr_fn = Llvm_ctx.ctx -> Tir.expr -> string * string

(** Body of the closure free-variable load arm. *)
val emit_fv_load :
  emit_atom:emit_atom_fn -> emit_expr:emit_expr_fn ->
  Llvm_ctx.ctx -> Tir.var -> Tir.expr -> Tir.expr -> string * string

(** Body of the Perceus-wrapped self-TCO arm, [ELet] shape. *)
val emit_self_tco_let :
  emit_atom:emit_atom_fn -> emit_expr:emit_expr_fn ->
  Llvm_ctx.ctx -> Tir.atom list -> Tir.expr -> string * string

(** Body of the Perceus-wrapped self-TCO arm, no-temp [ESeq] shape. *)
val emit_self_tco_seq :
  emit_atom:emit_atom_fn -> emit_expr:emit_expr_fn ->
  Llvm_ctx.ctx -> Tir.atom list -> Tir.expr -> string * string

(** Body of the Perceus-wrapped mutual-TCO arm, [ELet] shape. *)
val emit_mutual_tco_let :
  emit_atom:emit_atom_fn -> emit_expr:emit_expr_fn ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom list -> Tir.expr -> string * string

(** Body of the Perceus-wrapped mutual-TCO arm, no-temp [ESeq] shape. *)
val emit_mutual_tco_seq :
  emit_atom:emit_atom_fn -> emit_expr:emit_expr_fn ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom list -> Tir.expr -> string * string
