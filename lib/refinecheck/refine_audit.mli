(** Refinement coverage audit -- Task 1: enumerate every declared refinement
    occurrence.

    See [specs/2026-09-03-refinement-coverage-audit-design.md] and
    [specs/plans/2026-09-03-refinement-coverage-audit-plan.md].

    This module is a fork of the existing whole-type traversal in
    [Refine_check] ([warn_predicate_ty], [warn_predicate_expr_tys],
    [warn_predicate_decls]) that emits diagnostics for a few known-inert
    positions. This traversal emits nothing and touches no diagnostic
    context or obligation ledger: it only records, for every declared
    [A.TyRefine] occurrence reachable from a decl list, where it was found
    and how deep it was nested inside its enclosing declared type.

    Deliberately narrow surface: only [sites] is exposed. The recursive
    traversal itself ([walk_ty], [walk_expr], [walk_decls], ...) is
    implementation detail that a later task (classification) has no reason
    to call directly: it consumes the [site] list this produces. *)

(** Where a declared refinement was found.

    The first several constructors name the DECLARATION-LEVEL position the
    traversal started walking a type from. [Type_arg], [Arrow_domain] and
    [Arrow_codomain] are STRUCTURAL positions: once the traversal descends
    past the outermost type form (into a [TyCon] argument or either side of
    a [TyArrow]), a site's [position] (but not its [origin], see [site]
    below) is relabelled to describe the immediate structural container
    rather than carrying the original declaration-level label forward. A
    refinement found inside a [TyTuple] element, a [TyRecord] field of a
    NESTED (not declaration-top) record type, or a [TyLinear] wrapper keeps
    whatever [position] label it already had, since none of those forms has
    its own dedicated tag in this list; only its [nesting] changes to
    [Nested]. *)
