(** Interpreter runtime state and value-rendering helpers shared by the
    evaluator, the builtin table, and the protocol runtimes.

    Extracted verbatim from eval.ml — no behavior change.  This module
    exists because eval.ml depends on [Eval_net] / [Eval_builtins], so
    anything those modules need may no longer live in eval.ml. *)

open Eval_types

(** Vault: ETS-like in-memory key-value store.
    Each table is identified by an opaque integer handle.

    Concurrency design — sharded hash map with fine-grained locking:
    ─────────────────────────────────────────────────────────────────
    A vault_table is split into [vault_num_stripes] independent shards.
    Each shard is its own Hashtbl guarded by its own Mutex.

    Key → shard mapping: Hashtbl.hash(key_string) mod vault_num_stripes

    Properties:
    • Writes to different shards are fully parallel (no shared state).
    • Writes to the same shard serialize via that shard's Mutex.
    • vault_update reads under the lock, applies [f] outside the lock
      (so [f] may safely call other vault operations without deadlocking),
      then re-acquires the lock to commit. This is "optimistic": a concurrent
      write between the read and the commit would be seen as a lost-update in
      a truly parallel setting. In the cooperative interpreter this never
      happens; in compiled multi-threaded code callers should use explicit
      serialization for true atomicity.
    • vault_size acquires each shard's lock in turn for a consistent snapshot.

    In the cooperative single-threaded interpreter the Mutexes are always
    uncontended (near-zero overhead). They provide correct behavior when
    compiled March code eventually runs on real OS threads. *)

let vault_num_stripes = 16

type vault_row = {
  vr_value  : value;
  vr_expiry : float option;  (** None = permanent; Some t = Unix expiry time *)
}

type vault_shard = {
  vs_data  : (string, vault_row) Hashtbl.t;
  vs_mutex : Mutex.t;
}

type vault_table = {
  vt_id     : int;
  vt_name   : string;
  vt_shards : vault_shard array;  (** vault_num_stripes independent shards *)
}

(** Allocate a fresh vault_table with [vault_num_stripes] empty shards. *)
let vault_make_table (id : int) (name : string) : vault_table = {
  vt_id     = id;
  vt_name   = name;
  vt_shards = Array.init vault_num_stripes (fun _ ->
    { vs_data = Hashtbl.create 16; vs_mutex = Mutex.create () });
}

let vault_registry      : (int, vault_table) Hashtbl.t = Hashtbl.create 8
let vault_name_registry : (string, int) Hashtbl.t     = Hashtbl.create 8
let vault_next_id       : int ref = ref 0

(** Detect whether a VCon chain is a March list (Nil / Cons(h, t)). *)
let rec is_list_value = function
  | VCon ("Nil", []) -> true
  | VCon ("Cons", [_; t]) -> is_list_value t
  | _ -> false

