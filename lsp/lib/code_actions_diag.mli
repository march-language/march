(** Cursor- and diagnostic-driven code actions: quick fixes attached to a
    diagnostic (exhaustiveness, unused binding/import, naming, De Morgan, the
    fix registry, HTML close, refinement) plus the cursor-position
    refactorings that do not need the raw AST.

    As with [Code_actions_ast], the surface needed no curating — 1,019 lines
    export one value. [Analysis] re-exports it with
    [include Code_actions_diag], so [Analysis.code_actions_at] is what callers
    actually use. *)

(** [code_actions_at a ~line ~character ?diagnostics ()] returns every action
    offered at that cursor position, AST-driven and diagnostic-driven
    together, in the order the client should display them. The trailing [unit]
    is what closes the optional [?diagnostics]. *)
val code_actions_at :
  Analysis_util.t ->
  line:int ->
  character:int ->
  ?diagnostics:Analysis_util.Lsp.Types.Diagnostic.t list ->
  unit ->
  Analysis_util.Lsp.Types.CodeAction.t list
