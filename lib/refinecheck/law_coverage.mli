(** Law coverage (specs/2026-11-04-law-coverage-design.md §4): which pure
    functions no admitted law covers.

    A function is pure when [Refine_reflect] reflects it ([Reflected]); a
    function that takes functions ([Specialised]) is listed apart, since no
    lemma can quantify over a function yet.  A law covers a function when its
    theorem calls it; a call inside the proof does not count.  An unproved law
    covers nothing and is shown apart.  Reads verdicts only: nothing here
    changes what the check decides. *)

type status =
  | Uncovered
  | Unproved_only of string list  (** the unproved laws whose theorems call it *)
  | Covered of string list  (** the admitted laws whose theorems call it *)
  | Higher_order

type entry = {
  e_module : string;  (** the innermost module path, `Outer.Inner` *)
  e_name : string;  (** bare *)
  e_public : bool;
  e_span : March_ast.Ast.span;
  e_status : status;
  e_impl : (string * string) option;
      (** an impl method: (interface, impl type); its laws are the
          interface's, generated per impl, named `<law> (via <Iface>)` *)
  e_qname : string;  (** how the witness interpreter calls it (an impl method: its copy) *)
  e_fd : March_ast.Ast.fn_def;  (** its definition (an impl method: its copy) *)
  e_laws : string list;  (** the qualified names of the admitted laws covering it *)
}

(** The call heads of a lemma's theorem, as written (`cat`, `List.append`),
    deduplicated, in first-occurrence order.  Empty when [fd] has no theorem. *)
val theorem_calls : March_ast.Ast.fn_def -> string list

(** One entry per top-level user function that is reflected or specialised,
    in source order.  [rows]: [Refine_reflect.analyze]'s verdicts for the user
    module; [lemmas]: [!Refine_check.lemma_defs] (qualified name, definition,
    admitted); [decls]: the checked module's declarations (the stdlib's are
    prepended to them, and resolve a theorem's calls; only functions whose
    span [is_user] accepts are listed); [file_mod]: the user module's name,
    [entry_file] its file (functions of other loaded files are named by their
    own module path). *)
val entries :
  file_mod:string ->
  entry_file:string ->
  rows:Refine_reflect.row list ->
  lemmas:(string * March_ast.Ast.fn_def * bool) list ->
  decls:March_ast.Ast.decl list ->
  is_user:(March_ast.Ast.span -> bool) ->
  entry list

(** The text report, one block per module (§4), with [strength]'s verdict
    (§5) under each covered row it gives one for. *)
val report_lines : ?strength:(entry -> Law_strength.verdict option) -> entry list -> string list

(** One `{"kind":"law-coverage",...}` JSON object per entry (§4). *)
val json_lines : ?strength:(entry -> Law_strength.verdict option) -> entry list -> string list
