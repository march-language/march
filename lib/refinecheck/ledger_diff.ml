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

type key = { span : A.span; callee : string; predicate : string; kind : Ob.kind }

type snapshot = (key * Ob.verdict) list

type change = Closed | Opened | New_skip | New_violated | Unchanged

let change_name = function
  | Closed -> "closed"
  | Opened -> "opened"
  | New_skip -> "new-skip"
  | New_violated -> "new-violated"
  | Unchanged -> "unchanged"

let key_of (o : Ob.t) : key =
  { span = o.Ob.span; callee = o.Ob.callee; predicate = o.Ob.predicate; kind = o.Ob.kind }

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
let diff ~(before : snapshot) ~(after : snapshot) : (key * change) list =
  List.map (fun (k, v) -> (k, classify (List.assoc_opt k before) v)) after

let keys_with c d = List.filter_map (fun (k, c') -> if c' = c then Some k else None) d
let closed d = keys_with Closed d
let opened d = keys_with Opened d
let new_violated d = keys_with New_violated d
let new_skipped d = keys_with New_skip d

(* Unsettled sites in a snapshot — the old "debt" number, kept for reports. *)
let debt (s : snapshot) : int = List.length (List.filter (fun (_, v) -> not (settled v)) s)
