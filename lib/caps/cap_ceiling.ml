(* `needs` as a hard ceiling, checked against attributed use.
   See cap_ceiling.mli for why this is not another source-level AST walk. *)

type violation =
  | Undeclared of { cap : string; owner : string; span : March_ast.Ast.span }
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

let span_for module_spans owner =
  match List.assoc_opt owner module_spans with
  | Some sp -> sp
  | None -> March_ast.Ast.dummy_span

let check ~module_caps ~module_spans ~attribution ~caps =
  let attribution = List.filter (fun (c, _) -> not (is_foreign c)) attribution in
  let undeclared =
    List.filter_map
      (fun (cap, owner) ->
         if covered module_caps ~owner ~cap then None
         else Some (Undeclared { cap; owner; span = span_for module_spans owner }))
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
  | Undeclared { cap; owner; span = _ } ->
    Printf.sprintf
      "module `%s` uses `%s` but does not declare `needs %s`" owner cap cap
  (* Do NOT name a single cause here.  This message used to end "— it is
     reached only through indirect calls, whose callee is not statically
     known", asserting the one cause the check could imagine.  Every
     unattributable capability actually diagnosed in 2026-08 had a DIFFERENT
     cause — a builtin-name-table mismatch (fixed, #221), DCE fail-open
     charging main-less modules for the stdlib (fixed, #225), a signature-only
     capability (fixed, #225), and a nested-module actor handler's synthesized
     bare name (open, specs/todos/2026-08-08-actor-handler-attribution-…) —
     and each investigation began by disbelieving this message.  The check
     knows only that emitted code reaches the capability and attribution
     found no owner; say that, and point at what the user can actually do. *)
  | Unattributed { cap } ->
    Printf.sprintf
      "`%s` is used by emitted code but cannot be attributed to any module, \
       so no `needs` declaration can vouch for it. This fails closed. Likely \
       causes: the capability is reached only through an indirect call whose \
       callee is not statically known, or attribution has a gap for this \
       route — if adding the `needs` line does not resolve it, the route is \
       the compiler's gap, not your program's; please report it"
      cap
