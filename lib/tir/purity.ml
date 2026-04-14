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
]

let rec is_pure : Tir.expr -> bool = function
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
  | Tir.ECallPtr _             -> false  (* indirect call — unknown target *)
  | Tir.ELet (_, rhs, body)    -> is_pure rhs && is_pure body
  | Tir.ELetRec (fns, body)    ->
    List.for_all (fun fd -> is_pure fd.Tir.fn_body) fns && is_pure body
  | Tir.ECase (_, branches, default) ->
    List.for_all (fun b -> is_pure b.Tir.br_body) branches
    && Option.fold ~none:true ~some:is_pure default
  | Tir.EUpdate _              -> true
  | Tir.ESeq (e1, e2)          -> is_pure e1 && is_pure e2
