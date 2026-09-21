(** `@[endpoints]`: generate typed session endpoints for a protocol.

    Design record: specs/todos/2026-09-03-protocol-projector-typed-endpoints.md.

    March already projects a `protocol` onto every role and checks the
    projections against each other (lib/typecheck/typecheck_session.ml), but
    only the same-thread `Chan`/`MPST` runtime consumes those projections.  The
    `Session` capability (stdlib/session.march) runs for real -- event-driven,
    with a swappable transport -- and knows nothing about protocols: endpoints
    are `Int`, messages are `Bytes`.  This module is the join.  For a protocol
    declared

      @[endpoints]
      protocol Stream do … end

    it generates, as ordinary AST inserted next to the user's declarations:

    - one module `Stream_Msg` holding the message type (one constructor per
      message or label), a `Json` codec over `Bytes`, and the role indices;
    - one module per role, `Stream_Prod`, `Stream_Cons`, …, holding one
      [always_linear] type PER SESSION STATE and one function per transition;
    - one module `Stream_Run` with `run_<Role>` per role: the typed front of
      the stdlib role runner (`SessionNode.run`), which takes the role's body
      from its entry state and does the listen/connect/accept wiring
      (specs/progress/2026-09-16-role-runner.md).

    States as nominal linear types is what makes this cheap: the ORDINARY
    typechecker then enforces protocol order (only the transition taking the
    state you hold is callable) and linearity (a stale state cannot be reused,
    a live one cannot be abandoned) with no new machinery.

    Two things the review of the design found and this file must honour:

    - Linearity does NOT reach a lambda's parameters (a linear value passed
      into a callback and never used is accepted silently), and every generated
      callback is a lambda.  So every callback returns [Yield], a public type
      whose only constructor takes a value of a PRIVATE type, produced only by
      the wrappers that consume a state.  A callback that abandons its state
      has nothing to return.
    - The projection's offer/receive fusion (a label and its payload are ONE
      message) assumes every branch of a `choose` begins with a message from
      the chooser, and the language does not enforce that.  It is enforced
      here, with a diagnostic, before anything is generated.

    Why AST and not source text: [desugar_module] has some twenty callers
    (driver, LSP, REPL, forge, search, lint), and generating here is the only
    way every one of them -- the editor above all -- sees the generated
    modules.  Building AST also carries each payload type verbatim instead of
    printing and re-parsing it.  It is still checked like any other code: the
    typechecker runs after this. *)

open March_ast.Ast
module Err = March_errors.Errors
module D = Desugar_derive

let attr = "endpoints"

(* ── the local session type, over surface types ───────────────────────── *)

(** A role's projection, mirroring [Typecheck_session.project_steps] but over
    [Ast.ty] (so payload types survive verbatim) and carrying the message
    CONSTRUCTOR each step encodes to.  [LOffer]/[LChoose] fuse the label with
    the branch-head message that carries it. *)
type lty =
  | LSend   of string * string * ty * lty                (** to, ctor, payload, next *)
  | LRecv   of string * string * ty * lty                (** from, ctor, payload, next *)
  | LChoose of (string * string * string * ty * lty) list   (** (label, to, ctor, payload, next): each branch names its own receiver *)
  | LOffer  of string * (string * string * ty * lty) list   (** from, … *)
  | LRecvCrash of string * (string * string * ty * lty) list * lty
      (** from (a role that may crash), the messages it may send (as [LOffer]'s
          branches: one for `A -> B : T or crash`, one per label for a
          `choose by A` with a `crash` branch), and the crash continuation:
          what this role, the DETECTOR, does if [from] crashes before sending
          (2026-09-20 crash branches, design Part B). *)
  | LRec    of string * lty
  | LVar    of string
  | LEnd

(** Surface-type equality up to spans, for the multiparty merge rule. *)
let rec ty_equal (a : ty) (b : ty) : bool =
  match a, b with
  | TyCon (n, xs), TyCon (m, ys) ->
    n.txt = m.txt && List.length xs = List.length ys && List.for_all2 ty_equal xs ys
  | TyVar n, TyVar m -> n.txt = m.txt
  | TyArrow (a1, a2), TyArrow (b1, b2) -> ty_equal a1 b1 && ty_equal a2 b2
  | TyTuple xs, TyTuple ys -> List.length xs = List.length ys && List.for_all2 ty_equal xs ys
  | TyLinear (l, x), TyLinear (k, y) -> l = k && ty_equal x y
  | TyNat n, TyNat m -> n = m
  | _ -> false

let rec lty_equal (a : lty) (b : lty) : bool =
  let brs xs ys =
    List.length xs = List.length ys
    && List.for_all2
         (fun (l1, c1, t1, n1) (l2, c2, t2, n2) ->
            l1 = l2 && c1 = c2 && ty_equal t1 t2 && lty_equal n1 n2)
         xs ys
  in
  match a, b with
  | LSend (r1, c1, t1, n1), LSend (r2, c2, t2, n2)
  | LRecv (r1, c1, t1, n1), LRecv (r2, c2, t2, n2) ->
    r1 = r2 && c1 = c2 && ty_equal t1 t2 && lty_equal n1 n2
  | LChoose b1, LChoose b2 ->
    List.length b1 = List.length b2
    && List.for_all2
         (fun (l1, r1, c1, t1, n1) (l2, r2, c2, t2, n2) ->
            l1 = l2 && r1 = r2 && c1 = c2 && ty_equal t1 t2 && lty_equal n1 n2)
         b1 b2
  | LOffer (r1, b1), LOffer (r2, b2) -> r1 = r2 && brs b1 b2
  | LRecvCrash (r1, b1, c1), LRecvCrash (r2, b2, c2) -> r1 = r2 && brs b1 b2 && lty_equal c1 c2
  | LRec (x, s), LRec (y, t) -> x = y && lty_equal s t
  | LVar x, LVar y -> x = y
  | LEnd, LEnd -> true
  | _ -> false

(* ── annotated steps: every message gets its constructor name ─────────── *)

