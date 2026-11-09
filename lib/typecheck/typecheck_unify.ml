(** §1 Unification and §2 surface-type → internal-type conversion.

    The [pp_ty] helpers and the mismatch renderer, [session_ty_equal],
    [session_ty_exact_equal], [expand_record_ref], [unify], [report_mismatch],
    [surface_ty], [expand_record] and [instantiate_ctor].  Lifted verbatim out
    of [Typecheck] on 2026-08-27 (Target B, task B3 — Phase 6's task 6.7,
    which was gated on a module-initialisation-order hazard that turned out
    not to exist).

    {2 Why moving the [let () =] hook installation is safe}

    The whole initialisation-order surface of [lib/typecheck/] is one line,
    and it is in this band (a second, [inject_iface_exports_ref], never had a
    reader and was deleted 2026-09-11; see
    specs/2026-09-11-correctness-fixes-design.md §4):

    - [expand_record_ref] moves as a closed unit: its declaration, its single
      read site ([expand_nominal_record], beside it) and its installation are all three in this
      file, in that order.  [Typecheck_unify] initialises strictly before
      [Typecheck], so the install still precedes every possible read.

    {2 The standing check}

    No oracle can see module-initialisation order, so the property is asserted
    directly instead.  Two invariants, to be re-run by anything that touches
    this file:

    - [lib/typecheck/] must contain exactly TWO top-level effects — the two
      installations below.  Grep the whole directory for line-initial
      [let () =]; the count must stay 2.  If it ever grows, the argument above
      no longer covers the new effect and the hazard is live again: say so in
      that change.
    - The three CODE sites of the record-expansion hook — its declaration, the
      single dereference ([expand_nominal_record], which [unify] and the
      mismatch diff call), and its installation — must all be in
      this file, in that order.  Grep this file for line-initial
      [let expand_record_ref], for a dereference of it, and for its
      line-initial installation; three hits, no others anywhere in
      [typecheck.ml].

    The runnable form of both is recorded in the commit that created this file
    and in [specs/progress/2026-08-27-typecheck-target-b-decomposition.md].
    It is deliberately not spelled out here as a copy-pasteable command: a
    literal grep pattern written into the file it greps matches itself, which
    silently inflates the count it is supposed to pin.

    [include], not [open], at the call site: only [include] re-exports these
    names as part of [Typecheck]'s own surface, and consumers reach them
    through [let open] and through aliases (Tc., TC., T.) that no grep can
    see. *)

include Typecheck_types
include Typecheck_env
include Typecheck_builtins

(* =================================================================
   §1  Unification
   ================================================================= *)

(** Format a type for display in an error message.
    Uses pretty-printing with line-wrapping for long types. *)
let format_ty_for_error t =
  let flat = pp_ty t in
  if String.length flat > 50 then
    "\n    " ^ String.concat "\n    " (String.split_on_char '\n' (pp_ty_pretty ~indent:4 ~width:60 t))
  else "`" ^ flat ^ "`"

(** A capability passed where a different one is needed
    (specs/plans/2026-11-02-diagnostics-depth-plan.md §F1).  [unify] reaches
    this from the [Cap] argument it recursed into, so [have]/[need] are the
    two IO-lattice names and [p] the whole capability-valued expression.
    Reported as [cap_mismatch], not as a type mismatch between two
    unrelated-looking types, with one line of the lattice and the way out;
    [Typecheck.refine_capability_reports] later names the callee and attaches
    the fix, which need the declarations.  Recorded in
    [env.cap_mismatch_sites] for that pass. *)
let report_cap_mismatch env ~span ~reason ~(p : provided) ~have ~need =
  let module L = March_caps.Cap_lattice in
  let call = match reason with
    | Some (RFnArg (sp, _)) -> Some sp
    | _ -> None in
  let subject = match call with Some _ -> "this call" | None -> "this" in
  let arg = match p.p_name with
    | Some n -> Printf.sprintf "`%s` is" n
    | None -> "this is" in
  let arg_text = match p.p_name with Some n -> n | None -> "the capability" in
  let help =
    if cap_subsumes have need then
      Printf.sprintf "help: pass `cap_narrow(%s)`, which narrows it to `Cap(%s)`."
        arg_text need
    else
      Printf.sprintf
        "help: thread a `Cap(%s)` down from `main` (add a parameter for it) and \
         pass that here." need
  in
  let labels =
    (match call with
     | Some csp when csp <> span ->
       [ { Err.lbl_span = csp;
           lbl_message = Printf.sprintf "%s needs `Cap(%s)`" subject need } ]
     | _ -> [])
    @ (match p.p_name with
        | Some n ->
          (match StrMap.find_opt n env.binder_spans with
           | Some bsp when bsp <> span && bsp <> p.p_span ->
             [ { Err.lbl_span = bsp;
                 lbl_message = Printf.sprintf "`%s` was bound here as `Cap(%s)`" n have } ]
           | _ -> [])
        | None -> [])
  in
  env.cap_mismatch_sites :=
    { cm_span = span; cm_call = call; cm_arg_name = p.p_name;
      cm_have = have; cm_need = need; cm_in_fn = !(env.current_decl) }
    :: !(env.cap_mismatch_sites);
  Err.report env.errors
    { Err.severity = Error; span;
      message =
        Printf.sprintf "%s needs %s, but %s %s." subject (L.access need) arg
          (L.the_capability have);
      labels;
      notes = [ L.relation ~have ~need; help ];
      code = Err.Code.with_arg Err.Code.cap_mismatch need; fix = None }

(** The first field that differs between a provided and a required record. *)
let record_fields_note provided_flds required_flds =
  (* [report_type_mismatch]'s [expected] holds what was PROVIDED and its
     [found] what was REQUIRED — hence these names.  Getting this backwards is why an extra field used to be reported as a
     missing one ("present in the expected type but missing in the found
     type" for a field that was in the provided value and absent from the
     required type).  Report both directions, surplus first, and name the
     two sides in words rather than reusing the overloaded
     "expected"/"found" pair. *)
  let surplus = List.filter_map (fun (name, t1) ->
    match List.assoc_opt name required_flds with
    | Some t2 when pp_ty t1 <> pp_ty t2 ->
      Some (Printf.sprintf "Field `%s` mismatches: expected `%s` but got `%s`."
        name (pp_ty t2) (pp_ty t1))
    | None ->
      Some (Printf.sprintf
              "Field `%s` is present in the value provided, but the \
               expected type has no such field." name)
    | _ -> None) provided_flds
  in
  let absent = List.filter_map (fun (name, _) ->
    if List.mem_assoc name provided_flds then None
    else
      Some (Printf.sprintf
              "Field `%s` is required by the expected type, but the value \
               provided has no such field." name)) required_flds
  in
  match surplus @ absent with n :: _ -> [n] | [] -> []

(** A hint for a frequently confused pair, [provided] where [required] was needed. *)
let common_mismatch_hint provided required =
  match repr provided, repr required with
  | TCon ("Int", []), TCon ("Float", []) ->
    (* User provided Int, Float was required *)
    [ "Int and Float are distinct types in March.\n\
       Use `int_to_float(x)` to convert, or write a Float literal like `1.0`." ]
  | TCon ("Float", []), TCon ("Int", []) ->
    (* User provided Float, Int was required *)
    [ "Float and Int are distinct types in March.\n\
       Use `float_to_int(x)` to truncate, or write an Int literal like `1`." ]
  | TCon ("Int", []), TCon ("Bool", []) ->
    (* Expression was Int but Bool was required *)
    [ "March does not coerce Int to Bool.\n\
       Try an explicit comparison, e.g. `x != 0`." ]
  | TCon ("Int", []), TCon ("String", []) ->
    (* Expression was Int but String was required *)
    [ "Use `int_to_string(x)` to convert an Int to a String." ]
  | TCon ("Float", []), TCon ("String", []) ->
    (* Expression was Float but String was required *)
    [ "Use `float_to_string(x)` to convert a Float to a String." ]
  | TArrow _, _ ->
    [ "This value is a function. Did you forget to apply it to its arguments?" ]
  | _, TArrow _ ->
    [ "A function was expected here.\n\
       Did you mean to pass this as a callback?" ]
  | _ -> []


(** Two states of one generated protocol role (§F3): the facts for the
    state the value is in ([here]) and the one the call needs ([wanted]). *)
let protocol_step_pair provided required =
  match repr provided, repr required with
  | TCon (p, []), TCon (r, []) when p <> r ->
    (* The checker sees a role module's state names bare (`S_end`), and two
       roles can share one; the pair belongs to the one role that has both. *)
    let open March_ast.Protocol_states in
    let pairs = List.concat_map (fun (here : info) ->
        List.filter_map (fun (wanted : info) ->
            if here.ps_proto = wanted.ps_proto && here.ps_role = wanted.ps_role
            then Some (here, wanted) else None) (find_all r)) (find_all p) in
    (match pairs with [ pair ] -> Some pair | _ -> None)
  | _ -> None

(** A state of one role passed to another role's step (§F3): the body is
    written against the wrong role module.  Only an unambiguous pair: every
    role has an `S_end`, so two end states say nothing. *)
let protocol_role_pair provided required =
  match repr provided, repr required with
  | TCon (p, []), TCon (r, []) when p <> r ->
    let open March_ast.Protocol_states in
    let pairs = List.concat_map (fun (here : info) ->
        List.filter_map (fun (wanted : info) ->
            if here.ps_proto = wanted.ps_proto && here.ps_role <> wanted.ps_role
            then Some (here, wanted) else None) (find_all r)) (find_all p) in
    (match pairs with [ pair ] -> Some pair | _ -> None)
  | _ -> None

