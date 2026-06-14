(** Shared purity oracle.
    Conservative: returns [false] when uncertain.
    False negatives (treating pure as impure) are safe; false positives are not.

    Strategy: whitelist clearly-impure builtins. Any builtin name not on this
    list is assumed pure *for the purposes of fusion and inlining*, which only
    operate on stdlib list/math functions anyway.  User-defined function calls
    are conservatively treated as impure via the [ECallPtr] case. *)

(** Builtins that have observable side effects: IO, randomness, network,
    process control, actor/task creation, time. *)
let impure_builtins = [
  (* Console IO *)
  "print"; "println"; "march_print"; "march_println";
  "print_int"; "print_float"; "print_char";
  "read_line"; "io_read_line"; "process_read_line";
  (* File IO *)
  "file_read_line"; "file_open"; "file_close";
  "file_read"; "file_write"; "file_write_line";
  (* Network / TLS *)
  "tcp_connect"; "tcp_send_all"; "tcp_recv_all"; "tcp_recv_exact"; "tcp_close";
  "tls_connect"; "tls_read"; "tls_write"; "tls_close";
  (* Randomness / non-determinism *)
  "random_bytes"; "stdlib_random_bytes";
  "uuid_v4";
  (* Time *)
  "unix_time"; "sys_uptime_ms";
  (* Actors / tasks / processes *)
  "send"; "kill"; "spawn"; "receive";
  "task_spawn"; "task_spawn_steal"; "task_spawn_link";
  "actor_cast"; "actor_call"; "actor_reply";
  (* Process control *)
  "process_exit"; "process_spawn_sync";
  "process_set_env";
  (* Mutable state *)
  "march_set_global"; "vault_set"; "vault_drop"; "vault_update";
  "vault_put_new"; "vault_incr";
  (* Partial / diverging: integer division and remainder panic on a zero
     divisor (see march_checked_idiv/imod/umod in the runtime), matching the
     interpreter's "<op>: division by zero".  That divergence is observable,
     so DCE/fusion must not eliminate or reorder these even when the result
     is unused — `let _ = int_div(x, 0)` must still trap.  The "/" and "%"
     infix operators trap the same way (march_checked_div_op/mod_op, bare
     "division by zero" / "modulo by zero"); "/" also covers float division,
     which traps on 0.0 via march_checked_fdiv — so it is impure too. *)
  "int_div"; "int_mod"; "int_div_euclid"; "int_mod_euclid";
  "/"; "%";
]

module StringSet = Set.Make (String)

(** Core purity check, parameterized by a set of *user-defined* function names
    known to be impure (i.e. they transitively call an impure builtin).

    [is_pure] (the unparameterized form below) passes an empty set, preserving
    the original behavior for callers (fusion / inline) that only ask about
    expressions built from known-pure stdlib combinators.

    DCE must use [is_pure_ext] with the transitive impure-function set: it
    inspects raw call sites such as [EApp(System.put_env, …)] whose impurity is
    invisible at the call site — only the callee body reveals it. Treating such
    a binding as pure would let DCE delete observable side effects (e.g. the
    [setenv] performed by [System.put_env]). *)
let rec is_pure_ext (impure_fns : StringSet.t) : Tir.expr -> bool = function
  | Tir.EAtom _                -> true
  | Tir.ETuple _               -> true
  | Tir.ERecord _              -> true
  | Tir.EField _               -> true
  | Tir.EAlloc _               -> true   (* allocation is pure, side-effect-free *)
  | Tir.EStackAlloc _          -> true
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EFree _ | Tir.EReuse _
  | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _ -> false
  | Tir.EApp (f, _)            ->
    not (List.mem f.Tir.v_name impure_builtins)
    && not (StringSet.mem f.Tir.v_name impure_fns)
  | Tir.ECallPtr _             -> false  (* indirect call — unknown target *)
  | Tir.ELet (_, rhs, body)    -> is_pure_ext impure_fns rhs && is_pure_ext impure_fns body
  | Tir.ELetRec (fns, body)    ->
    List.for_all (fun fd -> is_pure_ext impure_fns fd.Tir.fn_body) fns
    && is_pure_ext impure_fns body
  | Tir.ECase (_, branches, default) ->
    List.for_all (fun b -> is_pure_ext impure_fns b.Tir.br_body) branches
    && Option.fold ~none:true ~some:(is_pure_ext impure_fns) default
  | Tir.EUpdate _              -> true
  | Tir.ESeq (e1, e2)          -> is_pure_ext impure_fns e1 && is_pure_ext impure_fns e2

(** Backward-compatible purity check assuming no user-defined function is known
    to be impure. Safe for callers reasoning only about builtin-based
    expressions (fusion, inline). *)
let is_pure (e : Tir.expr) : bool = is_pure_ext StringSet.empty e

(** Compute the set of top-level function names that are *impure*: those whose
    body either contains an [ECallPtr] / RC op, calls an impure builtin, or
    (transitively) calls another impure top-level function. Computed as a
    fixed point over the module's call graph. Functions whose definitions are
    not in the module (e.g. true builtins) are handled via [impure_builtins]. *)
let impure_fns_of_module (m : Tir.tir_module) : StringSet.t =
  let defined =
    List.fold_left (fun acc fd -> StringSet.add fd.Tir.fn_name acc)
      StringSet.empty m.Tir.tm_fns in
  let rec fixpoint impure =
    let impure' =
      List.fold_left (fun acc fd ->
        if StringSet.mem fd.Tir.fn_name acc then acc
        else if not (is_pure_ext acc fd.Tir.fn_body) then
          StringSet.add fd.Tir.fn_name acc
        else acc
      ) impure m.Tir.tm_fns
    in
    if StringSet.cardinal impure' = StringSet.cardinal impure then impure'
    else fixpoint impure'
  in
  (* Restrict the result to defined functions; builtin impurity is already
     covered by [impure_builtins] in [is_pure_ext]. *)
  StringSet.inter (fixpoint StringSet.empty) defined
