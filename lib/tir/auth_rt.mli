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

(** [restricts m ~sites] drops the run-time frame of every [restrict] block
    the static check already proves (ocap phase 5, decision 7).  [sites] is
    normally [Lower.restrict_sites].  A literal restrict (its [rs_text] is
    [Some _]) whose text carries no scope, and whose body calls no actor
    spawn, no fn of [reaches_actor_spawn] or [reaches_indirect_call], and no
    function value, is replaced by its body, and its [$auth_layer] fn is
    removed; every other restrict keeps its frame.  Runs before [frames].
    Returns the module and whether any frame was kept; with no sites, [m]
    itself (physically) and [false]. *)
val restricts :
  Tir.tir_module -> sites:(string, Lower_state.restrict_site) Hashtbl.t -> Tir.tir_module * bool

(** [grants m ~tbl] runs every fn of a granted dependency package ([tbl],
    keyed by TIR fn name: normally [Lower.fn_grant_tbl]) under its
    package's grant (ocap phase 6, plan decisions 6, 7 and 9).  A tagged fn
    [f] becomes a wrapper that enters [ByGrant(<pkg>)] around [f$grant], its
    original body, whose direct calls of its package's wrapped fns (not
    those in a lambda it makes) target their [$grant] bodies; every other
    call and every value use keeps the wrapper's name.  The wrapper is
    dropped (the fn left as it was) when the grant carries no scope, the
    fn is [fg_proven] and it reaches (through direct calls) no actor spawn,
    no call of a function value and no unresolved interface-method call
    (which mono may resolve to an impl outside the package).  A
    module-initialiser lambda made in a tagged fn
    ([Lower_state.is_module_init_lambda]) gets the grant's frame around its
    own body; so does a named fn value in a tagged module-initialiser fn
    whose call can depend on the authority, first turned into such a
    lambda (an eta expansion).  Runs after [frames]; returns the module and whether any
    grant frame was made: with an empty [tbl], [m] itself (physically) and
    [false]. *)
val grants :
  Tir.tir_module -> tbl:(string, Lower_state.fn_grant) Hashtbl.t -> Tir.tir_module * bool

(** [captures m ~has_frames ~repl]: a function value runs under the
    authority it was made under, not its caller's (design §5).  Runs right
    after [grants], with [has_frames] true when [frames], [restricts] or
    [grants] kept a frame.  The identity (physically [m]) when [not has_frames &&
    not repl]: with no frame every slot holds the launch authority, so a
    capture would change nothing.  Otherwise:
    - a lambda whose body reaches a capability operation, an actor spawn or
      a call of a function value enters the
      authority saved by [cap_save()] at the top of the body that makes it
      (or right after a [restrict] frame's entry, for one made inside it)
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
