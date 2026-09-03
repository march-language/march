(** Refinement coverage audit -- Task 1: enumerate every declared refinement
    occurrence. See the .mli for the public contract and design rationale.

    This is a FORK of the existing whole-type traversal in [Refine_check]
    ([warn_predicate_ty], [warn_predicate_expr_tys], [warn_predicate_decls],
    around [lib/refinecheck/refine_check.ml:668-936]), not a wrapper around
    it: that traversal emits diagnostics and deliberately skips positions
    (a type definition's record fields and variant arguments, an actor
    handler's parameter types, an actor's state fields) on grounds the
    design doc's nested-refinement todo falsifies. This traversal must cover
    all of those, so it is its own copy rather than a caller of the warning
    walk. Where the shapes coincide (decl and expr recursion) the structure
    is kept line-for-line with the original so the two do not silently
    drift apart. *)

module A = March_ast.Ast

type position =
  | Param of string * int
  | Return of string
  | Let_annot of string
  | Field of string * string
  | Variant_arg of string * string * int
  | Impl_ty of string
  | Type_arg
  | Arrow_domain
  | Arrow_codomain
  | Lambda_param of int
  | Expr_annot
  | Sig_fn of string
  | Extern_fn of string
  | Iface_method of string
  | Actor_handler_param of string * int

type nesting = Outermost | Nested

