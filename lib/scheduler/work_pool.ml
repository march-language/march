(** Work-stealing pool with Chase-Lev deques.

    Each worker thread maintains a deque. The owning thread pushes/pops
    from the bottom (LIFO). Stealing threads take from the top (FIFO).

    Reference: Chase & Lev, "Dynamic Circular Work-Stealing Deque" (2005). *)

module Deque = struct
  type 'a t = {
    mutable buffer : 'a option array;
    top    : int Atomic.t;    (** Steal from here (FIFO) *)
    bottom : int Atomic.t;    (** Push/pop here (LIFO) *)
    mutable capacity : int;
  }

  let create (cap : int) : 'a t =
    { buffer = Array.make cap None;
      top = Atomic.make 0;
      bottom = Atomic.make 0;
      capacity = cap }

  let push (d : 'a t) (v : 'a) : unit =
    let b = Atomic.get d.bottom in
    let t = Atomic.get d.top in
    let size = b - t in
    if size >= d.capacity then begin
      (* Grow buffer *)
      let new_cap = d.capacity * 2 in
      let new_buf = Array.make new_cap None in
      for i = t to b - 1 do
        new_buf.(i mod new_cap) <- d.buffer.(i mod d.capacity)
      done;
      d.buffer <- new_buf;
      d.capacity <- new_cap
    end;
    d.buffer.(b mod d.capacity) <- Some v;
    Atomic.set d.bottom (b + 1)

  let pop (d : 'a t) : 'a option =
    let b = Atomic.get d.bottom - 1 in
    Atomic.set d.bottom b;
    let t = Atomic.get d.top in
    let size = b - t in
    if size < 0 then begin
      (* Empty *)
      Atomic.set d.bottom t;
      None
    end else if size > 0 then begin
      (* More than one element — safe to take *)
      let v = d.buffer.(b mod d.capacity) in
      d.buffer.(b mod d.capacity) <- None;
      v
    end else begin
      (* Last element — race with steal *)
      let v = d.buffer.(b mod d.capacity) in
      if Atomic.compare_and_set d.top t (t + 1) then begin
        d.buffer.(b mod d.capacity) <- None;
        Atomic.set d.bottom (t + 1);
        v
      end else begin
        Atomic.set d.bottom (t + 1);
        None
      end
    end

  let steal (d : 'a t) : 'a option =
    let t = Atomic.get d.top in
    let b = Atomic.get d.bottom in
    let size = b - t in
    if size <= 0 then None
    else begin
      let v = d.buffer.(t mod d.capacity) in
      if Atomic.compare_and_set d.top t (t + 1) then begin
        d.buffer.(t mod d.capacity) <- None;
        v
      end else
        None  (* Lost race with another stealer or pop *)
    end

  let size (d : 'a t) : int =
    let b = Atomic.get d.bottom in
    let t = Atomic.get d.top in
    max 0 (b - t)
end

(** The work-stealing pool — a collection of worker deques. *)
type 'a t = {
  workers   : 'a Deque.t array;
  n_workers : int;
  mutable active : bool;
}

let create (n_workers : int) : 'a t =
  { workers = Array.init n_workers (fun _ -> Deque.create 64);
    n_workers;
    active = true }

let is_active (pool : 'a t) : bool = pool.active

(** Submit work to a specific worker's deque. *)
let submit (pool : 'a t) (worker_idx : int) (v : 'a) : unit =
  let idx = worker_idx mod pool.n_workers in
  Deque.push pool.workers.(idx) v

(** Try to steal work from a random other worker. *)
let try_steal (pool : 'a t) (my_idx : int) : 'a option =
  let victim = Random.int pool.n_workers in
  if victim = my_idx then None
  else Deque.steal pool.workers.(victim)
