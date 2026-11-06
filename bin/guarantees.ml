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

type label = Proved | Violated | Not_proved | Not_checked | Checked_compiler | Assumed

let label_text = function
  | Proved -> "proved"
  | Violated -> "violated"
  | Not_proved -> "not proved"
  | Not_checked -> "not checked"
  | Checked_compiler -> "checked (compiler)"
  | Assumed -> "assumed"

(* Worst first, for an actor's one-line summary.  [Assumed] is a boundary,
   not a weakness of this build, so it never decides the summary. *)
let rank = function
  | Violated -> 0 | Not_checked -> 1 | Not_proved -> 2 | Checked_compiler -> 3
  | Proved -> 4 | Assumed -> 5

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

let protocol_lines (pd : A.protocol_def) : int * line list =
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
  ( n,
    [ { what = "projection";
        label = Checked_compiler;
        detail =
          (if n = 2 then "the two roles' projections are dual"
           else "every send has the matching receive at its peer") };
      { what = "deadlock freedom"; label = Not_checked; detail = "no proof covers this protocol yet" } ] )

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
  List.iter
    (fun (name, pd) ->
      let n, lines = protocol_lines pd in
      print_block oc (Printf.sprintf "protocol %s (%d roles)" name n) lines)
    (protocols surface);
  if acts <> [] then
    print_block oc "runtime"
      [ { what = "mailbox order, Actor.call replies, DOWN delivery";
          label = Assumed;
          detail = "the runtime is trusted; nothing here proves it" } ];
  if acts = [] && protocols surface = [] then
    Printf.fprintf oc "no actors or protocols in %s\n" filename
