(* Per-site view of the obligation ledger, and the diff between two of them.

   The suggest tools used to score a hypothesis by COUNTING unproved
   obligations before and after it (the old [Precond_infer.count_debt]).  A
   count cannot tell "proved two, broke one" (+1, accepted) from "proved one"
   (+1, accepted): the broken site vanishes into the arithmetic.  Keying every
   obligation by its site and comparing verdicts site by site makes an
   OPENED site — previously proved, now anything else — visible, and the
   inference tools reject any hypothesis that opens one
   (specs/2026-10-20-refinement-suggest-lite-design.md §0, §2). *)

module A = March_ast.Ast
module Ob = Obligation

(* [inst] (the demand re-spelled in the caller's scope) tells apart two
   demands with the same predicate text at one call — `mean(positives(raw), n)`
   owes `_ > 0` for `n` (inst `n > 0`) and for the list's elements (no inst).
   Not every recording path fills it (a proved site may carry it where the
   skipped one did not), so [diff] matches on it first and without it second. *)
type key = { span : A.span; callee : string; predicate : string; kind : Ob.kind; inst : string option }

type snapshot = (key * Ob.verdict) list

type change = Closed | Opened | New_skip | New_violated | Unchanged

let change_name = function
  | Closed -> "closed"
  | Opened -> "opened"
  | New_skip -> "new-skip"
  | New_violated -> "new-violated"
  | Unchanged -> "unchanged"

let key_of (o : Ob.t) : key =
  { span = o.Ob.span; callee = o.Ob.callee; predicate = o.Ob.predicate; kind = o.Ob.kind; inst = o.Ob.inst }

(* A site is "settled" when nothing is owed there: proved, or deliberately
   waved through by the author ([Trusted] is not debt). *)
let settled = function Ob.Proved | Ob.Trusted -> true | Ob.Violated | Ob.Skipped _ -> false

(* Sorted, one verdict per key: a site recorded twice keeps its WORST verdict,
   so a duplicate cannot hide an unproved occurrence. *)
let of_list (l : (key * Ob.verdict) list) : snapshot =
  let worse a b = if settled a then b else a in
  List.stable_sort (fun (k1, _) (k2, _) -> compare k1 k2) l
  |> List.fold_left
       (fun acc (k, v) ->
         match acc with
         | (k', v') :: rest when k' = k -> (k, worse v' v) :: rest
         | _ -> (k, v) :: acc)
       []
  |> List.rev

let snapshot ?(is_user = fun (_ : A.span) -> true) () : snapshot =
  of_list
    (List.filter_map
       (fun (o : Ob.t) -> if is_user o.Ob.span then Some (key_of o, o.Ob.verdict) else None)
       (Ob.all ()))

let classify (before : Ob.verdict option) (after : Ob.verdict) : change =
  match before with
  | None -> (
    match after with
    | Ob.Violated -> New_violated
    | Ob.Skipped _ -> New_skip
    | Ob.Proved | Ob.Trusted -> Unchanged)
  | Some b -> (
    match settled b, settled after with
    | false, true -> Closed
    | true, false -> (match after with Ob.Violated -> New_violated | _ -> Opened)
    | false, false -> (
      match b, after with Ob.Skipped _, Ob.Violated -> New_violated | _ -> Unchanged)
    | true, true -> Unchanged)

(* Every key of [after], classified against [before].  A key present only in
   [before] has disappeared — its call no longer exists under the hypothesis —
   and owes nothing either way, so it is not reported. *)
let same_site (a : key) (b : key) =
  a.span = b.span && a.predicate = b.predicate && a.kind = b.kind

(* A site is matched across the two snapshots by (span, predicate, kind); the
   callee is a label only.  An element comparison is logged under the
   container VARIABLE once that variable carries an element refinement (the
   call `sum_pos(xs)` is `sum_pos` before the hypothesis and `xs` after it), so
   matching on the callee would turn one site into a vanished one and a new
   one, and hide exactly the close the hypothesis produced. *)
let contains (o : A.span) (s : A.span) =
  s.A.file = o.A.file
  && (s.A.start_line, s.A.start_col) >= (o.A.start_line, o.A.start_col)
  && (s.A.end_line, s.A.end_col) <= (o.A.end_line, o.A.end_col)

(* Fallback: once an ARGUMENT carries an element entry, the same demand is
   recorded at the argument's span (label `g(…)`) rather than the call's
   (label `sum_pos`).  An after-site with no exact match is paired with a
   before-site of the same predicate and kind whose span encloses it or that
   it encloses, provided that before-site itself has no exact match. *)
let nested_site (a : key) (b : key) =
  a.predicate = b.predicate && a.kind = b.kind && (contains a.span b.span || contains b.span a.span)

let diff ~(before : snapshot) ~(after : snapshot) : (key * change) list =
  (* Pair each after-site with at most one before-site, in three passes of
     decreasing precision — same site and [inst]; same site; a nested span —
     each pass only over the before-sites earlier passes left unpaired, so two
     demands at one call never compete for the same partner. *)
  let before_a = Array.of_list before and after_a = Array.of_list after in
  let used = Array.make (Array.length before_a) false in
  let pair = Array.make (Array.length after_a) None in
  let pass ok =
    Array.iteri
      (fun i (k, _) ->
        if pair.(i) = None then
          let rec find j =
            if j >= Array.length before_a then ()
            else
              let k', v' = before_a.(j) in
              if (not used.(j)) && ok k k' then begin used.(j) <- true; pair.(i) <- Some v' end
              else find (j + 1)
          in
          find 0)
      after_a
  in
  pass (fun a b -> same_site a b && a.inst = b.inst);
  pass same_site;
  pass nested_site;
  Array.to_list (Array.mapi (fun i (k, v) -> (k, classify pair.(i) v)) after_a)

let keys_with c d = List.filter_map (fun (k, c') -> if c' = c then Some k else None) d
let closed d = keys_with Closed d
let opened d = keys_with Opened d
let new_violated d = keys_with New_violated d
let new_skipped d = keys_with New_skip d

(* Unsettled sites in a snapshot — the old "debt" number, kept for reports. *)
let debt (s : snapshot) : int = List.length (List.filter (fun (_, v) -> not (settled v)) s)
