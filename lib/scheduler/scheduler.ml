(** Cooperative scheduler with reduction-counted preemption.

    Each actor/task gets a budget of [max_reductions] reductions per quantum.
    A "reduction" is one function application, pattern match, or message send.
    When the budget is exhausted, the scheduler preempts and moves to the next
    item in the run queue. *)

let max_reductions = 4_000

type reduction_ctx = {
  mutable remaining : int;
  mutable yielded   : bool;
}

let create_reduction_ctx () : reduction_ctx =
  { remaining = max_reductions; yielded = false }

let reset_budget (ctx : reduction_ctx) : unit =
  ctx.remaining <- max_reductions;
  ctx.yielded <- false

let tick (ctx : reduction_ctx) : bool =
  ctx.remaining <- ctx.remaining - 1;
  if ctx.remaining <= 0 then begin
    ctx.yielded <- true;
    true
  end else
    false

type proc_id = int

type proc_state =
  | PReady
  | PRunning
  | PWaiting
  | PDone
  | PDead of string

type proc = {
  pid        : proc_id;
  mutable state : proc_state;
  tier       : Task.tier;
  reduction  : reduction_ctx;
}

type run_queue = {
  mutable procs : proc Queue.t;
  mutable wait  : proc list;
}

let create_run_queue () : run_queue =
  { procs = Queue.create (); wait = [] }

let enqueue (rq : run_queue) (p : proc) : unit =
  p.state <- PReady;
  Queue.push p rq.procs

let dequeue (rq : run_queue) : proc option =
  if Queue.is_empty rq.procs then None
  else Some (Queue.pop rq.procs)

let park (rq : run_queue) (p : proc) : unit =
  p.state <- PWaiting;
  rq.wait <- p :: rq.wait

let wake (rq : run_queue) (pid : proc_id) : bool =
  match List.partition (fun p -> p.pid = pid) rq.wait with
  | ([p], rest) ->
    rq.wait <- rest;
    enqueue rq p;
    true
  | _ -> false