(* Which of the checker's three call-site machineries, if any, a [Param] or
   [Return] site's enclosing function definition is actually visible to.
   [scope_add_param] / [sig_of_clause] (parameter obligations) and
   [check_fn_post_verdict] (return postconditions) are reached ONLY from
   [visit_fn], which [visit_decl] calls exactly twice: once for [A.DFn], once
   per [A.DImpl] method (`refine_check.ml`'s [visit_decl]). A block-level
   [A.ELetFn] is never handed to either. An [A.DImpl] method additionally
   needs a MODULE-LEVEL judgement ([contract_is_enforced], keyed on whether
   the method's bare name is adoptable) before its PARAMETER refinements are
   assumed at all -- a single [site] cannot answer that, so [classify] never
   claims [Enforced] for one; see [classify]'s [Param] rule and Task 2's
   review, finding 6. *)
type fn_origin = Top_level_fn | Impl_method_fn | Local_fn

type site = {
  span : A.span;
  predicate : string;
  position : position;
  origin : position;
  nesting : nesting;
  origin_ty : A.ty;
  origin_fn : A.fn_def option;
  fn_origin : fn_origin option;
      (** [Some _] only for a [Param] or [Return] site whose declared type
          came from an actual function definition's parameter list or return
          annotation (see [walk_fn] / the [ELetFn] arm of [walk_expr]); [None]
          for every other position. *)
}

type disposition =
  | Enforced
  | Inert_warned of string
  | Unenforced of string

(* -- Span and name helpers ------------------------------------------------ *)

(* The span of a predicate expression, used as every site's [span] (see the
   .mli). Exhaustive over [A.expr] so a new expression form is forced to say
   what its span is here rather than silently falling through to a dummy
   one. [EResultRef] is the one constructor with no source span of its own
   at all: it is REPL-only magic ("v" / "v(N)") that the grammar reachable
   from [March_parser.Parser.module_] never produces, so it cannot appear in
   a refinement predicate parsed from source. [Ast.dummy_span] is the
   existing precedent for this exact case (see
   [lib/typecheck/typecheck_types.ml] and [lib/refactor/refactor.ml]), used
   here only because no real span exists to use, not as a shortcut around
   finding one. *)
let expr_span (e : A.expr) : A.span =
  match e with
  | A.ELit (_, sp)
  | A.EApp (_, _, sp)
  | A.ECon (_, _, sp)
  | A.ELam (_, _, sp)
  | A.EBlock (_, sp)
  | A.ELet (_, sp)
  | A.EMatch (_, _, sp)
  | A.ETuple (_, sp)
  | A.ERecord (_, sp)
  | A.ERecordUpdate (_, _, sp)
  | A.EField (_, _, sp)
  | A.EIf (_, _, _, sp)
  | A.ECond (_, sp)
  | A.EPipe (_, _, sp)
  | A.EAnnot (_, _, sp)
  | A.EHole (_, sp)
  | A.EAtom (_, _, sp)
  | A.ESend (_, _, sp)
  | A.ESpawn (_, sp)
  | A.EDbg (_, sp)
  | A.ELetFn (_, _, _, _, sp)
  | A.ELetQ (_, _, _, sp)
  | A.ELetStar (_, _, _, sp)
  | A.EAssert (_, sp)
  | A.ESigil (_, _, sp) -> sp
  | A.EVar n -> n.A.span
  | A.EResultRef _ -> A.dummy_span

(* A human-readable label for a binder pattern, used only for [Let_annot]'s
   name. The overwhelmingly common case is a bare variable; other patterns
   fall back to a placeholder rather than fabricating a name. *)
let pat_name (p : A.pattern) : string =
  match p with
  | A.PatVar n -> n.A.txt
  | A.PatWild _ -> "_"
  | A.PatCon (n, _) -> n.A.txt
  | A.PatAtom (a, _, _) -> ":" ^ a
  | A.PatAs (_, n, _) -> n.A.txt
  | A.PatTuple _ | A.PatLit _ | A.PatRecord _ | A.PatOr _ -> "<pattern>"

(* -- The type walk --------------------------------------------------------- *)

(* Forks [warn_predicate_ty] (refine_check.ml). [origin] is the
   declaration-level label the walk STARTED from at this type (which
   function, which field, which sig entry, ...) and never changes for the
   whole recursion through one declared type -- it is set once at each entry
   point ([start] below) and threaded unchanged. [pos] is the STRUCTURAL
   position label in force at this point of the recursion: it starts equal
   to [origin] and is relabelled as the walk descends into a [TyCon]
   argument or either side of a [TyArrow]. [depth] is the traversal's own
   recursion depth WITHIN this declared type, 0 at the position's own top.
   [depth] is what [nesting] is derived from -- never re-inspecting the type
   afterwards.

   The two labels answer different questions and Task 2 needs both: [origin]
   answers "does an existing inert-signature warning already cover this
   declaration", which does not care how deep the refinement sits (a `sig`
   or `interface` entry's WHOLE type is one inert unit, and the warning that
   says so, [warn_sig_fn_refinement] / [warn_iface_method_refinement] /
   [warn_extern_fn_refinement], fires from [ty_has_refinement]
   (refine_check.ml:685), which is depth-blind by design). [pos] answers
   "what specific type-shape sits immediately around this refinement", which
   is what [Type_arg] / [Arrow_domain] / [Arrow_codomain] name and what a
   per-site output line needs to describe a nested hole precisely.

   [TyTuple], a nested record field, and [TyLinear] have no dedicated
   structural tag, so a refinement below one of those keeps whatever [pos]
   was already in force; only its [nesting] moves to [Nested] once
   [depth > 0]. [origin] is never affected by any of this. *)
let rec walk_ty (sites : site list ref) ~(origin : position) ~(origin_ty : A.ty)
    ~(origin_fn : A.fn_def option) ~(fn_origin : fn_origin option) (pos : position)
    (depth : int) (t : A.ty) : unit =
  match t with
  | A.TyRefine (base, _binder, pred) ->
    let nesting = if depth = 0 then Outermost else Nested in
    sites :=
      { span = expr_span pred;
        predicate = Refine_scope.pred_str pred;
        position = pos;
        origin;
        nesting;
        origin_ty;
        origin_fn;
        fn_origin
      }
      :: !sites;
    walk_ty sites ~origin ~origin_ty ~origin_fn ~fn_origin pos (depth + 1) base
  | A.TyCon (_, args) ->
    List.iter (walk_ty sites ~origin ~origin_ty ~origin_fn ~fn_origin Type_arg (depth + 1)) args
  | A.TyArrow (a, b) ->
    walk_ty sites ~origin ~origin_ty ~origin_fn ~fn_origin Arrow_domain (depth + 1) a;
    walk_ty sites ~origin ~origin_ty ~origin_fn ~fn_origin Arrow_codomain (depth + 1) b
  | A.TyTuple ts ->
    List.iter (walk_ty sites ~origin ~origin_ty ~origin_fn ~fn_origin pos (depth + 1)) ts
  | A.TyRecord fs ->
    List.iter
      (fun (_, t) -> walk_ty sites ~origin ~origin_ty ~origin_fn ~fn_origin pos (depth + 1) t)
      fs
  | A.TyLinear (_, t) -> walk_ty sites ~origin ~origin_ty ~origin_fn ~fn_origin pos (depth + 1) t
  | A.TyChan _ | A.TyVar _ | A.TyNat _ | A.TyNatOp _ -> ()

