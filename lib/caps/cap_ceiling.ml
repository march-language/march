(* `needs` as a hard ceiling, checked against attributed use.
   See cap_ceiling.mli for why this is not another source-level AST walk. *)

type violation =
  | Undeclared of { cap : string; owner : string }
  | Unattributed of { cap : string }

(* Emitted from the presence of extern blocks, not from an attributed call
   site, so these have no owner by construction.  Typecheck's Check 5 already
   errors when an extern's capability is undeclared; treating them as
   unattributed here would report a violation on every FFI-using program. *)
let is_foreign c = c = "IO.Foreign" || c = "IO.Foreign.Blocking"

let declared_for module_caps owner =
  match List.assoc_opt owner module_caps with Some l -> l | None -> []

let covered module_caps ~owner ~cap =
  List.exists
    (fun need -> Cap_lattice.cap_subsumes need cap)
    (declared_for module_caps owner)

let check ~module_caps ~attribution ~caps =
  let attribution = List.filter (fun (c, _) -> not (is_foreign c)) attribution in
  let undeclared =
    List.filter_map
      (fun (cap, owner) ->
         if covered module_caps ~owner ~cap then None
         else Some (Undeclared { cap; owner }))
      attribution
  in
  (* A capability nobody can be held responsible for.  Fail-closed: see the
     .mli — an unattributable capability is the one an attacker would route
     through, so it must not certify. *)
  let unattributed =
    List.filter_map
      (fun cap ->
         if is_foreign cap then None
         else if List.exists (fun (c, _) -> c = cap) attribution then None
         else Some (Unattributed { cap }))
      caps
  in
  List.sort_uniq compare (undeclared @ unattributed)

let describe = function
  | Undeclared { cap; owner } ->
    Printf.sprintf
      "module `%s` uses `%s` but does not declare `needs %s`" owner cap cap
  | Unattributed { cap } ->
    Printf.sprintf
      "`%s` is used but cannot be attributed to any module — it is reached \
       only through indirect calls, whose callee is not statically known"
      cap
