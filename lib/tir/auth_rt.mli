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

(** [captures m ~has_frames ~repl]: a function value runs under the
    authority it was made under, not its caller's (design §5).  Runs right
    after [frames].  The identity (physically [m]) when [not has_frames &&
    not repl]: with no frame every slot holds the launch authority, so a
    capture would change nothing.  Otherwise:
    - a lambda whose body reaches a capability operation, an actor spawn or
      a call of a function value enters the
      authority saved by [cap_save()] at the top of the body that makes it
      ([cap_enter] / [cap_restore] around its body; a self-recursive lambda
      keeps its self tail call by moving its body to an uncaptured lambda);
    - a named fn used as a value (an [AVar] of such a fn of [m], or of a
      capability builtin, outside callee position) becomes such a lambda,
      an eta expansion;
    - nothing made by module-initialiser code (a module-level let's
      initialiser) captures: it runs under its caller's authority
      (design §21).

    It tells module-initialiser code apart through the [Lower_state] tables
    ([is_module_init_lambda], [is_module_init_binder], [is_module_init_fn])
    that the most recent [Lower.lower_module] left, reset by the next one:
    call it on that module, with no other lowering in between. *)
val captures : Tir.tir_module -> has_frames:bool -> repl:bool -> Tir.tir_module
