(** The AST-driven code-action engine: the refactorings that need to look at
    the parsed program rather than at a diagnostic — extract function, inline,
    introduce pipe, convert lambda, and the rest.

    Unlike most modules in this pass, its surface needed no curating: 1,097
    lines of source export exactly one value, and everything else was already
    local to [ast_code_actions] or lives in [Analysis_util]. This interface
    records that rather than narrowing it.

    [Code_actions_diag] [open]s this module and splices the result of
    [ast_code_actions] in at its original position in the concatenation, so
    the two engines together produce the same ordered list [Analysis] always
    returned. *)

val ast_code_actions :
  Analysis_util.t ->
  line:int ->
  character:int ->
  Analysis_util.Lsp.Types.CodeAction.t list
