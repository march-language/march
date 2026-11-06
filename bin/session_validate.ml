(** Translation validation of the two protocol projectors against
    [Session.Theory.project] (lemmas design §5.2, M6).

    For each protocol of the entry file, each projector's view
    ([Typecheck_session.theory_view], [Desugar_endpoints.theory_view]) gives
    the protocol as a [SessionGlobal] and every role's projection as a [SessionLocal].
    The stdlib's [project], run in the interpreter on those ground terms,
    must give the same [SessionLocal] ([Session.Theory.same]).  A role outside the
    fragment (it is not told a choice: [Session.Theory.informed] is false)
    is not compared, and said so.

    Evaluation, not SMT: the terms are ground, so the interpreter decides
    them whatever their size.  Once a projection agrees, every law
    [Session.Theory] proves about [project] holds for it. *)

module A = March_ast.Ast
module T = March_ast.Session_term
module V = March_eval.Eval_types
module W = March_refinecheck.Witness

type outcome = Agrees | Differs of string | Not_compared of string

type row = { proto : string; projector : string; role : string; outcome : outcome }

let rec v_global : T.global -> V.value = function
  | T.GEnd -> V.VCon ("GEnd", [])
  | T.GMsg (f, t, p, k) -> V.VCon ("GMsg", [ V.VInt f; V.VInt t; V.VInt p; v_global k ])
  | T.GChoice (c, bs) ->
    V.VCon ("GChoice",
            [ V.VInt c;
              List.fold_right (fun (l, g) acc -> V.VCon ("GBCons", [ V.VInt l; v_global g; acc ])) bs
                (V.VCon ("GBNil", [])) ])
  | T.GLoop (b, a) -> V.VCon ("GLoop", [ v_global b; v_global a ])
  | T.GVar i -> V.VCon ("GVar", [ V.VInt i ])

let rec v_local : T.local -> V.value = function
  | T.LEnd -> V.VCon ("LEnd", [])
  | T.LSend (p, t, k) -> V.VCon ("LSend", [ V.VInt p; V.VInt t; v_local k ])
  | T.LRecv (p, t, k) -> V.VCon ("LRecv", [ V.VInt p; V.VInt t; v_local k ])
  | T.LChoose bs -> V.VCon ("LChoose", [ v_branches bs ])
  | T.LOffer bs -> V.VCon ("LOffer", [ v_branches bs ])
  | T.LRec k -> V.VCon ("LRec", [ v_local k ])
  | T.LVar i -> V.VCon ("LVar", [ V.VInt i ])

and v_branches bs =
  List.fold_right (fun (l, k) acc -> V.VCon ("LBCons", [ V.VInt l; v_local k; acc ])) bs (V.VCon ("LBNil", []))

let theory_fn name = "Session.Theory." ^ name

let call name args =
  match W.call_fn_classified ~name:(theory_fn name) ~args with
  | W.C_ret v -> Ok v
  | W.C_overflow m | W.C_panic m | W.C_match_failure m | W.C_not_run m -> Error m
  | W.C_fuel -> Error "the interpreter ran out of fuel"

let check_view ~proto ~projector (view : (T.view, string) result) : row list =
  match view with
  | Error why -> [ { proto; projector; role = "*"; outcome = Not_compared why } ]
  | Ok v ->
    let g = v_global v.T.v_global in
    let mp = V.VBool v.T.v_multiparty in
    List.map
      (fun (role, local) ->
        let outcome =
          match local with
          | Error why -> Not_compared why
          | Ok l ->
            let r = V.VInt (List.assoc role v.T.v_roles) in
            (match call "informed" [ g; r; mp ] with
             | Error m -> Not_compared ("the theory could not be evaluated: " ^ m)
             | Ok (V.VBool false) -> Not_compared "the role is not told which branch a choice took"
             | Ok _ ->
               (match call "project" [ g; r; mp ] with
                | Error m -> Not_compared ("the theory could not be evaluated: " ^ m)
                | Ok spec ->
                  (match call "same" [ spec; v_local l ] with
                   | Ok (V.VBool true) -> Agrees
                   | Ok _ ->
                     Differs
                       (Printf.sprintf "the compiler built %s; Session.Theory.project gives %s, for %s"
                          (T.show_local l) (March_eval.Eval_runtime.value_to_string spec)
                          (T.show_global v.T.v_global))
                   | Error m -> Not_compared ("the theory could not be evaluated: " ^ m))))
        in
        { proto; projector; role; outcome })
      v.T.v_locals

