(* Deque operations benchmark — matches bench/deque_ops.march (100 rounds)
   Uses the same two-list functional deque algorithm as March, under OCaml's
   tracing GC instead of Perceus RC.  This isolates the GC-vs-RC difference.
   Compile:
     ocamlopt bench/ocaml/deque_ops.ml -o /tmp/ocaml_deque *)

(* Two-list functional deque: front in order, back in reverse order. *)
type 'a dq = { sz: int; front: 'a list; back: 'a list }

let empty = { sz = 0; front = []; back = [] }

(* Rebalance: when front runs out, reverse back into front. *)
let rebalance d =
  match d.front with
  | [] -> { sz = d.sz; front = List.rev d.back; back = [] }
  | _  -> d

let push_front d x = rebalance { sz = d.sz + 1; front = x :: d.front; back = d.back }
let push_back  d x = rebalance { sz = d.sz + 1; front = d.front; back = x :: d.back }

let pop_front d =
  match (rebalance d).front with
  | []     -> None, empty
  | h :: t -> Some h, rebalance { sz = d.sz - 1; front = t; back = d.back }

let push_step d n = push_back (push_front d n) (n + 10000)

let rec push_phase d n =
  if n = 0 then d else push_phase (push_step d n) (n - 1)

let rec drain d acc =
  match pop_front d with
  | None, _   -> acc
  | Some v, r -> drain r (acc + v)

let () =
  let total = ref 0 in
  for _ = 1 to 100 do
    let d = push_phase empty 10000 in
    total := !total + drain d 0
  done;
  Printf.printf "%d\n" !total
