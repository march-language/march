(** `@[remote]`: generate the receiver-side dispatch for an actor's typed
    remote messages.

    Design record: specs/progress/2026-09-15-remote-actor-dispatch.md
    (`Node.dispatch`).  A sender writes `Node.send(peer, to, msg)` and the
    compiler mints the wire type tag from `msg`'s declared type
    (Typecheck_caps.check_node_send_sites).  The receiver used to route by
    hand: compare `d.type_tag` with a string, decode with a `from_json` pinned
    by an annotation, and `send(pid, Ctor(x))`.  A library cannot do that for
    an actor -- it cannot name the actor's constructors -- but this generator
    can.  For

      @[remote]
      actor Counter do
        state { n : Int }
        init  { n: 0 }
        on Hit(h : Hit) do … end
      end

    it generates, right AFTER the actor (a nested module sees an actor's
    message constructors only once the actor is declared):

      mod Counter_Remote do
        fn dispatch(pid, d : Delivery) : Result(Bool, String) do
          match Node.payload(d) do
            Err(e) -> Err(e)
            Ok(v) ->
              if Node.accepts(d, fn (_w : Hit) -> ()) do
                let r : Result(Hit, Json.DecodeError) = from_json(v)
                match r do
                  Ok(x) -> do let _ = send(pid, Hit(x)) Ok(true) end
                  Err(_) -> Err("Counter: payload does not decode as Hit's message")
                end
              else … Ok(false) end
          end
        end
      end

    `Ok(true)`: delivered to [pid]'s mailbox.  `Ok(false)`: no handler of this
    actor takes the delivery's type.  `Err`: the payload is not JSON, or does
    not decode as the type its tag names.

    The tag comparison is `Node.accepts(d, witness)`, not a string literal: the
    tag is the type's MODULE-QUALIFIED name as the typechecker resolves it,
    which the surface spelling of an annotation does not determine.  The
    typechecker records the site like a `Node.send` and both backends rewrite
    it to `Node.tag_is(d, "<tag>")` (March_ast.Json_dispatch), so the sender's
    tag and the receiver's comparison come from one resolution.

    A handler is routable when it takes exactly one parameter, annotated with a
    user-declared named type without type arguments (not `Int`, `String`, ...).
    Other handlers are ignored (they are still local messages); an `@[remote]`
    actor with no routable handler is an error, since its
    dispatch would accept nothing.  The generated module is respanned like a
    derived declaration: `from_json` and `Node.accepts` are resolved per call
    SPAN, so the dummy spans must not collide. *)

open March_ast.Ast
module Err = March_errors.Errors
module D = Desugar_derive

let sp = dummy_span
let n = D.mk_name
let var s = EVar (n s)
let app f args = EApp (var f, args, sp)
let con c args = ECon (n c, args, sp)
let lit_str s = ELit (LitString s, sp)
let tycon s args = TyCon (n s, args)

let let_ ?ty name e =
  ELet ({ bind_pat = PatVar (n name); bind_ty = ty; bind_lin = Unrestricted; bind_expr = e }, sp)

let let_wild e = ELet ({ bind_pat = PatWild sp; bind_ty = None; bind_lin = Unrestricted; bind_expr = e }, sp)

let match_ scrut branches =
  EMatch (scrut, List.map (fun (p, body) -> { branch_pat = p; branch_guard = None; branch_body = body }) branches, sp)

let pcon c ps = PatCon (n c, ps)

(** Builtin types a remote message cannot be: a handler taking one of these
    is a local message, not a routing target. *)
let builtin_types = [ "Int"; "Float"; "String"; "Bool"; "Unit"; "Bytes"; "Atom"; "Pid"; "Cap" ]

(** The routable handlers: (constructor, the payload's surface type).  One
    parameter, annotated with a user-declared named type without arguments --
    the shape `derive Json` gives a codec and `Node.send` mints a tag for. *)
let routable (adef : actor_def) : (string * ty) list =
  List.filter_map
    (fun h ->
       match h.ah_params with
       | [ { param_ty = Some (TyCon (tn, []) as t); _ } ] when not (List.mem tn.txt builtin_types) ->
         Some (h.ah_msg.txt, t)
       | _ -> None)
    adef.actor_handlers

let dispatch_fn ~actor (routes : (string * ty) list) : decl =
  let decode_arm (ctor, ty) rest =
    let witness =
      ELam ([ { param_name = n "_w"; param_ty = Some ty; param_lin = Unrestricted } ], ETuple ([], sp), sp)
    in
    EIf
      ( app "Node.accepts" [ var "d"; witness ],
        EBlock
          ( [ let_ ~ty:(tycon "Result" [ ty; tycon "Json.DecodeError" [] ]) "r" (app "from_json" [ var "v" ]);
              match_ (var "r")
                [ ( pcon "Ok" [ PatVar (n "x") ],
                    EBlock ([ let_wild (ESend (var "pid", con ctor [ var "x" ], sp)); con "Ok" [ ELit (LitBool true, sp) ] ], sp) );
                  ( pcon "Err" [ PatWild sp ],
                    con "Err" [ lit_str (Printf.sprintf "%s: the payload does not decode as %s's message" actor ctor) ] ) ] ],
            sp ),
        rest,
        sp )
  in
  let chain = List.fold_right decode_arm routes (con "Ok" [ ELit (LitBool false, sp) ]) in
  let body =
    match_ (app "Node.payload" [ var "d" ])
      [ (pcon "Err" [ PatVar (n "e") ], con "Err" [ var "e" ]); (pcon "Ok" [ PatVar (n "v") ], chain) ]
  in
  DFn
    ( { fn_name = n "dispatch"; fn_vis = Public; fn_doc = None; fn_attrs = [];
        fn_ret_ty = Some (tycon "Result" [ tycon "Bool" []; tycon "String" [] ]);
        fn_bounds = [];
        fn_clauses =
          [ { fc_params =
                [ FPNamed { param_name = n "pid"; param_ty = None; param_lin = Unrestricted };
                  FPNamed { param_name = n "d"; param_ty = Some (tycon "Delivery" []); param_lin = Unrestricted } ];
              fc_guard = None; fc_body = body; fc_span = sp; fc_params_span = sp } ] },
      sp )

(** [decls] with an `<Actor>_Remote` module inserted after every `@[remote]`
    actor, recursing into nested modules. *)
let rec expand (errors : Err.ctx) (decls : decl list) : decl list =
  List.concat_map
    (function
      | DActor (_, name, adef, span) as d when adef.actor_remote ->
        (match routable adef with
         | [] ->
           Err.error errors ~span
             (Printf.sprintf
                "`@[remote]` actor `%s` has no handler a remote message can reach. A routable handler takes exactly one parameter annotated with a declared type that derives Json, e.g. `on Bump(h : Hit)`."
                name.txt);
           [ d ]
         | routes ->
           let m = DMod (n (name.txt ^ "_Remote"), Public, [ D.respan_derived_decl (dispatch_fn ~actor:name.txt routes) ], sp) in
           [ d; m ])
      | DMod (nm, vis, inner, s) -> [ DMod (nm, vis, expand errors inner, s) ]
      | d -> [ d ])
    decls