type astep =
  | AMsg    of string * string * ty * string        (** sender, receiver, payload, ctor *)
  | ALoop   of astep list
  | AChoice of string * (string * astep list) list  (** chooser, (label, steps); a branch labelled `crash` is the chooser's crash branch *)
  | AStop
  | ACrashOr of astep * astep list                  (** an [AMsg] with its sender's crash branch *)

let capitalize s =
  if s = "" then s else String.capitalize_ascii s

(** Name every message.  A labelled step (`item: Prod -> Cons : Int`) is
    named after its label (`Item`), and a `choose` branch's head message
    after the branch label (`more` -> `More`); any other message after its
    endpoints, numbered among the messages between the same pair so an
    unrelated edit elsewhere does not rename it (`Msg_Prod_Cons_1`).  Two
    steps with one name share a constructor when their payloads agree
    ([collect_ctors] rejects them when they differ, as it does two branch
    heads with one label).  Returns [None], having reported, when a branch
    does not begin with a message from the chooser -- the rule the
    offer/receive fusion needs and the language does not check -- or when a
    label is where it cannot mean anything: on a branch head, which the
    branch label already names, or spelling a synthesised `Msg_` name. *)
let annotate (errors : Err.ctx) ~(proto : string) ~(span : span)
    (steps : protocol_step list) : astep list option =
  let counts : (string * string, int) Hashtbl.t = Hashtbl.create 8 in
  let ok = ref true in
  let synth s r =
    let k = 1 + Option.value ~default:0 (Hashtbl.find_opt counts (s, r)) in
    Hashtbl.replace counts (s, r) k;
    Printf.sprintf "Msg_%s_%s_%d" s r k
  in
  let ctor_of s r = function
    | None -> synth s r
    | Some (label : name) ->
      let c = capitalize label.txt in
      if String.length c >= 4 && String.sub c 0 4 = "Msg_" then begin
        ok := false;
        Err.error errors ~span:label.span
          (Printf.sprintf
             "Protocol `%s`: the label `%s` would name the message `%s`, which is the shape \
              of the names `@[endpoints]` makes up for unlabelled steps (`Msg_<From>_<To>_<k>`), \
              so it could collide with one. Pick a label that does not start with `msg_`."
             proto label.txt c)
      end;
      c
  in
  let rec go (steps : protocol_step list) : astep list =
    List.concat_map
      (function
        | ProtoMsg (s, r, t, label) -> [ AMsg (s.txt, r.txt, t, ctor_of s.txt r.txt label) ]
        | ProtoLoop inner -> [ ALoop (go inner) ]
        | ProtoStop _ -> [ AStop ]
        (* `may crash` is a declaration, checked by the typechecker (rule 6);
           the roles it names reach [project] through [crashers_of]. *)
        | ProtoMayCrash _ -> []
        (* The message is named first, its crash branch after it, in reading
           order. *)
        | ProtoCrashOr (inner, crash, _) ->
          (match go [ inner ] with
           | [ (AMsg _ as m) ] -> [ ACrashOr (m, go crash) ]
           | other -> other @ go crash)
        | ProtoChoice (chooser, branches) ->
          [ AChoice
            (chooser.txt,
             List.map
               (fun (lbl, arm) ->
                  match arm with
                  | ProtoMsg (s, r, t, label) :: rest when s.txt = chooser.txt ->
                    (match label with
                     | None -> ()
                     | Some l ->
                       ok := false;
                       Err.error errors ~span:l.span
                         (Printf.sprintf
                            "Protocol `%s`: the branch label `%s` already names this message \
                             (`%s`), so the step cannot carry a label of its own. Remove `%s:`."
                            proto lbl.txt (capitalize lbl.txt) l.txt));
                    (lbl.txt, AMsg (s.txt, r.txt, t, capitalize lbl.txt) :: go rest)
                  | ProtoCrashOr (ProtoMsg (s, r, t, _), crash, _) :: rest when s.txt = chooser.txt ->
                    (lbl.txt, ACrashOr (AMsg (s.txt, r.txt, t, capitalize lbl.txt), go crash) :: go rest)
                  (* The chooser's crash branch has no head message: the
                     detector takes it when the chooser is gone. *)
                  | _ when lbl.txt = "crash" -> (lbl.txt, go arm)
                  | _ ->
                    ok := false;
                    Err.error errors ~span:lbl.span
                      (Printf.sprintf
                         "Protocol `%s`: `@[endpoints]` needs every branch of `choose by %s` \
                          to begin with a message from `%s`, because the label travels \
                          on that message. Branch `%s` does not."
                         proto chooser.txt chooser.txt lbl.txt);
                    (lbl.txt, go arm))
               branches) ])
      steps
  in
  let annotated = go steps in
  ignore span;
  if !ok then Some annotated else None

(** The roles a protocol declares `may crash`. *)
let crashers_of (steps : protocol_step list) : string list =
  List.concat_map (function ProtoMayCrash (rs, _) -> List.map (fun (r : name) -> r.txt) rs | _ -> []) steps

(** All roles, in order of FIRST APPEARANCE.  The typechecker sorts them, but
    the order here is user-visible -- it is the role index a transport is
    handed -- and "the order you wrote them in, from 1" is the one a reader
    can predict.  [Typecheck_session.project_protocol] uses the same set. *)
let roles_of (steps : astep list) : string list =
  let seen = ref [] in
  let add r = if not (List.mem r !seen) then seen := r :: !seen in
  let rec go = function
    | [] -> ()
    | AMsg (s, r, _, _) :: rest -> add s; add r; go rest
    | ALoop inner :: rest -> go inner; go rest
    | AChoice (c, brs) :: rest -> add c; List.iter (fun (_, arm) -> go arm) brs; go rest
    | AStop :: rest -> go rest
    | ACrashOr (m, crash) :: rest -> go [ m ]; go crash; go rest
  in
  go steps;
  List.rev !seen

(** The roles [role] exchanges a message with, in role-index order.  A
    network transport needs one connection per entry, and checks it has them
    before the session starts (`SessionNode.require`) instead of failing at
    the first `emit` with "no connection to role N". *)
let peers_of (steps : astep list) (roles : string list) (role : string) : string list =
  let pairs = ref [] in
  let rec go = function
    | [] -> ()
    | AMsg (s, r, _, _) :: rest -> pairs := (s, r) :: !pairs; go rest
    | ALoop inner :: rest -> go inner; go rest
    | AChoice (_, brs) :: rest -> List.iter (fun (_, arm) -> go arm) brs; go rest
    | AStop :: rest -> go rest
    | ACrashOr (m, crash) :: rest -> go [ m ]; go crash; go rest
  in
  go steps;
  List.filter
    (fun other ->
       other <> role
       && List.exists (fun (s, r) -> (s = role && r = other) || (s = other && r = role)) !pairs)
    roles

(** The multiparty merge of a non-chooser's branch projections.  Every arm
    identical: that arm (the role never learns the label).  Else the role
    must RECEIVE every arm's first message from one role, and offers over
    those heads.  [strict] (an ordinary `choose`): every head is a receive
    from [chooser], as [annotate] guarantees every branch begins with the
    chooser's message.  Lenient (a crash branch, whose arms the DETECTOR
    heads, not the chooser): the heads may come from any one role, and an
    arm that is itself an offer from that role is spliced in -- the ECOOP
    full merge, as far as the well-formedness rules (typecheck.ml,
    [check_crash_branches], rule 4) let a protocol reach here.  A merge that
    fails yields an offer the typechecker reports against, as before. *)
let merge ~multiparty ~strict ~chooser (arms : (string * lty) list) : lty =
  match arms with
  | (_, first) :: more when multiparty && List.for_all (fun (_, a) -> lty_equal a first) more -> first
  | _ ->
    let heads =
      List.map
        (fun (lbl, arm) ->
           match arm with
           | LRecv (from, ctor, t, next) when strict && from = chooser -> Some (from, [ (lbl, ctor, t, next) ])
           (* Told by the detector's messages, not the chooser's labels: name
              each arm after the message this role receives. *)
           | LRecv (from, ctor, t, next) when not strict -> Some (from, [ (ctor, ctor, t, next) ])
           | LOffer (from, brs) when not strict -> Some (from, brs)
           | _ -> None)
        arms
    in
    let from =
      match heads with
      | Some (f, _) :: _ when List.for_all (function Some (g, _) -> g = f | None -> false) heads -> Some f
      | _ -> None
    in
    (match from with
     | Some f -> LOffer (f, List.concat_map (function Some (_, brs) -> brs | None -> []) heads)
     | None ->
       (* A bystander whose branches differ but who never learns the label:
          not projectable.  Mirror the typechecker's answer (an offer it
          cannot run) so the fault is reported there. *)
       LOffer (chooser, List.map (fun (lbl, arm) -> (lbl, capitalize lbl, TyTuple [], arm)) arms))

(** Project onto [role].  Same rules as [project_steps]: a loop is a binder
    whose back-edge is the loop's own variable, `stop` is [LEnd] outright, and
    a non-chooser merges a choice only in a multiparty protocol and only when
    every branch projects identically.  A crash branch ends the protocol (or
    the loop): its continuation is [LEnd], never the enclosing one. *)