(** A role body calling another role's step: which role the state belongs
    to, which role the call is for, and the call this role takes instead. *)
let report_protocol_wrong_role env ~span ~provided
    ~(here : March_ast.Protocol_states.info) ~(wanted : March_ast.Protocol_states.info) =
  let name = match provided with
    | Some { p_name = Some n; _ } -> Some n
    | _ -> None in
  let subject = match name with Some n -> Printf.sprintf "`%s`" n | None -> "this state" in
  let message = Printf.sprintf
      "`%s` is a step of role `%s`, but %s belongs to role `%s` of protocol `%s`."
      wanted.ps_call wanted.ps_role subject here.ps_role here.ps_proto in
  let you_are_here = match here.ps_span with
    | Some sp -> [ { Err.lbl_span = sp;
                     lbl_message = Printf.sprintf "`%s` is here: it must %s" here.ps_role here.ps_doing } ]
    | None -> [] in
  let binder = match provided, name with
    | Some { p_span; _ }, Some n ->
      (match StrMap.find_opt n env.binder_spans with
       | Some bsp when bsp <> span && bsp <> p_span ->
         [ { Err.lbl_span = bsp; lbl_message = Printf.sprintf "`%s` is `%s`'s state, bound here" n here.ps_role } ]
       | _ -> [])
    | _ -> [] in
  let module_of call = match String.rindex_opt call '.' with
    | Some i -> String.sub call 0 i | None -> call in
  let diagram = match here.ps_pos with
    | Some p ->
      March_ast.Protocol_states.diagram ~proto:here.ps_proto ~role:here.ps_role
        ~subject:(Printf.sprintf "`%s`" here.ps_role) ~here:p
        ?tried:(Option.map (fun q ->
            (q, Printf.sprintf "`%s` tried this, but it is `%s`'s step" here.ps_role wanted.ps_role))
            wanted.ps_pos) ()
    | None -> None in
  Err.report env.errors
    { Err.severity = Error; span; message;
      labels = you_are_here @ binder;
      notes = [ Printf.sprintf "At this point `%s` must %s: take that step with `%s`."
                  here.ps_role here.ps_doing here.ps_call;
                Printf.sprintf "If this body is meant to play `%s`, give it a `%s` state instead."
                  wanted.ps_role (module_of wanted.ps_call) ]
              @ Option.to_list diagram;
      code = Err.Code.protocol_wrong_role; fix = None }

(** A role body taking a step the protocol does not allow at that point,
    said in protocol terms: what the call tries to do, what the role must do
    instead, a "you are here" label on that protocol step, and the function
    that takes it.  No generated state name appears. *)
