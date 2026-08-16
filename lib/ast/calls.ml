(** The single AST call-walker.

    Collects every direct function call in an expression as
    [(name, name_span, app_span)]:

    - [name] is the bare callee name, or ["Mod.fn"] for a qualified call;
    - [name_span] is where a diagnostic's caret goes;
    - [app_span] is the whole [EApp] node's span — the key
      [March_refinecheck.Obligation.record] files preconditions under, so a
      lookup keyed on [name_span] instead would silently never match.

    This module exists because the walk had THREE copies (two byte-identical
    in [typecheck.ml], one structural in [panic_surface_by_proof.ml]) and the
    drift between them was fail-OPEN: an [Ast.expr] form added to one and not
    another made a call that can panic compile clean inside [cap no_panic].
    It lives in [march_ast] because that library has no dependencies and both
    [march_typecheck] and [march_refinecheck] depend on it — the dependency
    direction that forced the third copy in the first place.

    NOTE this collects CALLS only. Capability and dependency analysis that
    must also see a function referenced as a VALUE (e.g. [map(xs, helper)])
    needs a free-variable walk instead — see [free_vars_expr] in
    [typecheck.ml]. Using this walker for that purpose is fail-open. *)
let rec calls_in_expr (acc : (string * Ast.span * Ast.span) list) (e : Ast.expr)
    : (string * Ast.span * Ast.span) list =
  match e with
  | Ast.EApp (Ast.EVar fn_name, args, sp) ->
    let acc = (fn_name.Ast.txt, fn_name.Ast.span, sp) :: acc in
    List.fold_left calls_in_expr acc args
  | Ast.EApp (Ast.EField (Ast.EVar mod_name, fn_name, _), args, sp) ->
    let qname = mod_name.Ast.txt ^ "." ^ fn_name.Ast.txt in
    let acc = (qname, fn_name.Ast.span, sp) :: acc in
    List.fold_left calls_in_expr acc args
  | Ast.EApp (f, args, _) ->
    List.fold_left calls_in_expr (calls_in_expr acc f) args
  | Ast.ECon (_, args, _) -> List.fold_left calls_in_expr acc args
  | Ast.ELam (_, body, _) -> calls_in_expr acc body
  | Ast.EBlock (es, _) -> List.fold_left calls_in_expr acc es
  | Ast.ELet (b, _) -> calls_in_expr acc b.Ast.bind_expr
  | Ast.EMatch (scrut, arms, _) ->
    let acc = calls_in_expr acc scrut in
    List.fold_left (fun a arm ->
      let a = Option.fold ~none:a ~some:(calls_in_expr a) arm.Ast.branch_guard in
      calls_in_expr a arm.Ast.branch_body) acc arms
  | Ast.ETuple (es, _) -> List.fold_left calls_in_expr acc es
  | Ast.ERecord (fields, _) ->
    List.fold_left (fun a (_, ex) -> calls_in_expr a ex) acc fields
  | Ast.ERecordUpdate (base, fields, _) ->
    let acc = calls_in_expr acc base in
    List.fold_left (fun a (_, ex) -> calls_in_expr a ex) acc fields
  | Ast.EField (inner, _, _) -> calls_in_expr acc inner
  | Ast.EIf (cond, then_, else_, _) ->
    calls_in_expr (calls_in_expr (calls_in_expr acc cond) then_) else_
  | Ast.ECond (arms, _) ->
    List.fold_left (fun a (ce, be) ->
      calls_in_expr (calls_in_expr a ce) be) acc arms
  | Ast.EPipe (a, b, _) -> calls_in_expr (calls_in_expr acc a) b
  | Ast.EAnnot (ex, _, _) -> calls_in_expr acc ex
  | Ast.EHole _ -> acc
  | Ast.EAtom (_, args, _) -> List.fold_left calls_in_expr acc args
  | Ast.ESend (a, b, _) -> calls_in_expr (calls_in_expr acc a) b
  | Ast.ESpawn (e, _) -> calls_in_expr acc e
  | Ast.EResultRef _ -> acc
  | Ast.EDbg (None, _) -> acc
  | Ast.EDbg (Some inner, _) -> calls_in_expr acc inner
  | Ast.ELetFn (_, _, _, body, _) -> calls_in_expr acc body
  | Ast.ELetQ (_, rhs, body, _) -> calls_in_expr (calls_in_expr acc rhs) body
  | Ast.ELetStar (_, rhs, body, _) -> calls_in_expr (calls_in_expr acc rhs) body
  | Ast.EAssert (e, _) -> calls_in_expr acc e
  | Ast.ESigil (_, content, _) -> calls_in_expr acc content
  | Ast.ELit _ | Ast.EVar _ -> acc

