(** Pattern-match compilation: decision-tree matrix compiler, guards, join
    points, and pattern-tag encoding (Wave 3 Task 9: split out of [Lower]).

    Moved verbatim from lower.ml's match-lowering section. These functions
    were originally part of lower.ml's single big [let rec ... and ...]
    chain together with [lower_expr]; two call directions exist between
    that chain and this module:
      - INTO this module: lower.ml's [EBlock]/[ELet] arm calls
        [collect_pat_names] (a pure function of [Ast.pattern] — no cycle);
        its [EMatch] arm calls [lower_match].
      - OUT of this module, back into [lower_expr]: [lower_branch_body_with_pat]
        and the guarded-match path in [lower_match] both call [lower_expr] to
        lower branch bodies/guards.
    That second direction is a genuine (small: 3 call sites) mutual-recursion
    edge back into lower.ml's [lower_expr]. Rather than leaving the whole
    match-compilation cluster in lower.ml (the plan's boundary explicitly
    assigns it here) or duplicating [lower_expr] to dodge the cycle
    (forbidden), the cycle is broken with a forward reference — the same
    idiom lower.ml already uses for [_ensure_module_lowered]:
    [_lower_expr_ref] is a mutable function pointer, installed once by
    lower.ml (via [Lower_match.install_lower_expr]) right after [lower_expr]
    is defined. This is a pure wiring change (an indirect call through a ref
    cell instead of a direct same-file call) — it does not alter any
    lowering decision or the TIR produced. *)

module Ast = March_ast.Ast

