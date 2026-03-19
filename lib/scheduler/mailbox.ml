(** Lock-free multi-producer/single-consumer mailbox queue.
    Based on Michael-Scott queue using OCaml 5 Atomic. *)

type 'a node = {
  value : 'a option;
  next  : 'a node option Atomic.t;
}

type 'a t = {
  head : 'a node Atomic.t;
  tail : 'a node Atomic.t;
}

let create () : 'a t =
  let sentinel = { value = None; next = Atomic.make None } in
  { head = Atomic.make sentinel; tail = Atomic.make sentinel }

let push (q : 'a t) (v : 'a) : unit =
  let new_node = { value = Some v; next = Atomic.make None } in
  let rec loop () =
    let tail = Atomic.get q.tail in
    let next = Atomic.get tail.next in
    match next with
    | None ->
      if Atomic.compare_and_set tail.next None (Some new_node) then
        ignore (Atomic.compare_and_set q.tail tail new_node)
      else loop ()
    | Some next_node ->
      ignore (Atomic.compare_and_set q.tail tail next_node);
      loop ()
  in
  loop ()

let pop (q : 'a t) : 'a option =
  let rec loop () =
    let head = Atomic.get q.head in
    match Atomic.get head.next with
    | None -> None
    | Some next ->
      if Atomic.compare_and_set q.head head next then
        next.value
      else loop ()
  in
  loop ()

let is_empty (q : 'a t) : bool =
  let head = Atomic.get q.head in
  Option.is_none (Atomic.get head.next)
