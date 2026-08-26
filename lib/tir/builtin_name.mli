(** Codegen-dispatched builtin names.  See [builtin_name.ml] for why this
    exists and for what deliberately is NOT in it. *)

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

(** The exact string [Llvm_emit] dispatches on. *)
val to_string : t -> string

(** Inverse of [to_string]; [None] for a name the emitter does not dispatch. *)
val of_string : string -> t option

(** [is c s] is [to_string c = s].  The guard form used in [emit_expr]. *)
val is : t -> string -> bool

(** Every constructor, used by the round-trip test. *)
val all : t list