let rec protocols (decls : A.decl list) : (string * A.protocol_def) list =
  List.concat_map
    (function
      | A.DProtocol (n, pd, _) -> [ (n.A.txt, pd) ]
      | A.DMod (_, _, inner, _) -> protocols inner
      | _ -> [])
    decls

(** Every row for the protocols of [surface] (the entry file's decls). *)
let run (surface : A.decl list) : row list =
  List.concat_map
    (fun (name, pd) ->
      let tc =
        match Hashtbl.find_opt T.typecheck_views name with
        | Some v -> v
        | None -> Error "the typechecker did not project it"
      in
      check_view ~proto:name ~projector:"typecheck" tc
      @ check_view ~proto:name ~projector:"endpoints" (March_desugar.Desugar_endpoints.theory_view pd))
    (protocols surface)

let rec has_loop : T.global -> bool = function
  | T.GLoop _ | T.GVar _ -> true
  | T.GEnd -> false
  | T.GMsg (_, _, _, k) -> has_loop k
  | T.GChoice (_, bs) -> List.exists (fun (_, g) -> has_loop g) bs

(** Whether the protocol is in the fragment the laws C3-C5 cover
    ([Session.Theory.in_fragment], evaluated on the typechecker's view, over
    all its roles): [Ok ()], or why not.  Inside it, `pairwise` (C3),
    `compose` (C4) and `progress` (C5) hold for the protocol once its
    projections are validated. *)
let fragment (name : string) : (unit, string) result =
  match Hashtbl.find_opt T.typecheck_views name with
  | None -> Error "the typechecker did not project it"
  | Some (Error why) -> Error why
  | Some (Ok v) ->
    let rs =
      List.fold_right (fun (_, i) acc -> V.VCon ("RCons", [ V.VInt i; acc ])) v.T.v_roles (V.VCon ("RNil", []))
    in
    let mp = V.VBool v.T.v_multiparty in
    (match call "in_fragment" [ v_global v.T.v_global; rs; mp ] with
     | Ok (V.VBool true) -> (
       (* The proved law's instance, run: C4 on the default schedule.  It
          cannot be false; if it is, the proof is unsound, which is a
          compiler bug, and nothing is claimed. *)
       match call "composes" [ v_global v.T.v_global; rs; mp; V.VCon ("PNil", []) ] with
       | Ok (V.VBool true) -> Ok ()
       | Ok _ -> Error "internal error: Session.Theory.compose's instance is false for this protocol (a compiler bug)"
       | Error m -> Error ("the theory could not be evaluated: " ^ m))
     | Ok _ ->
       Error
         (if has_loop v.T.v_global then "a loop (the laws cover loop-free protocols for now)"
          else
            "a choice whose other roles do not all see the same branches (a role other than the chooser \
             and the receiver of its first message must learn the label)")
     | Error m -> Error ("the theory could not be evaluated: " ^ m))

let outcome_text = function
  | Agrees -> "agrees with Session.Theory.project"
  | Differs d -> "DIFFERS: " ^ d
  | Not_compared why -> "not compared: " ^ why

(** `--validate-projections`: one line per protocol, projector and role on
    stdout; a difference is a compiler bug, so it fails the run. *)
let print (surface : A.decl list) : unit =
  let rows = run surface in
  List.iter
    (fun r -> Printf.printf "projection %s %s (%s): %s\n" r.proto r.role r.projector (outcome_text r.outcome))
    rows;
  List.iter
    (fun (name, _) ->
      match fragment name with
      | Ok () -> Printf.printf "laws %s: in the fragment (pairwise duality, composition, deadlock freedom)\n" name
      | Error why -> Printf.printf "laws %s: outside the fragment: %s\n" name why)
    (protocols surface);
  if List.exists (fun r -> match r.outcome with Differs _ -> true | _ -> false) rows then begin
    prerr_endline
      "projection: a compiler projector disagrees with Session.Theory.project; this is a compiler bug";
    exit 1
  end
