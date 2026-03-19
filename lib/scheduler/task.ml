(** Task representation for the scheduler.
    A task is a lightweight unit of work — either cooperative or work-stealing. *)

type task_id = int

type task_status =
  | Ready
  | Running
  | Blocked
  | Done
  | Failed of string

type 'a task = {
  id         : task_id;
  mutable status : task_status;
  mutable result : 'a option;
  mailbox    : 'a Mailbox.t;
  tier       : tier;
}

and tier =
  | Cooperative
  | WorkStealing

let next_task_id : task_id Atomic.t = Atomic.make 0

let fresh_id () : task_id =
  Atomic.fetch_and_add next_task_id 1
