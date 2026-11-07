(** `march --check --guarantees` (lemmas design §1.2 and §7, phase B): one
    labelled line per actor and protocol of the entry file, saying what this
    build established and what it rests on, then the details.

    The labels are the design's honest vocabulary, narrowed to what exists:

    - `proved`: the refinement checker proved every obligation of the kind
      about the code that runs.
    - `violated`: it found a counterexample (the build reports it too).
    - `not proved`: some obligation was neither proved nor refuted; the
      reason is the checker's own.
    - `not checked`: the program states a guarantee nothing checks.  Never
      left silent: this is the line that says so.
    - `checked (compiler)`: a compile-time check that is not a proof about
      a model (protocol projection).
    - `assumed`: the trust boundary (another node's messages, the runtime).

    The report reads the refinement ledger ([Obligation.all]) after the
    check ran, so it changes no verdict and adds no obligation. *)

module A = March_ast.Ast
module O = March_refinecheck.Obligation

type label =
  | Proved | Violated | Not_proved | Not_checked | Checked_compiler
  | Proved_model | Proved_model_tested | Proved_spec | Assumed

let label_text = function
  | Proved -> "proved"
  | Violated -> "violated"
  | Not_proved -> "not proved"
  | Not_checked -> "not checked"
  | Checked_compiler -> "checked (compiler)"
  | Proved_model -> "proved (model)"
  | Proved_model_tested -> "proved (model) · tested (runtime)"
  | Proved_spec -> "proved (spec) · validated (compiler)"
  | Assumed -> "assumed"

(* Worst first, for an actor's one-line summary.  [Assumed] is a boundary,
   not a weakness of this build, so it never decides the summary. *)
let rank = function
  | Violated -> 0 | Not_checked -> 1 | Not_proved -> 2 | Checked_compiler -> 3
  | Proved_model -> 4 | Proved_model_tested -> 5 | Proved_spec -> 6 | Proved -> 7 | Assumed -> 8

type line = { what : string; label : label; detail : string }

let last_segment s =
  match String.rindex_opt s '.' with
  | Some i -> String.sub s (i + 1) (String.length s - i - 1)
  | None -> s

let within (outer : A.span) (s : A.span) =
  s.A.file = outer.A.file
  && (s.A.start_line, s.A.start_col) >= (outer.A.start_line, outer.A.start_col)
  && (s.A.end_line, s.A.end_col) <= (outer.A.end_line, outer.A.end_col)

let plural n one many = if n = 1 then one else many

(* The verdict of a group of obligations, with what it rests on. *)
let summarise ~(where : string) (obs : O.t list) : (label * string) option =
  let n = List.length obs in
  if n = 0 then None
  else
    let violated = List.filter (fun (o : O.t) -> o.O.verdict = O.Violated) obs in
    let skipped =
      List.filter_map
        (fun (o : O.t) -> match o.O.verdict with O.Skipped r -> Some r | _ -> None)
        obs
    in
    let sites k = Printf.sprintf "%d of %d %s" k n (plural n "site" "sites") in
    if violated <> [] then
      Some (Violated, Printf.sprintf "%s %s, with a counterexample" (sites (List.length violated)) where)
    else if skipped <> [] then
      let reasons = List.sort_uniq compare (List.map O.reason_detail skipped) in
      Some
        ( Not_proved,
          Printf.sprintf "%s %s: %s" (sites (List.length skipped)) where
            (String.concat "; " reasons) )
    else Some (Proved, Printf.sprintf "%d %s %s" n (plural n "site" "sites") where)

(* Every fn the decls declare, by name, with its span (nested modules too). *)
let rec fn_spans (decls : A.decl list) : (string * A.span) list =
  List.concat_map
    (function
      | A.DFn (fd, sp) -> [ (fd.A.fn_name.A.txt, sp) ]
      | A.DMod (_, _, inner, _) -> fn_spans inner
      | _ -> [])
    decls

let rec actors (decls : A.decl list) : (string * A.actor_def * A.span) list =
  List.concat_map
    (function
      | A.DActor (_, n, ad, sp) -> [ (n.A.txt, ad, sp) ]
      | A.DMod (_, _, inner, _) -> actors inner
      | _ -> [])
    decls

let rec protocols (decls : A.decl list) : (string * A.protocol_def) list =
  List.concat_map
    (function
      | A.DProtocol (n, pd, _) -> [ (n.A.txt, pd) ]
      | A.DMod (_, _, inner, _) -> protocols inner
      | _ -> [])
    decls

let actor_lines ~(user : A.span -> bool) ~(fns : (string * A.span) list)
    ~(deploy_known : bool) (name : string) (ad : A.actor_def) : line list =
  let obs = List.filter (fun (o : O.t) -> user o.O.span) (O.all ()) in
  let low = String.lowercase_ascii name in
  let fn_span suffix = List.assoc_opt (low ^ suffix) fns in
  let in_fn suffix (o : O.t) =
    match fn_span suffix with Some sp -> within sp o.O.span | None -> false
  in
  let is_state (o : O.t) =
    o.O.kind = O.Precondition && last_segment o.O.callee = name
  in
  let handlers = List.map (fun (h : A.actor_handler) -> h.A.ah_msg.A.txt) ad.A.actor_handlers in
  let is_msg (o : O.t) =
    o.O.kind = O.Precondition
    && List.mem (last_segment o.O.callee) handlers
    && (match String.rindex_opt o.O.callee '.' with
        | None -> true
        | Some i -> last_segment (String.sub o.O.callee 0 i) = name)
  in
  let derived =
    match List.assoc_opt name !March_desugar.Desugar_migrate_derive.report with
    | Some (March_desugar.Desugar_migrate_derive.Derived _) -> true
    | _ -> false
  in
  (* A derived migration's body carries synthetic spans (file `<none>`,
     Desugar_derive.respan_derived_decl) under the actor's own span, so its
     obligations are told apart by that file, not by containment. *)
  let synthetic (o : O.t) = o.O.span.A.file = "<none>" in
  let in_migrate_state o = if derived then false else in_fn "_migrate_state" o in
  let migrate_state =
    if derived then List.filter (fun o -> is_state o && synthetic o) (O.all ())
    else List.filter (fun o -> is_state o && in_migrate_state o) obs
  in
  let state =
    List.filter (fun o -> is_state o && not (in_migrate_state o) && not (in_fn "_migrate_msg" o)) obs
  in
  let migrate_msg = List.filter (fun o -> is_msg o && in_fn "_migrate_msg" o) obs in
  let msgs = List.filter (fun o -> is_msg o && not (in_fn "_migrate_msg" o)) obs in
  let refined_fields =
    List.exists (fun (f : A.field) -> match f.A.fld_ty with A.TyRefine _ -> true | _ -> false)
      ad.A.actor_state
  in
  let refined_params =
    List.exists
      (fun (h : A.actor_handler) ->
        List.exists
          (fun (p : A.param) -> match p.A.param_ty with Some (A.TyRefine _) -> true | _ -> false)
          h.A.ah_params)
      ad.A.actor_handlers
  in
  let line what (l, d) = { what; label = l; detail = d } in
  let state_line =
    match summarise ~where:"in init and handlers" state with
    | Some s -> [ line "state refinements" s ]
    | None when refined_fields -> [ line "state refinements" (Not_proved, "no state is built where the checker sees it") ]
    | None -> []
  in
  let invariant_line =
    match ad.A.actor_invariant with
    | None -> []
    | Some _ ->
      [ line "@invariant"
          ( Not_checked,
            "init and handler results are not checked against it; a hot deploy checks \
             it on the migrated state" ) ]
  in
  let msg_line =
    match summarise ~where:"where a message is built" msgs with
    | Some s -> [ line "handler contracts" s ]
    | None when refined_params ->
      [ line "handler contracts" (Proved, "no message is built in this build, so none can break them") ]
    | None -> []
  in
  let deployed_note =
    if deploy_known then "against the deployed build"
    else "against its parameter type (no deployed build known)"
  in
  let accepted =
    List.mem name !Flags.accept_unproved || List.mem (name ^ ".state") !Flags.accept_unproved
  in
  let migrate_state_line =
    match fn_span "_migrate_state" with
    | None -> []
    | Some _ ->
      let what = if derived then "migrate_state (derived)" else "migrate_state" in
      (match summarise ~where:deployed_note migrate_state with
       | Some (Not_proved, d) ->
         [ line what
             ( Not_proved,
               d
               ^ (if accepted then "; accepted unproved, so a hot deploy checks it on the live state"
                  else
                    Printf.sprintf "; a hot deploy is refused unless built with \
                                    --accept-unproved %s.state" name) ) ]
       | Some s -> [ line what s ]
       | None ->
         [ line what (Proved, "builds a state with no refinement to establish") ])
  in
  let migrate_msg_line =
    match fn_span "_migrate_msg" with
    | None -> []
    | Some _ ->
      (match summarise ~where:deployed_note migrate_msg with
       | Some s -> [ line "migrate_msg" s ]
       | None -> [ line "migrate_msg" (Proved, "converts to no refined message") ])
  in
  let remote_line =
    if ad.A.actor_remote then
      [ line "messages from other nodes"
          (Assumed, "a remote sender's message is not checked against the handler contracts") ]
    else []
  in
  state_line @ invariant_line @ msg_line @ migrate_state_line @ migrate_msg_line @ remote_line