(* Entry point for a declared type: [pos] IS the origin here, by
   definition -- this is the top of the declared type at this declaration
   position, before any structural relabelling has had a chance to happen.
   [origin_ty] is [t] itself, captured once here and threaded unchanged
   through the whole recursive walk of this declared type -- Task 2's
   [classify] needs the UNMODIFIED declared type to hand to [refined_param_ty]
   / [refined_scope_ty], which each expect exactly the shape a parameter's or
   a let-binding's OWN annotation has, not a sub-form reached by descending
   into it. [origin_fn] is [None] unless the caller is walking a real
   [A.fn_def] whose return type this is (see [walk_fn]'s [Return] call); it
   answers whether an extractor can even be consulted, not just what it says,
   for the block-level [A.ELetFn] case where none of the checker's
   postcondition machinery is ever invoked (see [walk_expr]'s [ELetFn] arm and
   [classify]'s [Return] rule). [fn_origin] is the analogous marker for a
   [Param] site: [Some Top_level_fn] / [Some Impl_method_fn] / [Some Local_fn]
   from [walk_fn] / the [ELetFn] arm, [None] for every non-function
   position. *)
let start ?(origin_fn : A.fn_def option = None) ?(fn_origin : fn_origin option = None)
    (sites : site list ref) (pos : position) (t : A.ty) : unit =
  walk_ty sites ~origin:pos ~origin_ty:t ~origin_fn ~fn_origin pos 0 t

(* -- The expression walk ---------------------------------------------------- *)

(* Forks [warn_predicate_expr_tys] (refine_check.ml) line-for-line: same
   traversal, but every leaf that walk feeds to [warn_predicate_ty] this one
   feeds to [start] with an appropriate top-level [position] instead. *)
let rec walk_expr (sites : site list ref) (e : A.expr) : unit =
  let ge = walk_expr sites in
  match e with
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ -> ()
  | A.EApp (f, args, _) -> ge f; List.iter ge args
  | A.ECon (_, es, _) | A.EAtom (_, es, _) | A.ETuple (es, _) -> List.iter ge es
  | A.ELam (ps, body, _) ->
    List.iteri (fun idx (p : A.param) -> Option.iter (start sites (Lambda_param idx)) p.A.param_ty) ps;
    ge body
  | A.EBlock (es, _) -> List.iter ge es
  | A.ELet (b, _) ->
    Option.iter (start sites (Let_annot (pat_name b.A.bind_pat))) b.A.bind_ty;
    ge b.A.bind_expr
  | A.EMatch (e, brs, _) ->
    ge e;
    List.iter
      (fun (br : A.branch) ->
        Option.iter ge br.A.branch_guard;
        ge br.A.branch_body)
      brs
  | A.ERecord (fs, _) -> List.iter (fun (_, e) -> ge e) fs
  | A.ERecordUpdate (e, fs, _) -> ge e; List.iter (fun (_, e) -> ge e) fs
  | A.EField (e, _, _) -> ge e
  | A.EIf (c, t, e, _) -> ge c; ge t; ge e
  | A.ECond (arms, _) -> List.iter (fun (c, b) -> ge c; ge b) arms
  | A.EPipe (a, b, _) -> ge a; ge b
  | A.EAnnot (e, t, _) -> ge e; start sites Expr_annot t
  | A.ESend (a, b, _) -> ge a; ge b
  | A.ESpawn (e, _) -> ge e
  | A.EDbg (eo, _) -> Option.iter ge eo
  | A.ELetFn (n, ps, ret_ty, body, _) ->
    (* A block-level named function. There is no dedicated position for
       this in the design's [position] type, so it reuses [Param]/[Return]
       under the local function's own name, exactly as a top-level [DFn]
       would: qualitatively the same position, just reached through an
       expression rather than a decl.

       No [~origin_fn] on the [Return] site below (it stays [None]): there
       is no [A.fn_def] here at all, only bare params/return-type/body, and
       even if one were synthesised it would misrepresent reality --
       [check_fn_post_verdict] is invoked only through [visit_fn], reached
       only from [A.DFn] / [A.DImpl] (see [refine_check.ml]'s [visit_decl]),
       never from an [A.ELetFn]. A block-level function's return refinement
       is not merely unreachable BY this module's extractors; the checker
       itself never looks at it. [classify]'s [Return] rule reports this
       directly rather than guessing at what an extractor would say about a
       function definition that is never handed to one.

       [~fn_origin:Local_fn] on BOTH sites below, for the identical reason on
       the parameter side (Task 2's review, finding 5): [scope_add_param] /
       [sig_of_clause] -- the machinery that makes a parameter refinement
       oblige a caller -- consume an [A.fn_clause]'s params, reached only
       through [visit_fn], never through an [A.ELetFn]. Calling
       `helper(0)` against `fn helper(x : {Int | _ > 0}) : Int do x end`
       written as a block-level function obliges no one; [classify]'s
       [Param] rule must not report it as [Enforced] just because
       [refined_param_ty] happens to accept the type. *)
    List.iteri
      (fun idx (p : A.param) ->
        Option.iter (start sites ~origin_fn:None ~fn_origin:(Some Local_fn) (Param (n.A.txt, idx))) p.A.param_ty)
      ps;
    Option.iter (start sites ~origin_fn:None ~fn_origin:(Some Local_fn) (Return n.A.txt)) ret_ty;
    ge body
  | A.ELetQ (_, e1, e2, _) | A.ELetStar (_, e1, e2, _) -> ge e1; ge e2
  | A.EAssert (e, _) -> ge e
  | A.ESigil (_, e, _) -> ge e

(* -- The type-definition walk ----------------------------------------------- *)

(* [warn_predicate_decls] skips [DType]/[DAlwaysLinearType] entirely, on the
   ground that a refinement in a type definition is checked where it is
   used: the ground the design's nested-refinement todo falsifies. This
   walks a [type_def]'s record fields and variant arguments.

   [TDAlias] is not walked, and this is not a scoping choice: the parser
   never constructs [A.TDAlias] for anything a `type` declaration's grammar
   accepts. [lib/parser/parser.mly] builds every parsed `type` decl's
   [type_def] as either [TDVariant] (the general case, `parser.mly:960` and
   its production rules) or [TDRecord]; grepping the whole tree for
   [TDAlias] shows it constructed only outside the parser (desugar's
   identity mapping, dump, format, typecheck, lower). Concretely,
   `type Positive = {Int | _ > 0}` does not parse ("I got stuck here" at the
   `{`); the parenthesised, `linear`, tuple and arrow spellings are rejected
   the same way. A type constructor written as a variant argument, e.g.
   `type Positives = List({Int | _ > 0})`, DOES parse, but as a
   single-constructor [TDVariant], and IS enumerated, as
   [Variant_arg(Positives,List,0)]. So this arm is dead code today, kept
   here (rather than removed) only so the match stays exhaustive over
   [A.type_def] and a future grammar change that adds real alias support is
   forced to reconsider it instead of silently inheriting a no-op. *)
let walk_type_def (sites : site list ref) (type_name : string) (td : A.type_def) : unit =
  match td with
  | A.TDAlias _ -> ()
  | A.TDRecord fields ->
    List.iter (fun (f : A.field) -> start sites (Field (type_name, f.A.fld_name.A.txt)) f.A.fld_ty) fields
  | A.TDVariant variants ->
    List.iter
      (fun (v : A.variant) ->
        List.iteri
          (fun idx arg_ty -> start sites (Variant_arg (type_name, v.A.var_name.A.txt, idx)) arg_ty)
          v.A.var_args)
      variants

(* -- A function definition (shared by [DFn] and [DImpl]) -------------------- *)

let walk_fn (sites : site list ref) ~(fn_origin : fn_origin) (fd : A.fn_def) : unit =
  let fn_name = fd.A.fn_name.A.txt in
  (* [~origin_fn:(Some fd)] here (and only here): this is the one call to
     [start] whose [fd] is a REAL top-level or `impl` method definition, the
     exact shape [check_fn_post_verdict] consumes (called from [visit_fn],
     reached only through [A.DFn] / [A.DImpl] -- see [walk_decls]). The
     [ELetFn] arm of [walk_expr] below deliberately does NOT pass
     [~origin_fn], because a block-level function's return type is never
     handed to [check_fn_post_verdict] at all.

     [~fn_origin] distinguishes [Top_level_fn] from [Impl_method_fn]: the
     CALLER ([walk_decls]'s [A.DFn] / [A.DImpl] arms) knows which one this is,
     [walk_fn] itself does not need to, and only [classify]'s [Param] rule
     cares about the distinction (Task 2's review, finding 6 -- an `impl`
     method's parameter refinement is enforced only when the method's bare
     name is adoptable, a module-level fact no single [site] can determine,
     so [classify] must not claim [Enforced] for one). *)
  Option.iter (start sites ~origin_fn:(Some fd) ~fn_origin:(Some fn_origin) (Return fn_name)) fd.A.fn_ret_ty;
  List.iter
    (fun (c : A.fn_clause) ->
      List.iteri
        (fun idx (p : A.fn_param) ->
          match p with
          | A.FPNamed p -> Option.iter (start sites ~fn_origin:(Some fn_origin) (Param (fn_name, idx))) p.A.param_ty
          | A.FPDefault (p, default_expr) ->
            Option.iter (start sites ~fn_origin:(Some fn_origin) (Param (fn_name, idx))) p.A.param_ty;
            walk_expr sites default_expr
          | A.FPPat _ -> ())
        c.A.fc_params;
      Option.iter (walk_expr sites) c.A.fc_guard;
      walk_expr sites c.A.fc_body)
    fd.A.fn_clauses

(* -- The declaration walk ----------------------------------------------------
   Exhaustive over [A.decl] with no wildcard, mirroring [warn_predicate_decls]'s
   own discipline: a new decl form must break this build, not silently drop
   out of the audit. The "not walked" block below is genuinely inert: none
   of those forms carries a type annotation or expression that could hold a
   refinement predicate, the same list [warn_predicate_decls] arrived at
   after probing [DSig]/[DExtern] out of it. *)
let rec walk_decls (sites : site list ref) (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DFn (fd, _) -> walk_fn sites ~fn_origin:Top_level_fn fd
      | A.DMod (_, _, ds, _) -> walk_decls sites ds
      | A.DDescribe (_, ds, _) -> walk_decls sites ds
      | A.DImpl (idf, _) ->
        start sites (Impl_ty idf.A.impl_iface.A.txt) idf.A.impl_ty;
        List.iter (fun (_, fd) -> walk_fn sites ~fn_origin:Impl_method_fn fd) idf.A.impl_methods
      | A.DInterface (idf, _) ->
        List.iter
          (fun (m : A.method_decl) ->
            start sites (Iface_method m.A.md_name.A.txt) m.A.md_ty;
            Option.iter (walk_expr sites) m.A.md_default)
          idf.A.iface_methods
      | A.DLet (_, b, _) ->
        Option.iter (start sites (Let_annot (pat_name b.A.bind_pat))) b.A.bind_ty;
        walk_expr sites b.A.bind_expr
      (* [DType]/[DAlwaysLinearType]'s record fields and variant arguments
         were entirely absent from [warn_predicate_decls]'s walk. *)
      | A.DType (_, n, _, td, _) -> walk_type_def sites n.A.txt td
      | A.DAlwaysLinearType (_, n, _, td, _) -> walk_type_def sites n.A.txt td
      | A.DActor (_, actor_name, ad, _) ->
        walk_expr sites ad.A.actor_init;
        (* Actor state fields (`state { ... }`) are a [field list], the same
           shape a [TDRecord] uses, and were never walked at all: neither
           this module's own earlier revision nor [warn_predicate_decls]
           reached them. Reuse [Field] under the actor's own name, exactly
           as [walk_type_def] does for a record type. *)
        List.iter
          (fun (f : A.field) -> start sites (Field (actor_name.A.txt, f.A.fld_name.A.txt)) f.A.fld_ty)
          ad.A.actor_state;
        List.iter
          (fun (h : A.actor_handler) ->
            List.iteri
              (fun idx (p : A.param) ->
                Option.iter (start sites (Actor_handler_param (h.A.ah_msg.A.txt, idx))) p.A.param_ty)
              h.A.ah_params;
            walk_expr sites h.A.ah_body)
          ad.A.actor_handlers;
        (* A supervisor actor's declared child specs (`supervise { ... }`)
           carry their own field list, [sc_fields], same shape again. *)
        Option.iter
          (fun (sc : A.supervise_config) ->
            List.iter
              (fun (sf : A.supervise_field) ->
                start sites (Field (actor_name.A.txt, sf.A.sf_name.A.txt)) sf.A.sf_ty)
              sc.A.sc_fields)
          ad.A.actor_supervise;
        Option.iter (walk_expr sites) ad.A.actor_invariant
      | A.DApp (app, _) ->
        walk_expr sites app.A.app_body;
        Option.iter (walk_expr sites) app.A.app_on_start;
        Option.iter (walk_expr sites) app.A.app_on_stop
      | A.DTest (t, _) -> walk_expr sites t.A.test_body
      | A.DSetup (e, _) | A.DSetupAll (e, _) -> walk_expr sites e
      | A.DSig (_, sd, _) ->
        List.iter (fun ((fn_name : A.name), (t : A.ty)) -> start sites (Sig_fn fn_name.A.txt) t) sd.A.sig_fns
      | A.DExtern (ed, _) ->
        List.iter
          (fun (ef : A.extern_fn) ->
            let name = ef.A.ef_name.A.txt in
            (* Both params and return share ONE position tag: the
               [position] type gives [Extern_fn] a single string, no
               per-parameter index, matching [warn_extern_fn_refinement]'s
               own treatment of the whole extern signature as one inert
               unit. *)
            List.iter (fun (_, t) -> start sites (Extern_fn name) t) ef.A.ef_params;
            start sites (Extern_fn name) ef.A.ef_ret_ty)
          ed.A.ext_fns
      (* -- Not walked. Named so a new decl form breaks the build. --
         Genuinely inert: none of these carries a type annotation or
         expression that can hold a refinement predicate. [DDeriving] and
         [DSatisfy] are desugared into [DImpl] before this ever runs. -- *)
      | A.DProtocol _ | A.DTransitions _
      | A.DNeeds _ | A.DProofCap _ | A.DOpts _
      | A.DDeriving _ | A.DSatisfy _
      | A.DUse _ | A.DAlias _ -> ())
    decls

let sites (decls : A.decl list) : site list =
  let acc = ref [] in
  walk_decls acc decls;
  List.rev !acc

(* -- Task 2: classification -------------------------------------------------

   [classify] never emits a diagnostic, touches no obligation ledger, and
   never invokes the solver: it calls the checker's own EXTRACTORS (which
   return an [option], no solving involved) and reports what they say, rather
   than restating their acceptance rules. Every module referenced below
   ([Refine_post], reached through [Refine_check]'s own include chain
   documented at the top of this file / the plan's Shared facts) is already a
   dependency of this library. *)

(* The reason a [Nested] site is unenforced, specialised by [position] when
   the structural container names something specific ([Type_arg],
   [Arrow_domain], [Arrow_codomain]), and falling back to rule 1's own literal
   wording otherwise (reached when [position] still equals [origin] despite
   being [Nested] -- below a [TyTuple] element, a nested [TyRecord] field, a
   [TyLinear] wrapper, or a further layer of a stacked refinement; see the
   .mli's [nesting] doc). *)
let nested_reason (pos : position) : string =
  match pos with
  | Type_arg ->
    "the refinement sits inside a type constructor's argument (for example \
     `List({Int | _ > 0})`); refined_param_ty, refined_scope_ty and \
     return_refine_ext all match only an outermost TyRefine, so a refinement \
     this deep is invisible to every one of them"
  | Arrow_domain ->
    "the refinement sits in the domain of a function-typed value (for \
     example `({Int | _ > 0}) -> Int`); no extractor descends into an arrow \
     type looking for a nested refinement"
  | Arrow_codomain ->
    "the refinement sits in the codomain of a function-typed value (for \
     example `Int -> {Int | _ > 0}`); no extractor descends into an arrow \
     type looking for a nested refinement"
  | Param _ | Return _ | Let_annot _ | Field _ | Variant_arg _ | Impl_ty _
  | Lambda_param _ | Expr_annot | Sig_fn _ | Extern_fn _ | Iface_method _
  | Actor_handler_param _ ->
    "below the outermost position of the declared type"

(* Rule 2's disposition for a `sig` / `extern` / `interface` entry: derived
   from [Refine_check.ty_has_refinement], the WARNING's own condition, rather
   than asserted -- Task 2's review, finding 2. Narrowing [ty_has_refinement]
   (e.g. no longer descending into a [TyCon] argument) silently stops the
   warning from firing for a nested refinement in one of these three
   positions; deriving from the same predicate means that exact regression
   reddens [audit-classify] instead of leaving it green while the warning
   goes silent underneath it. Falls back to [Unenforced] -- not a guess -- if
   the audit found a refinement here that the warning's own condition somehow
   does not see, which would itself be worth investigating rather than
   papering over as [Inert_warned]. *)
let inert_signature_verdict (warning_name : string) (subject : string) (site : site) : disposition =
  if Refine_check.ty_has_refinement site.origin_ty then
    Inert_warned
      (Printf.sprintf "%s: %s carries a refinement, and ty_has_refinement confirms the warning fires"
         warning_name subject)
  else
    Unenforced
      (Printf.sprintf
         "the audit found a refinement here that ty_has_refinement does not see, so %s will not fire \
          for %s -- this is itself a finding, not a guess"
         warning_name subject)

let classify (site : site) : disposition =
  match site.origin with
  (* Rule 2, tried FIRST: a `sig` / `extern` / `interface` entry's WHOLE
     declared type is one inert unit as far as the existing warning is
     concerned, regardless of nesting -- see the .mli's [origin] doc and
     Task 1's review, finding 1. *)
  | Sig_fn name ->
    inert_signature_verdict "warn_sig_fn_refinement" (Printf.sprintf "the `sig` signature of `%s`" name) site
  | Extern_fn name ->
    inert_signature_verdict "warn_extern_fn_refinement"
      (Printf.sprintf "the `extern` signature of `%s`" name) site
  | Iface_method name ->
    inert_signature_verdict "warn_iface_method_refinement"
      (Printf.sprintf "the interface signature of `%s`" name) site
  (* Rule 1: nesting, tested for everything rule 2 did not already dispose
     of. *)
  | (Param _ | Lambda_param _ | Return _ | Let_annot _ | Field _
    | Variant_arg _ | Impl_ty _ | Type_arg | Arrow_domain | Arrow_codomain
    | Expr_annot | Actor_handler_param _)
    when site.nesting = Nested -> Unenforced (nested_reason site.position)
  (* Rules 3-6: [nesting = Outermost] here, so [origin = position] (see the
     .mli), and every remaining case dispatches on the declaration-level
     kind. *)
  (* [Lambda_param] is ALWAYS [Unenforced], regardless of what
     [refined_param_ty] would say about its declared type: an [A.ELam]'s own
     parameter is never routed through [scope_add_param] / [sig_of_clause] at
     all (those consume an [A.fn_clause]'s params; a lambda has none), so no
     call site is ever obliged by it. Task 2's review, finding 4. *)
  | Lambda_param _ ->
    Unenforced
      "an A.ELam parameter is never scope-checked: scope_add_param and \
       sig_of_clause both consume an A.fn_clause's params, which a lambda \
       does not have, so no call through this lambda is ever obliged by its \
       own parameter's refinement"
  | Param _ -> (
    match site.fn_origin with
    | Some Local_fn ->
      Unenforced
        "this is a block-level function's own parameter: scope_add_param and \
         sig_of_clause are reached only through visit_fn, which is called \
         for A.DFn and A.DImpl, never for a local A.ELetFn, so no caller is \
         ever obliged by it (the same reason this declaration form's Return \
         site is Unenforced)"
    | Some Impl_method_fn ->
      Unenforced
        "this is an `impl` method's parameter, whose enforcement depends on \
         a module-level fact a single site cannot determine: \
         contract_is_enforced only assumes it when the method's bare name is \
         adoptable (exactly one `impl` defines it and no top-level `fn` \
         shares the name); when it is not, visit_decl strips the parameter \
         refinement from the body and no caller is obliged. The audit \
         reports Unenforced rather than guess at adoptability from this site \
         alone"
    | Some Top_level_fn -> (
      match Refine_post.refined_param_ty (Some site.origin_ty) with
      | Some _ -> Enforced
      | None ->
        Unenforced
          "refined_param_ty does not accept this declared base type: only \
           an Int, a String, a Bool, a Float, or a registered record/ADT \
           base is scope-checked at a parameter")
    | None ->
      failwith
        "Refine_audit.classify: unreachable -- every Param site's fn_origin \
         is set by walk_fn or the ELetFn arm of walk_expr")
  | Return _ -> (
    match site.origin_fn with
    | None ->
      Unenforced
        "this is a block-level function's return type: check_fn_post_verdict \
         is reached only through visit_fn, which is called for A.DFn and \
         A.DImpl, never for a local A.ELetFn, so no extractor is ever \
         consulted for this position"
    | Some fd -> (
      match Refine_post.return_refine_ext fd with
      | Some _ -> Enforced
      | None ->
        if Refine_post.post_induction_shape fd <> None then Enforced
        else
          Unenforced
            "the return refinement matches neither return_refine_ext's \
             accepted bases (Int, Bool, Float, or a registered record) nor \
             post_induction_shape's Tier 2 induction shape (a single clause \
             with no guard, returning a non-record ADT with a usable \
             predicate AND a measure already declared over that ADT -- \
             post_induction_shape itself gates on measure_preamble_sorts, so \
             this verdict is sensitive to --no-measure-axioms and to \
             whether the audit's join point runs after that ADT's measure \
             has been registered)"))
  | Let_annot _ -> (
    match Refine_post.refined_scope_ty (Some site.origin_ty) with
    | Some _ -> Enforced
    | None -> Unenforced "refined_scope_ty does not accept this declared type at a local binding")
  | Field _ ->
    Unenforced
      "a record (or actor-state) field's declared type is never re-examined \
       once a value is constructed; the checker has no extractor for a \
       stored field, only for a parameter, a return, or a let-binding"
  | Variant_arg _ ->
    Unenforced
      "a variant constructor's argument type is never re-examined once a \
       value is constructed; the checker has no extractor for a stored \
       constructor argument"
  | Impl_ty _ ->
    Unenforced
      "the type an `impl Iface(T)` block names is a type ascription, not a \
       value position the checker ever inspects for a refinement"
  | Expr_annot ->
    Unenforced
      "an EAnnot expression annotation is not read by any refinement \
       extractor: EAnnot is produced only by desugar's DApp handling and is \
       never scope-checked"
  | Actor_handler_param _ ->
    Unenforced
      "an actor handler parameter's declared type is never scope-checked: \
       refined_param_ty is called only from a `fn`'s own parameter walk, \
       never from an actor handler's"
  (* [origin] is set only by [start], which is called exclusively with a
     declaration-level position -- never with [Type_arg], [Arrow_domain] or
     [Arrow_codomain] (see [walk_ty]: those three are only ever passed as the
     STRUCTURAL [pos] argument of a recursive call, never as [origin]). A
     [site] reaching this arm would violate that invariant; surfacing it as a
     hard failure is more useful than silently inventing a disposition for
     data this module never produces. *)
  | Type_arg | Arrow_domain | Arrow_codomain ->
    failwith
      "Refine_audit.classify: unreachable -- origin is never Type_arg / \
       Arrow_domain / Arrow_codomain"