let report_protocol_step_order env ~span ~provided
    ~(here : March_ast.Protocol_states.info) ~(wanted : March_ast.Protocol_states.info) =
  (* Two steps can read alike (two sends of a `String` to `L`); then each is
     told apart by its line in the protocol. *)
  let says (i : March_ast.Protocol_states.info) =
    match i.ps_span with
    | Some sp when here.ps_doing = wanted.ps_doing ->
      Printf.sprintf "%s (the step on line %d)" i.ps_doing sp.Ast.start_line
    | _ -> i.ps_doing in
  let message = Printf.sprintf
      "Role `%s` tries to %s here, but at this point protocol `%s` says it must %s."
      here.ps_role (says wanted) here.ps_proto (says here) in
  let you_are_here = match here.ps_span with
    | Some sp -> [ { Err.lbl_span = sp;
                     lbl_message = Printf.sprintf "`%s` is here: it must %s" here.ps_role here.ps_doing } ]
    | None -> [] in
  let binder = match provided with
    | Some { p_name = Some n; p_span; _ } ->
      (match StrMap.find_opt n env.binder_spans with
       | Some bsp when bsp <> span && bsp <> p_span ->
         [ { Err.lbl_span = bsp; lbl_message = Printf.sprintf "`%s` is the state bound here" n } ]
       | _ -> [])
    | _ -> [] in
  (* The conversation drawn out: the step tried is marked where it sits,
     after the step due (skipped ahead), or before it (taken again: the
     loop's next round, or a step on a state already used). *)
  let diagram = match here.ps_pos with
    | Some p ->
      let tried = Option.map (fun q ->
          let again = March_ast.Protocol_states.pos_before q p in
          (q, if wanted.ps_doing = "close the conversation"
              then Printf.sprintf "`%s` tried to close here" here.ps_role
              else Printf.sprintf "`%s` tried this%s" here.ps_role (if again then " again" else "")))
          wanted.ps_pos in
      March_ast.Protocol_states.diagram ~proto:here.ps_proto ~role:here.ps_role
        ~subject:(Printf.sprintf "`%s`" here.ps_role) ~here:p ?tried ()
    | None -> None in
  (* Closing at the top of a `loop`: the usual cause is a branch that
     repeats, whose callback closed where it should have gone round again. *)
  let repeat_note =
    match here.ps_pos with
    | Some p when wanted.ps_doing = "close the conversation"
                  && March_ast.Protocol_states.at_loop_start ~proto:here.ps_proto p ->
      [ Printf.sprintf
          "This state is the top of protocol `%s`'s `loop`, where a branch that repeats \
           comes back to. To go round again, pass the state to a function that takes it \
           as a parameter (usually `%s`'s own function, called again) instead of closing."
          here.ps_proto here.ps_role ]
    | _ -> [] in
  Err.report env.errors
    { Err.severity = Error; span; message;
      labels = you_are_here @ binder;
      notes = Printf.sprintf "Take that step with `%s` first." here.ps_call
              :: repeat_note @ Option.to_list diagram;
      code = Err.Code.protocol_step_order; fix = None }

(* A capability for another capability: its own message (§F1). *)
let cap_pair_of ~occurs_violation ?provided expected found =
    match repr expected, repr found, provided with
    | TCon (have, []), TCon (need, []), Some p
      when (not occurs_violation) && have <> need
           && cap_subsumes "IO" have && cap_subsumes "IO" need
           && (match repr p.p_ty with
               | TCon ("Cap", [ inner ]) ->
                 (match repr inner with TCon (h, []) -> h = have | _ -> false)
               | _ -> false) ->
      Some (have, need, p)
    | _ -> None

(** Report a type mismatch with a conversational Elm-style message. *)
let rec report_mismatch env ~span ?(occurs_violation = false) ~reason ?provided expected found =
  match cap_pair_of ~occurs_violation ?provided expected found with
  | Some (have, need, p) -> report_cap_mismatch env ~span ~reason ~p ~have ~need
  | None -> report_type_mismatch env ~span ~occurs_violation ~reason ?provided expected found

and report_type_mismatch env ~span ~occurs_violation ~reason ?provided ?diff expected found =
  match protocol_step_pair expected found with
  | Some (here, wanted) when not occurs_violation ->
    report_protocol_step_order env ~span ~provided ~here ~wanted
  | _ ->
  match protocol_role_pair expected found with
  | Some (here, wanted) when not occurs_violation ->
    report_protocol_wrong_role env ~span ~provided ~here ~wanted
  | _ ->
  (* Build headline, using pretty-printing for long types.
     Convention: `expected` = inferred type of the expression (what was provided);
                 `found`    = required type from context (what was needed).
     Headline uses standard compiler phrasing: "expected <required> but got <provided>". *)
  (* Two sides can print identically while being structurally distinct: a
     [TCon] with no arguments prints bare, and a [TRecord] prints as the
     declared name recovered from its field signature.  A parameterised record
     type referenced with zero type arguments therefore renders exactly like a
     literal of that same type, giving the useless "expected `Ops` but got
     `Ops`".  When that happens, spell the record side out structurally so the
     headline actually says something. *)
  let structurally_distinct =
    match repr expected, repr found with
    | TCon (n1, a1), TCon (n2, a2) ->
      n1 <> n2 || List.length a1 <> List.length a2
    | TCon _, TRecord _ | TRecord _, TCon _ -> true
    | _ -> false
  in
  let same_printed =
    structurally_distinct && pp_ty (repr expected) = pp_ty (repr found)
  in
  let render t =
    match repr t with
    | TRecord ((_ :: _) as flds) when same_printed ->
      "{ " ^ String.concat ", "
               (List.map (fun (n, ft) -> n ^ " : " ^ pp_ty ft) flds) ^ " }"
    | _ -> pp_ty t
  in
  let pretty t =
    if same_printed then render t else pp_ty_pretty ~indent:4 ~width:60 t
  in
  let fmt t =
    if same_printed then "`" ^ render t ^ "`" else format_ty_for_error t
  in
  let exp_str = fmt expected in
  let fnd_str = fmt found in
  let headline =
    match diff with
    | Some (h, _) -> h
    | None ->
    if String.length (render expected) > 50 || String.length (render found) > 50 then
      Printf.sprintf "expected:\n    %s\nbut got:\n    %s"
        (String.concat "\n    " (String.split_on_char '\n' (pretty found)))
        (String.concat "\n    " (String.split_on_char '\n' (pretty expected)))
    else
      render_parts
        [ MPText "expected "; MPText fnd_str;
          MPText " but got "; MPText exp_str; MPText "." ]
  in
  let why_note =
    match reason with
    | None   -> []
    | Some r -> [ string_of_reason r ]
  in
  (* Contextual hint: when both types share the same constructor but differ
     in one argument, identify which argument mismatches. *)
  let mismatch_note =
    match diff with
    | Some (_, note) -> [ note ]
    | None ->
    match repr expected, repr found with
    | TCon (name1, args1), TCon (name2, args2)
      when name1 = name2 && List.length args1 = List.length args2 ->
      (match find_arg_mismatch name1 args1 args2 with
       | Some (i, cname, exp_arg, fnd_arg) ->
         let ordinal = match i with 1 -> "1st" | 2 -> "2nd" | 3 -> "3rd"
           | n -> string_of_int n ^ "th" in
         [ Printf.sprintf "The %s argument of `%s` mismatches: expected `%s` but got `%s`."
             ordinal cname (pp_ty fnd_arg) (pp_ty exp_arg) ]
       | None -> [])
    | TRecord provided_flds, TRecord required_flds ->
      record_fields_note provided_flds required_flds
    | _ -> []
  in
  (* Common-case hints for frequently-confused types.
     NOTE: `expected` here = the inferred type of the expression (what was provided);
           `found`    here = the required type from context (what was needed).
     Matches are on (provided, required) order. *)
  (* Generated session states (`@[endpoints]`): `S_<step>` is the state a
     role is in before it takes <step>, and `Yield` is what a finished role
     body produces. A mismatch between two of them, or between `S_end` and
     `Yield`, is a protocol-order or a wrong-role mistake, and the type names
     alone do not say so. *)
  let short name = match String.rindex_opt name '.' with
    | Some i -> String.sub name (i + 1) (String.length name - i - 1)
    | None -> name in
  let is_state name = String.length (short name) > 2 && String.sub (short name) 0 2 = "S_" in
  let session_hint =
    match repr expected, repr found with
    | TCon (p, []), TCon (r, []) when is_state p && is_state r ->
      [ Printf.sprintf
          "Both are states of a generated protocol role: `%s` is the state the role is in \
           before that step, and this call is a different step. Either the protocol takes \
           the steps in another order, or this body is written for a different role than \
           the one it is run as (`run_<Role>` and `<Role>.register` decide which)."
          (short p) ]
    | TCon (p, []), TCon (r, []) when short p = "S_end" && short r = "Yield" ->
      [ "A role body ends by closing the conversation: `<Role>.close(s, st)` on the final \
         state produces the `Yield` the callback must return." ]
    | TCon (p, []), TCon (r, []) when is_state p && short r = "Yield" ->
      [ Printf.sprintf
          "The callback must finish the conversation: keep taking the protocol's steps from \
           `%s` until `<Role>.close(s, st)`, which produces the `Yield`."
          (short p) ]
    | _ -> []
  in
  (* With a diff the two roots share a head, so these hints, about the
     roots, don't apply; the ones for the parts would name the wrong value. *)
  let common_hint =
    if diff <> None then [] else
      match common_mismatch_hint expected found with
      | [] -> Option.to_list (Typecheck_suggest.conversion_note env expected found)
      | hs -> hs
  in
  (* Same-printed-name explanation.  Two shapes reach here: a genuine
     global-namespace collision, and (commoner) a parameterised record type
     referenced with zero type arguments.
     March has a single global type namespace, so a user-defined type can share
     its printed name with a stdlib type (e.g. local `Config` vs `Config` from the
     standard library).  When that happens unification fails but both sides render
     identically, yielding the baffling "expected `Config` but got `Config`".
     Detect the case — the two reprs print the same string but are structurally
     distinct — and explain it.  We compare structural shapes (TCon vs TRecord,
     constructor name, argument count) rather than exact identity so we only fire
     when the types genuinely differ despite printing alike. *)
  let same_name_note =
    let pe = pp_ty (repr expected) in
    if not same_printed then []
    else
      (* The commonest way to get here is not a collision at all: a record type
         declared WITH type parameters, referenced somewhere that supplies
         none.  Say that instead of blaming the namespace. *)
      match StrMap.find_opt pe env.records with
      | Some ((_ :: _) as params, _) ->
        [ Printf.sprintf
            "`%s` is declared with %d type parameter%s (`%s(%s)`), but here it \
             is used with none. A bare `%s` never unifies with `%s(%s)`; \
             supply the argument, or declare the type without parameters."
            pe (List.length params)
            (if List.length params = 1 then "" else "s")
            pe (String.concat ", " params)
            pe pe (String.concat ", " params) ]
      | _ ->
      [ Printf.sprintf
          "Two distinct types are both named `%s` — they print the same but have \
           different definitions. March has a single global type namespace, so a \
           local type collides with any same-named type from another module or the \
           standard library.\n\
           Rename one of them (e.g. `App%s`), or qualify/avoid the import that \
           brings the other `%s` into scope."
          pe pe pe ]
  in
  let labels =
    match reason with
    | Some r ->
      (match span_of_reason r with
       | Some rsp when rsp <> span ->
         [ { Err.lbl_span = rsp;
             lbl_message  = "the expected type comes from here" } ]
       | _ -> [])
    | None -> []
  in
  (* D5: where the PROVIDED type came from. "this is `T`" on the expression
     (dropped by the renderer when it is the primary span), and, for a
     variable whose binder is in scope, "`x` was bound here as `T`" on the
     binder. [p_ty] is the whole expression's type, not the inner argument
     the headline may be about. *)
  let labels =
    match provided with
    | None -> labels
    | Some p ->
      let t = pp_ty (repr p.p_ty) in
      let this_is =
        if p.p_span = span then []
        else [ { Err.lbl_span = p.p_span;
                 lbl_message = Printf.sprintf "this is `%s`" t } ]
      in
      let binder =
        match p.p_name with
        | Some n ->
          (match StrMap.find_opt n env.binder_spans with
           | Some bsp when bsp <> span && bsp <> p.p_span ->
             [ { Err.lbl_span = bsp;
                 lbl_message = Printf.sprintf "`%s` was bound here as `%s`" n t } ]
           | _ -> [])
        | None -> []
      in
      labels @ this_is @ binder
  in
  (* An occurs-check failure is a fundamentally different situation than an
     ordinary mismatch: the type variable would have to equal a type that
     contains itself (e.g. a self-referential record field inferred without
     a type annotation to anchor it, so the compiler discovers the recursion
     structurally instead of stopping at a nominal type name). The plain
     "expected X but got Y" headline above is technically accurate but reads
     as a random-looking, unmemorable variable name mismatching an unrelated
     type — nothing about it says "this can't ever be finite" or suggests
     the fix. Lead with that explanation instead. *)
  let occurs_note =
    if occurs_violation then
      [ "This type would have to be infinitely recursive to satisfy every \
         use — it isn't possible to infer it automatically. Add an explicit \
         type annotation (e.g. on the function parameter or `let` binding) \
         naming the recursive type by its declared name." ]
    else []
  in
  Err.report env.errors
    { Err.severity = Error; span; message = headline;
      labels;
      (* At most one "likely cause" hint: an occurs failure explains the
         whole error on its own (stacking "did you mean to pass this as a
         callback?" under it contradicted it), and the more specific
         session / same-name explanations pre-empt the generic one. *)
      notes =
        Err.first_cause
          [ occurs_note;
            why_note @ mismatch_note
            @ Err.first_cause [ session_hint; same_name_note; common_hint ] ];
      code = Err.Code.type_mismatch; fix = None }

(** Structural equality for session types (used by [unify] for [TChan] cases).
    Intentionally ignores payload types — only checks session structure shape. *)
let rec session_ty_equal s1 s2 =
  match s1, s2 with
  | SEnd, SEnd -> true
  | SError, SError -> true
  | SSend (_, s1'), SSend (_, s2') -> session_ty_equal s1' s2'
  | SRecv (_, s1'), SRecv (_, s2') -> session_ty_equal s1' s2'
  | SChoose bs1, SChoose bs2 | SOffer bs1, SOffer bs2 | SOfferPending bs1, SOfferPending bs2 ->
    List.length bs1 = List.length bs2 &&
    List.for_all2 (fun (l1, s1') (l2, s2') ->
        l1 = l2 && session_ty_equal s1' s2') bs1 bs2
  | SRec (x1, s1'), SRec (x2, s2') -> x1 = x2 && session_ty_equal s1' s2'
  | SVar x1, SVar x2 -> x1 = x2
  | SMSend (r1, _, s1'), SMSend (r2, _, s2') -> r1 = r2 && session_ty_equal s1' s2'
  | SMRecv (r1, _, s1'), SMRecv (r2, _, s2') -> r1 = r2 && session_ty_equal s1' s2'
  | _ -> false

(** Exact structural equality including payload types.
    Used by MPST mergeability check to determine if branches can be merged.
    Two branches can be merged only if they are completely identical. *)
let rec session_ty_exact_equal s1 s2 =
  match s1, s2 with
  | SEnd, SEnd -> true
  | SError, SError -> true
  | SSend (t1, s1'), SSend (t2, s2') ->
    pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | SRecv (t1, s1'), SRecv (t2, s2') ->
    pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | SChoose bs1, SChoose bs2 | SOffer bs1, SOffer bs2 | SOfferPending bs1, SOfferPending bs2 ->
    List.length bs1 = List.length bs2 &&
    List.for_all2 (fun (l1, s1') (l2, s2') ->
        l1 = l2 && session_ty_exact_equal s1' s2') bs1 bs2
  | SRec (x1, s1'), SRec (x2, s2') -> x1 = x2 && session_ty_exact_equal s1' s2'
  | SVar x1, SVar x2 -> x1 = x2
  | SMSend (r1, t1, s1'), SMSend (r2, t2, s2') ->
    r1 = r2 && pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | SMRecv (r1, t1, s1'), SMRecv (r2, t2, s2') ->
    r1 = r2 && pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | _ -> false

(** Normalize type-level nat arithmetic.
    Reduces concrete sub-expressions and applies identity / annihilation laws.
    The result is in weak-head normal form: outer-most TNatOp is simplified as
    far as possible, sub-expressions are recursively normalized. *)
let rec normalize_tnat t =
  match repr t with
  | TNatOp (op, a, b) ->
    let a = normalize_tnat a and b = normalize_tnat b in
    (match op, a, b with
     | Ast.NatAdd, TNat m, TNat n  -> TNat (m + n)
     | Ast.NatAdd, t',    TNat 0   -> t'
     | Ast.NatAdd, TNat 0, t'      -> t'
     | Ast.NatMul, TNat m, TNat n  -> TNat (m * n)
     | Ast.NatMul, _,     TNat 0   -> TNat 0
     | Ast.NatMul, TNat 0, _       -> TNat 0
     | Ast.NatMul, t',    TNat 1   -> t'
     | Ast.NatMul, TNat 1, t'      -> t'
     | _                           -> TNatOp (op, a, b))
  | t -> t

(** Assert that a [TRecord]'s field list satisfies the sorted-name invariant.
    Raises [Failure] with a diagnostic if the invariant is violated.
    Called at every TRecord unification site to catch construction-path bugs
    early — a misordered TRecord produces confusing "type mismatch" errors
    that look like unrelated failures.
    Only active in debug builds (guarded by [Sys.getenv_opt]) to avoid overhead
    in production; set [MARCH_DEBUG_TC=1] to enable. *)
let assert_trecord_sorted flds label =
  match Sys.getenv_opt "MARCH_DEBUG_TC" with
  | Some _ ->
    let names = List.map fst flds in
    let sorted = List.sort String.compare names in
    if names <> sorted then
      failwith (Printf.sprintf
        "INVARIANT VIOLATION: TRecord %s has unsorted fields [%s]; expected [%s]. \
         All TRecord values must be constructed with List.sort."
        label
        (String.concat ", " names)
        (String.concat ", " sorted))
  | None -> ()

(** Forward ref to [expand_record], which is defined later because it depends on
    [surface_ty].  [unify] uses it to reconcile a nominal record [TCon] with the
    structural [TRecord] the same type expands to elsewhere (see the
    [TCon]/[TRecord] case in [unify]).  Wired up immediately after
    [expand_record] is defined. *)
let expand_record_ref : (env -> ty -> ty option) ref =
  ref (fun _ _ -> None)

(** The hook's one read site; [unify] and the mismatch diff below call it. *)
let expand_nominal_record env t = !expand_record_ref env t

(* -----------------------------------------------------------------
   Structural type diffs (specs/plans/2026-11-02-diagnostics-depth-plan.md §X2).

   When [unify] fails below the pair it was called on, the mismatch is
   reported on the whole pair, with a note that prints the provided type and
   puts a caret under each part that differs.  The parts are found by a
   read-only walk over the two types after unification, so this changes
   only what is reported, never what is inferred.
   ----------------------------------------------------------------- *)

(** One step from a type to one of its parts. *)
type diff_step =
  | DArg of string * int  (** argument [i] (from 1) of type constructor [name] *)
  | DComp of int          (** tuple component [i] (from 1) *)
  | DField of string      (** record field *)
  | DParam                (** a function type's parameter *)
  | DResult               (** a function type's result *)

(** A part where the provided type and the required one plainly differ: the
    path to it from the root (root first) and the two parts. *)
type type_diff = { td_path : diff_step list; td_provided : ty; td_required : ty }

let rec strip_lin t = match repr t with TLin (_, i) -> strip_lin i | t -> t

(** The parts where [provided] and [required] differ.  One-sided like
    [Typecheck.types_apart]: a type variable, an error or a channel never
    differs, so a part is reported only when its heads plainly disagree. *)
let type_diffs env provided required =
  let rec go rpath a b acc =
    let a = strip_lin a and b = strip_lin b in
    let here () = { td_path = List.rev rpath; td_provided = a; td_required = b } :: acc in
    match a, b with
    | (TError | TVar _ | TChan _ | TNatOp _), _
    | _, (TError | TVar _ | TChan _ | TNatOp _) -> acc
    | TCon (n1, a1), TCon (n2, a2) when n1 = n2 && List.length a1 = List.length a2 ->
      fst (List.fold_left2 (fun (acc, i) x y -> (go (DArg (n1, i) :: rpath) x y acc, i + 1))
             (acc, 1) a1 a2)
    | TTuple t1, TTuple t2 when List.length t1 = List.length t2 ->
      fst (List.fold_left2 (fun (acc, i) x y -> (go (DComp i :: rpath) x y acc, i + 1))
             (acc, 1) t1 t2)
    | TRecord f1, TRecord f2 when List.map fst f1 = List.map fst f2 ->
      List.fold_left2 (fun acc (n, x) (_, y) -> go (DField n :: rpath) x y acc) acc f1 f2
    | TArrow (p1, r1), TArrow (p2, r2) ->
      go (DResult :: rpath) r1 r2 (go (DParam :: rpath) p1 p2 acc)
    | TNat n1, TNat n2 when n1 = n2 -> acc
    | TCon _, TRecord _ ->
      (match expand_nominal_record env a with
       | Some (TRecord _ as a') -> go rpath a' b acc | _ -> here ())
    | TRecord _, TCon _ ->
      (match expand_nominal_record env b with
       | Some (TRecord _ as b') -> go rpath a b' acc | _ -> here ())
    | _ -> here ()
  in
  List.rev (go [] provided required [])

(** Print [t] as [pp_ty] would, except that a part with a difference below
    it is spelled out (a record by its fields, so a caret can point into
    it), and, when [elide], a part with none prints as `…`.  Returns the text
    and, for each path in [targets], the column and width of its part. *)
let pp_ty_diff env ~elide ~targets t =
  let buf = Buffer.create 64 in
  let marks = ref [] in
  (* Columns, not bytes: `…` is three bytes wide in UTF-8. *)
  let col () =
    let n = ref 0 in
    String.iter (fun c -> if Char.code c land 0xC0 <> 0x80 then incr n) (Buffer.contents buf);
    !n in
  let add = Buffer.add_string buf in
  let rec is_prefix p q = match p, q with
    | [], _ -> true | x :: p', y :: q' -> x = y && is_prefix p' q' | _ -> false in
  let rec go ?(parens = false) rpath t =
    let path = List.rev rpath in
    if List.mem path targets then begin
      let start = col () in
      add (pp_ty ~parens t);
      marks := (path, (start, col () - start)) :: !marks
    end
    else if not (List.exists (is_prefix path) targets) then
      add (if elide then "…" else pp_ty ~parens t)
    else
      match repr t with
      | TLin (Ast.Linear, i) -> add "linear "; go ~parens:true rpath i
      | TLin (Ast.Affine, i) -> add "affine "; go ~parens:true rpath i
      | TLin ((Ast.Unrestricted | Ast.Ghost), i) -> go ~parens rpath i
      | TCon (name, (_ :: _ as args)) ->
        add name; add "(";
        List.iteri (fun i a -> if i > 0 then add ", "; go (DArg (name, i + 1) :: rpath) a) args;
        add ")"
      | TTuple (_ :: _ as ts) ->
        add "(";
        List.iteri (fun i a -> if i > 0 then add ", "; go (DComp (i + 1) :: rpath) a) ts;
        add ")"
      | TRecord (_ :: _ as flds) ->
        let shown = if not elide then flds else
            List.filter (fun (n, _) ->
                List.exists (is_prefix (path @ [ DField n ])) targets) flds in
        add "{ ";
        List.iteri (fun i (n, ft) ->
            if i > 0 then add ", ";
            add n; add " : "; go (DField n :: rpath) ft) shown;
        if List.length shown < List.length flds then add ", …";
        add " }"
      | TCon _ as tc ->
        (match expand_nominal_record env tc with
         | Some (TRecord _ as r) -> go ~parens rpath r
         | _ -> add (pp_ty ~parens tc))
      | TArrow (a, b) ->
        if parens then add "(";
        go ~parens:true (DParam :: rpath) a; add " -> "; go (DResult :: rpath) b;
        if parens then add ")"
      | t -> add (pp_ty ~parens t)
  in
  go [] t;
  (Buffer.contents buf, List.rev !marks)

(** The headline and diff note for a mismatch between [provided] and
    [required] that differ below the root, or [None] when no part plainly
    differs.  The headline elides equal parts when either type is long. *)
let diff_mismatch_message env ~provided ~required =
  match type_diffs env provided required with
  | [] | [ { td_path = []; _ } ] -> None  (* nothing, or the roots themselves *)
  | diffs ->
    let targets = List.map (fun d -> d.td_path) diffs in
    let long = String.length (pp_ty provided) > 50 || String.length (pp_ty required) > 50 in
    let got, marks = pp_ty_diff env ~elide:long ~targets provided in
    let want, _ = pp_ty_diff env ~elide:long ~targets required in
    let headline =
      if String.length got > 60 || String.length want > 60 then
        Printf.sprintf "expected:\n    %s\nbut got:\n    %s" want got
      else Printf.sprintf "expected `%s` but got `%s`." want got in
    let shown = List.filteri (fun i _ -> i < 3) diffs in
    let carets = List.filter_map (fun d ->
        match List.assoc_opt d.td_path marks with
        | Some (c, w) ->
          Some (Printf.sprintf "    %s%s expected `%s`" (String.make c ' ')
                  (String.make (max 1 w) '^') (pp_ty d.td_required))
        | None -> None) shown in
    let more = List.length diffs - List.length shown in
    let fields = match diffs with
      | [ { td_provided = TRecord p; td_required = TRecord r; _ } ] -> record_fields_note p r
      | _ -> [] in
    let note =
      String.concat "\n"
        ([ "The types differ here:"; "    " ^ got ] @ carets
         @ (if more > 0 then [ Printf.sprintf "    (and %d more)" more ] else [])
         @ fields) in
    Some (headline, note)

(** Unify [t1] and [t2], reporting any mismatch to [env.errors].
    Uses [TError] as a recovery sentinel — if either side is [TError]
    the constraint is silently satisfied (the error was already reported). *)
let rec unify env ~span ?(reason = None) ?provided t1 t2 =
  let inner = ref [] in
  unify_at env ~span ~reason ?provided ~inner ~depth:0 t1 t2;
  match List.rev !inner with
  | [] -> ()
  | (p1, p2) :: _ ->
    (* It failed below the root: report the whole pair, with a diff (§X2).
       If no part plainly differs any more, fall back to the first inner
       pair, as before. *)
    match diff_mismatch_message env ~provided:t1 ~required:t2 with
    | Some diff ->
      report_type_mismatch env ~span ~occurs_violation:false ~reason ?provided ~diff t1 t2
    | None -> report_mismatch env ~span ~reason ?provided p1 p2

(** [unify]'s walk.  A plain mismatch below the root ([depth > 0]) is
    collected in [inner] for [unify] to report once on the whole pair; an
    occurs failure and a capability-for-capability pair keep their own
    reports, at the part. *)
and unify_at env ~span ~reason ?provided ~inner ~depth t1 t2 =
  let unify env ~span ~reason ?provided a b =
    unify_at env ~span ~reason ?provided ~inner ~depth:(depth + 1) a b in
  let report_mismatch env ~span ?(occurs_violation = false) ~reason ?provided a b =
    if depth = 0 || occurs_violation
       || cap_pair_of ~occurs_violation ?provided a b <> None then
      report_mismatch env ~span ~occurs_violation ~reason ?provided a b
    else inner := (a, b) :: !inner in
  let t1 = normalize_tnat t1 and t2 = normalize_tnat t2 in
  match t1, t2 with
  (* Error sentinel absorbs everything *)
  | TError, _ | _, TError -> ()

  (* Same variable — trivially unified *)
  | TVar r1, TVar r2 when r1 == r2 -> ()

  (* Bind a variable *)
  | TVar r, t | t, TVar r ->
    (match !r with
     | Unbound (id, level) ->
       if occurs id level t then begin
         report_mismatch env ~span ~reason ?provided ~occurs_violation:true t1 t2;
         r := Link TError
       end else begin
         (* Proof-cap forge hook: if [r] is a tagged [cap_narrow]-result inner
            var (see [cap_producer_ivars]), reject the instant it is bound to a
            nominal proof cap — a cap_narrow value can NEVER become a proof cap,
            in any position or flow (direct, let-generalized, or laundered
            through a polymorphic function). If it binds to ANOTHER var, propagate
            the tag so the check fires when that var is eventually pinned. IO caps
            are not in [proof_caps], so IO-lattice narrowing is never affected. *)
         (match Hashtbl.find_opt env.cap_producer_ivars id with
          | Some cn_sp ->
            let forge_error p =
              Err.error ~code:Err.Code.cap_narrow_invalid env.errors ~span:cn_sp
                (render_parts [
                  MPCode "cap_narrow"; MPText " cannot produce "; MPCode ("Cap(" ^ p ^ ")");
                  MPText " — "; MPCode ("Cap(" ^ p ^ ")");
                  MPText " is a proof capability, not an IO capability.";
                  MPBreak;
                  MPText "hint: a proof capability may only be minted by a public function of its declaring module via ";
                  MPCode "mint_cap";
                  MPText "; cap_narrow only attenuates IO capabilities." ])
            in
            (match repr t with
             (* Tag is on the inner cap var: [a] binds directly to a proof cap. *)
             | TCon (p, []) when List.mem_assoc p env.proof_caps -> forge_error p
             (* Tag is on a whole-value var (laundered result): binds to Cap(P). *)
             | TCon ("Cap", [inner]) ->
               (match repr inner with
                | TCon (p, []) when List.mem_assoc p env.proof_caps -> forge_error p
                | TVar r2 ->
                  (* Cap of an unbound var: propagate the tag to the inner var. *)
                  (match !r2 with
                   | Unbound (id2, _) -> Hashtbl.replace env.cap_producer_ivars id2 cn_sp
                   | Link _ -> ())
                | _ -> ())
             (* Binds to another bare var: propagate the tag so the check fires
                when that var is eventually pinned. *)
             | TVar r2 ->
               (match !r2 with
                | Unbound (id2, _) -> Hashtbl.replace env.cap_producer_ivars id2 cn_sp
                | Link _ -> ())
             | _ -> ())
          | None -> ());
         (* A [linear x : a] opt-in is keyed on [a]'s id.  If [a] is linked to
            another unbound variable, that one becomes the representative the
            scheme will quantify, so the mark moves with it -- else the opt-in
            is silently lost and an opted-in function is refused at a linear
            type depending on which way the link happened to point. *)
         (if Hashtbl.mem env.linear_ok_ids id then
            match repr t with
            | TVar { contents = Unbound (id2, _) } ->
              Hashtbl.replace env.linear_ok_ids id2 ()
            | _ -> ());
         r := Link t
       end
     | Link _ -> assert false)  (* repr should have resolved links *)

  | TCon (n1, a1), TCon (n2, a2) ->
    if n1 = n2 && List.length a1 = List.length a2 then
      List.iter2 (unify env ~span ~reason ?provided) a1 a2
    else
      (report_mismatch env ~span ~reason ?provided t1 t2)

  | TArrow (a1, b1), TArrow (a2, b2) ->
    unify env ~span ~reason ?provided a1 a2;
    unify env ~span ~reason ?provided b1 b2

  | TTuple ts1, TTuple ts2 when List.length ts1 = List.length ts2 ->
    List.iter2 (unify env ~span ~reason ?provided) ts1 ts2

  | TRecord f1, TRecord f2 ->
    (* Defensive: check the sorted-name invariant when debug mode is on.
       A TRecord with unsorted fields produces confusing mismatches here
       because ns1 <> ns2 even if the field sets are identical. *)
    assert_trecord_sorted f1 "lhs";
    assert_trecord_sorted f2 "rhs";
    let ns1 = List.map fst f1 and ns2 = List.map fst f2 in
    if ns1 <> ns2 then
      report_mismatch env ~span ~reason ?provided t1 t2
    else
      List.iter2
        (fun (_, t1) (_, t2) -> unify env ~span ~reason ?provided t1 t2)
        f1 f2

  (* Reconcile a nominal record [TCon] with its structural [TRecord] form.
     A record type's *name* and its *field structure* are interchangeable in
     March's structural record model, but the two representations reach [unify]
     from different paths: [surface_ty] expands a record annotation to a
     [TRecord], while lighter-weight converters (notably [prebind_fn_scheme],
     which pre-binds cross-module function signatures in Pass 1 without record
     field information) leave the same type as a nominal [TCon(Name)].  When a
     cross-module qualified reference like `Cfg.Site` meets the owning module's
     own structural use, the two sides collide as `TCon` vs `TRecord`.  Expand
     the [TCon] side via the [expand_record_ref] hook (a no-op unless [Name]
     denotes a known record that is not also a colliding variant — variants and
     opaque types stay nominal) and retry; fall back to a genuine mismatch if it
     does not name an unambiguous record. *)
  | (TCon _ as tc), (TRecord _ as tr) | (TRecord _ as tr), (TCon _ as tc) ->
    (match expand_nominal_record env tc with
     | Some (TRecord _ as expanded) -> unify env ~span ~reason ?provided expanded tr
     | _ -> report_mismatch env ~span ~reason ?provided t1 t2)

  | TLin (l1, inner1), TLin (l2, inner2) when l1 = l2 ->
    unify env ~span ~reason ?provided inner1 inner2

  (* Transparent coercion: a linear/affine value is structurally the same
     type as its inner (unrestricted) type.  This allows e.g. a field of
     type [linear Int] to unify with an expected [Int] at a use site while
     still preserving the TLin wrapper for linearity tracking in let-bindings. *)
  | TLin (_, inner), other | other, TLin (_, inner) ->
    unify env ~span ~reason ?provided inner other

  | TNat n1, TNat n2 when n1 = n2 -> ()

  (* Structural unification for nat ops that could not be fully normalized
     (e.g. both sides have the same un-solved variable structure). *)
  | TNatOp (op1, a1, b1), TNatOp (op2, a2, b2) when op1 = op2 ->
    unify env ~span ~reason ?provided a1 a2;
    unify env ~span ~reason ?provided b1 b2

  (* Solve: one side is a concrete nat, the other is a partially-known op.
     E.g. TVar a + TNat 2 = TNat 5  →  a = 3. *)
  | TNatOp (op, a, b), TNat n ->
    solve_nat_eq env ~span ~reason ?provided op a b n
  | TNat n, TNatOp (op, a, b) ->
    solve_nat_eq env ~span ~reason ?provided op a b n

  (* Session-typed channels unify by checking their current session states match. *)
  | TChan r1, TChan r2 ->
    (* An unrefined `offer` continuation is a session STATE now
       ([SOfferPending]), so it would survive being unified into a fresh ref
       by itself; the guard stays because the diagnostic is the useful one:
       a `Chan(R, P)` annotation, an `if`/`match` join or a call-site parameter
       that meets it is told to match on the label, not that two session
       types mismatch.  (F5 residual, 2026-07-27; state form 2026-09-17.) *)
    if (not (r1 == r2)) && (session_pending !r1 || session_pending !r2) then
      Err.error ~code:Err.Code.session_offer_unrefined env.errors ~span (offer_unrefined_message "This channel")
    else if not (session_ty_equal !r1 !r2) then
      Err.error ~code:Err.Code.session_type_mismatch env.errors ~span
        (Printf.sprintf
           "Session type mismatch: expected channel at `%s` but found `%s`."
           (pp_session_ty !r1) (pp_session_ty !r2))

  | _ ->
    report_mismatch env ~span ~reason ?provided t1 t2

(** Solve a type-level nat equation: (op a b) = n.
    Handles exactly the cases where one operand is an unbound TVar and
    the other is a concrete TNat, so we can isolate the variable.
    Falls back to [report_mismatch] for anything more complex. *)
and solve_nat_eq env ~span ~reason ?provided op a b n =
  match op, a, b with
  (* a + k = n  →  a = n - k  (when n >= k) *)
  | Ast.NatAdd, TVar _, TNat k when n >= k ->
    unify env ~span ~reason ?provided a (TNat (n - k))
  (* k + a = n  →  a = n - k  (when n >= k) *)
  | Ast.NatAdd, TNat k, TVar _ when n >= k ->
    unify env ~span ~reason ?provided b (TNat (n - k))
  (* a * k = n  →  a = n / k  (when k divides n) *)
  | Ast.NatMul, TVar _, TNat k when k <> 0 && n mod k = 0 ->
    unify env ~span ~reason ?provided a (TNat (n / k))
  (* k * a = n  →  a = n / k  (when k divides n) *)
  | Ast.NatMul, TNat k, TVar _ when k <> 0 && n mod k = 0 ->
    unify env ~span ~reason ?provided b (TNat (n / k))
  | _ ->
    report_mismatch env ~span ~reason ?provided (TNatOp (op, a, b)) (TNat n)

(* =================================================================
   §2  Surface-type → internal-type conversion
   ================================================================= *)

(** Whether [steps] contain `may crash` or a crash branch anywhere.  Crash
    branches are projected only by the `@[endpoints]` generator
    (lib/desugar/desugar_endpoints.ml); the `Chan(Role, Proto)` API refuses
    such a protocol rather than run a projection that ignores them
    (2026-09-20 crash branches). *)
let rec has_crash_branches (steps : Ast.protocol_step list) : bool =
  List.exists
    (function
      | Ast.ProtoMayCrash _ | Ast.ProtoCrashOr _ -> true
      | Ast.ProtoLoop (inner, _) -> has_crash_branches inner
      | Ast.ProtoChoice (_, brs) ->
        List.exists (fun (l, arm) -> l.Ast.txt = "crash" || has_crash_branches arm) brs
      | Ast.ProtoMsg _ | Ast.ProtoStop _ | Ast.ProtoRoleNeeds _ -> false)
    steps

(** True when [name] denotes a variant/sum type in scope — i.e. some
    constructor has it as its parent type ([ci_type], matched bare or as a
    [.name] suffix since [ci_type] may be module-qualified).

    Records register in [env.records] under their BARE name globally, so a
    user's `type Color = Red | Green | Blue` collides in that flat namespace
    with, e.g., stdlib `Plot.Color = { r, g, b }`.  Without this guard the
    record-structural expansion below (and in [register_impl_shape]) rewrites
    the variant's `impl Eq(Color)` to the record's `TRecord{r,g,b}` shape,
    which then never matches the variant's `TCon("Color")` dispatch target —
    the derived impl becomes invisible and the type "does not implement Eq".
    A variant type is never itself a record, so suppressing the expansion for
    variant names only removes incorrect expansions. *)
let name_is_variant env name = ctors_name_a_variant env.ctors name

(* Names of records currently being structurally expanded on the current
   [surface_ty]/[expand_record] call path. A record field that mentions its
   own type — directly (`type Tr = { left : Option(Tr), ... }`) or through a
   cycle of records — would otherwise make expansion require expanding the
   same record again, forever: expanding [Tr]'s fields expands [Option(Tr)],
   which expands its argument [Tr], which re-enters the very branch that
   started this. Shared between [surface_ty] and [expand_record] since a
   chain can pass through either. *)
let expanding_records : StringSet.t ref = ref StringSet.empty

(* Transparent aliases currently being expanded on the current [surface_ty]
   call path, innermost first. Unlike a record, an alias has no nominal form to
   fall back on: `type A = A`, or a cycle `type A = B` / `type B = A`, names no
   type at all, and expanding it would recurse forever. On a repeat [surface_ty]
   reports the cycle and returns [TError]. No source syntax builds an alias
   today (the only ones are `@[endpoints]`'s generated `Entry`s, whose
   right-hand sides are never aliases), so this guards whoever adds alias
   syntax rather than anything reachable now. *)
let expanding_aliases : string list ref = ref []

(** [Some "<Actor>_Msg"] when [name] is `<Actor>.Msg` (or `M.<Actor>.Msg`)
    for an actor whose message constructors are in scope, and no real type of
    that name exists. *)
let actor_msg_alias env (name : string) : string option =
  match actor_msg_alias_target name with
  | None -> None
  | Some _ when lookup_type name env <> None -> None
  | Some target ->
    if StrMap.exists (fun _ cis ->
        List.exists (fun ci -> ci.ci_is_actor_msg && ci.ci_type = target) cis)
        env.ctors
    then Some target else None

(** The key a QUALIFIED type name [name] (`A.T`) is registered under when it
    is written relative to an enclosing module, or [None] when [name] resolves
    as written (or is bare, or names nothing under any enclosing module).

    Pass 1 seeds a submodule's public types under its path from the ENTRY
    module's top level (`Outer.A.T`), and a nested module's export step adds
    only the BARE `T`; so `A.T` written inside `Outer` (or inside a sibling of
    `A`) found nothing, though the same reference one level up -- where the
    path IS `A` -- worked.  A name resolves the way a lexical reference does:
    innermost enclosing module first.  [env.cap_qual_prefix] is that module's
    path (`Outer.B` inside `mod B` of `mod Outer`).  Every `@[endpoints]`
    protocol in a nested, library or stdlib module hits this: its generated
    modules name each other's types (`P_Msg.Msg`, `P_A.Entry`) relatively
    (specs/progress/2026-10-03-endpoints-protocol-in-nested-module.md). *)
let lexical_qualified_type env (name : string) : string option =
  (* Types and aliases only: [env.records] can hold a qualified key that
     names no type -- a nested module re-exports every bare record key in its
     scope that matches one of its public names, so a role module's `Entry`
     alias exports the stdlib's unrelated `Entry` record as `P_A.Entry`. *)
  let known k = StrMap.mem k env.types || StrMap.mem k env.ty_aliases in
  if env.cap_qual_prefix = "" || not (String.contains name '.') || known name then None
  else
    let rec go prefix =
      let k = prefix ^ "." ^ name in
      if known k then Some k
      else match String.rindex_opt prefix '.' with
        | Some i -> go (String.sub prefix 0 i)
        | None -> None
    in
    go env.cap_qual_prefix

(** Convert a surface [Ast.ty] to an internal [ty].
    [tvars] accumulates a mapping from type-variable *names* to fresh
    unification-variable ids (so that two mentions of [a] in the same
    annotation get the same variable). *)
let rec surface_ty env ~(tvars : (string * ty) list ref) (s : Ast.ty) : ty =
  match s with
  | Ast.TyCon (name, args) when lexical_qualified_type env name.Ast.txt <> None ->
    let q = Option.get (lexical_qualified_type env name.Ast.txt) in
    surface_ty env ~tvars (Ast.TyCon ({ name with Ast.txt = q }, args))
  | Ast.TyCon (name, args) ->
    (* Skip when [caller = ""]: either no fn has been entered yet, or (since
       Fix round 1) a callerless surface_ty call site — interface method
       signature, impl header/when-constraint — deliberately blanked
       [current_decl] via [with_no_caller] to suppress recording rather than
       misattribute to an unrelated function. Either way, an empty caller was
       never a meaningful attribution for `forge search --callers`. *)
    (if String.contains name.Ast.txt '.' && !(env.current_decl) <> "" then
       env.refs := { callee = name.Ast.txt;
                     caller = !(env.current_decl);
                     ref_kind = `TypeRef;
                     ref_file = name.Ast.span.Ast.file;
                     ref_line = name.Ast.span.Ast.start_line } :: !(env.refs));
    (* Special case: Chan(Role, Proto) — session-typed channel endpoint.
       Users write Chan(RoleName, ProtoName) in type annotations.
       The parser produces TyCon("Chan", [TyCon("Role",[]), TyCon("Proto",[])]).
       We intercept this before the normal type-lookup path. *)
    (match name.txt, args with
     | "Chan", [Ast.TyCon (role, []); Ast.TyCon (proto, [])] ->
       (match StrMap.find_opt proto.txt env.protocols with
        | None ->
          Err.error ~code:Err.Code.unknown_protocol env.errors ~span:proto.span
            (Printf.sprintf "I don't know a protocol called `%s`." proto.txt);
          TChan (ref SError)
        | Some pi when has_crash_branches pi.pi_def.Ast.proto_steps ->
          Err.error ~code:Err.Code.protocol_crash_branches env.errors ~span:proto.span
            (Printf.sprintf
               "Protocol `%s` has crash branches, and those are only supported \
                with `@[endpoints]`: `Chan(%s, %s)` cannot run them."
               proto.txt role.txt proto.txt);
          TChan (ref SError)
        | Some pi ->
          (match List.assoc_opt role.txt pi.pi_projections with
           | None ->
             Err.error ~code:Err.Code.unknown_role env.errors ~span:role.span
               (Printf.sprintf
                  "Protocol `%s` has no role called `%s`.\n\
                   Known roles: %s"
                  proto.txt role.txt
                  (String.concat ", " (List.map fst pi.pi_projections)));
             TChan (ref SError)
           | Some sty ->
             TLin (Ast.Linear, TChan (ref sty))))
     | _ when StrMap.mem name.Ast.txt env.ty_aliases ->
       (* A transparent alias stands for its right-hand side: substitute the
          arguments for the parameters and resolve THAT, so the alias is the
          type it names at every later step -- unification, and the
          `always_linear` discipline, which reads the expanded type's name. *)
       let params, rhs = StrMap.find name.Ast.txt env.ty_aliases in
       let args' = List.map (surface_ty env ~tvars) args in
       if List.mem name.Ast.txt !expanding_aliases then begin
         (* [expanding_aliases] is innermost-first; the cycle is the stretch
            from this alias's outer occurrence in to here. *)
         let rec upto acc = function
           | [] -> acc
           | n :: _ when n = name.Ast.txt -> n :: acc
           | n :: rest -> upto (n :: acc) rest
         in
         let cycle = upto [] !expanding_aliases @ [name.Ast.txt] in
         Err.error ~code:Err.Code.recursive_type_alias env.errors ~span:name.Ast.span
           (Printf.sprintf "`%s` is defined in terms of itself (%s)."
              name.Ast.txt
              (String.concat " -> " (List.map (Printf.sprintf "`%s`") cycle)));
         TError
       end else if List.length params <> List.length args' then begin
         Err.error ~code:Err.Code.type_arity env.errors ~span:name.Ast.span
           (Printf.sprintf "`%s` expects %d type argument(s) but got %d."
              name.Ast.txt (List.length params) (List.length args'));
         TError
       end else begin
         let saved = !tvars in
         List.iter2 (fun pname arg -> tvars := (pname, arg) :: !tvars) params args';
         let outer = !expanding_aliases in
         expanding_aliases := name.Ast.txt :: outer;
         let t =
           Fun.protect
             ~finally:(fun () -> expanding_aliases := outer)
             (fun () -> surface_ty env ~tvars rhs)
         in
         tvars := saved;
         t
       end
     | _ when args = [] && actor_msg_alias env name.Ast.txt <> None ->
       (* `<Actor>.Msg` (DD step 6, plan II.4.8): the source name of an
          actor's message type, a typecheck-side alias of the lowered
          `<Actor>_Msg` its message constructors already have. *)
       (match actor_msg_alias env name.Ast.txt with
        | Some t -> TCon (t, [])
        | None -> TError)
     | "Chan", _ when name.txt = "Chan" ->
       Err.error ~code:Err.Code.type_arity env.errors ~span:name.span
         "Chan expects exactly two type arguments: Chan(RoleName, ProtocolName)";
       TChan (ref SError)
     | _ ->
    let env_loaded, arity = match lookup_type name.txt env with
      | Some a -> env, a
      | None   ->
        (* Try qualified module resolution: "Mod.Type" *)
        match resolve_qualified_type name.txt env with
        | env', Some a -> env', a
        | _ ->
          Err.error ~code:Err.Code.unknown_qualified_name env.errors ~span:name.span
            (qualified_error_msg name.txt env);
          env, 0
    in
    (* March uses a single global type namespace: a type declared inside a
       module has its *bare* name as its canonical identity.  Both the type's
       own registration and the result type of its constructors use the bare
       form (see the constructor `ci_type = name.txt` sites and the "ci_type is
       the BARE type name" note in Pass 1b).  A *qualified* reference like
       `Token.Token` from outside the module must therefore resolve to the SAME
       nominal `TCon` as the bare `Token`, otherwise a value produced inside the
       module (bare) fails to unify against the qualified annotation with the
       baffling "expected `Token.Token` but got `Token`".  Canonicalize the
       constructor name to its bare suffix whenever that suffix denotes a type
       of the same arity in scope. *)
    let canon_name =
      (* [canon_type_name] takes the component after the LAST '.' (the
         type's own name) as the bare suffix; it is shared with the builtin
         signatures' [canon_qualified_tcons] so both routes agree.
         Look up the bare suffix in [env_loaded] (not the pre-resolution
         [env]): when [name.txt] needed [resolve_qualified_type] to lazily
         load its module, [load_module_into_env]'s [ExType]/[ExRecord] arms
         seed the BARE name too (first-wins — see their doc comment), so an
         opaque `ptype` seen for the first time via qualification (e.g.
         `RRB.Vec`, never promoted to the outer bare namespace since it's
         never `Public`) still canonicalizes correctly.  Looking this up in
         the original [env] would always miss for such a type, silently
         skipping canonicalization and leaving a real value (whose actual
         type uses the bare `TCon`) unable to unify against the qualified
         annotation. *)
      canon_type_name env_loaded name.txt arity
    in
    let args' = List.map (surface_ty env ~tvars) args in
    (* `Pid(a)` is the actor pid, a builtin whose one parameter is the actor's
       state type ([t_pid]); the bare name `Pid` in scope is the stdlib's
       `Global_pid.Pid` RECORD (arity 0), a flat-namespace collision.  The
       one-argument spelling is the builtin's -- it is how `is_alive : Pid(a)
       -> Bool` and the builtin `Down` constructor's payload are typed -- so
       it must not be measured against the record's arity.  Reported nowhere
       before 2026-09-13 only because the `Down` constructor's table carries
       a dummy span and such diagnostics were filtered out. *)
    let actor_pid = name.txt = "Pid" && List.length args' = 1 in
    if List.length args' <> arity && not actor_pid then
      Err.error ~code:Err.Code.type_arity env.errors ~span:name.span
        (Printf.sprintf "`%s` expects %d type argument(s) but got %d."
           name.txt arity (List.length args'));
    (* If this is a named record type, expand it structurally so that
       type annotations like `: Point` unify correctly with record literals.
       Skip when the name also denotes a variant (see [name_is_variant]): the
       local variant shadows a same-named record from another module. *)
    (match StrMap.find_opt name.txt env.records with
     | Some (params, field_decls)
       when List.length params = List.length args'
            && not (name_is_variant env name.txt) ->
       if StringSet.mem name.txt !expanding_records then
         (* Already expanding this record on the current path — a directly
            or mutually self-referential field. Stop unfolding and return
            the plain nominal type instead of recursing forever; [unify]'s
            lazy TCon<->TRecord reconciliation (via [expand_record_ref])
            expands one level on demand wherever a field is actually used,
            so this loses no precision the caller needed right now. *)
         TCon (canon_name, args')
       else begin
         let saved = !tvars in
         List.iter2 (fun pname arg -> tvars := (pname, arg) :: !tvars) params args';
         expanding_records := StringSet.add name.txt !expanding_records;
         let flds =
           Fun.protect
             ~finally:(fun () ->
                 expanding_records := StringSet.remove name.txt !expanding_records)
             (fun () ->
                List.map (fun (fn, fty) -> (fn, surface_ty env ~tvars fty)) field_decls)
         in
         tvars := saved;
         TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds)
       end
     | _ ->
       (* For qualified names not in env.records, check the module registry for
          ExRecord entries. This handles record types in modules loaded lazily
          (not pre-registered via stdlib_file_list) so cross-module field access
          and structural unification work correctly without env threading. *)
       let registry_record =
         match split_qualified name.txt with
         | None -> None
         | Some (mod_name, member) ->
           let open March_modules.Module_registry in
           (match ensure_loaded mod_name with
            | None -> None
            | Some exports ->
              List.fold_left (fun acc entry ->
                match acc with
                | Some _ -> acc
                | None ->
                  (match entry.ex_kind with
                   | ExRecord (arity, fields) when entry.ex_name = member ->
                     let params = List.init arity
                       (fun i -> Printf.sprintf "$t%d" i) in
                     (* Thread an env enriched with the DEFINING module's exports
                        so the record's field types — stored as UNRESOLVED surface
                        types that name sibling types by their BARE name (`scope :
                        UniqueScope`) — resolve against those siblings' bare names.
                        Without this the fields would be expanded in the referrer's
                        env, which has only the qualified sibling names, failing
                        with a bogus "I cannot find `UniqueScope`" pointing at the
                        definer's field span.  [load_module_into_env] seeds both
                        the qualified and bare forms (first-wins), so this cannot
                        clobber a name the referrer already bound. *)
                     let fenv = load_module_into_env mod_name exports env in
                     Some (params, fields, fenv)
                   | _ -> None)
              ) None exports.me_entries)
       in
       (match registry_record with
        | Some (params, field_decls, fenv)
          when List.length params = List.length args'
               && not (name_is_variant env name.txt) ->
          let saved = !tvars in
          List.iter2 (fun pname arg -> tvars := (pname, arg) :: !tvars) params args';
          let flds = List.map (fun (fn, fty) -> (fn, surface_ty fenv ~tvars fty)) field_decls in
          tvars := saved;
          TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds)
        | _ ->
          (* Normalize built-in unit/bool so surface annotations unify with internal reps *)
          match canon_name with
          | "Unit" -> t_unit
          | _ -> TCon (canon_name, args'))))

  | Ast.TyVar name ->
    (match List.assoc_opt name.txt !tvars with
     | Some t -> t
     | None   ->
       let t = fresh_var env.level in
       tvars := (name.txt, t) :: !tvars;
       t)

  | Ast.TyArrow (a, b) ->
    TArrow (surface_ty env ~tvars a, surface_ty env ~tvars b)

  | Ast.TyTuple ts ->
    TTuple (List.map (surface_ty env ~tvars) ts)

  | Ast.TyRecord flds ->
    let flds' = List.map (fun (n, t) -> (n.Ast.txt, surface_ty env ~tvars t)) flds in
    TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds')

  | Ast.TyLinear (lin, t) ->
    TLin (lin, surface_ty env ~tvars t)

  | Ast.TyNat n  -> TNat n
  | Ast.TyNatOp (op, a, b) ->
    TNatOp (op, surface_ty env ~tvars a, surface_ty env ~tvars b)

  | Ast.TyChan (role, proto) ->
    (* Look up the protocol and project onto the given role. *)
    (match StrMap.find_opt proto.txt env.protocols with
     | None ->
       Err.error ~code:Err.Code.unknown_protocol env.errors ~span:proto.span
         (Printf.sprintf "I don't know a protocol called `%s`." proto.txt);
       TChan (ref SError)
     | Some pi when has_crash_branches pi.pi_def.Ast.proto_steps ->
       Err.error ~code:Err.Code.protocol_crash_branches env.errors ~span:proto.span
         (Printf.sprintf
            "Protocol `%s` has crash branches, and those are only supported \
             with `@[endpoints]`: the channel API cannot run them."
            proto.txt);
       TChan (ref SError)
     | Some pi ->
       (match List.assoc_opt role.txt pi.pi_projections with
        | None ->
          Err.error ~code:Err.Code.unknown_role env.errors ~span:role.span
            (Printf.sprintf
               "Protocol `%s` has no role called `%s`.\n\
                Known roles: %s"
               proto.txt role.txt
               (String.concat ", " (List.map fst pi.pi_projections)));
          TChan (ref SError)
        | Some sty ->
          TChan (ref sty)))
  (* Carry the refinement in the internal type.  It is transparent to
     unification (repr strips it), so base-type inference is unchanged; the
     predicate is read only at the deliberate obligation sites. *)
  | Ast.TyRefine (base, binder, pred) ->
    let b = match binder with None -> "_" | Some n -> n.Ast.txt in
    TRefine (surface_ty env ~tvars base, b, pred)

(** Instantiate a constructor's type at the current level.
    Creates fresh unification variables for each type parameter of the
    parent type, then converts the constructor's argument surface-types
    using those variables.  Returns [(arg_tys, result_ty)]:
    - [arg_tys]   : the expected type of each constructor argument
    - [result_ty] : the type the fully-applied constructor produces *)
let instantiate_ctor env (ci : ctor_info) : ty list * ty =
  (* One fresh unification variable per type parameter *)
  let fresh_pairs = List.map (fun name -> (name, fresh_var env.level)) ci.ci_params in
  let tvars = ref fresh_pairs in
  (* Convert each argument's surface type, substituting the fresh vars *)
  let arg_tys = List.map (surface_ty env ~tvars) ci.ci_arg_tys in
  (* Build TCon(ParentType, [fresh_a; fresh_b; …]) *)
  let result_ty = TCon (ci.ci_type, List.map snd fresh_pairs) in
  (arg_tys, result_ty)

(** Try to expand a [TCon] of a named record type to [TRecord].
    Returns the [TRecord] type if the name is a known record def, else [None].
    Falls back to the module registry for cross-module record types that were
    loaded lazily (not pre-registered in env.records via stdlib_file_list). *)
let expand_record env ty =
  match repr ty with
  | TRecord _ as t -> Some t
  | TCon (name, args) ->
    let record_info =
      match StrMap.find_opt name env.records with
      | Some _ as r -> r
      | None ->
        (* Qualified type like "NodeIdentity.Identity": check registry for ExRecord *)
        (match split_qualified name with
         | None -> None
         | Some (mod_name, member) ->
           let open March_modules.Module_registry in
           match ensure_loaded mod_name with
           | None -> None
           | Some exports ->
             List.fold_left (fun acc entry ->
               match acc with
               | Some _ -> acc
               | None ->
                 match entry.ex_kind with
                 | ExRecord (arity, fields) when entry.ex_name = member ->
                   let params = List.init arity (fun i ->
                     Printf.sprintf "$t%d" i) in
                   Some (params, fields)
                 | _ -> None
             ) None exports.me_entries)
    in
    (match record_info with
     | Some (params, field_decls) when List.length params = List.length args ->
       if StringSet.mem name !expanding_records then
         (* Same self-referential-record guard as [surface_ty]'s own
            record-expansion branch (they share [expanding_records]): don't
            re-expand a record already being expanded on this path. *)
         Some (TCon (name, args))
       else begin
         let tvars = ref (List.combine params args) in
         expanding_records := StringSet.add name !expanding_records;
         let flds =
           Fun.protect
             ~finally:(fun () ->
                 expanding_records := StringSet.remove name !expanding_records)
             (fun () ->
                List.map (fun (fn, fty) -> (fn, surface_ty env ~tvars fty)) field_decls)
         in
         Some (TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds))
       end
     | _ -> None)
  | _ -> None

(* Wire up the forward ref so [unify] (defined earlier) can reconcile a nominal
   record [TCon] with its structural [TRecord] form.  Guard with
   [name_is_variant] exactly as [surface_ty]'s own record-expansion does: in a
   global-namespace collision a variant and a record can share a printed name
   (and the record leaks into [env.records] under that bare name), so a bare
   [TCon] naming the *variant* must NOT be expanded into the colliding record's
   structure — that would silently unify two genuinely distinct types and
   swallow the "two distinct types share the name" diagnostic. *)
let () = expand_record_ref := (fun env ty ->
  match repr ty with
  | TCon (name, _) when name_is_variant env name -> None
  | _ -> expand_record env ty)

(** A type whose values must be consumed exactly once: a [TLin Linear] wrapper
    (session channels excluded; they are tracked affine) or an
    [always_linear] type. *)
let is_linear_ty env t =
  match repr t with
  | TLin (Ast.Linear, inner) ->
    (match repr inner with TChan _ -> false | _ -> true)
  | TCon (name, _) -> resolves_always_linear name env
  | _ -> false

(** The linearity a record FIELD of type [fty] carries: a [linear]/[affine]
    qualifier ([TLin]); an [always_linear] type, which is [Linear] wherever it
    is stored; or a type that HOLDS a linear value by ownership -- a tuple
    component, a list element, a variant payload, as [holds_linear] decides for
    a binding -- which is [Linear] too (2026-09-19).  Without that last case a
    field such as `slot : Option(Parked_B)` was an ordinary field: an actor
    could overwrite it with `None` and drop a live value unchecked, which is
    exactly the move the per-field rules exist to refuse.  A field whose type
    is itself a record is not promoted here, for the reason [holds_linear]
    gives: its own linear fields would need their own sentinels, and promoting
    the whole nested record would count every read of an ordinary inner field
    as a use of it.  [None] for an ordinary field. *)
let rec field_linearity env fty =
  match repr fty with
  | TLin (lin, _) when lin <> Ast.Unrestricted -> Some lin
  | TCon (name, _) when resolves_always_linear name env -> Some Ast.Linear
  | TTuple _ | TCon _ when contains_linear ~records:false env fty -> Some Ast.Linear
  | _ -> None

(** A type that is linear or holds a linear value by ownership: a tuple
    component, a list element, an ADT payload, a record field.  Not the type
    argument of an opaque handle ([Pid], [Vault], [Task]), which refers to
    values rather than holding one. *)
and contains_linear ?(records = true) env t =
  is_linear_ty env t
  || (match repr t with
      | TTuple ts -> List.exists (contains_linear ~records env) ts
      | TCon (n, args) when n = "List" || name_is_variant env n ->
        List.exists (contains_linear ~records env) args
      | TRecord flds when records ->
        List.exists (fun (_, ft) -> field_linearity env ft <> None) flds
      | _ -> false)

(** The linearity a BINDING of type [t] gets by what it holds: an
    [always_linear] type, or a tuple, list or ADT value holding a linear value,
    is [Linear].  A record is not: its linear fields are tracked per field
    ([bind_linear_field_sentinels]), and making the record itself linear would
    count every field read as a use of the whole. *)
let holds_linear env t =
  match repr t with
  | TLin _ | TRecord _ -> false
  | _ -> contains_linear ~records:false env t

(** Register per-field linear sentinels for a named record variable [varname].
    When [ty] is or expands to a TRecord with linear fields, adds phantom
    ["varname#fieldname"] entries to env.lin so that EField accesses on
    that variable can detect double-use of individual linear fields. *)
let bind_linear_field_sentinels varname ty env =
  match expand_record env (repr ty) with
  | Some (TRecord flds) ->
    List.fold_left (fun acc_env (fname, fty) ->
        match field_linearity env fty with
        | Some lin ->
          let key = varname ^ "#" ^ fname in
          let le = { le_name = key; le_lin = lin; le_used = ref false; le_first_use = ref None;
                     le_pending = None; le_dup = ref None; le_mixed = ref None;
                     le_where = ref []; le_exit = ref []; le_poisoned = ref false } in
          { acc_env with lin = le :: acc_env.lin }
        | _ -> acc_env
      ) env flds
  | _ -> env
