(* Obligation ledger for the refinement checker.
   March reports a violation only when a predicate can NEVER hold; every other
   outcome is silence.  That makes silence ambiguous between "proved", "skipped
   because the checker could not reflect it", and "the solver did not decide" —
   and that ambiguity is not cosmetic: `{List(a) | len(_) > 0}` shipped
   enforcing nothing while the suite stayed green, because a contract that
   checks nothing and a contract that passes look identical from outside.
   Every obligation now leaves a record, so the outcome is countable. *)

type reason =
  | Unreflectable_predicate  (* the goal did not translate into SMT at all *)
  | Unreflectable_subject    (* the SUBJECT (the actual argument) did not reflect *)
  | Sort_conflict            (* a symbol would have been declared at two sorts *)
  | Float_sort_gate          (* the float/formula wellsortedness gate rejected it *)
  | Solver_undecided         (* neither goal nor its negation was Verified *)

type verdict = Proved | Violated | Skipped of reason

type t = { span : March_ast.Ast.span; callee : string; predicate : string; verdict : verdict }

let log : t list ref = ref []
let reset () = log := []
let record (o : t) : unit = log := o :: !log
let all () : t list = List.rev !log

let reason_name = function
  | Unreflectable_predicate -> "unreflectable-predicate"
  | Unreflectable_subject -> "unreflectable-subject"
  | Sort_conflict -> "sort-conflict"
  | Float_sort_gate -> "float-sort-gate"
  | Solver_undecided -> "solver-undecided"

(* One clause of plain English per reason, for the `cap verified` error text.
   [reason_name] alone is a debug-report slug; once a reason reaches a USER it
   has to say what actually happened, and it must not over-claim — which is why
   [Unreflectable_subject] exists as its own reason at all.  The two used to be
   one: a record-typed argument whose ACTUAL could not be reflected was filed
   under "unreflectable predicate", so a user with a perfectly ordinary
   predicate would have been told to rewrite it and sent chasing the wrong
   thing.  Nothing but a debug count depended on the conflation. *)
let reason_detail = function
  | Unreflectable_predicate ->
    "the predicate uses vocabulary the checker cannot translate to SMT"
  | Unreflectable_subject ->
    "the argument's own value could not be translated to SMT, so no goal was built"
  | Sort_conflict -> "reflecting it would declare one symbol at two different sorts"
  | Float_sort_gate -> "the float wellsortedness gate rejected the formula"
  | Solver_undecided -> "the solver proved neither the predicate nor its negation"

let summary () =
  let proved = ref 0 and violated = ref 0 and skips = Hashtbl.create 8 in
  List.iter
    (fun o ->
      match o.verdict with
      | Proved -> incr proved
      | Violated -> incr violated
      | Skipped r ->
        Hashtbl.replace skips r (1 + Option.value ~default:0 (Hashtbl.find_opt skips r)))
    !log;
  (!proved, !violated, Hashtbl.fold (fun r n acc -> (r, n) :: acc) skips [])