(** [names_and_name_spans e] is [calls_in_expr] projected to the
    [(name, name_span)] pairs the typechecker's two former copies returned.
    Argument order and list order match those copies exactly, so consumers
    substitute without a behavior change. *)
let names_and_name_spans (e : Ast.expr) : (string * Ast.span) list =
  List.map (fun (n, name_span, _) -> (n, name_span)) (calls_in_expr [] e)

(** [spawned_actor_names e] is every actor name appearing in a [spawn(Actor)]
    position inside [e], as a bare string.  The actor name in an [ESpawn] is
    always a plain nullary constructor or variable — [Typecheck]'s spawn arm
    rejects any computed actor expression — so it is matched here exactly the
    way that arm extracts it ([ECon(n,[],_)] / [EVar n]).

    Why this exists: the whole-program capability GRANT ([check_main_grant])
    walks the static reference graph from [main].  An actor's message handlers
    are synthesized functions ([<Actor>_<Msg>]) that carry their own capability
    closure, but nothing in ordinary reference-following reaches them — a
    [spawn(Actor)] site names the actor, not its handlers, and [free_vars_expr]
    sees the actor only as a nullary [ECon] tag it discards.  Feeding these
    names in as reference edges (paired with the [DActor] arm registering
    [Actor -> handler] edges) is what makes a handler's IO count against the
    grant, closing a runtime-exploitable bypass where a handler could reach a
    capability the grant never authorized.  A handler is charged when its actor
    is SPAWNED (reachable), not merely defined, so a never-spawned actor stays
    free exactly like any other dead code. *)
let rec spawned_actor_names (acc : string list) (e : Ast.expr) : string list =
  match e with
  | Ast.ESpawn (inner, _) ->
    let acc =
      match inner with
      | Ast.ECon (n, [], _) | Ast.EVar n -> n.Ast.txt :: acc
      | _ -> acc
    in
    spawned_actor_names acc inner
  | Ast.EApp (f, args, _) ->
    List.fold_left spawned_actor_names (spawned_actor_names acc f) args
  | Ast.ECon (_, args, _) -> List.fold_left spawned_actor_names acc args
  | Ast.ELam (_, body, _) -> spawned_actor_names acc body
  | Ast.EBlock (es, _) -> List.fold_left spawned_actor_names acc es
  | Ast.ELet (b, _) -> spawned_actor_names acc b.Ast.bind_expr
  | Ast.EMatch (scrut, arms, _) ->
    let acc = spawned_actor_names acc scrut in
    List.fold_left (fun a arm ->
      let a =
        Option.fold ~none:a ~some:(spawned_actor_names a) arm.Ast.branch_guard
      in
      spawned_actor_names a arm.Ast.branch_body) acc arms
  | Ast.ETuple (es, _) -> List.fold_left spawned_actor_names acc es
  | Ast.ERecord (fields, _) ->
    List.fold_left (fun a (_, ex) -> spawned_actor_names a ex) acc fields
  | Ast.ERecordUpdate (base, fields, _) ->
    let acc = spawned_actor_names acc base in
    List.fold_left (fun a (_, ex) -> spawned_actor_names a ex) acc fields
  | Ast.EField (inner, _, _) -> spawned_actor_names acc inner
  | Ast.EIf (cond, then_, else_, _) ->
    spawned_actor_names
      (spawned_actor_names (spawned_actor_names acc cond) then_) else_
  | Ast.ECond (arms, _) ->
    List.fold_left (fun a (ce, be) ->
      spawned_actor_names (spawned_actor_names a ce) be) acc arms
  | Ast.EPipe (a, b, _) -> spawned_actor_names (spawned_actor_names acc a) b
  | Ast.EAnnot (ex, _, _) -> spawned_actor_names acc ex
  | Ast.EAtom (_, args, _) -> List.fold_left spawned_actor_names acc args
  | Ast.ESend (a, b, _) -> spawned_actor_names (spawned_actor_names acc a) b
  | Ast.EDbg (Some inner, _) -> spawned_actor_names acc inner
  | Ast.ELetFn (_, _, _, body, _) -> spawned_actor_names acc body
  | Ast.ELetQ (_, rhs, body, _) ->
    spawned_actor_names (spawned_actor_names acc rhs) body
  | Ast.EAssert (e, _) -> spawned_actor_names acc e
  | Ast.ESigil (_, content, _) -> spawned_actor_names acc content
  | Ast.EHole _ | Ast.EResultRef _ | Ast.EDbg (None, _)
  | Ast.ELit _ | Ast.EVar _ -> acc