let rec project ~proto ~multiparty (steps : astep list) (role : string) (cont : lty) : lty =
  match steps with
  | [] -> cont
  | step :: rest ->
    let rest_ty () = project ~proto ~multiparty rest role cont in
    (match step with
     | AMsg (s, r, t, ctor) ->
       if s = role then LSend (r, ctor, t, rest_ty ())
       else if r = role then LRecv (s, ctor, t, rest_ty ())
       else rest_ty ()
     | ACrashOr (AMsg (s, r, t, ctor), crash) ->
       let crash_ty () = project ~proto ~multiparty crash role LEnd in
       if s = role then
         (* A crashed role does nothing: the crash branch does not exist for it. *)
         LSend (r, ctor, t, rest_ty ())
       else if r = role then LRecvCrash (s, [ (ctor, ctor, t, rest_ty ()) ], crash_ty ())
       else
         (* A third party: told by the detector [r] which way it went. *)
         merge ~multiparty ~strict:false ~chooser:r [ (ctor, rest_ty ()); ("crash", crash_ty ()) ]
     | ACrashOr (other, crash) ->
       (* Not a message (cannot be built by [annotate]); project what is there. *)
       project ~proto ~multiparty (other :: crash @ rest) role cont
     | ALoop inner ->
       let x = proto ^ "_loop" in
       (match project ~proto ~multiparty inner role (LVar x) with
        | LVar _ -> rest_ty ()
        | body -> LRec (x, body))
     | AStop -> LEnd
     | AChoice (chooser, branches) ->
       let after = rest_ty () in
       let crash_arm = List.find_opt (fun (lbl, _) -> lbl = "crash") branches in
       let normal = List.filter (fun (lbl, _) -> lbl <> "crash") branches in
       let arms =
         List.map (fun (lbl, arm) -> (lbl, project ~proto ~multiparty arm role after)) normal
       in
       let crash_ty = Option.map (fun (_, arm) -> project ~proto ~multiparty arm role LEnd) crash_arm in
       if chooser = role then
         (* The branch head is this role's own send (checked in [annotate]), so
            its receiver is the branch's destination -- per branch, since a
            multiparty choice may tell a different role on each label.  The
            crash branch, if any, is not this role's: it has crashed. *)
         LChoose
           (List.map
              (fun (lbl, arm) ->
                 match arm with
                 | LSend (to_, ctor, t, next) -> (lbl, to_, ctor, t, next)
                 | _ -> (lbl, chooser, capitalize lbl, TyTuple [], arm))
              arms)
       else
         (match crash_ty with
          | None -> merge ~multiparty ~strict:true ~chooser arms
          | Some crash ->
            (* Every branch head is a message from the chooser (checked in
               [annotate]); the role that RECEIVES all of them is the
               detector, and takes the crash branch if the chooser is gone
               (rule 5: there is one such role).  Anyone else merges the
               branches with the crash branch, told apart by the detector. *)
            let heads =
              List.map
                (fun (lbl, arm) ->
                   match arm with
                   | LRecv (from, ctor, t, next) when from = chooser -> Some (lbl, ctor, t, next)
                   | _ -> None)
                arms
            in
            if heads <> [] && List.for_all Option.is_some heads then
              LRecvCrash (chooser, List.map Option.get heads, crash)
            else
              merge ~multiparty ~strict:false ~chooser (arms @ [ ("crash", crash) ])))

(* ── AST helpers ──────────────────────────────────────────────────────── *)

let sp = dummy_span
let n = D.mk_name
let tycon s args = TyCon (n s, args)
let t_int = tycon "Int" []
let t_bytes = tycon "Bytes" []
let t_string = tycon "String" []
let t_cap_session = tycon "Cap" [ tycon "Session.Live" [] ]
let var s = EVar (n s)
let app f args = EApp (var f, args, sp)
let con c args = ECon (n c, args, sp)
let lit_int i = ELit (LitInt i, sp)
let lit_str s = ELit (LitString s, sp)
let let_ ?ty name e = ELet ({ bind_pat = PatVar (n name); bind_ty = ty; bind_lin = Unrestricted; bind_expr = e }, sp)
let let_wild e = ELet ({ bind_pat = PatWild sp; bind_ty = None; bind_lin = Unrestricted; bind_expr = e }, sp)
let block es = EBlock (es, sp)
let match_ scrut branches =
  EMatch (scrut, List.map (fun (p, body) -> { branch_pat = p; branch_guard = None; branch_body = body }) branches, sp)
let pcon c ps = PatCon (n c, ps)
let pvar s = PatVar (n s)
let lam names body =
  ELam (List.map (fun s -> { param_name = n s; param_ty = None; param_lin = Unrestricted }) names, body, sp)
let param ?(lin = Unrestricted) name ty = FPNamed { param_name = n name; param_ty = Some ty; param_lin = lin }

(** A public single-clause function with typed parameters and a return type.
    [linear] names the parameters declared `linear` (used exactly once). *)
let fn ?(linear = []) name params ret body : decl =
  DFn
    ( { fn_name = n name; fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = Some ret;
        fn_bounds = [];
        fn_clauses =
          [ { fc_params =
                List.map (fun (p, t) -> param ~lin:(if List.mem p linear then Linear else Unrestricted) p t) params;
              fc_guard = None; fc_body = body; fc_span = sp; fc_params_span = sp } ] },
      sp )

let variant name args : variant = { var_name = n name; var_args = args; var_vis = Public }

let string_concat a b = app "++" [ a; b ]

let panic msg = app "panic" [ lit_str msg ]

(* ── state naming ─────────────────────────────────────────────────────── *)

(** Every distinct node of the projection is a state; name it after what the
    role must do there (`S_send_Item`, `S_offer_more_done`, `S_end`), so an
    unrelated edit elsewhere in the protocol does not rename it.  A second
    state that would take the same name gets a numeric suffix. *)
let state_names (root : lty) : (lty * string) list =
  let taken : (string, int) Hashtbl.t = Hashtbl.create 8 in
  let fresh base =
    match Hashtbl.find_opt taken base with
    | None -> Hashtbl.replace taken base 1; base
    | Some k -> Hashtbl.replace taken base (k + 1); Printf.sprintf "%s_%d" base (k + 1)
  in
  let labels brs = String.concat "_" (List.map (fun (l, _, _, _) -> l) brs) in
  let acc = ref [] in
  let rec go (t : lty) =
    match t with
    | LRec (_, body) -> go body
    | LVar _ -> ()
    | LEnd -> if not (List.exists (fun (s, _) -> s == t) !acc) then acc := (t, fresh "S_end") :: !acc
    | LSend (_, ctor, _, next) -> acc := (t, fresh ("S_send_" ^ ctor)) :: !acc; go next
    | LRecv (_, ctor, _, next) -> acc := (t, fresh ("S_recv_" ^ ctor)) :: !acc; go next
    | LChoose brs ->
      acc := (t, fresh ("S_choose_" ^ String.concat "_" (List.map (fun (l, _, _, _, _) -> l) brs))) :: !acc;
      List.iter (fun (_, _, _, _, nx) -> go nx) brs
    | LOffer (_, brs) -> acc := (t, fresh ("S_offer_" ^ labels brs)) :: !acc; List.iter (fun (_, _, _, nx) -> go nx) brs
    | LRecvCrash (_, brs, crash) ->
      (* From the detector's side one message with a crash branch is still
         one receive: `S_recv_<Ctor>`, as without the branch.  A `choose`
         with a `crash` branch is an offer over its labels, `crash` included. *)
      let base = match brs with [ (_, ctor, _, _) ] -> "S_recv_" ^ ctor | _ -> "S_offer_" ^ labels brs ^ "_crash" in
      acc := (t, fresh base) :: !acc;
      List.iter (fun (_, _, _, nx) -> go nx) brs;
      go crash
  in
  go root;
  List.rev !acc

(** The state a continuation lands in: [LVar] resolves to its binder's body,
    [LEnd]s all share one name. *)
let rec resolve (binders : (string * lty) list) (t : lty) : lty =
  match t with
  | LRec (x, body) -> resolve ((x, body) :: binders) body
  | LVar x -> (match List.assoc_opt x binders with Some b -> resolve binders b | None -> t)
  | _ -> t

let rec binders_of (t : lty) acc =
  match t with
  | LRec (x, body) -> binders_of body ((x, body) :: acc)
  | LSend (_, _, _, nx) | LRecv (_, _, _, nx) -> binders_of nx acc
  | LChoose brs -> List.fold_left (fun a (_, _, _, _, nx) -> binders_of nx a) acc brs
  | LOffer (_, brs) -> List.fold_left (fun a (_, _, _, nx) -> binders_of nx a) acc brs
  | LRecvCrash (_, brs, crash) -> binders_of crash (List.fold_left (fun a (_, _, _, nx) -> binders_of nx a) acc brs)
  | LVar _ | LEnd -> acc

(* ── generation ───────────────────────────────────────────────────────── *)

(** Distinct message constructors across every role, with their payloads.  The
    same constructor reached twice must carry the same payload. *)
let collect_ctors (errors : Err.ctx) ~proto ~span (steps : astep list) : (string * ty) list option =
  let acc = ref [] and ok = ref true in
  let add c t =
    match List.assoc_opt c !acc with
    | None -> acc := (c, t) :: !acc
    | Some t' ->
      if not (ty_equal t t') then begin
        ok := false;
        Err.error errors ~span
          (Printf.sprintf
             "Protocol `%s`: the label `%s` is used for two messages with different payload \
              types, so `@[endpoints]` cannot give it one constructor. Rename one of them."
             proto c)
      end
  in
  let rec go = function
    | [] -> ()
    | AMsg (_, _, t, c) :: rest -> add c t; go rest
    | ALoop inner :: rest -> go inner; go rest
    | AChoice (_, brs) :: rest -> List.iter (fun (_, arm) -> go arm) brs; go rest
    | AStop :: rest -> go rest
    | ACrashOr (m, crash) :: rest -> go [ m ]; go crash; go rest
  in
  go steps;
  if !ok then Some (List.rev !acc) else None

(** A protocol's fingerprint: a digest of its roles and steps (every message
    with its sender, receiver, constructor and payload type; loops, choices
    and stops), so two nodes built from different versions of a protocol can
    tell before they exchange a message.  An access point refuses an
    invitation whose fingerprint is not its own
    (specs/2026-09-19-choreography-access-points-and-crash-branches-design.md). *)
let rec ty_key (t : ty) : string =
  match t with
  | TyCon (c, []) -> c.txt
  | TyCon (c, args) -> c.txt ^ "(" ^ String.concat "," (List.map ty_key args) ^ ")"
  | TyVar v -> "'" ^ v.txt
  | TyArrow (a, b) -> "(" ^ ty_key a ^ "->" ^ ty_key b ^ ")"
  | TyTuple ts -> "(" ^ String.concat "," (List.map ty_key ts) ^ ")"
  | TyRecord fs -> "{" ^ String.concat "," (List.map (fun (f, t) -> f.txt ^ ":" ^ ty_key t) fs) ^ "}"
  | TyLinear (_, t) -> "lin " ^ ty_key t
  | TyNat k -> string_of_int k
  | _ -> "?"

let fingerprint_of ~proto (roles : string list) (steps : astep list) : string =
  let b = Buffer.create 256 in
  let rec go = function
    | [] -> ()
    | AMsg (f, t, ty, c) :: rest ->
      Buffer.add_string b (Printf.sprintf "%s>%s:%s(%s);" f t c (ty_key ty)); go rest
    | ALoop inner :: rest -> Buffer.add_string b "loop{"; go inner; Buffer.add_string b "}"; go rest
    | AChoice (by, brs) :: rest ->
      Buffer.add_string b ("choose " ^ by ^ "{");
      List.iter (fun (l, arm) -> Buffer.add_string b (l ^ "->"); go arm; Buffer.add_string b "|") brs;
      Buffer.add_string b "}"; go rest
    | AStop :: rest -> Buffer.add_string b "stop;"; go rest
    | ACrashOr (m, crash) :: rest ->
      go [ m ]; Buffer.add_string b "crash{"; go crash; Buffer.add_string b "}"; go rest
  in
  Buffer.add_string b (proto ^ "[" ^ String.concat "," roles ^ "]");
  go steps;
  Digest.to_hex (Digest.string (Buffer.contents b))

(** `<P>_Msg`: the message type, its `Json` codec over `Bytes`, and the role
    indices.  The derive is expanded HERE, inside the generated module, so it
    rebinds nobody's bare `to_json`/`from_json` in the user's module. *)
let msg_module (errors : Err.ctx) ~proto ~span ~fingerprint (ctors : (string * ty) list) (roles : string list)
    (peers : (string * string list) list) : decl =
  let mname = proto ^ "_Msg" in
  let msg_td = TDVariant (List.map (fun (c, t) -> variant c [ t ]) ctors) in
  let msg_decl = DType (Public, n "Msg", [], msg_td, sp) in
  let json_fns = D.expand_derive errors [ ("Msg", ([], msg_td)) ] (n "Msg") [ n "Json" ] span in
  let encode =
    fn "encode" [ ("m", tycon "Msg" []) ] t_bytes
      (app "Bytes.from_string" [ app "Json.to_string" [ app "to_json" [ var "m" ] ] ])
  in
  let decode =
    fn "decode" [ ("b", t_bytes) ] (tycon "Msg" [])
      (match_ (app "Json.parse" [ app "Bytes.to_string" [ var "b" ] ])
         [ ( pcon "Ok" [ pvar "jv" ],
             block
               [ let_ ~ty:(tycon "Result" [ tycon "Msg" []; t_string ]) "r" (app "from_json" [ var "jv" ]);
                 match_ (var "r")
                   [ (pcon "Ok" [ pvar "m" ], var "m");
                     ( pcon "Err" [ pvar "e" ],
                       app "panic" [ string_concat (lit_str (proto ^ ": undecodable message: ")) (var "e") ] ) ] ] );
           ( pcon "Err" [ pvar "e" ],
             app "panic" [ string_concat (lit_str (proto ^ ": message is not JSON: ")) (var "e") ] ) ])
  in
  (* `try_decode`: what the generated receive handlers use, so an
     undecodable message is the transport's to report (`Session.fail`) rather
     than a panic in whatever turn the delivery runs in.  `decode` stays for
     callers that want the panic. *)
  let try_decode =
    fn "try_decode" [ ("b", t_bytes) ] (tycon "Result" [ tycon "Msg" []; t_string ])
      (match_ (app "Json.parse" [ app "Bytes.to_string" [ var "b" ] ])
         [ ( pcon "Ok" [ pvar "jv" ],
             block
               [ let_ ~ty:(tycon "Result" [ tycon "Msg" []; t_string ]) "r" (app "from_json" [ var "jv" ]);
                 match_ (var "r")
                   [ (pcon "Ok" [ pvar "m" ], con "Ok" [ var "m" ]);
                     (pcon "Err" [ pvar "e" ], con "Err" [ string_concat (lit_str "undecodable message: ") (var "e") ]) ] ] );
           (pcon "Err" [ pvar "e" ], con "Err" [ string_concat (lit_str "message is not JSON: ") (var "e") ]) ])
  in
  (* 1-based, in order of first appearance; see [roles_of]. *)
  let role_fns = List.mapi (fun i r -> fn ("role_" ^ r) [] t_int (lit_int (i + 1))) roles in
  let index_of r = 1 + Option.get (List.find_index (fun x -> x = r) roles) in
  let int_list rs = List.fold_right (fun r acc -> con "Cons" [ lit_int (index_of r); acc ]) rs (con "Nil" []) in
  (* `peers_<R>()`: the role indices [R] exchanges a message with; see [peers_of]. *)
  let peer_fns = List.map (fun (r, ps) -> fn ("peers_" ^ r) [] (tycon "List" [ t_int ]) (int_list ps)) peers in
  (* `role_names()`: every role's name with its index, for
     `SessionNode.addrs_from_env`, which reads `<P>_<ROLE>_ADDR` per role. *)
  let role_names =
    fn "role_names" [] (tycon "List" [ TyTuple [ t_string; t_int ] ])
      (List.fold_right
         (fun r acc -> con "Cons" [ ETuple ([ lit_str r; lit_int (index_of r) ], sp); acc ])
         roles (con "Nil" []))
  in
  (* `others_<R>()`: every role but [R], ascending -- the roles an initiator
     fills from access points (it needs all of them, not only its peers). *)
  let other_fns =
    List.map (fun r -> fn ("others_" ^ r) [] (tycon "List" [ t_int ]) (int_list (List.filter (fun x -> x <> r) roles))) roles
  in
  let fp = fn "fingerprint" [] t_string (lit_str fingerprint) in
  (* `role_name(i)`: a role's name from its number, for messages -- every
     `RunError` carries role numbers, and a user never writes those. *)
  let role_name =
    fn "role_name" [ ("i", t_int) ] t_string
      (List.fold_right
         (fun r acc -> EIf (app "==" [ var "i"; lit_int (index_of r) ], lit_str r, acc, sp))
         roles (app "int_to_string" [ var "i" ]))
  in
  DMod (n mname, Public, (msg_decl :: json_fns) @ [ encode; decode; try_decode ] @ role_fns @ peer_fns @ other_fns
                         @ [ role_names; fp; role_name ], sp)

(** `<P>_<Role>`: one [always_linear] type per state and one function per
    transition, plus the unforgeable [Yield].  Also returns the name of the
    role's ENTRY state (what `register` yields), which `<P>_Run` types the
    role's body by. *)
let role_module (errors : Err.ctx) ~proto ~span ~(roles : string list) ~(nctors : int) (role : string) (root : lty)
    : decl * string =
  let mname = proto ^ "_" ^ role in
  let msg = proto ^ "_Msg" in
  let names = state_names root in
  let binders = binders_of root [] in
  let state_of t =
    let t = resolve binders t in
    match List.find_opt (fun (s, _) -> s == t) names with
    | Some (_, nm) -> nm
    | None -> (match List.find_opt (fun (s, _) -> lty_equal s t) names with Some (_, nm) -> nm | None -> "S_end")
  in
  let sty nm = tycon nm [] in
  let t_yield = tycon "Yield" [] in
  let yield = con "Yield" [ con "Secret" [] ] in
  let role_idx r = app (msg ^ ".role_" ^ r) [] in
  let state_types =
    List.map (fun (_, nm) -> DAlwaysLinearType (Public, n nm, [], TDVariant [ variant nm [ t_int ] ], sp)) names
  in
  let secret = DType (Private, n "Secret", [], TDVariant [ variant "Secret" [] ], sp) in
  let yield_ty = DType (Public, n "Yield", [], TDVariant [ variant "Yield" [ tycon "Secret" [] ] ], sp) in
  (* `Session.suspend` hands the handler `(from, msg, ep)`; the handler decodes
     and dispatches on the constructor, hands the callback the payload and the
     NEXT state built on the continuation endpoint, and returns the endpoint
     as the raw handler's `Int`. *)
  (* The catch-all for a message this state cannot receive.  Omitted when the
     listed arms already cover every constructor of `<P>_Msg`: it would be
     unreachable, and a warning the user can neither see nor fix. *)
  let unexpected_arm covered body = if covered >= nctors then [] else [ (PatWild sp, body) ] in
  (* A delivery the continuation cannot take -- undecodable, or a message
     this state does not receive -- is handed to the transport
     (`Session.fail`), which decides: the same-thread transports panic as the
     handler itself used to, `SessionNode` ends the session and reports
     `Protocol`.  The handler then returns its endpoint, as any handler does. *)
  let fail_with why = block [ let_wild (app "Session.fail" [ var "s"; var "ep1"; why ]); var "ep1" ] in
  (* `from` is the role this state receives from, which the projection carries
     (LRecv/LOffer).  A transport with several peers parks a delivery from
     anyone else until the continuation that wants it is installed; a
     same-thread or two-party transport ignores it.  Passing 0 here would be
     the old "whoever speaks next", which reorders under a real network. *)
  let suspend_with from ep arms =
    app "Session.suspend"
      [ var "s"; ep; role_idx from;
        lam [ "_from"; "msg"; "ep1" ]
          (match_ (app (msg ^ ".try_decode") [ var "msg" ])
             [ ( pcon "Ok" [ pvar "m" ],
                 match_ (var "m")
                   (List.map
                      (fun (ctor, cb, next_nm) ->
                         ( pcon (msg ^ "." ^ ctor) [ pvar "v" ],
                           block [ let_wild (app cb [ var "v"; con next_nm [ var "ep1" ] ]); var "ep1" ] ))
                      arms
                    @ unexpected_arm (List.length arms)
                        (fail_with (lit_str (Printf.sprintf "%s, role %s: unexpected message" proto role)))) );
               ( pcon "Err" [ pvar "e" ],
                 fail_with (string_concat (lit_str (Printf.sprintf "%s, role %s: " proto role)) (var "e")) ) ]) ]
  in
  (* ── failure (specs/todos/2026-09-18-choreography-failure-handling.md) ──
     A cancel handler receives the role this receive was waiting on, why it
     is gone, and a [Cancelled_<Role>] token -- and NO session state.  Its
     only way to produce the [Yield] it must return is `cancelled(s, c)`,
     which consumes the token.  So a cancel handler cannot communicate in the
     failed session: it holds nothing any step function accepts.  That is
     Maty's typing of a failure callback, `end -> end`, from the linearity
     the callback API already has. *)
  let cancelled_name = "Cancelled_" ^ role in
  let t_cancelled = tycon cancelled_name [] in
  let cancelled_ty = DType (Public, n cancelled_name, [], TDVariant [ variant cancelled_name [ tycon "Secret" [] ] ], sp) in
  let cancelled_fn =
    fn "cancelled" [ ("s", t_cap_session); ("c", t_cancelled) ] t_yield
      (match_ (var "c") [ (pcon cancelled_name [ PatWild sp ], block [ let_wild (var "s"); yield ]) ])
  in
  let t_on_cancel = TyArrow (t_int, TyArrow (t_string, TyArrow (t_cancelled, t_yield))) in
  (* ── crash branches (design Part B, 2026-09-20) ──
     A receive from a role that `may crash` takes a second callback: what to
     do if that role crashes before sending.  Unlike a cancel handler it gets
     a LIVE state, the crash branch's first, and the conversation goes on
     without the crashed role.  [Crashed_<Role>] carries what the transport
     knows: the role and the cause. *)
  let crashed_name = "Crashed_" ^ role in
  let t_crashed = tycon crashed_name [] in
  let crashed_ty =
    DType
      ( Public, n crashed_name, [],
        TDRecord
          [ { fld_name = n "role"; fld_ty = t_int; fld_lin = Unrestricted };
            { fld_name = n "cause"; fld_ty = t_string; fld_lin = Unrestricted } ],
        sp )
  in
  (* `Session.on_crash(s, ep, role, h)` installs the crash continuation for
     [role] with the continuation that `suspend` installs next, and returns
     [ep] (threaded through, as `on_cancel` is). *)
  let with_crash from ep crash_nm =
    app "Session.on_crash"
      [ var "s"; ep; role_idx from;
        lam [ "c_role"; "c_cause"; "c_ep" ]
          (block
             [ let_wild
                 (app "on_crash"
                    [ ERecord ([ (n "role", var "c_role"); (n "cause", var "c_cause") ], sp);
                      con crash_nm [ var "c_ep" ] ]);
               var "c_ep" ]) ]
  in
  (* `Session.on_cancel(s, ep, h)` installs the cancel handler with the
     continuation that `suspend` installs next, and returns [ep] -- threaded
     through, because [ep] is bound from a linear state and may be used once. *)
  let with_cancel ep =
    app "Session.on_cancel"
      [ var "s"; ep;
        lam [ "c_role"; "c_cause"; "c_ep" ]
          (block
             [ let_wild (app "on_cancel" [ var "c_role"; var "c_cause"; con cancelled_name [ con "Secret" [] ] ]);
               var "c_ep" ]) ]
  in
  let transitions =
    List.concat_map
      (fun (node, this) ->
         let on_ep body = match_ (var "st") [ (pcon this [ pvar "ep" ], body) ] in
         (* `leave_<state>(s, st, why)`: exit the session from this state on
            purpose (Maty's `leave`).  The endpoint is cancelled with cause
            "left: why" and the peers are told. *)
         let leave_fn =
           match node with
           | LEnd | LRec _ | LVar _ -> []
           | _ ->
             let short =
               if String.length this > 2 && String.sub this 0 2 = "S_" then String.sub this 2 (String.length this - 2)
               else this
             in
             [ fn ("leave_" ^ short) [ ("s", t_cap_session); ("st", sty this); ("why", t_string) ] t_yield
                 (on_ep (block [ let_wild (app "Session.leave" [ var "s"; var "ep"; var "why" ]); yield ])) ]
         in
         leave_fn @
         match node with
         | LSend (to_, ctor, payload, next) ->
           let nx = state_of next in
           [ fn ("send_" ^ ctor) [ ("s", t_cap_session); ("st", sty this); ("v", payload) ] (sty nx)
               (on_ep
                  (con nx
                     [ app "Session.emit"
                         [ var "s"; var "ep"; role_idx to_; app (msg ^ ".encode") [ con (msg ^ "." ^ ctor) [ var "v" ] ] ] ])) ]
         | LChoose brs ->
           List.map
             (fun (lbl, to_, ctor, payload, next) ->
                let nx = state_of next in
                fn ("choose_" ^ lbl) [ ("s", t_cap_session); ("st", sty this); ("v", payload) ] (sty nx)
                  (on_ep
                     (con nx
                        [ app "Session.emit"
                            [ var "s"; var "ep"; role_idx to_; app (msg ^ ".encode") [ con (msg ^ "." ^ ctor) [ var "v" ] ] ] ])))
             brs
         | LRecv (from, ctor, payload, next) ->
           let nx = state_of next in
           [ fn ("recv_" ^ ctor)
               [ ("s", t_cap_session); ("st", sty this); ("k", TyArrow (payload, TyArrow (sty nx, t_yield))) ]
               t_yield
               (on_ep (block [ let_wild (suspend_with from (var "ep") [ (ctor, "k", nx) ]); yield ]));
             (* the same receive, with a cancel handler *)
             fn ("recv_" ^ ctor ^ "_or")
               [ ("s", t_cap_session); ("st", sty this); ("k", TyArrow (payload, TyArrow (sty nx, t_yield)));
                 ("on_cancel", t_on_cancel) ]
               t_yield
               (on_ep (block [ let_wild (suspend_with from (with_cancel (var "ep")) [ (ctor, "k", nx) ]); yield ])) ]
         | LOffer (from, brs) ->
           let cbs = List.map (fun (lbl, ctor, payload, next) -> (lbl, ctor, payload, state_of next)) brs in
           let offer_name = "offer_" ^ String.concat "_" (List.map (fun (l, _, _, _) -> l) brs) in
           let branch_params =
             List.map (fun (lbl, _, payload, nx) -> ("on_" ^ lbl, TyArrow (payload, TyArrow (sty nx, t_yield)))) cbs
           in
           let arms = List.map (fun (lbl, ctor, _, nx) -> (ctor, "on_" ^ lbl, nx)) cbs in
           [ fn offer_name ([ ("s", t_cap_session); ("st", sty this) ] @ branch_params) t_yield
               (on_ep (block [ let_wild (suspend_with from (var "ep") arms); yield ]));
             (* the same offer, with a cancel handler *)
             fn (offer_name ^ "_or")
               ([ ("s", t_cap_session); ("st", sty this) ] @ branch_params @ [ ("on_cancel", t_on_cancel) ])
               t_yield
               (on_ep (block [ let_wild (suspend_with from (with_cancel (var "ep")) arms); yield ])) ]
         | LRecvCrash (from, brs, crash) ->
           let cbs = List.map (fun (lbl, ctor, payload, next) -> (lbl, ctor, payload, state_of next)) brs in
           let crash_nx = state_of crash in
           let t_on_crash = TyArrow (t_crashed, TyArrow (sty crash_nx, t_yield)) in
           let arms = List.map (fun (lbl, ctor, _, nx) -> (ctor, "on_" ^ lbl, nx)) cbs in
           (match cbs with
            | [ (_, ctor, payload, nx) ] ->
              (* `recv_<Ctor>(s, st, k, on_crash)`: the receive, with what to
                 do if the sender crashes instead.  No `_or` form: the sender
                 may crash, and that is what the second callback is for. *)
              [ fn ("recv_" ^ ctor)
                  [ ("s", t_cap_session); ("st", sty this); ("k", TyArrow (payload, TyArrow (sty nx, t_yield)));
                    ("on_crash", t_on_crash) ]
                  t_yield
                  (on_ep (block [ let_wild (suspend_with from (with_crash from (var "ep") crash_nx) [ (ctor, "k", nx) ]); yield ])) ]
            | _ ->
              let offer_name = "offer_" ^ String.concat "_" (List.map (fun (l, _, _, _) -> l) brs) ^ "_crash" in
              let branch_params =
                List.map (fun (lbl, _, payload, nx) -> ("on_" ^ lbl, TyArrow (payload, TyArrow (sty nx, t_yield)))) cbs
              in
              [ fn offer_name ([ ("s", t_cap_session); ("st", sty this) ] @ branch_params @ [ ("on_crash", t_on_crash) ]) t_yield
                  (on_ep (block [ let_wild (suspend_with from (with_crash from (var "ep") crash_nx) arms); yield ])) ])
         | LEnd ->
           [ fn "close" [ ("s", t_cap_session); ("st", sty this) ] t_yield
               (on_ep (block [ let_wild (app "Session.close" [ var "s"; var "ep" ]); yield ])) ]
         | LRec _ | LVar _ -> [])
      names
  in
  (* Transitions are named after the message (`send_Item`, `recv_Item`), and
     a message name may be shared by two steps when their payloads agree (one
     constructor in `<P>_Msg`); but a role that takes BOTH steps would get two
     functions of one name, the second silently shadowing the first.  Report
     it, the way the event API below reports one name received in two states. *)
  let () =
    let seen = Hashtbl.create 16 in
    List.iter
      (function
        | DFn (fd, _) ->
          let f = fd.fn_name.txt in
          if Hashtbl.mem seen f then
            Err.error errors ~span
              (Printf.sprintf
                 "Protocol `%s`, role %s: two steps %s takes are named alike, so the role module \
                  would define `%s` twice. A message name can be shared only by steps no single \
                  role takes both of. Rename one of them."
                 proto role role f)
          else Hashtbl.replace seen f ()
        | _ -> ())
      transitions
  in
  (* ── the event API: the same states, driven from an actor's own handler ──
     `await_*` parks an endpoint (a linear [Parked] the actor keeps in its
     state), `resume` turns a delivery into an [Event] carrying the payload and
     the next state, matched with `state` in scope.  Design record:
     specs/todos/2026-09-13-endpoints-event-api-actor-state.md. *)
  (* Types and constructors live in one flat namespace today (the FQN-identity
     plan is open), so every name here carries the role: two roles' `Parked`
     would be ONE nominal type with both roles' constructors, and the user's
     `match` on a `resume` result would be told the other role's messages are
     missing.  Message-shaped constructors are prefixed `Got_` for the same
     reason: `More` is already `<P>_Msg`'s constructor. *)
  let parked_name = "Parked_" ^ role and received_name = "Received_" ^ role in
  let idle_c = "Idle_" ^ role and closed_c = "Closed_" ^ role in
  let t_parked = tycon parked_name [] in
  let secret_v = con "Secret" [] in
  let receiving =
    List.filter_map
      (fun (node, this) ->
         match node with
         | LRecv (_, ctor, payload, next) -> Some (this, [ (ctor, payload, state_of next) ])
         | LOffer (_, brs) -> Some (this, List.map (fun (_, ctor, payload, next) -> (ctor, payload, state_of next)) brs)
         (* The messages only: a crash reaching a hosted endpoint is phase B2
            (specs/progress/2026-09-20-crash-branches-b1.md). *)
         | LRecvCrash (_, brs, _) -> Some (this, List.map (fun (_, ctor, payload, next) -> (ctor, payload, state_of next)) brs)
         | _ -> None)
      names
  in
  let event_ctors =
    List.fold_left
      (fun acc (_, arms) ->
         List.fold_left
           (fun acc (ctor, payload, nx) ->
              match List.assoc_opt ctor acc with
              | None -> acc @ [ (ctor, (payload, nx)) ]
              | Some (_, nx') ->
                if nx <> nx' then
                  Err.error errors ~span
                    (Printf.sprintf
                       "Protocol `%s`, role %s: message `%s` is received in two states with \
                        different continuations, so the event API cannot give it one \
                        constructor. Rename one of them."
                       proto role ctor);
                acc)
           acc arms)
      [] receiving
  in
  let parked_ty =
    DAlwaysLinearType
      ( Public, n parked_name, [],
        TDVariant
          ((variant idle_c [ tycon "Secret" [] ]
            :: List.map (fun (this, _) -> variant ("Awaiting_" ^ this) [ t_int; tycon "Secret" [] ]) receiving)
           @ [ variant closed_c [ tycon "Secret" [] ] ]),
        sp )
  in
  let event_ty =
    if event_ctors = [] then []
    else
      [ DType (Public, n received_name, [],
               TDVariant (List.map (fun (ctor, (payload, nx)) -> variant ("Got_" ^ ctor) [ payload; sty nx ]) event_ctors), sp) ]
  in
  let where = Printf.sprintf "%s, role %s" proto role in
  let idle = fn "idle" [] t_parked (con idle_c [ secret_v ]) in
  let take_idle =
    fn "take_idle" [ ("p", t_parked) ] (TyTuple [])
      (match_ (var "p")
         [ (pcon idle_c [ PatWild sp ], ETuple ([], sp));
           (PatWild sp, panic (where ^ ": take_idle on an endpoint that was already started")) ])
  in
  let await_fn ~from name this =
    (* Suspend so the transport knows the endpoint awaits; the handler must
       never run -- the actor resumes the endpoint itself.  `ep` is bound from
       a linear scrutinee and inherits its linearity, so it is used ONCE:
       `suspend` returns the endpoint, and that result is what gets parked. *)
    fn name [ ("s", t_cap_session); ("st", sty this) ] t_parked
      (match_ (var "st")
         [ ( pcon this [ pvar "ep" ],
             con ("Awaiting_" ^ this)
               [ app "Session.suspend"
                   [ var "s"; var "ep"; role_idx from;
                     lam [ "_from"; "_msg"; "_ep" ]
                       (panic (where ^ ": this endpoint is actor-hosted; deliver through `resume`, not the transport handler")) ];
                 secret_v ] ) ])
  in
  let awaits =
    List.concat_map
      (fun (node, this) ->
         match node with
         | LRecv (from, ctor, _, _) -> [ await_fn ~from ("await_" ^ ctor) this ]
         | LOffer (from, brs) -> [ await_fn ~from ("await_" ^ String.concat "_" (List.map (fun (l, _, _, _) -> l) brs)) this ]
         | LRecvCrash (from, brs, _) ->
           let nm = match brs with [ (_, ctor, _, _) ] -> ctor | _ -> String.concat "_" (List.map (fun (l, _, _, _) -> l) brs) ^ "_crash" in
           [ await_fn ~from ("await_" ^ nm) this ]
         | LEnd ->
           [ fn "finish" [ ("s", t_cap_session); ("st", sty this) ] t_parked
               (match_ (var "st")
                  [ (pcon this [ pvar "ep" ],
                     block [ let_wild (app "Session.close" [ var "s"; var "ep" ]); con closed_c [ secret_v ] ]) ]) ]
         | _ -> [])
      names
  in
  let resume =
    if event_ctors = [] then []
    else
      [ fn "resume" [ ("p", t_parked); ("from", t_int); ("msg", t_bytes); ("ep", t_int) ] (tycon received_name [])
          (block
             [ let_wild (var "from");
               match_ (var "p")
                 ((List.map
                     (fun (this, arms) ->
                        ( pcon ("Awaiting_" ^ this) [ pvar "ep0"; PatWild sp ],
                          EIf
                            ( app "==" [ var "ep"; var "ep0" ],
                              match_ (app (msg ^ ".decode") [ var "msg" ])
                                (List.map
                                   (fun (ctor, _, nx) ->
                                      (pcon (msg ^ "." ^ ctor) [ pvar "v" ], con ("Got_" ^ ctor) [ var "v"; con nx [ var "ep" ] ]))
                                   arms
                                 @ unexpected_arm (List.length arms)
                                     (panic (Printf.sprintf "%s: unexpected message in state %s" where this))),
                              panic (where ^ ": delivery for another endpoint"),
                              sp ) ))
                     receiving)
                  @ [ (pcon idle_c [ PatWild sp ], panic (where ^ ": delivery before the endpoint was started"));
                      (pcon closed_c [ PatWild sp ], panic (where ^ ": delivery to a closed endpoint")) ]) ]) ]
  in
  (* `cancel(p)`: the hosted endpoint was cancelled (its runner said so,
     through `host_<Role>_or`'s cancel function).  Consumes the parked value
     and returns [Closed]: the actor must store it, as for any other step,
     and nothing can resume a closed endpoint. *)
  let cancel_parked =
    (* One arm per constructor, never a top-level `_`: a wildcard over the
       whole value would DISCARD a linear [Parked], which the checker
       rejects; matching the constructor consumes it. *)
    fn "cancel" [ ("p", t_parked) ] t_parked
      (match_ (var "p")
         ((pcon idle_c [ PatWild sp ], con closed_c [ secret_v ])
          :: List.map (fun (this, _) -> (pcon ("Awaiting_" ^ this) [ PatWild sp; PatWild sp ], con closed_c [ secret_v ])) receiving
          @ [ (pcon closed_c [ PatWild sp ], con closed_c [ secret_v ]) ]))
  in
  let event_api = (parked_ty :: event_ty) @ (idle :: take_idle :: cancel_parked :: awaits) @ resume in
  let entry = state_of root in
  let register =
    fn "register" [ ("s", t_cap_session); ("ap", t_int) ] (sty entry)
      (con entry [ app "Session.register" [ var "s"; var "ap"; role_idx role ] ])
  in
  ignore roles;
  (* Every transition takes `Cap(Session.Live)`, so the module acknowledges
     the dependency itself rather than leaning on the enclosing module's
     manifest -- the capability checker asks each module for its own. *)
  let needs = DNeeds ([ ([ n "Session"; n "Live" ], None) ], sp) in
  (DMod (n mname, Public,
         (needs :: secret :: yield_ty :: cancelled_ty :: crashed_ty :: state_types) @ (register :: cancelled_fn :: transitions) @ event_api, sp),
   entry)

(** `<P>_Run`: the role runner's typed front.  Per role,

      run_<Role>(io, node_id, secret, addrs, body) : Result((), SessionNode.RunError)
      host_<Role>(io, node_id, secret, addrs, host, start, deliver) : the same, hosted in actor [host]

    where [body] takes the session capability and the role's ENTRY state (so
    a body written for another role, or for another point of this one, is a
    type error) and `addrs_from_env()` reads `<P>_<ROLE>_ADDR` per role.  The
    wiring itself -- who listens, who dials, in what order, the `require`
    check -- is `SessionNode.run`, a stdlib function: it names no protocol
    constructor, so nothing about it needs generating, only these types.
    Design: specs/progress/2026-09-16-role-runner.md. *)
let run_module ~proto ~(roles : (string * string) list) : decl =
  let mname = proto ^ "_Run" in
  let msg = proto ^ "_Msg" in
  let t_unit = TyTuple [] in
  let unit = ETuple ([], sp) in
  let t_addrs = tycon "List" [ tycon "SessionNode.Addr" [] ] in
  let runners =
    List.map
      (fun (role, entry) ->
         let rm = proto ^ "_" ^ role in
         let t_body = TyArrow (t_cap_session, TyArrow (tycon (rm ^ "." ^ entry) [], tycon (rm ^ ".Yield") [])) in
         fn ("run_" ^ role)
           [ ("io", tycon "Cap" [ tycon "IO" [] ]); ("node_id", t_string); ("secret", t_string);
             ("addrs", t_addrs); ("body", t_body) ]
           (tycon "Result" [ t_unit; tycon "SessionNode.RunError" [] ])
           (app "SessionNode.run"
              [ var "io"; app (msg ^ ".role_" ^ role) []; app (msg ^ ".peers_" ^ role) []; var "node_id";
                var "secret"; var "addrs"; lam [ "_ep" ] unit;
                lam [ "s" ]
                  (block [ let_wild (app "body" [ var "s"; app (rm ^ ".register") [ var "s"; lit_int 0 ] ]); unit ]) ]))
      roles
  in
  (* `cluster_<Role>(io, node, session, body)`: the same role over a running
     cluster node (`ClusterNode.start`) instead of connections of its own --
     `SessionNode.run_cluster`: peers found by name under the session id,
     frames over the node's shared connections, SWIM as the failure
     detector. Design: specs/progress/2026-09-18-cluster-node-service.md. *)
  let clusters =
    List.map
      (fun (role, entry) ->
         let rm = proto ^ "_" ^ role in
         let t_body = TyArrow (t_cap_session, TyArrow (tycon (rm ^ "." ^ entry) [], tycon (rm ^ ".Yield") [])) in
         fn ("cluster_" ^ role)
           [ ("io", tycon "Cap" [ tycon "IO" [] ]); ("node", tycon "ClusterNode.ClusterHandle" []);
             ("session", t_string); ("body", t_body) ]
           (tycon "Result" [ t_unit; tycon "SessionNode.RunError" [] ])
           (app "SessionNode.run_cluster"
              [ var "io"; var "node"; app (msg ^ ".role_" ^ role) []; app (msg ^ ".peers_" ^ role) [];
                var "session"; lam [ "_ep" ] unit;
                lam [ "s" ]
                  (block [ let_wild (app "body" [ var "s"; app (rm ^ ".register") [ var "s"; lit_int 0 ] ]); unit ]) ]))
      roles
  in
  (* `offer_<Role>(io, node, capacity, body)`: an ACCESS POINT -- this node
     plays [Role] in up to [capacity] sessions at once, each formed when an
     initiator invites it, each run by [body] in its own task.  And
     `initiate_<Role>(io, node, body)`: start one session in [Role], filling
     every other role from the access points that offer it.  Both are
     `SessionNode.offer_role` / `initiate`; the front supplies the protocol's name
     and fingerprint, the role, its peers and the other roles.  Design:
     specs/2026-09-19-choreography-access-points-and-crash-branches-design.md. *)
  let offers =
    List.map
      (fun (role, entry) ->
         let rm = proto ^ "_" ^ role in
         let t_body = TyArrow (t_cap_session, TyArrow (tycon (rm ^ "." ^ entry) [], tycon (rm ^ ".Yield") [])) in
         fn ("offer_" ^ role)
           [ ("io", tycon "Cap" [ tycon "IO" [] ]); ("node", tycon "ClusterNode.ClusterHandle" []);
             ("capacity", t_int); ("body", t_body) ]
           (tycon "Result" [ tycon "SessionNode.Offer" []; tycon "SessionNode.RunError" [] ])
           (app "SessionNode.offer_role"
              [ var "io"; var "node"; lit_str proto; app (msg ^ ".fingerprint") []; app (msg ^ ".role_" ^ role) [];
                app (msg ^ ".peers_" ^ role) []; var "capacity"; lam [ "_ep" ] unit;
                lam [ "s" ]
                  (block [ let_wild (app "body" [ var "s"; app (rm ^ ".register") [ var "s"; lit_int 0 ] ]); unit ]) ]))
      roles
  in
  let initiators =
    List.map
      (fun (role, entry) ->
         let rm = proto ^ "_" ^ role in
         let t_body = TyArrow (t_cap_session, TyArrow (tycon (rm ^ "." ^ entry) [], tycon (rm ^ ".Yield") [])) in
         fn ("initiate_" ^ role)
           [ ("io", tycon "Cap" [ tycon "IO" [] ]); ("node", tycon "ClusterNode.ClusterHandle" []); ("body", t_body) ]
           (tycon "Result" [ t_unit; tycon "SessionNode.RunError" [] ])
           (app "SessionNode.initiate"
              [ var "io"; var "node"; lit_str proto; app (msg ^ ".fingerprint") []; app (msg ^ ".role_" ^ role) [];
                app (msg ^ ".peers_" ^ role) []; app (msg ^ ".others_" ^ role) []; lam [ "_ep" ] unit;
                lam [ "s" ]
                  (block [ let_wild (app "body" [ var "s"; app (rm ^ ".register") [ var "s"; lit_int 0 ] ]); unit ]) ]))
      roles
  in
  (* `host_<Role>(io, node_id, secret, addrs, host, start, deliver)`: the
     same party, the role hosted in the actor [host] through the event API.
     Nothing here is typed by the protocol beyond the role and its peers --
     the actor registers and parks itself (`take_idle`, `register`,
     `await_*`) and its resume handler takes `(s, from, msg, ep)` as
     `deliver` hands them on -- so the front adds only the role and peer set.
     [host] is the actor's pid; `Pid(a)`'s parameter is phantom to the
     linearity checker (typecheck.ml, [consumed_var_ids]), which is what lets
     an actor whose state holds the linear `Parked_<Role>` be passed here. *)
  let hosters =
    List.map
      (fun (role, _entry) ->
         let t_start = TyArrow (t_cap_session, t_unit) in
         let t_deliver = TyArrow (t_cap_session, TyArrow (t_int, TyArrow (t_bytes, TyArrow (t_int, t_unit)))) in
         fn ("host_" ^ role)
           [ ("io", tycon "Cap" [ tycon "IO" [] ]); ("node_id", t_string); ("secret", t_string);
             ("addrs", t_addrs); ("host", tycon "Pid" [ TyVar (n "a") ]); ("start", t_start); ("deliver", t_deliver) ]
           (tycon "Result" [ t_unit; tycon "SessionNode.RunError" [] ])
           (app "SessionNode.run_hosted"
              [ var "io"; app (msg ^ ".role_" ^ role) []; app (msg ^ ".peers_" ^ role) []; var "node_id";
                var "secret"; var "addrs"; lam [ "_ep" ] unit; app "pid_to_int" [ var "host" ]; var "start";
                var "deliver" ]))
      roles
  in
  (* `host_<Role>_or(…, start, deliver, cancel)`: the same, and the actor is
     told when its endpoint is cancelled: `cancel(s, role, cause, ep)`. *)
  let hosters_or =
    List.map
      (fun (role, _entry) ->
         let t_start = TyArrow (t_cap_session, t_unit) in
         let t_deliver = TyArrow (t_cap_session, TyArrow (t_int, TyArrow (t_bytes, TyArrow (t_int, t_unit)))) in
         let t_cancel = TyArrow (t_cap_session, TyArrow (t_int, TyArrow (t_string, TyArrow (t_int, t_unit)))) in
         fn ("host_" ^ role ^ "_or")
           [ ("io", tycon "Cap" [ tycon "IO" [] ]); ("node_id", t_string); ("secret", t_string);
             ("addrs", t_addrs); ("host", tycon "Pid" [ TyVar (n "a") ]); ("start", t_start); ("deliver", t_deliver);
             ("cancel", t_cancel) ]
           (tycon "Result" [ t_unit; tycon "SessionNode.RunError" [] ])
           (app "SessionNode.run_hosted_or"
              [ var "io"; app (msg ^ ".role_" ^ role) []; app (msg ^ ".peers_" ^ role) []; var "node_id";
                var "secret"; var "addrs"; lam [ "_ep" ] unit; app "pid_to_int" [ var "host" ]; var "start";
                var "deliver"; var "cancel" ]))
      roles
  in
  (* `offer_hosted_<Role>(io, node, capacity, host, start, deliver, cancel)`
     and `cluster_hosted_<Role>(io, node, session, host, start, deliver,
     cancel)`: the access point and the one-session cluster runner with the
     role hosted in the actor [host], as `host_<Role>_or` hosts it over the
     runner's own connections.  A hosted offer runs many sessions in ONE
     actor (one `Parked_<Role>` per session id, in a `LinearMap`), so every
     callback carries the session id: `start(sid, s)`, `deliver(sid, s, from,
     msg, ep)`, `cancel(sid, s, role, cause, ep)`; `cluster_hosted_<Role>`
     takes the same callbacks so one actor serves both.  Design:
     specs/2026-09-20-hosted-offers-implementation.md. *)
  let t_start_sid = TyArrow (t_string, TyArrow (t_cap_session, t_unit)) in
  let t_deliver_sid =
    TyArrow (t_string, TyArrow (t_cap_session, TyArrow (t_int, TyArrow (t_bytes, TyArrow (t_int, t_unit)))))
  in
  let t_cancel_sid =
    TyArrow (t_string, TyArrow (t_cap_session, TyArrow (t_int, TyArrow (t_string, TyArrow (t_int, t_unit)))))
  in
  let hosted_callbacks =
    [ ("host", tycon "Pid" [ TyVar (n "a") ]); ("start", t_start_sid); ("deliver", t_deliver_sid); ("cancel", t_cancel_sid) ]
  in
  let offers_hosted =
    List.map
      (fun (role, _entry) ->
         fn ("offer_hosted_" ^ role)
           ([ ("io", tycon "Cap" [ tycon "IO" [] ]); ("node", tycon "ClusterNode.ClusterHandle" []); ("capacity", t_int) ]
            @ hosted_callbacks)
           (tycon "Result" [ tycon "SessionNode.Offer" []; tycon "SessionNode.RunError" [] ])
           (app "SessionNode.offer_hosted"
              [ var "io"; var "node"; lit_str proto; app (msg ^ ".fingerprint") []; app (msg ^ ".role_" ^ role) [];
                app (msg ^ ".peers_" ^ role) []; var "capacity"; lam [ "_ep" ] unit; app "pid_to_int" [ var "host" ];
                var "start"; var "deliver"; var "cancel" ]))
      roles
  in
  let clusters_hosted =
    List.map
      (fun (role, _entry) ->
         fn ("cluster_hosted_" ^ role)
           ([ ("io", tycon "Cap" [ tycon "IO" [] ]); ("node", tycon "ClusterNode.ClusterHandle" []); ("session", t_string) ]
            @ hosted_callbacks)
           (tycon "Result" [ t_unit; tycon "SessionNode.RunError" [] ])
           (app "SessionNode.run_cluster_hosted"
              [ var "io"; var "node"; app (msg ^ ".role_" ^ role) []; app (msg ^ ".peers_" ^ role) []; var "session";
                lam [ "_ep" ] unit; app "pid_to_int" [ var "host" ];
                lam [ "s" ] (app "start" [ var "session"; var "s" ]);
                lam [ "s"; "from"; "m"; "ep" ] (app "deliver" [ var "session"; var "s"; var "from"; var "m"; var "ep" ]);
                lam [ "s"; "role"; "cause"; "ep" ] (app "cancel" [ var "session"; var "s"; var "role"; var "cause"; var "ep" ]) ]))
      roles
  in
  let addrs =
    fn "addrs_from_env" [] t_addrs (app "SessionNode.addrs_from_env" [ lit_str proto; app (msg ^ ".role_names") [] ])
  in
  (* `error_message(e)`: `SessionNode.run_error_message` with this protocol's
     role NAMES in place of the numbers. *)
  let error_message =
    fn "error_message" [ ("e", tycon "SessionNode.RunError" []) ] t_string
      (app "SessionNode.run_error_message_named" [ var "e"; lam [ "i" ] (app (msg ^ ".role_name") [ var "i" ]) ])
  in
  (* What `SessionNode.run` needs; declared here so the capability checker,
     which asks each module for its own, sees them on the generated module. *)
  let needs =
    DNeeds
      ( List.map (fun path -> (List.map n path, None))
          [ [ "IO" ]; [ "IO"; "Mut" ]; [ "IO"; "NetConnect" ]; [ "IO"; "NetListen" ]; [ "IO"; "Spawn" ];
            [ "Session"; "Live" ] ],
        sp )
  in
  DMod (n mname, Public,
        (needs :: addrs :: error_message :: runners) @ clusters @ offers @ initiators @ hosters @ hosters_or
        @ offers_hosted @ clusters_hosted, sp)

(** Whether [expand] emits `<P>_Run`.  On for every real compile.  A test that
    typechecks generated code against a thin stdlib without `SessionNode`
    turns it off (test/test_endpoints.ml); the module's shape is asserted
    there with it on, and the native and two-node fixtures typecheck it for
    real. *)
let emit_runner = ref true

(** Every payload type declared in THIS module must derive `Json`: the
    generated `<P>_Msg` codec assumes every nested type has one, and without
    it `--check` said nothing, the compile failed with an "ambiguous
    interface-method call" from codegen, and the interpreter panicked at the
    first `encode`. Types from other modules are not checked here (their
    derives are not in [decls]); builtins need no derive. Reports one error
    per offending step; the result is informational (generation goes on). *)
let check_payload_codecs (errors : Err.ctx) ~proto ~span (decls : decl list) (steps : astep list) : bool =
  let declared =
    List.filter_map (function
      | DType (_, nm, _, _, _) | DAlwaysLinearType (_, nm, _, _, _) -> Some nm.txt
      | _ -> None) decls
  in
  let derives_json =
    List.filter_map (function
      | DDeriving (nm, ifaces, _) when List.exists (fun i -> i.txt = "Json") ifaces -> Some nm.txt
      | _ -> None) decls
  in
  let rec missing (t : ty) : string list =
    match t with
    | TyCon (c, args) ->
      let here = if List.mem c.txt declared && not (List.mem c.txt derives_json) then [ c.txt ] else [] in
      here @ List.concat_map missing args
    | TyTuple ts -> List.concat_map missing ts
    | TyLinear (_, t) -> missing t
    | _ -> []
  in
  let ok = ref true in
  let rec go = function
    | [] -> ()
    | AMsg (f, t, ty, _) :: rest ->
      (match missing ty with
       | [] -> ()
       | names ->
         ok := false;
         List.iter (fun nm ->
           Err.error errors ~span
             (Printf.sprintf
                "Protocol `%s`: the message `%s -> %s : %s` carries `%s`, which has no JSON codec. \
                 Every payload crosses the network as JSON: add `derive Json for %s`."
                proto f t (ty_key ty) nm nm)) names);
      go rest
    | ALoop inner :: rest -> go inner; go rest
    | AChoice (_, brs) :: rest -> List.iter (fun (_, arm) -> go arm) brs; go rest
    | AStop :: rest -> go rest
    | ACrashOr (m, crash) :: rest -> go [ m ]; go crash; go rest
  in
  go steps;
  !ok

(** Every generated declaration for the `@[endpoints]` protocols in [decls],
    or [] -- the common case -- when there are none.  Generated functions are
    respanned like derived ones (see [Desugar_derive]'s span note). *)
let expand (errors : Err.ctx) (decls : decl list) : decl list =
  List.concat_map
    (function
      | DProtocol (name, pdef, span) when List.mem attr pdef.proto_attrs ->
        let proto = name.txt in
        (match annotate errors ~proto ~span pdef.proto_steps with
         | None -> []
         | Some steps ->
           (* Reported, not fatal: the modules are still generated, so the
              user's code sees one error about the payload rather than a
              cascade of "Unknown module `P_Msg`". *)
           ignore (check_payload_codecs errors ~proto ~span decls steps);
           (match collect_ctors errors ~proto ~span steps with
            | None -> []
            | Some ctors ->
              let roles = roles_of steps in
              let multiparty = List.length roles > 2 in
              let respan_mod = function
                | DMod (nm, vis, ds, s) -> DMod (nm, vis, List.map D.respan_derived_decl ds, s)
                | d -> d
              in
              let peers = List.map (fun r -> (r, peers_of steps roles r)) roles in
              let fingerprint = fingerprint_of ~proto roles steps in
              let msg = msg_module errors ~proto ~span ~fingerprint ctors roles peers in
              let role_mods =
                List.map
                  (fun role ->
                     role_module errors ~proto ~span ~roles ~nctors:(List.length ctors) role
                       (project ~proto ~multiparty steps role LEnd))
                  roles
              in
              let run =
                if !emit_runner then [ run_module ~proto ~roles:(List.map2 (fun r (_, e) -> (r, e)) roles role_mods) ]
                else []
              in
              List.map respan_mod ((msg :: List.map fst role_mods) @ run)))
      | _ -> [])
    decls
