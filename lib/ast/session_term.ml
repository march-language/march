(** The terms of [Session.Theory] (stdlib/session_theory.march) in OCaml:
    a protocol as a [SessionGlobal], a role's projection as a [SessionLocal], over [Int]
    ids for roles, labels and payload types.

    The compiler has two projectors (the [Chan(Role, Proto)] typechecker,
    [Typecheck_session.project_steps_at], and the [@[endpoints]] generator,
    [Desugar_endpoints.project]).  Each one's output is converted to a
    [local] here and checked against the stdlib's [project] by evaluation
    (lemmas design §5.2, M6: translation validation), so that what the
    stdlib proves about [project] holds for the protocols the compiler
    actually builds.

    A conversion is faithful or it refuses ([Outside]): a protocol outside
    the theory's fragment (a crash branch) is never squeezed into it. *)

type global =
  | GEnd
  | GMsg of int * int * int * global        (** from, to, payload, next *)
  | GChoice of int * (int * global) list    (** chooser, labelled branches *)
  | GLoop of global * global                (** body (ends in [GVar 0]), after *)
  | GVar of int                             (** de Bruijn: 0 is the nearest loop *)

type local =
  | LEnd
  | LSend of int * int * local              (** peer, payload, next *)
  | LRecv of int * int * local
  | LChoose of (int * local) list
  | LOffer of (int * local) list
  | LRec of local
  | LVar of int

(** Why a protocol, or a projection, is outside the theory's fragment. *)
exception Outside of string

(** A name → id table (roles, labels or payload types of one protocol). *)
type ids = { tbl : (string, int) Hashtbl.t; mutable next : int }

let ids () = { tbl = Hashtbl.create 8; next = 0 }

let id (t : ids) (s : string) : int =
  match Hashtbl.find_opt t.tbl s with
  | Some i -> i
  | None ->
    let i = t.next in
    Hashtbl.replace t.tbl s i;
    t.next <- i + 1;
    i

(** The protocol's steps as a [global]: every choice's branches carry the
    steps after it, a loop's body ends in its own back-edge, `stop` is
    [GEnd] (it ends the conversation for every role, as both projectors
    read it).  [payload] names a message type. *)
let global_of_steps ~(role : string -> int) ~(label : string -> int) ~(payload : Ast.ty -> int)
    (steps : Ast.protocol_step list) : global =
  let rec go steps cont =
    match steps with
    | [] -> cont
    | Ast.ProtoMsg (s, r, t, _) :: rest -> GMsg (role s.Ast.txt, role r.Ast.txt, payload t, go rest cont)
    | Ast.ProtoLoop (inner, _) :: rest -> GLoop (go inner (GVar 0), go rest cont)
    | Ast.ProtoChoice (c, branches) :: rest ->
      if List.exists (fun ((l : Ast.name), _) -> l.Ast.txt = "crash") branches then
        raise (Outside "a crash branch");
      let after = go rest cont in
      GChoice (role c.Ast.txt, List.map (fun ((l : Ast.name), st) -> (label l.Ast.txt, go st after)) branches)
    | Ast.ProtoStop _ :: _ -> GEnd
    | Ast.ProtoRoleNeeds _ :: rest -> go rest cont
    | Ast.ProtoMayCrash _ :: _ -> raise (Outside "a role that may crash")
    | Ast.ProtoCrashOr _ :: _ -> raise (Outside "a crash branch")
  in
  go steps GEnd

(** The index of loop variable [x] among the enclosing binders [env]
    (innermost first). *)
let var_index (env : string list) (x : string) : int =
  let rec go i = function
    | [] -> raise (Outside ("an unbound loop variable " ^ x))
    | y :: rest -> if y = x then i else go (i + 1) rest
  in
  go 0 env

let rec show_global = function
  | GEnd -> "GEnd"
  | GMsg (f, t, p, k) -> Printf.sprintf "GMsg(%d, %d, %d, %s)" f t p (show_global k)
  | GChoice (c, bs) ->
    Printf.sprintf "GChoice(%d, %s)" c
      (String.concat "" (List.map (fun (l, g) -> Printf.sprintf "GBCons(%d, %s, " l (show_global g)) bs)
       ^ "GBNil" ^ String.make (List.length bs) ')')
  | GLoop (b, a) -> Printf.sprintf "GLoop(%s, %s)" (show_global b) (show_global a)
  | GVar i -> Printf.sprintf "GVar(%d)" i

let rec show_local = function
  | LEnd -> "LEnd"
  | LSend (p, t, k) -> Printf.sprintf "LSend(%d, %d, %s)" p t (show_local k)
  | LRecv (p, t, k) -> Printf.sprintf "LRecv(%d, %d, %s)" p t (show_local k)
  | LChoose bs -> "LChoose(" ^ show_branches bs ^ ")"
  | LOffer bs -> "LOffer(" ^ show_branches bs ^ ")"
  | LRec k -> "LRec(" ^ show_local k ^ ")"
  | LVar i -> Printf.sprintf "LVar(%d)" i

and show_branches bs =
  String.concat "" (List.map (fun (l, k) -> Printf.sprintf "LBCons(%d, %s, " l (show_local k)) bs)
  ^ "LBNil" ^ String.make (List.length bs) ')'

(** One projector's view of one protocol: the protocol, whether it is
    multiparty (more than two roles, as both projectors decide it), and each
    role's projection converted, or why it could not be. *)
type view = {
  v_global : global;
  v_multiparty : bool;
  v_roles : (string * int) list;
  v_locals : (string * (local, string) result) list;
}

(** The typechecker's view of each protocol it checked, by protocol name
    (filled by [Typecheck], read by the validator). *)
let typecheck_views : (string, (view, string) result) Hashtbl.t = Hashtbl.create 8
