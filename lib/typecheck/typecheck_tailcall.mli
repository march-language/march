(** Tail-call enforcement — March's guarantee that a self- or mutually
    recursive function in tail position does not grow the stack.

    A pure AST pass: it references nothing in the inference knot, not even
    [env], [ty] or [scheme], and shares only the error sink. [Typecheck]
    [include]s it and calls [enforce_tail_calls_in_decls] once per module.

    That single entry point is the whole contract. The call-graph machinery
    behind it — [collect_pattern_vars], [collect_direct_fn_calls], [find_sccs],
    [is_infix_op], [is_structurally_smaller], [scrutinee_is_param_or_smaller]
    and the recursive [check_tail_position] walk — has no caller outside this
    file and is now private, as is the [Aliases] module the structure uses to
    keep [Ast]/[Err]/[StringSet] from colliding with [Typecheck]'s own on
    [include]. *)

(** [enforce_tail_calls_in_decls ~file_mod ctx decls] reports, into [ctx],
    every recursive call that a [tailrec]-annotated function makes outside
    tail position. [mod_path] qualifies names in the message when the decls
    came from a nested module. *)
val enforce_tail_calls_in_decls :
  ?mod_path:string ->
  file_mod:string ->
  March_errors.Errors.ctx ->
  March_ast.Ast.decl list ->
  unit