let rec list_elems acc = function
  | VCon ("Nil", []) -> List.rev acc
  | VCon ("Cons", [h; t]) -> list_elems (h :: acc) t
  | v -> List.rev (v :: acc)  (* improper list — shouldn't happen *)

(** The user-facing display name for a [VCon]'s tag: strips any collision
    qualification (e.g. "DcA.Thing.Shared" -> "Shared") down to the bare
    ctor name a March programmer actually wrote, the same way [ECon]
    evaluation already strips an explicit `Type.Ctor` qualifier (e.g.
    `Result.Ok`) before ever constructing the value. A bare (non-colliding)
    tag has no '.' and is returned unchanged — byte-identical to before
    collision-qualified tags existed. Show/print output must never leak the
    internal qualified identity; only [==]/pattern-match/dispatch consult
    the raw (possibly-qualified) tag. *)
let display_tag (tag : string) : string =
  match String.rindex_opt tag '.' with
  | Some i -> String.sub tag (i + 1) (String.length tag - i - 1)
  | None -> tag

let rec value_to_string v =
  match v with
  | VInt n    -> string_of_int n
  | VFloat f  ->
    let s = string_of_float f in
    if String.contains s '.' || String.contains s 'e' then s
    else s ^ ".0"
  | VString s -> "\"" ^ String.escaped s ^ "\""
  | VBool b   -> string_of_bool b
  | VAtom a   -> ":" ^ a
  | VUnit     -> "()"
  | VTuple vs ->
    "(" ^ String.concat ", " (List.map value_to_string vs) ^ ")"
  | VRecord fields ->
    "{ " ^ String.concat ", "
      (List.map (fun (k, v) -> k ^ ": " ^ value_to_string v) fields)
    ^ " }"
  | VCon ("Nil", []) -> "[]"
  | VCon ("Cons", _) as v when is_list_value v ->
    "[" ^ String.concat ", " (List.map value_to_string (list_elems [] v)) ^ "]"
  | VCon (tag, []) -> display_tag tag
  | VCon (tag, args) ->
    display_tag tag ^ "(" ^ String.concat ", " (List.map value_to_string args) ^ ")"
  | VClosure _  -> "<fn>"
  | VBuiltin (n, _) ->
    let is_rec = String.length n >= 5 && String.sub n 0 5 = "<rec:" in
    if is_rec then "<fn>" else "<builtin:" ^ n ^ ">"
  | VPid pid -> "Pid(" ^ string_of_int pid ^ ")"
  | VTask id -> Printf.sprintf "<task:%d>" id
  | VCancelToken r -> Printf.sprintf "<cancel_token:%s>" (if !r then "cancelled" else "active")
  | VTimerRef t -> Printf.sprintf "<timer_ref:%s>" (if t.tt_cancelled then "cancelled" else "pending")
  | VWorkPool -> "<work_pool>"
  | VCap (pid, epoch) -> Printf.sprintf "Cap(%d, epoch=%d)" pid epoch
  | VActorId pid -> Printf.sprintf "ActorId(%d)" pid
  | VChan ce ->
    Printf.sprintf "Chan(%s#%d, %s)" ce.ce_proto ce.ce_id ce.ce_role
  | VMChan me ->
    Printf.sprintf "MChan(%s#%d, %s)" me.me_proto me.me_id me.me_role
  | VForeign (lib, sym, _, _, _) ->
    Printf.sprintf "<foreign:%s:%s>" lib sym
  | VMultiarity variants ->
    let arities = List.map (fun (a, _) -> string_of_int a) variants in
    Printf.sprintf "<fn/%s>" (String.concat "|" arities)
  | VNativeIntArr a ->
    let n = Array.length a in
    if n <= 8 then
      "NativeIntArr[" ^ String.concat ", " (Array.to_list (Array.map string_of_int a)) ^ "]"
    else
      Printf.sprintf "NativeIntArr(%d)[%s, ...]" n
        (String.concat ", " (List.init 4 (fun i -> string_of_int a.(i))))
  | VNativeFloatArr a ->
    let n = Array.length a in
    let fmt f = let s = string_of_float f in
                if String.contains s '.' || String.contains s 'e' then s else s ^ ".0" in
    if n <= 8 then
      "NativeFloatArr[" ^ String.concat ", " (Array.to_list (Array.map fmt a)) ^ "]"
    else
      Printf.sprintf "NativeFloatArr(%d)[%s, ...]" n
        (String.concat ", " (List.init 4 (fun i -> fmt a.(i))))
  | VNativeF32Arr a ->
    let n = Array.length a in
    let fmt f = let s = string_of_float f in
                if String.contains s '.' || String.contains s 'e' then s else s ^ ".0" in
    if n <= 8 then
      "NativeF32Arr[" ^ String.concat ", " (Array.to_list (Array.map fmt a)) ^ "]"
    else
      Printf.sprintf "NativeF32Arr(%d)[%s, ...]" n
        (String.concat ", " (List.init 4 (fun i -> fmt a.(i))))
  | VNativeI32Arr a ->
    let n = Array.length a in
    if n <= 8 then
      "NativeI32Arr[" ^ String.concat ", " (Array.to_list (Array.map string_of_int a)) ^ "]"
    else
      Printf.sprintf "NativeI32Arr(%d)[%s, ...]" n
        (String.concat ", " (List.init 4 (fun i -> string_of_int a.(i))))
  | VNativeU8Arr a ->
    let n = Array.length a in
    if n <= 8 then
      "NativeU8Arr[" ^ String.concat ", " (Array.to_list (Array.map string_of_int a)) ^ "]"
    else
      Printf.sprintf "NativeU8Arr(%d)[%s, ...]" n
        (String.concat ", " (List.init 4 (fun i -> string_of_int a.(i))))
  | VF32x4 a ->
    let fmt f = let s = string_of_float f in
                if String.contains s '.' || String.contains s 'e' then s else s ^ ".0" in
    "F32x4[" ^ String.concat ", " (Array.to_list (Array.map fmt a)) ^ "]"
  | VF64x2 a ->
    let fmt f = let s = string_of_float f in
                if String.contains s '.' || String.contains s 'e' then s else s ^ ".0" in
    "F64x2[" ^ String.concat ", " (Array.to_list (Array.map fmt a)) ^ "]"
  | VI32x4 a ->
    "I32x4[" ^ String.concat ", " (Array.to_list (Array.map string_of_int a)) ^ "]"
  | VI64x2 a ->
    "I64x2[" ^ String.concat ", " (Array.to_list (Array.map Int64.to_string a)) ^ "]"
  | VU8x16 a ->
    "U8x16[" ^ String.concat ", " (Array.to_list (Array.map string_of_int a)) ^ "]"
  | VTypedArray arr ->
    let elems = Array.to_list arr in
    "[|" ^ String.concat ", " (List.map value_to_string elems) ^ "|]"
  | VVaultHandle id ->
    (match Hashtbl.find_opt vault_registry id with
     | Some t -> Printf.sprintf "Vault(\"%s\"#%d)" t.vt_name id
     | None   -> Printf.sprintf "Vault(#%d)" id)
  | VRingBuf r ->
    Printf.sprintf "RingBuf(size=%d, cap=%d)" r.rb_size r.rb_cap
  | VResource _ -> "#<resource>"
