(** Run-time frames for function `needs` clauses (ocap phase 4): see
    auth_rt.ml.  Runs right after [Lower.lower_module] (native, [--jit], the
    REPL JIT and JS). *)

(** The fns of a module that reach an actor spawn through direct calls. *)
val reaches_actor_spawn : Tir.tir_module -> Set.Make(String).t

(** The fns of a module that reach a call of a function value (an
    [ECallPtr], or an [EApp] of a local binding) through direct calls. *)
val reaches_indirect_call : Tir.tir_module -> Set.Make(String).t

(** [frames m ~needs] frames every fn of [m] whose `needs` clause
    ([needs], keyed by TIR fn name: normally [Lower.fn_needs_tbl]) carries a
    scope, or that reaches an actor spawn or a call of a function value,
    except the program entry.  Returns
    the module and whether any frame was made; with none, [m] itself
    (physically). *)
val frames :
  Tir.tir_module -> needs:(string, Lower_state.fn_needs) Hashtbl.t -> Tir.tir_module * bool
