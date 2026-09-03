(** Refinement checking — the post-typecheck pass that discharges refinement
    obligations through the Z3 bridge.

    {1 What this interface is}

    The implementation has {b 198} top-level values. Seventeen of them have a
    caller outside this module; the rest are the checker's internals and are
    now hidden. See the module docstring and the §-numbered table of contents
    in [refine_check.ml] for the internal structure.

    Everything here was kept because a sweep of [bin/ lib/ lsp/ forge/ test/
    js/] found it referenced from outside — qualified ([Refine_check.x]) or
    through the [RC.]/[Rc.] aliases in [precond_infer], [postcond_infer] and
    [bin/main.ml]. Mentions inside doc comments were discarded by hand. If you
    need something that is not here, expose it deliberately rather than
    reaching around the interface.

    {1 The one entry point}

    [check_module] is what the driver calls: 52 of the qualified references in
    the tree are to it. Everything else exists because two later passes
    ([precond_infer], [postcond_infer], [division_safety]) and the migration
    checker re-use pieces of the machinery it sets up — several of them
    {i require} [check_module] to have run first, because the registration
    globals they read are populated by it. *)

module A = March_ast.Ast
module Smt = March_refine.Smt
module Err = March_errors.Errors

(** {1 Types crossing the boundary} *)

(** A refined parameter: position, predicate binder, predicate expression, and
    the SMT sort of its base type when that base is not [Int] (a [String], a
    registered ADT, or a 1-constructor record; [None] for plain [Int]). *)
type rparam = {
  idx : int;
  binder : string;
  pred : A.expr;
  sort : string option;
}

(** How a return refinement's predicate relates to the callee's parameters:
    [Closed] mentions only the binder and is usable as-is; [Relational] also
    mentions the named parameters and needs their actuals substituted;
    [Unusable] cannot be reflected. *)
type pred_scope = Closed | Relational of string list | Unusable

(** A function's refinement-relevant signature: parameter names, which of them
    are strings, their scalar SMT sorts, the refined ones, and the return
    refinement with its sort. *)
type fn_sig = {
  param_names : string list;
  param_str : bool list;
  param_scalar : Smt.sort list;
  refined : rparam list;
  ret : (string * A.expr) option;
  ret_sort : string option;
}

(** Resolution context for a call: the current module path, its aliases, its
    [use] selectors, and the locally bound names that shadow them. *)
type rctx = {
  modpath : string;
  aliases : (string * string) list;
  uses : (string * A.use_selector * string) list;
  locals : string list;
}

(** The empty context — module path [""], nothing aliased, used or shadowed. *)
val rctx0 : rctx

(** {1 Entry point} *)

(** Check one module: register its types and measures, walk every declaration,
    and report violated preconditions, postconditions and division-safety
    obligations through the error context.

    [?root] is the project root handed to the SMT bridge (default
    [Sys.getcwd ()]). [?measure_axioms] enables the measure-axiom preamble
    (default [true]). [?stdlib_files] names the files that ARE the standard
    library, which decides whether a competing [List.length] is the stdlib's
    own; omitting it is safe (the answer becomes "no file is") but disables
    nothing. *)
val check_module :
  ?root:string ->
  ?measure_axioms:bool ->
  ?stdlib_files:string list ->
  Err.ctx ->
  A.module_ ->
  unit

(** {1 Signature extraction and resolution}

    Used by [precond_infer] / [postcond_infer] to answer "what would the
    checker make of this function?" without paying for a full
    [check_module]. *)

(** The refinement signature of a function definition. *)
val sig_of_fn : A.fn_def -> fn_sig

(** Every definition in a declaration list, by name; [None] where a name is
    defined more than once ambiguously. *)
val collect_all_defs : A.decl list -> (string, fn_sig option) Hashtbl.t

(** The signature a refined function-typed {i parameter} presents to calls made
    through it, or [None] when it has none. *)
val entry_of_sig : fn_sig -> fn_sig option

(** How a predicate relates to a parameter list — see {!pred_scope}. *)
val classify_pred : string -> string list -> A.expr -> pred_scope

(** Whether a name is one of the operators a refinement predicate may apply. *)
val known_predicate_fn : string -> bool

(** The [impl] methods whose contracts [collect_all_defs] can adopt
    unambiguously. *)
