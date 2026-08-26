(** Codegen-dispatched builtin names, as a variant rather than raw strings.

    [Llvm_emit.emit_expr] dispatches these builtins with
    [when f.Tir.v_name = "task_await"] guards.  Nothing checked that set for
    exhaustiveness, overlap, or typos, so a builtin added to one emitter site
    and forgotten at another failed SILENTLY — the arm simply never fired and
    the generic fallback emitted plausible-but-wrong code.

    Naming the set makes a typo a compile error, makes the set enumerable
    ([all]), and gives [Llvm_emit.builtin_arm_site] an exhaustiveness surface:
    adding a constructor here without recording where it is emitted is a
    non-exhaustive match, which this project builds as an error.

    ONLY names dispatched by the LLVM emitter's [emit_expr] belong here.
    [root_cap] is deliberately absent: it is dispatched in [emit_atom], not
    [emit_expr], and adding it would make this set lie about what it covers.
    Interpreter-only builtins live in [Eval_prim]; the two sets differ. *)

type t =
  | Actor_register
  | Actor_reply
  | Bool_to_string
  | Chan_choose
  | Chan_send
  | Float_to_string
  | Get_work_pool
  | Html_auto_escape
  | Html_escape_ctx
  | Int_abs
  | Int_div
  | Int_div_euclid
  | Int_max_value
  | Int_min_value
  | Int_mod
  | Int_mod_euclid
  | Int_not
  | Int_popcount
  | Int_pow
  | Int_to_string
  | Mpst_send
  | Negate
  | Not
  | Pmap_threshold
  | Receive
  | Record_from_list
  | Record_get
  | Record_has_key
  | Record_put
  | Remote_ref_hashes
  | Send
  | Signal_raise_self
  | Signal_unwatch
  | Signal_watch
  | Task_await
  | Task_await_unwrap
  | Task_cancel
  | Task_cancel_by_id
  | Task_cancel_token_new
  | Task_is_cancelled
  | Task_reductions
  | Task_spawn
  | Task_spawn_steal
  | Task_spawn_with_cancel
  | Task_yield
  | To_string
  | Vault_drop
  | Vault_get
  | Vault_incr
  | Vault_ns_drop
  | Vault_ns_get
  | Vault_ns_set
  | Vault_push_capped
  | Vault_put_new
  | Vault_set
  | Vault_set_ttl
  | Vault_update

(* [all] and [to_string] are the single source of truth.  [of_string] is
   derived from them, so a new constructor cannot be added to one direction
   and forgotten in the other. *)
let to_string = function
  | Actor_register -> "actor_register"
  | Actor_reply -> "actor_reply"
  | Bool_to_string -> "bool_to_string"
  | Chan_choose -> "chan_choose"
  | Chan_send -> "chan_send"
  | Float_to_string -> "float_to_string"
  | Get_work_pool -> "get_work_pool"
  | Html_auto_escape -> "html_auto_escape"
  | Html_escape_ctx -> "html_escape_ctx"
  | Int_abs -> "int_abs"
  | Int_div -> "int_div"
  | Int_div_euclid -> "int_div_euclid"
  | Int_max_value -> "int_max_value"
  | Int_min_value -> "int_min_value"
  | Int_mod -> "int_mod"
  | Int_mod_euclid -> "int_mod_euclid"
  | Int_not -> "int_not"
  | Int_popcount -> "int_popcount"
  | Int_pow -> "int_pow"
  | Int_to_string -> "int_to_string"
  | Mpst_send -> "mpst_send"
  | Negate -> "negate"
  | Not -> "not"
  | Pmap_threshold -> "pmap_threshold"
  | Receive -> "receive"
  | Record_from_list -> "record_from_list"
  | Record_get -> "record_get"
  | Record_has_key -> "record_has_key"
  | Record_put -> "record_put"
  | Remote_ref_hashes -> "remote_ref_hashes"
  | Send -> "send"
  | Signal_raise_self -> "signal_raise_self"
  | Signal_unwatch -> "signal_unwatch"
  | Signal_watch -> "signal_watch"
  | Task_await -> "task_await"
  | Task_await_unwrap -> "task_await_unwrap"
  | Task_cancel -> "task_cancel"
  | Task_cancel_by_id -> "task_cancel_by_id"
  | Task_cancel_token_new -> "task_cancel_token_new"
  | Task_is_cancelled -> "task_is_cancelled"
  | Task_reductions -> "task_reductions"
  | Task_spawn -> "task_spawn"
  | Task_spawn_steal -> "task_spawn_steal"
  | Task_spawn_with_cancel -> "task_spawn_with_cancel"
  | Task_yield -> "task_yield"
  | To_string -> "to_string"
  | Vault_drop -> "vault_drop"
  | Vault_get -> "vault_get"
  | Vault_incr -> "vault_incr"
  | Vault_ns_drop -> "vault_ns_drop"
  | Vault_ns_get -> "vault_ns_get"
  | Vault_ns_set -> "vault_ns_set"
  | Vault_push_capped -> "vault_push_capped"
  | Vault_put_new -> "vault_put_new"
  | Vault_set -> "vault_set"
  | Vault_set_ttl -> "vault_set_ttl"
  | Vault_update -> "vault_update"

let all =
  [ Actor_register; Actor_reply; Bool_to_string; Chan_choose; Chan_send;
    Float_to_string; Get_work_pool; Html_auto_escape; Html_escape_ctx;
    Int_abs; Int_div; Int_div_euclid; Int_max_value; Int_min_value;
    Int_mod; Int_mod_euclid; Int_not; Int_popcount; Int_pow;
    Int_to_string; Mpst_send; Negate; Not; Pmap_threshold; Receive;
    Record_from_list; Record_get; Record_has_key; Record_put;
    Remote_ref_hashes; Send; Signal_raise_self; Signal_unwatch;
    Signal_watch; Task_await; Task_await_unwrap; Task_cancel;
    Task_cancel_by_id; Task_cancel_token_new; Task_is_cancelled;
    Task_reductions; Task_spawn; Task_spawn_steal; Task_spawn_with_cancel;
    Task_yield; To_string; Vault_drop; Vault_get; Vault_incr;
    Vault_ns_drop; Vault_ns_get; Vault_ns_set; Vault_push_capped;
    Vault_put_new; Vault_set; Vault_set_ttl; Vault_update ]

let table : (string, t) Hashtbl.t =
  let h = Hashtbl.create 64 in
  List.iter (fun c -> Hashtbl.replace h (to_string c) c) all;
  h

let of_string s = Hashtbl.find_opt table s

let is c s = String.equal (to_string c) s
