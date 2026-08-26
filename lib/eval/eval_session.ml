(** Session-typed channel runtime and multi-party (MPST) runtime.
    Extracted verbatim from eval.ml:3731-3856 — no behavior change. *)

open Eval_types
open Eval_prim

(* ------------------------------------------------------------------ *)
(* Session-typed channel runtime                                       *)
(* ------------------------------------------------------------------ *)

let next_chan_id : int ref = ref 0

(** Create a linked pair of channel endpoints for [proto_name].
    The two roles are [role_a] and [role_b]. Returns (endpoint_a, endpoint_b)
    where a's out_q = b's in_q and vice versa. *)
let chan_new proto_name role_a role_b =
  let id = !next_chan_id in
  incr next_chan_id;
  let q_ab = Queue.create () in  (* a sends, b receives *)
  let q_ba = Queue.create () in  (* b sends, a receives *)
  let ep_a = { ce_id = id; ce_role = role_a; ce_proto = proto_name;
               ce_closed = false; ce_out_q = q_ab; ce_in_q = q_ba } in
  let ep_b = { ce_id = id; ce_role = role_b; ce_proto = proto_name;
               ce_closed = false; ce_out_q = q_ba; ce_in_q = q_ab } in
  (ep_a, ep_b)

(** Send [v] on channel endpoint [ce]. Returns the same endpoint
    (the type system ensures linearity; here we just pass it through). *)
let chan_send ce v =
  if ce.ce_closed then
    eval_error "Chan.send: channel %s#%d is already closed" ce.ce_proto ce.ce_id;
  Queue.push v ce.ce_out_q;
  VChan ce

(** Receive from channel endpoint [ce].
    Blocks until a value is available (in the synchronous eval model,
    the sender runs first so the queue is always populated).
    Returns (value, new_endpoint_as_VTuple). *)
let chan_recv ce =
  if ce.ce_closed then
    eval_error "Chan.recv: channel %s#%d is already closed" ce.ce_proto ce.ce_id;
  if Queue.is_empty ce.ce_in_q then
    eval_error
      "Chan.recv: channel %s#%d has no pending value — \
       did you run the sender first?" ce.ce_proto ce.ce_id;
  let v = Queue.pop ce.ce_in_q in
  VTuple [v; VChan ce]

(** Close channel endpoint [ce]. The endpoint must not be in-use after this. *)
let chan_close ce =
  if ce.ce_closed then
    eval_error "Chan.close: channel %s#%d was already closed" ce.ce_proto ce.ce_id;
  ce.ce_closed <- true;
  VUnit

(* ------------------------------------------------------------------ *)
(* Multi-party session (MPST) runtime                                  *)
(* ------------------------------------------------------------------ *)

(** Create N linked MPST endpoints for [proto_name] with the given [roles]
    (sorted list of role name strings).
    For each ordered pair (A, B) of distinct roles, creates one shared Queue
    such that A.me_out_qs["B"] == B.me_in_qs["A"].
    Returns endpoints in the same order as [roles]. *)
let mpst_new proto_name roles =
  let id = !next_chan_id in
  incr next_chan_id;
  (* Pre-allocate all pairwise queues. *)
  let pair_queues : (string * string, value Queue.t) Hashtbl.t =
    Hashtbl.create (List.length roles * List.length roles)
  in
  List.iter (fun a ->
      List.iter (fun b ->
          if a <> b then
            Hashtbl.replace pair_queues (a, b) (Queue.create ())
        ) roles
    ) roles;
  (* Build one endpoint per role. *)
  List.map (fun role ->
      let out_qs = Hashtbl.create (List.length roles) in
      let in_qs  = Hashtbl.create (List.length roles) in
      List.iter (fun other ->
          if other <> role then begin
            Hashtbl.replace out_qs other (Hashtbl.find pair_queues (role, other));
            Hashtbl.replace in_qs  other (Hashtbl.find pair_queues (other, role))
          end
        ) roles;
      VMChan { me_id = id; me_role = role; me_proto = proto_name;
               me_closed = false; me_out_qs = out_qs; me_in_qs = in_qs }
    ) roles

(** Send [v] from [me] to [target_role].
    Returns the same endpoint (linearity enforced by the type system). *)
let mpst_send me target_role v =
  if me.me_closed then
    eval_error "MPST.send: session %s#%d (%s) is already closed"
      me.me_proto me.me_id me.me_role;
  (match Hashtbl.find_opt me.me_out_qs target_role with
   | None ->
     eval_error "MPST.send: role `%s` has no channel to `%s` in protocol `%s`"
       me.me_role target_role me.me_proto
   | Some q ->
     Queue.push v q;
     VMChan me)

(** Receive from [source_role] into [me].
    Returns (value, same_endpoint_as_VMChan). *)
let mpst_recv me source_role =
  if me.me_closed then
    eval_error "MPST.recv: session %s#%d (%s) is already closed"
      me.me_proto me.me_id me.me_role;
  (match Hashtbl.find_opt me.me_in_qs source_role with
   | None ->
     eval_error "MPST.recv: role `%s` has no channel from `%s` in protocol `%s`"
       me.me_role source_role me.me_proto
   | Some q ->
     if Queue.is_empty q then
       eval_error
         "MPST.recv: role `%s` expected a message from `%s` in session %s#%d \
          but the queue is empty — did you run the sender first?"
         me.me_role source_role me.me_proto me.me_id;
     let v = Queue.pop q in
     VTuple [v; VMChan me])

(** Close an MPST endpoint. *)
let mpst_close me =
  if me.me_closed then
    eval_error "MPST.close: session %s#%d (%s) was already closed"
      me.me_proto me.me_id me.me_role;
  me.me_closed <- true;
  VUnit

