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
      [always_linear] type PER SESSION STATE and one function per transition.

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
  | LRec (x, s), LRec (y, t) -> x = y && lty_equal s t
  | LVar x, LVar y -> x = y
  | LEnd, LEnd -> true
  | _ -> false

(* ── annotated steps: every message gets its constructor name ─────────── *)

type astep =
  | AMsg    of string * string * ty * string        (** sender, receiver, payload, ctor *)
  | ALoop   of astep list
  | AChoice of string * (string * astep list) list  (** chooser, (label, steps) *)
  | AStop

let capitalize s =
  if s = "" then s else String.capitalize_ascii s

(** Name every message.  A `choose` branch's head message is named after its
    label (`more` -> `More`); any other message after its endpoints, numbered
    among the messages between the same pair so an unrelated edit elsewhere
    does not rename it (`Msg_Prod_Cons_1`).  Returns [None], having reported,
    when a branch does not begin with a message from the chooser -- the rule
    the offer/receive fusion needs and the language does not check. *)
let annotate (errors : Err.ctx) ~(proto : string) ~(span : span)
    (steps : protocol_step list) : astep list option =
  let counts : (string * string, int) Hashtbl.t = Hashtbl.create 8 in
  let ok = ref true in
  let synth s r =
    let k = 1 + Option.value ~default:0 (Hashtbl.find_opt counts (s, r)) in
    Hashtbl.replace counts (s, r) k;
    Printf.sprintf "Msg_%s_%s_%d" s r k
  in
  let rec go (steps : protocol_step list) : astep list =
    List.map
      (function
        | ProtoMsg (s, r, t) -> AMsg (s.txt, r.txt, t, synth s.txt r.txt)
        | ProtoLoop inner -> ALoop (go inner)
        | ProtoStop _ -> AStop
        | ProtoChoice (chooser, branches) ->
          AChoice
            (chooser.txt,
             List.map
               (fun (lbl, arm) ->
                  match arm with
                  | ProtoMsg (s, r, t) :: rest when s.txt = chooser.txt ->
                    (lbl.txt, AMsg (s.txt, r.txt, t, capitalize lbl.txt) :: go rest)
                  | _ ->
                    ok := false;
                    Err.error errors ~span:lbl.span
                      (Printf.sprintf
                         "Protocol `%s`: `@[endpoints]` needs every branch of `choose by %s` \
                          to begin with a message from `%s`, because the label travels \
                          on that message. Branch `%s` does not."
                         proto chooser.txt chooser.txt lbl.txt);
                    (lbl.txt, go arm))
               branches))
      steps
  in
  let annotated = go steps in
  ignore span;
  if !ok then Some annotated else None

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
  in
  go steps;
  List.rev !seen

(** Project onto [role].  Same rules as [project_steps]: a loop is a binder
    whose back-edge is the loop's own variable, `stop` is [LEnd] outright, and
    a non-chooser merges a choice only in a multiparty protocol and only when
    every branch projects identically. *)
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
     | ALoop inner ->
       let x = proto ^ "_loop" in
       (match project ~proto ~multiparty inner role (LVar x) with
        | LVar _ -> rest_ty ()
        | body -> LRec (x, body))
     | AStop -> LEnd
     | AChoice (chooser, branches) ->
       let after = rest_ty () in
       let arms =
         List.map (fun (lbl, arm) -> (lbl, project ~proto ~multiparty arm role after)) branches
       in
       if chooser = role then
         (* The branch head is this role's own send (checked in [annotate]), so
            its receiver is the branch's destination -- per branch, since a
            multiparty choice may tell a different role on each label. *)
         LChoose
           (List.map
              (fun (lbl, arm) ->
                 match arm with
                 | LSend (to_, ctor, t, next) -> (lbl, to_, ctor, t, next)
                 | _ -> (lbl, chooser, capitalize lbl, TyTuple [], arm))
              arms)
       else
         (match arms with
          | (_, first) :: more when multiparty && List.for_all (fun (_, a) -> lty_equal a first) more ->
            first
          | _ ->
            (* Every branch head is a message from the chooser (checked in
               [annotate]); this role offers only if it RECEIVES those heads. *)
            let heads =
              List.map
                (fun (lbl, arm) ->
                   match arm with
                   | LRecv (from, ctor, t, next) when from = chooser -> Some (lbl, ctor, t, next)
                   | _ -> None)
                arms
            in
            if List.for_all Option.is_some heads then
              LOffer (chooser, List.map Option.get heads)
            else
              (* A bystander whose branches differ but who never learns the
                 label: not projectable.  Mirror the typechecker's answer
                 (an offer it cannot run) so the fault is reported there. *)
              LOffer (chooser, List.map (fun (lbl, arm) -> (lbl, capitalize lbl, TyTuple [], arm)) arms)))

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
let param name ty = FPNamed { param_name = n name; param_ty = Some ty; param_lin = Unrestricted }

