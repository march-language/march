(** Law strength (specs/2026-11-04-law-coverage-design.md §5): small edits to
    a covered function's own body that every law covering it still accepts.

    An edit changes one site of one function's body.  Whether it typechecks,
    changes behaviour and survives the laws is decided by [judge]. *)

type edit = {
  ed_desc : string;  (** in words: ``return `xs` unchanged``, `swap the arguments of `cat`` *)
  ed_span : March_ast.Ast.span;  (** the site *)
  ed_fn : March_ast.Ast.fn_def;  (** the whole edited definition *)
  ed_same_type : (March_ast.Ast.span * March_ast.Ast.span) list;
      (** the edit typechecks when each pair of sites has one type in the
          checked module's type map: the swapped arguments or fields, a
          recursive call and the variable replacing it.  Every other kind
          preserves types by construction (a returned parameter is declared
          with the result type; a match arm's result moves only when it names
          none of its own pattern's variables). *)
}

(** At most 20 edits, deterministic: by kind (return a parameter, swap call
    arguments, swap constructor fields, change an Int literal, swap two match
    arms' results, drop the recursive call, change a comparison), each kind
    in pre-order source position. *)
val edits : March_ast.Ast.fn_def -> edit list

type verdict = {
  v_total : int;  (** edits that changed behaviour and were decided *)
  v_survivors : edit list;  (** of those, the ones every covering law accepts *)
  v_undecided : int;  (** edits no input or no law could decide *)
  v_partial : (int * int) option;  (** the budget ran out: (judged, of) *)
  v_no_gen : bool;  (** a parameter has no generator: not run *)
}

(** Judge [fd]'s edits (§5): each that [typecheck] accepts is installed in a
    copy of [module_], compared with the original on the
    parity net's inputs for [fd]'s parameters (an edit that changes no result
    is dropped), then judged by [laws], each evaluated as `--lemma-test`
    does.  [name] calls [fd] in the witness interpreter.  The witness module
    is [module_] again on return.  Budget: `MARCH_LAW_STRENGTH_MS` (default
    5000) per function. *)
val judge :
  module_:March_ast.Ast.module_ ->
  name:string ->
  laws:(string * March_ast.Ast.fn_def * bool) list ->
  typecheck:(edit -> bool) ->
  March_ast.Ast.fn_def ->
  verdict