val adoptable_impl_methods : A.decl list -> string list

(** The same function with every parameter refinement erased — used where a
    contract must not be assumed because no caller was obliged to establish
    it. *)
val strip_param_refinements : A.fn_def -> A.fn_def

(** {1 Shadowing helpers}

    Exposed for [division_safety], which threads the same fact channels: a
    name rebound in between must retire from every channel, or a stale fact
    proves a goal about a different value. *)

(** Retire path facts mentioning any of the given rebound names. *)
val path_shadow : (A.expr * bool) list -> string list -> (A.expr * bool) list

(** Every name a pattern binds. *)
val pat_binders : A.pattern -> string list

(** {1 Traversal and postconditions}

    These require [check_module]'s registration globals to be populated, i.e.
    they are not standalone entry points. *)

(** Walk a declaration list, checking every call site in it. *)
val visit_decls :
  root:string ->
  Err.ctx ->
  (string, fn_sig option) Hashtbl.t ->
  rctx ->
  A.decl list ->
  unit

(** Call sites the last walk PROMOTED to a demonstrated precondition failure:
    the span the warning was reported at, the enclosing function's qualified
    name, and its [fn_def]. Most recent first; [check_module] clears it.

    Exposed for [Precond_infer.attach_promoted_fixes], which drains it AFTER
    the walk to attach the precondition each site should declare. It is
    deliberately not drained during the walk — see the ref's own comment in
    [Refine_call]. *)
val promoted_sites : (A.span * string * A.fn_def) list ref

(** Source files the caller declared to be the stdlib's, as handed to
    [check_module ~stdlib_files]. The one notion of "not the user's code" the
    pass has; exposed so a post-pass reuses it rather than inventing a second. *)
val stdlib_source_files : string list ref

(** Check one function's postcondition and report it. *)
val check_fn_post : root:string -> Err.ctx -> A.fn_def -> unit

(** The same check as a verdict. [?emit:false] answers "would this
    postcondition verify?" without emitting a diagnostic or double-counting
    the obligation. *)
val check_fn_post_verdict :
  root:string -> Err.ctx -> ?emit:bool -> A.fn_def -> bool

(** Drop the postconditions that did not verify, so no later obligation may
    rest on an unproven premise. *)
val gate_unverified_posts :
  root:string ->
  Err.ctx ->
  (string, fn_sig option) Hashtbl.t ->
  A.decl list ->
  unit

(** {1 Priming the type tables}

    Called by [--check-migration], which runs [check_fn_post] against a
    synthesised signature and so must register the sorts itself. *)

val register_adt_names : A.decl list -> unit
val register_field_sorts : A.decl list -> unit

(** {1 The inert-signature warning's own condition}

    True iff [t] carries a refinement ANYWHERE the warning machinery looks --
    a [TyCon] argument, either side of a [TyArrow], a [TyTuple] element, a
    [TyRecord] field, or a [TyLinear] wrapper. This is exactly the condition
    [warn_sig_fn_refinement] / [warn_extern_fn_refinement] /
    [warn_iface_method_refinement] gate on before firing (see
    [warn_predicate_decls]'s `sig_fns` / `extern_fn` / `md_ty` arms).  Exposed
    so [Refine_audit.classify] can DERIVE its [Inert_warned] verdict from the
    warning's own condition rather than assert the correspondence -- see Task
    2's review, finding 2: narrowing this function's recursion silently
    breaks the correspondence while leaving every other test green. *)
val ty_has_refinement : A.ty -> bool

(** {1 Not API — declared only because they are dead}

    These three have no caller anywhere: not in this module, not outside it.
    Hiding them would make each an [unused-value-declaration] error under
    warnings-as-errors, so they are declared here with this note instead. They
    are candidates for deletion, not for use.

    [register_types_for_check] is the interesting one: its own docstring says
    [--check-migration] calls it, and [--check-migration] does not — it calls
    {!register_adt_names} and {!register_field_sorts} directly (see
    [bin/main.ml]'s [Rc] block), so the table-clearing that only this function
    does never happens. That is a behavioural question, not an interface one;
    it is recorded in this phase's progress note rather than changed here. *)

val smt_sort_of_marker : string option -> Smt.sort
val register_types_for_check : A.decl list -> unit
val expr_binds_name : string -> A.expr -> bool