(* The protocol's lines from its translation-validation rows
   ([Session_validate], M6): a projection that agrees with
   [Session.Theory.project] inherits what the stdlib proves about it. *)
let protocol_lines ~(fragment : (unit, string) result) (rows : Session_validate.row list) (pd : A.protocol_def)
    : int * line list =
  let rec roles acc = function
    | [] -> acc
    | A.ProtoMsg (s, r, _, _) :: rest -> roles (s.A.txt :: r.A.txt :: acc) rest
    | A.ProtoLoop (steps, _) :: rest -> roles (roles acc steps) rest
    | A.ProtoChoice (c, branches) :: rest ->
      roles (List.fold_left (fun acc (_, st) -> roles acc st) (c.A.txt :: acc) branches) rest
    | A.ProtoCrashOr (inner, crash, _) :: rest -> roles acc (inner :: crash @ rest)
    | _ :: rest -> roles acc rest
  in
  let n = List.length (List.sort_uniq compare (roles [] pd.A.proto_steps)) in
  let module S = Session_validate in
  (* The endpoints generator applies to some protocols only; a row saying it
     does not is no evidence either way. *)
  let rows =
    List.filter
      (fun (r : S.row) ->
        not (r.S.projector = "endpoints" && r.S.role = "*"
             && (match r.S.outcome with S.Not_compared _ -> true | _ -> false)))
      rows
  in
  let differs = List.filter (fun (r : S.row) -> match r.S.outcome with S.Differs _ -> true | _ -> false) rows in
  let not_compared =
    List.filter_map
      (fun (r : S.row) ->
        match r.S.outcome with
        | S.Not_compared why -> Some (if r.S.role = "*" then why else Printf.sprintf "%s: %s" r.S.role why)
        | _ -> None)
      rows
    |> List.sort_uniq compare
  in
  let projectors =
    List.sort_uniq compare (List.map (fun (r : S.row) -> r.S.projector) rows) |> String.concat " and "
  in
  let projection =
    if differs <> [] then
      { what = "projection"; label = Violated;
        detail =
          Printf.sprintf
            "the %s projector disagrees with Session.Theory.project for %s (a compiler bug; \
             --validate-projections shows both)"
            (List.hd differs).S.projector
            (String.concat ", " (List.sort_uniq compare (List.map (fun (r : S.row) -> r.S.role) differs))) }
    else if not_compared <> [] then
      { what = "projection"; label = Not_checked;
        detail = "outside Session.Theory's fragment (" ^ String.concat "; " not_compared ^ ")" }
    else if rows = [] then
      { what = "projection"; label = Not_checked; detail = "no projection was compared" }
    else
      { what = "projection"; label = Proved_spec;
        detail =
          Printf.sprintf "the %s %s agree%s with Session.Theory.project for every role%s"
            projectors (if String.contains projectors ' ' then "projectors" else "projector")
            (if String.contains projectors ' ' then "" else "s")
            (if n = 2 then ", whose two projections are dual (Session.Theory.project_dual)" else "") }
  in
  (* C3-C5 hold for a protocol in Session.Theory's fragment once its
     projections are validated (the laws are about `project`). *)
  let laws =
    if projection.label <> Proved_spec then Error "its projections are not validated"
    else fragment
  in
  let pairwise =
    if n = 2 then []
    else
      match laws with
      | Ok () ->
        [ { what = "pairwise duality"; label = Proved_spec;
            detail = "what each pair of roles does with each other is dual (Session.Theory.pairwise)" } ]
      | Error why ->
        [ { what = "pairwise duality"; label = Checked_compiler;
            detail = "every send has the matching receive at its peer; not proved: " ^ why } ]
  in
  let deadlock =
    match laws with
    | Ok () ->
      { what = "deadlock freedom"; label = Proved_spec;
        detail =
          "on the protocol's own schedule every role can take each step and every role finishes \
           (Session.Theory.progress, projections_compose; synchronous delivery)" }
    | Error why -> { what = "deadlock freedom"; label = Not_checked; detail = "not proved: " ^ why }
  in
  (n, (projection :: pairwise) @ [ deadlock ])