(** Forward reference to [Lower.lower_expr] ([env -> Ast.expr -> Tir.expr]),
    installed once lower.ml has defined [lower_expr] (mirrors
    [Lower_state._ensure_module_lowered]'s wiring). Breaks the
    lower.ml <-> lower_match.ml mutual-recursion cycle described in this
    file's module doc without duplicating [lower_expr] here or leaving this
    cluster in lower.ml. *)
let _lower_expr_ref : (Lower_state.env -> Ast.expr -> Tir.expr) ref =
  ref (fun _ _ -> failwith "lower_match: lower_expr not yet installed")

let install_lower_expr (f : Lower_state.env -> Ast.expr -> Tir.expr) : unit =
  _lower_expr_ref := f

let lower_expr (env : Lower_state.env) (e : Ast.expr) : Tir.expr =
  !_lower_expr_ref env e

(** True if [pat] matches everything without discriminating (wildcard / var / as-var). *)
let rec is_trivial_pat : Ast.pattern -> bool = function
  | Ast.PatWild _ | Ast.PatVar _ -> true
  | Ast.PatAs (p, _, _) -> is_trivial_pat p
  | _ -> false

(** True if [pat] contains an or-pattern anywhere.  Used by [lower_match] to
    decide whether an arm body needs hoisting into a shared join point:
    [expand_or_rows] (below) splits a row headed by an or-pattern into one
    row per alternative, all referencing the SAME lowered body expression, so
    without hoisting that body would be duplicated once per alternative in
    the emitted decision tree. *)
let rec pat_has_or : Ast.pattern -> bool = function
  | Ast.PatOr _ -> true
  | Ast.PatAs (p, _, _) -> pat_has_or p
  | Ast.PatCon (_, ps) | Ast.PatAtom (_, ps, _) | Ast.PatTuple (ps, _) ->
    List.exists pat_has_or ps
  | Ast.PatRecord (fs, _) -> List.exists (fun (_, p) -> pat_has_or p) fs
  | Ast.PatWild _ | Ast.PatVar _ | Ast.PatLit _ -> false

(** Wrap [body] with bindings from a trivial pattern on [scrut].
    Handles PatVar (bind), PatWild (no-op), PatAs (bind outer name + recurse). *)
let rec bind_trivial_pat (env : Lower_state.env) (scrut : Tir.atom) (pat : Ast.pattern) (body : Tir.expr) : Tir.expr =
  match pat with
  | Ast.PatWild _ -> body
  | Ast.PatVar n ->
    (* Use the typechecker's type for this variable (via its source span) so that
       field accesses on pattern-matched records resolve to the correct offsets.
       Without this, record field lookups fall back to index 0 for all fields. *)
    let resolved_ty = Lower_state.ty_of_span env n.span in
    let v : Tir.var = { v_name = n.txt; v_ty = resolved_ty; v_lin = Tir.Unr } in
    Tir.ELet (v, Tir.EAtom scrut, body)
  | Ast.PatAs (inner, n, _) ->
    let v : Tir.var = { v_name = n.txt; v_ty = Lower_state.ty_of_span env n.span; v_lin = Tir.Unr } in
    let named_body = Tir.ELet (v, Tir.EAtom scrut, body) in
    bind_trivial_pat env scrut inner named_body
  | _ -> body

(** Format an [Ast.span] as "file:line:col" for a fail-loudly diagnostic. *)
let string_of_pat_span (sp : Ast.span) : string =
  Printf.sprintf "%s:%d:%d" sp.Ast.file sp.Ast.start_line sp.Ast.start_col

(** Extract the span of any pattern, for fail-loudly diagnostics. *)
let span_of_pat : Ast.pattern -> Ast.span = function
  | Ast.PatWild sp         -> sp
  | Ast.PatVar  name       -> name.Ast.span
  | Ast.PatCon  (name, _)  -> name.Ast.span
  | Ast.PatAtom (_, _, sp) -> sp
  | Ast.PatTuple (_, sp)   -> sp
  | Ast.PatLit  (_, sp)    -> sp
  | Ast.PatRecord (_, sp)  -> sp
  | Ast.PatAs   (_, _, sp) -> sp
  | Ast.PatOr   (_, sp)    -> sp

(** Return the string tag and sub-pattern list for a pattern that discriminates.
    PatCon → (tag, subs); PatTuple → ("$Tuple", subs); PatLit → (repr, []).
    Returns None for trivial patterns.

    [br_tag] namespace (see also llvm_emit.ml's [emit_case] decoder, which
    must be kept in sync with every case below):
      - ADT ctor / atom-ctor tags  → bare or dotted name, first char 'A'-'Z'
        (e.g. "Some", "Inline.Text")
      - Tuple                      → "$TupleN"           (leading '$')
      - Int literal                → decimal digits, optional leading '-'
      - Bool literal                → "true" / "false"   (lowercase)
      - String literal              → "\"..\""            (leading '"')
      - Atom literal / pattern     → ":name"             (leading ':')
      - Float literal (NEW)        → "#<hex-float>"      (leading '#') —
        see below. *)
let pat_tag_and_subs (env : Lower_state.env) (scrut : Tir.atom) (pat : Ast.pattern)
  : (string * Ast.pattern list) option =
  match pat with
  | Ast.PatCon ({ txt = tag; _ }, subs) ->
    (* Keep the constructor pattern's FULL text (e.g. "Inline.Text", "T.B").
       A type-qualified pattern carries its own disambiguating qualifier; codegen
       (qualified_br_key in llvm_emit) resolves it to the right ctor_info key.
       Stripping to the bare name here loses that qualifier, so a bare ctor name
       that collides with another type's constructor (e.g. stdlib Xml.XmlNode.Text)
       resolves ambiguously to the wrong tag when the scrutinee type was not
       propagated to codegen.

       Collision-conditional module qualification (Task 4 of
       docs/superpowers/plans/2026-07-21-ctor-module-identity.md — the
       pattern-side counterpart of Task 3's [ECon]/[EAlloc] fix in
       [Lower.lower_expr]): a BARE tag (no '.' — the user wrote a plain
       `Shared`, not a qualified `DcA.Thing.Shared`) matched against a
       scrutinee whose [Tir.ty] is a colliding [TCon(type_name, _)] (per
       the whole plan's "TCon stays bare" invariant, [type_name] alone
       cannot distinguish DcA.Thing from DcB.Thing) is qualified here by
       [env.mod_prefix] — the LEXICAL enclosing module of the match
       expression THIS pattern belongs to — into the SAME
       "Mod.Type.Ctor" form Task 3 already produces for construction.
       Once qualified upstream (here, before this pattern ever becomes a
       TIR [branch.br_tag]), [llvm_case.ml]'s [qualified_br_key] takes its
       exact-match [Hashtbl.mem ctx.Llvm_ctx.ctor_info br_tag] branch —
       already correct, no change needed there. Gated on membership in the
       NARROW [Lower_state.shared_ctor_collision_tbl] (Task 5.5 — public,
       impl-bearing collisions only, mirrors Task 3's [ECon] gate exactly),
       NOT the broad [Collision_set.is_colliding]: a stdlib structural-interop
       [ptype] (two [ptype Seq(a) = Seq(a)] declarations relied on for a
       cross-module hand-off) collides by [Collision_set]'s measure but must
       NOT be qualified here — construction (in the producing module) and this
       consuming pattern must both stay bare so they agree via [ctor_entry]'s
       suffix resolver rather than qualifying to two DIFFERENT modules. A
       non-colliding (or non-public / impl-less colliding) type's tag is
       unconditionally the old bare form, so ordinary programs are
       byte-identical.

       A QUALIFIED tag the user wrote directly (already contains '.') is
       NOT necessarily already in the "Mod.Type.Ctor" form [qualified_br_key]
       exact-matches: the documented qualified-pattern syntax
       (specs/lang/pattern-matching.md "Qualified Constructor Patterns",
       `Http.Ok(resp)` / `Json.Ok(data)`) writes a MODULE prefix, i.e. TWO
       segments ("B.Ok"), while construction above produces THREE
       ("B.Result.Ok") — a bare string compare between those never
       succeeds, so a spec-legal qualified pattern on a public, impl-bearing
       double collision silently mismatched every arm (P0:
       builtin-ctor-collision-gap, 2026-07-22). Try the qualifier
       (everything before the LAST '.') as a MODULE prefix the same way the
       bare branch below does; only when that resolves via
       [Lower_state.shared_ctor_collision_type] is the tag re-expanded to
       the 3-segment form. This is safe for the two cases that must stay
       untouched: an already-3-segment tag's qualifier is "Mod.Type." (not
       a real module prefix key), so the lookup misses and the tag passes
       through verbatim — already an exact [ctor_info] hit; and a genuine
       `Type.Ctor` reference (e.g. `List.Cons`, "List" a type, not a
       module) likewise has no [shared_ctor_collision_type] entry and is
       unchanged. *)
    let tag =
      match String.rindex_opt tag '.' with
      | None ->
        (match scrut with
         | Tir.AVar v ->
           (match v.Tir.v_ty with
            | Tir.TCon (type_name, _)
              when env.Lower_state.mod_prefix <> ""
                   && Lower_state.shared_ctor_collision_type
                        env.Lower_state.mod_prefix tag <> None ->
              env.Lower_state.mod_prefix ^ type_name ^ "." ^ tag
            | _ -> tag)
         | _ -> tag)
      | Some i ->
        let qual = String.sub tag 0 (i + 1) in
        let short_tag = String.sub tag (i + 1) (String.length tag - i - 1) in
        (match Lower_state.shared_ctor_collision_type qual short_tag with
         | Some _ ->
           (match scrut with
            | Tir.AVar { Tir.v_ty = Tir.TCon (type_name, _); _ } ->
              qual ^ type_name ^ "." ^ short_tag
            | _ -> tag)
         | None -> tag)
    in
    Some (tag, subs)
  | Ast.PatTuple (subs, _) ->
    Some (Tir_names.tuple_tag (List.length subs), subs)
  | Ast.PatLit (Ast.LitInt n, _)    -> Some (string_of_int n, [])
  | Ast.PatLit (Ast.LitBool b, _)   -> Some (Tir_names.bool_lit_tag b, [])
  | Ast.PatLit (Ast.LitString s, _) -> Some ("\"" ^ s ^ "\"", [])
  | Ast.PatLit (Ast.LitAtom a, _)   -> Some (":" ^ a, [])
  | Ast.PatLit (Ast.LitFloat f, _)  ->
    (* Encode as "#" ^ OCaml hex-float ("%h"), e.g. "#0x1.8p+0" for 1.5.
       Unlike "%g"/[Float.to_string] (which round to ~12 significant decimal
       digits and can map two distinct doubles to the same string, or fail to
       parse back to the exact original bit pattern), "%h" is an exact,
       lossless base-2 encoding of the IEEE-754 bits — round-trips via
       [float_of_string] for every finite/subnormal/zero value, and the
       leading '#' does not collide with any other tag form (ctor names start
       uppercase, tuples '$', ints digits/'-', bools true/false, strings '"',
       atoms ':'). The decoder (llvm_emit.ml's [emit_case], float-chain
       branch) must parse this exact form back with [Int64.bits_of_float] /
       the equivalent LLVM hex-double literal. *)
    Some (Printf.sprintf "#%h" f, [])
  (* The parser emits PatAtom for bare atom patterns (:get) and atom
     constructor patterns (:Tag(x)).  PatLit(LitAtom) is never generated
     by the parser; it would only appear if constructed directly in tests. *)
  | Ast.PatAtom (a, [], _)   -> Some (":" ^ a, [])
  | Ast.PatAtom (a, subs, _) -> Some (a, subs)
  (* Records carry no tag — they are expanded into per-field columns by
     [expand_record_column] before tag dispatch is ever reached, so
     [pat_tag_and_subs] never sees one. Or-patterns are split into one row
     per alternative by [expand_or_rows] before tag dispatch, so it never
     sees one either. *)
  | Ast.PatWild _ | Ast.PatVar _ | Ast.PatAs _ | Ast.PatRecord _ | Ast.PatOr _ -> None

(* Compile a pattern matrix to a TIR expression (decision tree).

   [scruts]   — list of TIR atoms currently under scrutiny (one per column).
   [rows]     — list of (pattern list, body): each pattern list has exactly
                one element per scrutinee.  Rows are tried top-to-bottom; the
                first matching row wins.
   [fallback] — optional expression used when no row matches (non-exhaustive). *)
(** True if a fallback expression is "small enough" that inlining it
    multiple times in the decision tree is cheap.  Currently: only [EAtom]
    qualifies (a single variable or literal reference).  Everything else
    is hoisted into a local 0-arg function (join point) so that fall-through
    sites become tiny calls instead of duplicated sub-trees.

    Without this, decision-tree compilation of deeply-nested patterns with
    fallbacks (e.g. nested [Cons] / string-literal patterns in a multi-arm
    [match]) produces TIR that grows exponentially in the number of arms,
    because the same fallback expression gets inlined into every failing
    branch at every nesting level. *)
let is_atomic_fallback : Tir.expr -> bool = function
  | Tir.EAtom _ -> true
  | _ -> false

(** Strip a first-column as-pattern: bind the alias to the current scrutinee
    and continue matching on the inner pattern.

    [is_trivial_pat] already routes an as-pattern over a TRIVIAL inner
    (`x as y`) into the default rows, where [bind_trivial_pat] binds both
    names.  Only a NON-TRIVIAL inner (`Some(x) as s`) reaches the ctor-row
    path, where [pat_tag_and_subs] returns None for PatAs and the row would
    hit the fail-loudly "unhandled pattern kind" branch.  Rewriting the row
    here keeps the alias binding and lets the inner pattern dispatch
    normally. *)
let strip_as_column (env : Lower_state.env) (scrut : Tir.atom)
    (rows : (Ast.pattern list * Tir.expr) list)
  : (Ast.pattern list * Tir.expr) list =
  List.map (fun (pats, body) ->
    match pats with
    | Ast.PatAs (inner, n, _) :: rest when not (is_trivial_pat inner) ->
      let v : Tir.var = {
        v_name = n.Ast.txt;
        v_ty   = Lower_state.ty_of_span env n.Ast.span;
        v_lin  = Tir.Unr;
      } in
      (inner :: rest, Tir.ELet (v, Tir.EAtom scrut, body))
    | _ -> (pats, body)) rows

(** Split a row whose first column is an or-pattern into one row per
    alternative.  Alternatives bind no variables (enforced at typecheck), so
    the rows can share one body expression. *)
let expand_or_rows (rows : (Ast.pattern list * Tir.expr) list)
  : (Ast.pattern list * Tir.expr) list =
  List.concat_map (fun (pats, body) ->
    match pats with
    | Ast.PatOr (alts, _) :: rest ->
      List.map (fun a -> (a :: rest, body)) alts
    | _ -> [(pats, body)]) rows

(** The sorted union of field names mentioned by every [PatRecord] in the
    first column, or [None] if no row has a record pattern there.

    The union (not any single row's list) is what makes every row expand to
    the same arity, which the matrix invariant requires. *)
let record_fields_in_column (rows : (Ast.pattern list * Tir.expr) list)
  : string list option =
  let names =
    List.concat_map (function
      | (Ast.PatRecord (fs, _) :: _, _) ->
        List.map (fun ((n : Ast.name), _) -> n.Ast.txt) fs
      | _ -> []) rows
  in
  if names = [] then None
  else Some (List.sort_uniq String.compare names)

(** Hoist a (non-atomic) fallback expression [fb] into a fresh 0-arg join
    point.  Returns [(clo_var, lambda_expr)] where:
      - [lambda_expr] is the lambda-creation site
        [ELetRec([jp_fn], EAtom(AVar jp_fn))] whose body is [fb];
        [Defun.defunctionalize] lifts [jp_fn] to a top-level fn with a
        closure struct for [fb]'s free variables.
      - [clo_var] is the fresh variable the closure is bound to; every
        fall-through site becomes [EApp(clo_var, [])], which Defun rewrites
        to [ECallPtr].

    Callers bind the closure with [ELet(clo_var, lambda_expr, body)] and use
    [EApp(clo_var, [])] as the (shared) fall-through call inside [body], so
    the fallback body is emitted ONCE instead of duplicated at every
    fall-through site. *)
let hoist_fallback_jp (fb : Tir.expr) : Tir.var * Tir.expr =
  let jp_fn_name = Lower_state.fresh_name "jp" in
  let jp_fn_ty   = Tir.TFn ([], Lower_types.unknown_ty) in
  let jp_fn : Tir.fn_def = {
    fn_name   = jp_fn_name;
    fn_params = [];
    fn_ret_ty = Lower_types.unknown_ty;
    fn_body   = fb;
    fn_kind   = Tir.FnJoinPoint;
  } in
  let jp_fn_var : Tir.var = {
    v_name = jp_fn_name; v_ty = jp_fn_ty; v_lin = Tir.Unr;
  } in
  let lambda_expr = Tir.ELetRec ([jp_fn], Tir.EAtom (Tir.AVar jp_fn_var)) in
  let clo_name = Lower_state.fresh_name "jp_clo" in
  let clo_var : Tir.var = {
    v_name = clo_name; v_ty = jp_fn_ty; v_lin = Tir.Unr;
  } in
  (clo_var, lambda_expr)

(** Public entry point: hoist a non-trivial [fallback] into a join point
    before invoking [compile_matrix_impl].

    The join point is materialized as a 0-arg lambda whose closure is
    bound to a fresh variable; every fall-through site in the generated
    decision tree becomes an indirect call to that closure rather than
    an inline copy of the fallback expression.  This makes the lifted
    fallback shared once by [Defun.defunctionalize] (via the standard
    "lambda creation" pattern [ELetRec([fn], EAtom(AVar fn))]) instead
    of being duplicated 4× per nesting level, which is what produces
    the exponential TIR blowup for nested [Cons] / string-literal
    patterns in multi-arm matches. *)
let rec compile_matrix
    (env      : Lower_state.env)
    (scruts   : Tir.atom list)
    (rows     : (Ast.pattern list * Tir.expr) list)
    (fallback : Tir.expr option)
  : Tir.expr =
  match fallback with
  | None -> compile_matrix_impl env scruts rows None
  | Some fb when is_atomic_fallback fb ->
    compile_matrix_impl env scruts rows fallback
  | Some fb ->
    let (clo_var, lambda_expr) = hoist_fallback_jp fb in
    (* Every fall-through site uses [EApp(clo_var, [])].  Defun rewrites
       this to [ECallPtr] because [clo_var] has a [TFn] type and is not
       a top-level name. *)
    let jp_call = Tir.EApp (clo_var, []) in
    let body    = compile_matrix_impl env scruts rows (Some jp_call) in
    Tir.ELet (clo_var, lambda_expr, body)

and compile_matrix_impl
    (env      : Lower_state.env)
    (scruts   : Tir.atom list)
    (rows     : (Ast.pattern list * Tir.expr) list)
    (fallback : Tir.expr option)
  : Tir.expr =
  match rows with
  | [] ->
    (match fallback with Some f -> f | None -> Lower_state.nonexhaustive_panic ())
  | ([], body) :: _ -> body   (* zero scrutinees remaining → first row wins *)
  | _ ->
    match scruts with
    | [] ->
      (match rows with (_, body) :: _ -> body | [] ->
        (match fallback with Some f -> f | None -> Lower_state.nonexhaustive_panic ()))
    | scrut :: rest_scruts ->
      let rows = expand_or_rows rows in
      let rows = strip_as_column env scrut rows in
      (match record_fields_in_column rows with
       | Some fields ->
         expand_record_column env scrut rest_scruts fields rows fallback
       | None ->
      (* Split rows into a front block of non-trivial first-column rows and
         a (possibly empty) suffix starting at the first trivial first-column
         row.  The suffix becomes the default for all ECase branches. *)
      let rec split_at_trivial acc = function
        | [] -> (List.rev acc, [])
        | ((fp :: _), _) as row :: rest ->
          if is_trivial_pat fp then (List.rev acc, row :: rest)
          else split_at_trivial (row :: acc) rest
        | rows -> (List.rev acc, rows)  (* empty pattern list — treat as trivial *)
      in
      let (ctor_rows, default_rows) = split_at_trivial [] rows in

      (* Build the fallback expression for rows at and after the first trivial row. *)
      let default =
        match default_rows with
        | [] -> fallback
        | (fp :: rest_pats, body) :: more ->
          (* Bind the trivial first-column pattern on [scrut], then continue
             matching remaining columns (rest_scruts) with remaining patterns
             (rest_pats).  Any further rows (more) become the inner fallback. *)
          let inner_fb = compile_matrix env (scrut :: rest_scruts) more fallback in
          let body_with_bindings = bind_trivial_pat env scrut fp body in
          (* If there are more columns, we still need to compile them.
             For the trivial row itself, the remaining columns are rest_pats
             matched against rest_scruts. *)
          let full_body =
            if rest_pats = [] || rest_scruts = [] then body_with_bindings
            else
              let inner_rows = [(rest_pats, body_with_bindings)] in
              compile_matrix env rest_scruts inner_rows (Some inner_fb)
          in
          (* The full default also handles any subsequent trivial rows via inner_fb *)
          let _ = inner_fb in   (* inner_fb used above only as compile_matrix fallback *)
          Some full_body
        | ([], body) :: _ -> Some body
      in

      (* Group non-trivial ctor_rows by their first-column tag, preserving order. *)
      (* tag_groups: assoc list of (tag, (arity, rows_rev ref)) *)
      let tag_groups : (string * (int * (Ast.pattern list * Tir.expr) list ref)) list ref
          = ref [] in
      List.iter (fun (pats, body) ->
          match pats with
          | fp :: rest_pats ->
            (match pat_tag_and_subs env scrut fp with
             | None ->
               (* [ctor_rows] only ever contains non-trivial first-column
                  patterns (split_at_trivial routed every PatWild/PatVar/PatAs
                  row into default_rows above), so pat_tag_and_subs returning
                  None here means a discriminating pattern kind it doesn't
                  know how to tag — e.g. before this fix, LitFloat and
                  PatRecord.  Silently discarding the row (as this branch
                  used to) makes the arm's body unreachable with no
                  diagnostic — the exact B4 bug (float-literal match arms
                  silently dropped in compiled mode).  Fail loudly instead. *)
               failwith (Printf.sprintf
                 "lower: unhandled pattern kind in match compilation at %s — \
                  pat_tag_and_subs does not know how to tag this pattern, so \
                  the arm would be silently dropped instead of compiled"
                 (string_of_pat_span (span_of_pat fp)))
             | Some (tag, subs) ->
               let arity = List.length subs in
               let row_entry = (subs @ rest_pats, body) in
               (match List.assoc_opt tag !tag_groups with
                | Some (_, rows_ref) -> rows_ref := !rows_ref @ [row_entry]
                | None ->
                  tag_groups := !tag_groups @ [(tag, (arity, ref [row_entry]))]))
          | [] -> ()
        ) ctor_rows;

      (* For each tag group, compile sub-pattern rows recursively. *)
      let tir_branches =
        List.filter_map (fun (tag, (arity, rows_ref)) ->
            (* Field types default to [unknown_ty] (TVar "_"), but that
               sentinel is deliberately excluded from mono.ml's substitution
               (Mono.has_tvar (TVar "_") = false — "lowering fallback
               placeholder, not a real polymorph"), so it can never resolve
               to a concrete type. For a NAMED field (`Cons(h, t) -> ...`),
               that's fixed downstream: bind_trivial_pat rebinds `h` via
               Lower_state.ty_of_span, which returns the typechecker's real
               (trackable) unification variable for that pattern occurrence,
               and mono.ml's substitution resolves it normally. A WILDCARD
               field (`Cons(_, t) -> ...`) has no such rebinding, so its
               br_var kept unknown_ty forever — Rc_types.needs_rc (TVar "_")
               conservatively = true, so Perceus emits a dec_rc on it, and
               since the field's actual runtime representation (for a
               concretely-scalar instantiation like List(Float)) is a raw
               unboxed double bit-reinterpreted as "ptr" (Llvm_ctx.coerce
               ("double","ptr") — no boxing), that dec_rc dereferences a
               raw float bit pattern as a heap pointer and crashes.
               Fix: look up EVERY field's type the same way named fields
               already do — via ty_of_span on the sub-pattern's own span
               (typecheck.ml's infer_pattern now records PatWild's fresh_var
               into type_map too) — so wildcard-discarded fields flow
               through mono.ml's substitution exactly like named ones.
               Scans ALL rows in the group (not just the first) for a
               resolvable span at each position: a shared tag can combine
               rows whose sub-pattern at position [i] differs in shape
               (e.g. one row wildcards a field another row names), but they
               all denote the SAME constructor field, so any row's
               resolvable span is authoritative. *)
            (* IMPORTANT: only give a field its concrete type when EVERY row
               wildcard-discards it.  A wildcard-discarded field is never rebound
               by name, so it exists only for RC — and needs the concrete type so
               Rc_types.needs_rc doesn't spuriously dec_rc an unboxed scalar (the
               List(Float) crash above).  But a field BOUND by name in any row is
               rebound downstream via bind_trivial_pat as `let n = <sub_var>` with
               n's real type; if the sub_var ALSO carries that concrete scalar
               type, the ELet's source and target types match, so codegen elides
               the uniform→natural untag — and the field's runtime value in the
               uniform ADT cell is TAGGED.  That regressed `Ok(n) -> int_to_string(n)`
               on Result(Int): int_to_string received the tagged pointer (15 = 7<<1|1)
               instead of 7.  Keeping the sub_var at the erased placeholder for any
               named field preserves the untag at the binding's use sites, while the
               named rebinding still gives Perceus the real type. *)
            let field_ty_at (i : int) : Tir.ty =
              let all_wild =
                List.for_all (fun (pats, _) ->
                    match List.nth_opt pats i with
                    | Some (Ast.PatWild _) -> true
                    | Some _               -> false
                    | None                 -> true)
                  !rows_ref
              in
              if not all_wild then Lower_types.unknown_ty
              else
                let rec scan = function
                  | [] -> Lower_types.unknown_ty
                  | (pats, _) :: rest ->
                    (match List.nth_opt pats i with
                     | Some p ->
                       let t = Lower_state.ty_of_span env (span_of_pat p) in
                       if t = Lower_types.unknown_ty then scan rest else t
                     | None -> scan rest)
                in
                scan !rows_ref
            in
            let sub_vars = List.init arity (fun i ->
                { Tir.v_name = Lower_state.fresh_name "f"; v_ty = field_ty_at i; v_lin = Tir.Unr }
              ) in
            let sub_atoms = List.map (fun v -> Tir.AVar v) sub_vars in
            let combined_scruts = sub_atoms @ rest_scruts in
            let branch_body =
              compile_matrix env combined_scruts !rows_ref default
            in
            Some { Tir.br_tag = tag; br_vars = sub_vars; br_body = branch_body }
          ) !tag_groups
      in

      (* If there are no ECase branches (all rows were trivial), the default
         already covers everything — just return it. *)
      if tir_branches = [] then
        (match default with Some d -> d | None -> Lower_state.nonexhaustive_panic ())
      else
        (* A [None] default here reaches llvm_emit's [emit_case] as
           [default_opt = None], which — for the literal-chain (int/atom/
           bool/string/float) and switch encodings alike — emits a bare LLVM
           `unreachable` terminator on the fallthrough edge.  `unreachable` is
           undefined behaviour if actually executed at runtime: on this
           target it was observed to silently fall through to whichever arm
           the optimizer happened to place last, printing a WRONG matched
           value with exit 0 — worse than a crash, and a second compiled/
           interpreter divergence beyond B4's dropped-arm bug (the
           interpreter panics via its own exhaustiveness check).  Ensure
           every non-exhaustive [ECase] gets a real panic on the fallback
           edge instead of relying on the typechecker's (incomplete, e.g. for
           Float/String, which have no finite exhaustiveness check) static
           guarantee. *)
        let default = match default with
          | Some _ -> default
          | None -> Some (Lower_state.nonexhaustive_panic ())
        in
        Tir.ECase (scrut, tir_branches, default))