(** A public single-clause function with typed parameters and a return type. *)
let fn name params ret body : decl =
  DFn
    ( { fn_name = n name; fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = Some ret;
        fn_bounds = [];
        fn_clauses =
          [ { fc_params = List.map (fun (p, t) -> param p t) params; fc_guard = None; fc_body = body;
              fc_span = sp; fc_params_span = sp } ] },
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
  in
  go steps;
  if !ok then Some (List.rev !acc) else None

(** `<P>_Msg`: the message type, its `Json` codec over `Bytes`, and the role
    indices.  The derive is expanded HERE, inside the generated module, so it
    rebinds nobody's bare `to_json`/`from_json` in the user's module. *)
let msg_module (errors : Err.ctx) ~proto ~span (ctors : (string * ty) list) (roles : string list) : decl =
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
  (* 1-based, in order of first appearance; see [roles_of]. *)
  let role_fns = List.mapi (fun i r -> fn ("role_" ^ r) [] t_int (lit_int (i + 1))) roles in
  DMod (n mname, Public, (msg_decl :: json_fns) @ [ encode; decode ] @ role_fns, sp)

(** `<P>_<Role>`: one [always_linear] type per state and one function per
    transition, plus the unforgeable [Yield]. *)
let role_module ~proto ~(roles : string list) (role : string) (root : lty) : decl =
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
  let suspend_with ep arms =
    app "Session.suspend"
      [ var "s"; ep;
        lam [ "_from"; "msg"; "ep1" ]
          (match_ (app (msg ^ ".decode") [ var "msg" ])
             (List.map
                (fun (ctor, cb, next_nm) ->
                   ( pcon (msg ^ "." ^ ctor) [ pvar "v" ],
                     block [ let_wild (app cb [ var "v"; con next_nm [ var "ep1" ] ]); var "ep1" ] ))
                arms
              @ [ (PatWild sp, panic (Printf.sprintf "%s, role %s: unexpected message" proto role)) ])) ]
  in
  let transitions =
    List.concat_map
      (fun (node, this) ->
         let on_ep body = match_ (var "st") [ (pcon this [ pvar "ep" ], body) ] in
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
         | LRecv (_, ctor, payload, next) ->
           let nx = state_of next in
           [ fn ("recv_" ^ ctor)
               [ ("s", t_cap_session); ("st", sty this); ("k", TyArrow (payload, TyArrow (sty nx, t_yield))) ]
               t_yield
               (on_ep (block [ let_wild (suspend_with (var "ep") [ (ctor, "k", nx) ]); yield ])) ]
         | LOffer (_, brs) ->
           let cbs = List.map (fun (lbl, ctor, payload, next) -> (lbl, ctor, payload, state_of next)) brs in
           [ fn ("offer_" ^ String.concat "_" (List.map (fun (l, _, _, _) -> l) brs))
               ([ ("s", t_cap_session); ("st", sty this) ]
                @ List.map (fun (lbl, _, payload, nx) -> ("on_" ^ lbl, TyArrow (payload, TyArrow (sty nx, t_yield)))) cbs)
               t_yield
               (on_ep
                  (block
                     [ let_wild (suspend_with (var "ep") (List.map (fun (lbl, ctor, _, nx) -> (ctor, "on_" ^ lbl, nx)) cbs));
                       yield ])) ]
         | LEnd ->
           [ fn "close" [ ("s", t_cap_session); ("st", sty this) ] t_yield
               (on_ep (block [ let_wild (app "Session.close" [ var "s"; var "ep" ]); yield ])) ]
         | LRec _ | LVar _ -> [])
      names
  in
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
  DMod (n mname, Public, (needs :: secret :: yield_ty :: state_types) @ (register :: transitions), sp)

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
           (match collect_ctors errors ~proto ~span steps with
            | None -> []
            | Some ctors ->
              let roles = roles_of steps in
              let multiparty = List.length roles > 2 in
              let respan_mod = function
                | DMod (nm, vis, ds, s) -> DMod (nm, vis, List.map D.respan_derived_decl ds, s)
                | d -> d
              in
              let msg = msg_module errors ~proto ~span ctors roles in
              let role_mods =
                List.map
                  (fun role -> role_module ~proto ~roles role (project ~proto ~multiparty steps role LEnd))
                  roles
              in
              List.map respan_mod (msg :: role_mods)))
      | _ -> [])
    decls
