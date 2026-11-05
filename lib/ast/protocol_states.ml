(** Generated session states → the protocol step each one stands for
    (specs/plans/2026-11-02-diagnostics-depth-plan.md §F3).

    `@[endpoints]` turns every node of a role's projection into a state type
    (`Stream_Cons.S_recv_Msg_Prod_Cons_1`, `S_choose_more_done`, `S_end`), and a
    role body is written against those names.  A body that takes a step out of
    order is therefore a type mismatch between two generated names, which says
    nothing about the protocol the user wrote.  [Desugar_endpoints] records here,
    for each state, what the role does there and where the protocol says so;
    [Typecheck_unify] reads it to phrase the mismatch in protocol terms.

    Display only: nothing reads it to decide a type.  Process-global and never
    reset; keys are the role module's qualified state names, which a later
    desugar of the same protocol overwrites with the same facts. *)

type info = {
  ps_proto : string;          (** the protocol, `Stream` *)
  ps_role  : string;          (** the role, `Cons` *)
  ps_doing : string;          (** what the role does in this state, in prose:
                                  "send an `Int` to `Prod`", "close the conversation" *)
  ps_call  : string;          (** the generated function that takes the step,
                                  `Stream_Cons.recv_Msg_Prod_Cons_1` *)
  ps_span  : Ast.span option; (** the protocol step, when it has one *)
}

let table : (string, info) Hashtbl.t = Hashtbl.create 16

let record ~state info = Hashtbl.replace table state info

let last_component s =
  match String.rindex_opt s '.' with
  | Some i -> String.sub s (i + 1) (String.length s - i - 1)
  | None -> s

(** Every state whose last name component is [name]'s: the checker sees a
    role module's state types bare, and two roles may both have `S_end`. *)
let find_all name =
  let short = last_component name in
  Hashtbl.fold (fun k v acc -> if last_component k = short then v :: acc else acc) table []