(** Replace a first-column record pattern with one column per field.

    Binds [ELet(f_<name>, EField(scrut, name), …)] around the recursive call
    so each field is projected exactly once and shared by every row.

    Field types matter: a field var left at [Lower_types.unknown_ty] makes
    Perceus treat an unboxed scalar as RC-managed (the same hazard documented
    on [infer_pattern]'s PatWild arm in typecheck.ml).  Prefer the scrutinee's
    own structural [TRecord] type; fall back to the typechecker's recorded
    type for the sub-pattern's span; only then give up and use [unknown_ty]. *)
and expand_record_column
    (env         : Lower_state.env)
    (scrut       : Tir.atom)
    (rest_scruts : Tir.atom list)
    (fields      : string list)
    (rows        : (Ast.pattern list * Tir.expr) list)
    (fallback    : Tir.expr option)
  : Tir.expr =
  let scrut_field_ty name =
    match scrut with
    | Tir.AVar { Tir.v_ty = Tir.TRecord fs; _ } -> List.assoc_opt name fs
    | _ -> None
  in
  (* First span the typechecker recorded for a sub-pattern of this field. *)
  let span_field_ty name =
    let rec search = function
      | [] -> None
      | (Ast.PatRecord (fs, _) :: _, _) :: more ->
        (match List.find_opt (fun ((n : Ast.name), _) -> n.Ast.txt = name) fs with
         | Some (_, Ast.PatVar vn)  -> Some (Lower_state.ty_of_span env vn.Ast.span)
         | Some (_, Ast.PatWild sp) -> Some (Lower_state.ty_of_span env sp)
         | _ -> search more)
      | _ :: more -> search more
    in
    search rows
  in
  let field_ty name =
    match scrut_field_ty name with
    | Some t -> t
    | None ->
      (match span_field_ty name with
       | Some t -> t
       | None -> Lower_types.unknown_ty)
  in
  let field_vars =
    List.map (fun name ->
      let v : Tir.var = {
        v_name = Lower_state.fresh_name ("f_" ^ name);
        v_ty   = field_ty name;
        v_lin  = Tir.Unr;
      } in
      (name, v)) fields
  in
  let new_scruts =
    List.map (fun (_, v) -> Tir.AVar v) field_vars @ rest_scruts in
  let expand_row (pats, body) =
    match pats with
    | Ast.PatRecord (fs, _) :: rest ->
      let sub name =
        match List.find_opt (fun ((n : Ast.name), _) -> n.Ast.txt = name) fs with
        | Some (_, p) -> p
        | None -> Ast.PatWild Ast.dummy_span   (* field not mentioned by this row *)
      in
      Some (List.map (fun name -> sub name) fields @ rest, body)
    | fp :: rest when is_trivial_pat fp ->
      (* A wildcard/var row in a record column matches every record; bind its
         name to the whole record and wildcard out every field column. *)
      let body' = bind_trivial_pat env scrut fp body in
      Some (List.map (fun _ -> Ast.PatWild Ast.dummy_span) fields @ rest, body')
    | _ ->
      (* Unreachable: the column's static type is a record, so no other
         discriminating pattern kind can appear here. *)
      None
  in
  let rows' = List.filter_map expand_row rows in
  let inner = compile_matrix env new_scruts rows' fallback in
  List.fold_right (fun (name, v) acc ->
    Tir.ELet (v, Tir.EField (scrut, name), acc)) field_vars inner

(** Collect the (name, span) of every variable binding in a pattern,
    including [PatAs] outer names.  Used to register pattern-bound locals
    in [_fn_param_types] before lowering a branch body so that those
    names are not rewritten through [_use_aliases] (e.g. a pattern
    variable [status] must not become [HttpServer.status]). *)
let rec collect_pat_names : Ast.pattern -> (string * Ast.span) list = function
  | Ast.PatWild _ -> []
  | Ast.PatVar n -> [(n.txt, n.span)]
  | Ast.PatCon (_, subs) -> List.concat_map collect_pat_names subs
  | Ast.PatAtom (_, subs, _) -> List.concat_map collect_pat_names subs
  | Ast.PatTuple (subs, _) -> List.concat_map collect_pat_names subs
  | Ast.PatLit _ -> []
  | Ast.PatRecord (fields, _) ->
    List.concat_map (fun (_, p) -> collect_pat_names p) fields
  | Ast.PatAs (p, n, _) -> (n.txt, n.span) :: collect_pat_names p
  | Ast.PatOr (ps, _) -> List.concat_map collect_pat_names ps

(** Lower a branch body with the pattern's bound names registered in
    [_fn_param_types] for the duration of the lowering.  Restores any
    shadowed entries afterwards. *)
let lower_branch_body_with_pat (env : Lower_state.env) (pat : Ast.pattern) (body : Ast.expr) : Tir.expr =
  let names = collect_pat_names pat in
  let saved_shadowed = List.filter_map (fun (name, _) ->
      match Hashtbl.find_opt Lower_state._fn_param_types name with
      | Some ty -> Some (name, ty)
      | None -> None) names in
  List.iter (fun (name, sp) ->
    Hashtbl.replace Lower_state._fn_param_types name (Lower_state.ty_of_span env sp)) names;
  let result = lower_expr env body in
  List.iter (fun (name, _) -> Hashtbl.remove Lower_state._fn_param_types name) names;
  List.iter (fun (name, ty) ->
    Hashtbl.replace Lower_state._fn_param_types name ty) saved_shadowed;
  result

(** Lower a single-scrutinee match to a TIR decision tree.
    Branches with [when] guards are handled by embedding a boolean check
    in the branch body: if the guard is false, control falls through to the
    remaining branches. *)
let lower_match (env : Lower_state.env) (scrut : Tir.atom) (branches : Ast.branch list) : Tir.expr =
  let has_guards = List.exists (fun (br : Ast.branch) ->
      br.branch_guard <> None) branches in
  if not has_guards then begin
    (* Fast path: no guards — use efficient matrix compilation.

       An or-pattern's arm body is referenced once per alternative after
       [expand_or_rows] splits the row.  Hoist it into a shared 0-arg join
       point first (alternatives bind no variables, so nothing needs to be
       passed) rather than emitting N copies. *)
    let wraps = ref [] in
    let rows = List.map (fun (br : Ast.branch) ->
        let body = lower_branch_body_with_pat env br.branch_pat br.branch_body in
        if pat_has_or br.branch_pat then begin
          let (clo_var, lambda_expr) = hoist_fallback_jp body in
          wraps := (clo_var, lambda_expr) :: !wraps;
          ([br.branch_pat], Tir.EApp (clo_var, []))
        end else ([br.branch_pat], body)) branches in
    let tree = compile_matrix env [scrut] rows None in
    List.fold_left (fun acc (clo_var, lambda_expr) ->
      Tir.ELet (clo_var, lambda_expr, acc)) tree !wraps
  end else begin
    (* Guards present: compile each branch individually with fallthrough
       to the remaining branches when the guard fails.

       The fallthrough expression ([rest_expr] = the lowering of the
       remaining arms) is referenced in TWO places per arm:
         1. the guard-fail default (the ECase's [Some ...] branch), and
         2. the pattern-fail fallback (passed to [compile_matrix]).
       Embedding [rest_expr] directly in both — and letting [compile_matrix]
       re-hoist a FRESH join point around it every level — duplicated the
       whole tail (panic bodies, "zero" bodies, and every deeper join point)
       once per arm, producing O(arms) join-point closures with byte-
       identical bodies.  Instead, hoist [rest_expr] into ONE 0-arg join
       point and reference the SAME [EApp(clo_var, [])] in both spots, so the
       tail body is emitted once.  We call [compile_matrix_impl] directly
       (not [compile_matrix]) with the already-hoisted call so the fallback
       is not re-hoisted into a second join point.

       The join point is only materialized when the tail is actually
       reachable — i.e. the arm has a guard (guard may fail) or a non-trivial
       pattern (pattern may not match).  An unguarded, trivial (wildcard/var)
       final arm always matches, so its tail is dead and no closure is
       emitted for it. *)
    let rec go = function
      | [] -> Lower_state.nonexhaustive_panic ()  (* every branch's guard failed *)
      | (br : Ast.branch) :: rest ->
        let rest_expr = go rest in
        (* Register pattern-bound names while lowering the body and guard
           so that [resolve_use_alias] treats them as locals. *)
        let pat_names = collect_pat_names br.branch_pat in
        let saved_shadowed = List.filter_map (fun (name, _) ->
            match Hashtbl.find_opt Lower_state._fn_param_types name with
            | Some ty -> Some (name, ty)
            | None -> None) pat_names in
        List.iter (fun (name, sp) ->
          Hashtbl.replace Lower_state._fn_param_types name (Lower_state.ty_of_span env sp)) pat_names;
        let body = lower_expr env br.branch_body in
        (* An or-pattern's arm body is referenced once per alternative after
           [expand_or_rows] (inside [compile_matrix_impl]) splits the row.
           Hoist it into a shared 0-arg join point first, exactly as the
           no-guard fast path above does, rather than emitting N copies. *)
        let (body, or_wrap) =
          if pat_has_or br.branch_pat then
            let (clo_var, lambda_expr) = hoist_fallback_jp body in
            (Tir.EApp (clo_var, []), fun e -> Tir.ELet (clo_var, lambda_expr, e))
          else (body, fun e -> e)
        in
        let guard_expr_opt = Option.map (lower_expr env) br.branch_guard in
        List.iter (fun (name, _) -> Hashtbl.remove Lower_state._fn_param_types name) pat_names;
        List.iter (fun (name, ty) ->
          Hashtbl.replace Lower_state._fn_param_types name ty) saved_shadowed;
        (* The tail is reachable iff the guard can fail OR the pattern can
           fail to match. *)
        let needs_fallback =
          br.branch_guard <> None || not (is_trivial_pat br.branch_pat) in
        let (fallback_opt, wrap) =
          if needs_fallback then
            let (clo_var, lambda_expr) = hoist_fallback_jp rest_expr in
            (Some (Tir.EApp (clo_var, [])),
             fun e -> Tir.ELet (clo_var, lambda_expr, e))
          else
            (None, fun e -> e)
        in
        let guarded_body = match guard_expr_opt with
          | None -> body
          | Some guard_expr ->
            let gv : Tir.var = { v_name = Lower_state.fresh_name "guard";
                                 v_ty = Tir.TBool; v_lin = Tir.Unr } in
            let guard_fail = match fallback_opt with
              | Some call -> call
              | None -> Lower_state.nonexhaustive_panic () in
            Tir.ELet (gv, guard_expr,
              Tir.ECase (Tir.AVar gv,
                [{ br_tag = Tir_names.bool_lit_tag true; br_vars = []; br_body = body }],
                Some guard_fail))
        in
        or_wrap (wrap (compile_matrix_impl env [scrut]
                [([br.branch_pat], guarded_body)] fallback_opt))
    in
    go branches
  end