let pad s w = if String.length s >= w then s else s ^ String.make (w - String.length s) ' '

let print_block (oc : out_channel) (head : string) (lines : line list) =
  (* The worst label, [Assumed] aside; a block of nothing but trust
     boundaries is `assumed`, never `proved`. *)
  let worst =
    match List.filter (fun l -> l.label <> Assumed) lines with
    | [] -> Assumed
    | l0 :: rest ->
      List.fold_left (fun acc l -> if rank l.label < rank acc then l.label else acc) l0.label rest
  in
  Printf.fprintf oc "%s: %s\n" head
    (if lines = [] then "nothing stated" else label_text worst);
  let w = List.fold_left (fun acc l -> max acc (String.length l.what)) 0 lines in
  List.iter
    (fun l -> Printf.fprintf oc "  %s  %s: %s\n" (pad l.what w) (label_text l.label) l.detail)
    lines

(** Print the report for the entry file [filename] (and [user_files]):
    [desugared] supplies the actors and the migration functions, [surface]
    (the decls before desugar) the protocols. *)
let print ?(oc = stdout) ~filename ~user_files ~(surface : A.decl list) (desugared : A.decl list) =
  let user (sp : A.span) =
    let f = sp.A.file in
    f = filename || List.mem f user_files
  in
  let fns = fn_spans desugared in
  let deploy_known = !March_refinecheck.Hcr_baseline.baseline <> [] in
  let acts = List.filter (fun (_, _, sp) -> user sp) (actors desugared) in
  List.iter
    (fun (name, ad, _) ->
      print_block oc ("actor " ^ name) (actor_lines ~user ~fns ~deploy_known name ad))
    acts;
  let rows = Session_validate.run surface in
  List.iter
    (fun (name, pd) ->
      let n, lines =
        protocol_lines ~fragment:(Session_validate.fragment name)
          (List.filter (fun (r : Session_validate.row) -> r.Session_validate.proto = name) rows) pd
      in
      print_block oc (Printf.sprintf "protocol %s (%d roles)" name n) lines)
    (protocols surface);
  if acts <> [] then
    (* Actor.Theory (stdlib/actor_theory.march) proves these about a model
       of the mailbox; the runtime is tied to the model by the native
       fixtures named here (lemmas design §4.2, M8).  Never more than
       `proved (model) · tested (runtime)`. *)
    print_block oc "runtime"
      [ { what = "per-sender message order";
          label = Proved_model_tested;
          detail =
            "Actor.Theory.enq_self, enq_other, replay_order, call_keeps_others; tested: \
             actor_theory_conformance, actor_call_in_handler_keeps_messages" };
        { what = "Actor.call replies";
          label = Proved_model_tested;
          detail =
            "a late reply never answers a later call (Actor.Theory.stale_reply_ignored, \
             call_reply_cat); tested: actor_call_late_reply" };
        { what = "DOWN delivery";
          label = Proved_model;
          detail =
            "at most once, never dropped by a full mailbox (Actor.Theory.down_at_most_once, \
             down_never_dropped); the runtime is not yet tested against it" } ];
  if acts = [] && protocols surface = [] then
    Printf.fprintf oc "no actors or protocols in %s\n" filename
