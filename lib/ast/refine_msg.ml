(** Author-written messages on refinement-predicate conjuncts.

    `{Int | _ >= 0 else "index must not be negative" && _ < len(xs) else "…"}`
    attaches a message to each top-level `&&` conjunct.  The parser wraps a
    conjunct in [Ast.ERefineMsg] ([attach]); desugar strips every wrapper
    ([strip], from [Desugar.desugar_ty]) and records the message here against
    the span of the conjunct it belonged to.  Nothing after desugar ever sees
    the wrapper, so no predicate reasoning had to learn about it: the
    refinement checker asks [message_for] only when it renders a diagnostic
    about one conjunct.

    Why a table and not a field on the AST: every pass after desugar would
    otherwise have to step around the wrapper, and a missed step silently
    weakens a proof.  The one place a desugared AST outlives its desugar is the
    stdlib AST cache ([bin/toolchain.ml]), which stores the stdlib's entries
    beside its decls ([entries_for], [restore]).

    Staleness: entries are keyed by source span, and a span can outlive the
    text that was there (an editor session re-checking a file after the author
    deleted a message).  So the first time one desugar pass meets a predicate
    from a file, every older entry for that file is dropped before the new
    ones go in ([begin_pass] marks the start of a pass). *)

let table : (Ast.span, string) Hashtbl.t = Hashtbl.create 64

(* Files whose old entries this desugar pass has already dropped. *)
let purged : (string, unit) Hashtbl.t = Hashtbl.create 8

let begin_pass () = Hashtbl.reset purged

let purge_file (file : string) =
  if not (Hashtbl.mem purged file) then begin
    Hashtbl.replace purged file ();
    let stale =
      Hashtbl.fold
        (fun (sp : Ast.span) _ acc -> if sp.Ast.file = file then sp :: acc else acc)
        table []
    in
    List.iter (Hashtbl.remove table) stale
  end

let rec span_of (e : Ast.expr) : Ast.span =
  match e with
  | Ast.EVar n -> n.Ast.span
  | Ast.EResultRef _ -> Ast.dummy_span
  | Ast.ELit (_, sp) | Ast.EApp (_, _, sp) | Ast.ECon (_, _, sp) | Ast.ELam (_, _, sp)
  | Ast.EBlock (_, sp) | Ast.ELet (_, sp) | Ast.EMatch (_, _, sp) | Ast.ETuple (_, sp)
  | Ast.ERecord (_, sp) | Ast.ERecordUpdate (_, _, sp) | Ast.EField (_, _, sp)
  | Ast.EIf (_, _, _, sp) | Ast.ECond (_, sp) | Ast.EPipe (_, _, sp)
  | Ast.EAnnot (_, _, sp) | Ast.EHole (_, sp) | Ast.EAtom (_, _, sp)
  | Ast.ESend (_, _, sp) | Ast.ESpawn (_, sp) | Ast.EDbg (_, sp)
  | Ast.ELetFn (_, _, _, _, sp) | Ast.ELetQ (_, _, _, sp) | Ast.ELetStar (_, _, _, sp)
  | Ast.EAssert (_, sp) | Ast.ESigil (_, _, sp) -> sp
  | Ast.ERefineMsg (inner, _, _) -> span_of inner

let is_and = function
  | Ast.EApp (Ast.EVar { Ast.txt = "&&"; _ }, [ _; _ ], _) -> true
  | _ -> false

(** [p else "msg"], as the parser builds it.  `else` binds tighter than `&&`,
    so in `a && b else "m"` the message belongs to [b]: descend the right
    spine of a conjunction to its last conjunct. *)
let rec attach (p : Ast.expr) (msg : string) (sp : Ast.span) : Ast.expr =
  match p with
  | Ast.EApp (op, [ a; b ], asp) when is_and p -> Ast.EApp (op, [ a; attach b msg sp ], asp)
  | p -> Ast.ERefineMsg (p, msg, sp)

(** Remove every wrapper from a predicate's `&&` spine, recording each
    message against its conjunct's span. *)
let rec strip (e : Ast.expr) : Ast.expr =
  match e with
  | Ast.EApp (op, [ a; b ], sp) when is_and e -> Ast.EApp (op, [ strip a; strip b ], sp)
  | Ast.ERefineMsg (inner, msg, _) ->
    let inner = strip inner in
    let sp = span_of inner in
    purge_file sp.Ast.file;
    Hashtbl.replace table sp msg;
    inner
  | e ->
    purge_file (span_of e).Ast.file;
    e

(** The author's message for one conjunct of a predicate, if it carried one. *)
let message_for (conjunct : Ast.expr) : string option =
  Hashtbl.find_opt table (span_of conjunct)

(** The entries recorded for [files], for a cache that stores desugared decls
    (the stdlib AST cache in [bin/toolchain.ml]) to keep beside them. *)
let entries_for ~(files : string list) : (Ast.span * string) list =
  Hashtbl.fold
    (fun (sp : Ast.span) msg acc -> if List.mem sp.Ast.file files then (sp, msg) :: acc else acc)
    table []

(** Put back what [entries_for] saved, replacing anything recorded for those
    files: the cache hit stands in for desugaring them. *)
let restore ~(files : string list) (entries : (Ast.span * string) list) =
  let stale =
    Hashtbl.fold
      (fun (sp : Ast.span) _ acc -> if List.mem sp.Ast.file files then sp :: acc else acc)
      table []
  in
  List.iter (Hashtbl.remove table) stale;
  List.iter (fun (sp, msg) -> Hashtbl.replace table sp msg) entries
