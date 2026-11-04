(** Law strength (specs/2026-11-04-law-coverage-design.md §5): small edits to
    a covered function's own body that every law covering it still accepts.

    An edit changes one site of one function's body.  Whether it typechecks,
    changes behaviour and survives the laws is decided by [judge]. *)

type edit = {
  ed_desc : string;  (** in words: ``return `xs` unchanged``, `swap the arguments of `cat`` *)
  ed_span : March_ast.Ast.span;  (** the site *)
  ed_fn : March_ast.Ast.fn_def;  (** the whole edited definition *)
}

(** At most 20 edits, deterministic: by kind (return a parameter, swap call
    arguments, swap constructor fields, change an Int literal, swap two match
    arms' results, drop the recursive call, change a comparison), each kind
    in pre-order source position. *)
val edits : March_ast.Ast.fn_def -> edit list
