(** Refinement coverage audit — Task 1: enumerate every declared refinement
    occurrence.

    See [specs/2026-09-03-refinement-coverage-audit-design.md] and
    [specs/plans/2026-09-03-refinement-coverage-audit-plan.md].

    This module is a fork of the existing whole-type traversal in
    [Refine_check] ([warn_predicate_ty], [warn_predicate_expr_tys],
    [warn_predicate_decls]) that emits diagnostics for a few known-inert
    positions.  This traversal emits nothing and touches no diagnostic
    context or obligation ledger — it only records, for every declared
    [A.TyRefine] occurrence reachable from a decl list, where it was found
    and how deep it was nested inside its enclosing declared type.

    Deliberately narrow surface: only [sites] is exposed.  The recursive
    traversal itself ([walk_ty], [walk_expr], [walk_decls], ...) is
    implementation detail that a later task (classification) has no reason
    to call directly — it consumes the [site] list this produces. *)

(** Where a declared refinement was found.

    The first several constructors name the DECLARATION-LEVEL position the
    traversal started walking a type from.  [Type_arg], [Arrow_domain] and
    [Arrow_codomain] are STRUCTURAL positions: once the traversal descends
    past the outermost type form (into a [TyCon] argument or either side of
    a [TyArrow]), the position is relabelled to describe the immediate
    structural container rather than carrying the original declaration-level
    label forward.  A refinement found inside a [TyTuple] element, a
    [TyRecord] field of a NESTED (not declaration-top) record type, or a
    [TyLinear] wrapper keeps whatever position label it already had, since
    none of those forms has its own dedicated tag in this list — only its
    [nesting] changes to [Nested]. *)
type position =
  | Param of string * int        (** function name, 0-based parameter index *)
  | Return of string              (** function name *)
  | Let_annot of string           (** binder name (or a pattern placeholder) *)
  | Field of string * string      (** type name, field name *)
  | Variant_arg of string * string * int  (** type name, variant name, 0-based arg index *)
  | Type_arg                      (** nested inside a [TyCon] argument *)
  | Arrow_domain                  (** nested inside a [TyArrow]'s domain *)
  | Arrow_codomain                (** nested inside a [TyArrow]'s codomain *)
  | Lambda_param of int           (** 0-based parameter index of an [ELam] *)
  | Expr_annot                    (** an [EAnnot] type annotation on an expression *)
  | Sig_fn of string              (** function name inside a `sig` block *)
  | Extern_fn of string           (** function name inside an `extern` block;
                                       covers both its parameter types and its
                                       return type — the existing warning this
                                       position feeds treats the whole extern
                                       signature as one inert unit *)
  | Iface_method of string        (** method name inside an `interface` block *)
  | Actor_handler_param of string * int
      (** handler message name, 0-based parameter index *)

(** [Outermost] means the [TyRefine] sits at the very top of the declared
    type at this position (depth 0 of the traversal, i.e. it IS the
    declared type, or the immediate result of peeling only further
    [TyRefine] layers). [Nested] means it was reached below that, e.g. below
    a [TyCon] argument, a [TyArrow] side, a [TyTuple] element, a [TyRecord]
    field of a nested record, or a [TyLinear] wrapper. Computed purely from
    the traversal's own recursion depth, never by re-inspecting the type
    after the fact. *)
type nesting = Outermost | Nested

(** [span] is always the predicate expression's OWN span — the third
    component of the [A.TyRefine (base, binder, pred)] this site came from.
    [A.TyRefine] itself carries no span (see the design's "Shared facts"),
    and the predicate's span is the one neighbour available uniformly at
    every position and every nesting depth, unlike a declaration-level
    neighbour (a function name, a field name, ...) which is out of scope
    once the traversal has descended past the outermost type form. *)
type site = { span : March_ast.Ast.span; predicate : string; position : position; nesting : nesting }

(** Enumerate every declared [A.TyRefine] occurrence reachable from [decls],
    in the positions this module claims to cover (see [position] above).
    Callable on a module that was never typechecked or refinement-checked;
    emits no diagnostic and touches no obligation ledger. Order is the
    traversal's own left-to-right, top-to-bottom order; callers that need a
    set should build one from the result. *)
val sites : March_ast.Ast.decl list -> site list