type position =
  | Param of string * int        (** function name, 0-based parameter index *)
  | Return of string              (** function name *)
  | Let_annot of string           (** binder name (or a pattern placeholder) *)
  | Field of string * string      (** type name, field name. Also used for an
                                       actor's state field and a supervisor
                                       actor's child-spec field, under the
                                       actor's own name: those are declared
                                       with the same [A.field] shape a record
                                       type uses. *)
  | Variant_arg of string * string * int  (** type name, variant name, 0-based arg index *)
  | Impl_ty of string             (** the interface name of an `impl Iface(T)`
                                       block, for the type [T] it is for *)
  | Type_arg                      (** nested inside a [TyCon] argument *)
  | Arrow_domain                  (** nested inside a [TyArrow]'s domain *)
  | Arrow_codomain                (** nested inside a [TyArrow]'s codomain *)
  | Lambda_param of int           (** 0-based parameter index of an [ELam] *)
  | Expr_annot                    (** an [EAnnot] type annotation on an expression *)
  | Sig_fn of string              (** function name inside a `sig` block *)
  | Extern_fn of string           (** function name inside an `extern` block;
                                       covers both its parameter types and its
                                       return type: the existing warning this
                                       position feeds treats the whole extern
                                       signature as one inert unit *)
  | Iface_method of string        (** method name inside an `interface` block *)
  | Actor_handler_param of string * int
      (** handler message name, 0-based parameter index *)

(** [Outermost] means the [TyRefine] sits at the very top of the declared
    type at this position (depth 0 of the traversal, i.e. it IS the
    declared type itself). [Nested] means it was reached below that: below a
    [TyCon] argument, a [TyArrow] side, a [TyTuple] element, a [TyRecord]
    field of a nested record, a [TyLinear] wrapper, OR below another
    [TyRefine] layer of a stacked refinement such as
    [{ { Int | _ > 3 } | _ < 9 }] -- the OUTER predicate ([_ < 9]) is
    [Outermost] and the inner one ([_ > 3]) is [Nested], matching what the
    checker's own extractors do: [refined_param_ty] (refine_scope.ml:344)
    requires the base of the type it is given to be a [TyCon], so a stacked
    refinement's inner layer is never the base an extractor looks at either,
    and routing it to [Nested] here (rather than treating "peeling only
    further [TyRefine] layers" as still [Outermost]) is the reading that
    matches the checker, not an approximation of it. Computed purely from
    the traversal's own recursion depth, never by re-inspecting the type
    after the fact. *)
type nesting = Outermost | Nested

(** Which of the checker's call-site machineries, if any, a [Param] or
    [Return] site's enclosing function definition is actually visible to.
    [scope_add_param] / [sig_of_clause] (parameter obligations) and
    [check_fn_post_verdict] (return postconditions) are reached ONLY through
    [visit_fn], called exactly twice by [visit_decl]: once for [A.DFn], once
    per [A.DImpl] method. A block-level [A.ELetFn] is never handed to either.
    An [A.DImpl] method's PARAMETER refinements additionally need a
    MODULE-LEVEL judgement ([contract_is_enforced], keyed on whether the
    method's bare name is adoptable -- exactly one `impl` defines it and no
    top-level `fn` shares the name) before they are ever assumed; a single
    [site] cannot answer that question, so [classify] never claims [Enforced]
    for an [Impl_method_fn] parameter, regardless of adoptability. *)
type fn_origin = Top_level_fn | Impl_method_fn | Local_fn

(** [span] is always the predicate expression's OWN span: the third
    component of the [A.TyRefine (base, binder, pred)] this site came from.
    [A.TyRefine] itself carries no span (see the design's "Shared facts"),
    and the predicate's span is the one neighbour available uniformly at
    every position and every nesting depth, unlike a declaration-level
    neighbour (a function name, a field name, ...) which is out of scope
    once the traversal has descended past the outermost type form.

    [position] and [origin] answer two different questions and a caller
    should not conflate them:

    - [origin] is the DECLARATION-LEVEL label the traversal started this
      type's walk from, held fixed for every site found anywhere inside
      that type, however deep. Test [origin] to ask "does an existing
      per-declaration warning already cover this site regardless of
      nesting", which is exactly how [warn_sig_fn_refinement],
      [warn_iface_method_refinement] and [warn_extern_fn_refinement] behave
      today: each fires from [ty_has_refinement] (refine_check.ml:685),
      which does not care how deep the refinement is, because the WHOLE
      declared type is one inert unit as far as that warning is concerned.
      A `sig Store do fn put : Int -> {Int | _ > 0} end` entry has
      [origin = Sig_fn "put"] for its one site, even though the refinement
      itself sits in the codomain of an arrow, one level below the top of
      `put`'s declared type.
    - [position] is the STRUCTURAL label of the immediate type-form
      surrounding the refinement at the point it was found: it starts equal
      to [origin] and is overwritten by [Type_arg] / [Arrow_domain] /
      [Arrow_codomain] as the traversal descends into those forms. Test
      [position] to describe precisely what kind of nested slot a hole sits
      in, e.g. for a per-site diagnostic line. For the `put` example above,
      [position = Arrow_codomain].

    [origin] always equals [position] when [nesting = Outermost]: at depth 0
    no relabelling has had a chance to happen yet. The converse does not
    hold: a [Nested] site reached only through a [TyTuple] element, a nested
    [TyRecord] field, a [TyLinear] wrapper, or another [TyRefine] layer
    (none of which relabel [position]) still has [origin = position], even
    though it is [Nested]. Only crossing a [TyCon] argument or a [TyArrow]
    side ever makes them differ. Test the field that answers the question
    being asked rather than relying on whether they happen to match. *)
type site = {
  span : March_ast.Ast.span;
  predicate : string;
  position : position;
  origin : position;
  nesting : nesting;
  origin_ty : March_ast.Ast.ty;
      (** The declared type exactly as found at [origin], UNMODIFIED by any
          structural relabelling -- the same value [start] was called with.
          [classify] hands this straight to [Refine_scope.refined_param_ty] /
          [Refine_scope.refined_scope_ty] / inspects it directly for a
          [Return] site, since those extractors each expect exactly the shape
          a parameter's, a let-binding's, or a function's own return
          annotation has. *)
  origin_fn : March_ast.Ast.fn_def option;
      (** [Some fd] only when [origin] is a [Return] site backed by a REAL
          top-level [fn] or `impl` method definition -- the exact shape
          [check_fn_post_verdict] consumes (reached only through [A.DFn] /
          [A.DImpl]). [None] everywhere else, including a block-level
          function's ([A.ELetFn]) own [Return] site: the checker's
          postcondition machinery is never invoked on a local function at
          all, so there is no extractor for [classify] to consult, and
          fabricating a synthetic [A.fn_def] to feed one would misrepresent
          that fact rather than report it. *)
  fn_origin : fn_origin option;
      (** [Some _] only for a [Param] or [Return] site whose declared type
          came from an actual function definition's parameter list or return
          annotation. [None] for every other position (including
          [Lambda_param], which is never backed by an [A.fn_clause] at all --
          see [classify]'s [Lambda_param] rule). *)
}

(** Enumerate every declared [A.TyRefine] occurrence reachable from [decls],
    in the positions this module claims to cover (see [position] above).
    Callable on a module that was never typechecked or refinement-checked;
    emits no diagnostic and touches no obligation ledger. Order is the
    traversal's own left-to-right, top-to-bottom order; callers that need a
    set should build one from the result. *)
val sites : March_ast.Ast.decl list -> site list

(** Task 2: what, if anything, the checker actually does with a declared
    refinement occurrence. *)
type disposition =
  | Enforced  (** the checker's own extractor accepts this declared type. *)
  | Inert_warned of string
      (** the position is one of the three the compiler already names in a
          diagnostic ([warn_sig_fn_refinement], [warn_extern_fn_refinement],
          [warn_iface_method_refinement]) -- the string names which one. *)
  | Unenforced of string
      (** declared, silent, and nothing tells the user: the string is a
          reason specific to THIS site's position, never a shared sentence
          reused across positions (see [classify]'s implementation notes). *)

(** Classify one [site]: calls the checker's own extractors -- never
    restates their acceptance rules -- and reports what they say. Emits no
    diagnostic, touches no obligation ledger, and never invokes the solver.

    NOT a pure function of [site] alone: the [Return] rule (via [origin_fn])
    and, for an ADT/record base, the [Param] / [Let_annot] rules read the
    GLOBAL [adt_ctors] / [ctor_field_names] tables that
    [Refine_check.register_adt_names] / [Refine_check.register_field_sorts]
    populate as a side effect. REQUIRES those to have already run over the
    [A.decl list] this [site] came from (and every OTHER declaration its
    extractors might need to resolve an ADT/record name against, i.e. the
    whole module, not just the one declaration containing this site) -- the
    same order [Refine_check.check_module] itself uses, near the top of the
    pipeline, well before it would ever reach a Task 3 call site for this
    function. Without that priming, every ADT and record base reads as
    unregistered and reads as [Unenforced] regardless of what the checker
    would actually do once registered -- Task 2's review, finding 3. A
    caller that runs [classify] over a corpus WITHOUT calling
    [check_module] first (directly, or via those two registration
    functions) will silently under-report and must not commit the result as
    a baseline.

    CAN RAISE [Failure] if [site.origin] is [Type_arg], [Arrow_domain] or
    [Arrow_codomain] -- an invariant [sites] itself guarantees never happens
    ([origin] is set only by [start], which is never called with a
    structural position; see [walk_ty]) and [site.fn_origin] is [None] for a
    [Param] site (guaranteed never to happen the same way, by [walk_fn] and
    the [ELetFn] arm of [walk_expr]). A [site] built by hand rather than
    produced by [sites] must preserve both invariants or [classify] may
    raise.

    Rule order (see [refine_audit.ml] for the full rationale and the exact
    reason string per position):

    1. [origin] is [Sig_fn] / [Extern_fn] / [Iface_method]: [Inert_warned]
       iff [Refine_check.ty_has_refinement origin_ty] -- the WARNING's own
       condition, called rather than assumed, so a change that silently
       stops the warning from firing is caught here too -- tried BEFORE
       nesting, because such a signature's refinement is always [Nested]
       (any signature that takes an argument is a [TyArrow]) and nesting
       would otherwise hide a position the compiler already warns about by
       name. [Unenforced] if [ty_has_refinement] disagrees with what [sites]
       found (a finding in its own right, not a guess).
    2. [nesting = Nested]: [Unenforced], for everything rule 1 did not
       already dispose of.
    3. [Lambda_param]: ALWAYS [Unenforced] -- an [A.ELam]'s own parameter is
       never routed through [scope_add_param] / [sig_of_clause] at all, so
       [refined_param_ty] accepting its declared type is irrelevant; no call
       site is ever obliged by it.
    4. [Param]: dispatches on [fn_origin] first. [Some Local_fn] (a
       block-level [A.ELetFn]'s own parameter) and [Some Impl_method_fn] (an
       `impl` method's parameter, whose enforcement additionally needs a
       module-level adoptability judgement no single [site] can make) are
       ALWAYS [Unenforced]. [Some Top_level_fn]: [Enforced] iff
       [Refine_post.refined_param_ty] accepts [origin_ty].
    5. [Return]: [Enforced] iff [Refine_post.return_refine_ext] (via
       [origin_fn]) accepts, or [Refine_post.post_induction_shape] (the
       solver-free half of [check_post_induction], called directly -- no
       longer a duplicate) accepts. [origin_fn = None] (a block-level
       [A.ELetFn]) is always [Unenforced]: the checker never verifies a
       local function's return at all.
    6. [Let_annot]: [Enforced] iff [Refine_post.refined_scope_ty] accepts
       [origin_ty].
    7. Every other position ([Field], [Variant_arg], [Impl_ty], [Expr_annot],
       [Actor_handler_param]): always [Unenforced], each with its own reason
       string -- there is no extractor for any of them, nested or not. *)
val classify : site -> disposition

(** {1 Task 4 fix: desugar-dropped and desugar-relocated occurrences}

    [sites] walks whatever decl list it is given. Every caller in this
    codebase gives it the POST-desugar list, because that is what
    [Refine_check.check_module] itself checks. But [classify] answers "does
    the checker's own extractor accept this occurrence", which silently
    assumes the occurrence [classify] is looking at is the same one the
    USER wrote and the same one a normal call resolves to. Two desugar
    transforms break that assumption for a function declaration:

    - A multi-head function's clause merge ([lib/desugar/desugar.ml]'s
      general path, [mk_named_param]) rebuilds every parameter with
      [param_ty = None], discarding a declared parameter refinement before
      [sites] can ever see it. The occurrence is not [Unenforced]; it does
      not exist post-desugar at all, so [classify] never runs on it, and
      the whole-plan review's finding 2 calls this the more serious of the
      two: a declared refinement with no disposition whatsoever.
    - A default-argument function ([expand_defaults_decl]) survives desugar
      only under mangled arity-variant names ([f$1], [f$2], ...); no decl
      named [f] remains. A refined parameter that survives on [f$2] still
      gets an [Enforced] verdict from [classify], because [classify] has no
      way to know a plain call written [f(...)] can never resolve to
      [f$2]'s signature at all. This is finding 1: a false [Enforced].

    [desugar_dropped] answers both by comparing the PRE-desugar site list
    against the POST-desugar one, with no knowledge of which specific
    desugar transform is responsible -- so the same check also catches the
    next transform that drops or relocates a refinement, not just these
    two. See [refine_audit.ml] for the exact matching rule and its
    justification (why it is neither pure name matching nor pure span
    matching, and what a legitimate desugar rename would need to avoid
    being flagged). *)

(** [desugar_dropped ~pre ~post] returns every site in [pre] that has no
    matching occurrence in [post]: same [origin] (the declaration-level
    position, including the enclosing name(s)) and the same [predicate]
    text -- EXCEPT for a [Return] site, matched by predicate text alone
    (see [refine_audit.ml] for why: a postcondition is checked against a
    function's own body regardless of what the declaration is named, so
    matching it by name would misreport [expand_defaults_decl]'s renamed
    full-arity variant as dropped when its return is genuinely still
    enforced). These are declared refinements that desugar either
    discarded entirely or moved under a name/position the checker no
    longer associates with a caller's plain use of the original name --
    report them [Unenforced], never [Enforced] or [Inert_warned],
    regardless of what a POST-desugar site at a similar-looking position
    might say. *)
val desugar_dropped : pre:site list -> post:site list -> site list
