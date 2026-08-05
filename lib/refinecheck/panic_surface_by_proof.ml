(* Proof-based panic surface for `cap no_panic` modules.

   `cap no_panic` used to reject every name on the panic-surface ban list by a
   purely SYNTACTIC match, plus a transitive fixpoint that blamed every caller
   up the chain.  For a name that has no contract and could never have one —
   `panic`, `panic_`, `todo_`, `unreachable_` — that is exactly right, and it
   still lives in [Typecheck.check_no_panic_module], unchanged.

   For a name that carries a REAL refinement precondition, banning it by name
   is both too strict and beside the point: `List.tail` panics precisely when
   `len(xs) > 0` fails, which is the very thing [Refine_check] already decides
   at each call site.  This pass asks that question instead.  It does NOT
   discharge anything itself — building a second VC generator here would be
   free to drift from the real one — it only READS the per-call-site verdict
   index [Refine_check] populated, via [Obligation.obligations_at].

   Why a separate pass rather than a branch inside the typechecker: that index
   does not exist until [Refine_check.check_module] has run, which is after
   typechecking.  Hence [bin/main.ml] calls this right after
   [Division_safety.check_module] (which only ADDS to the index; it does not
   reset it).

   Two rules, and both directions of getting them wrong are serious:

   - Only [Proved] is silent.  [Violated], [Skipped _], [Trusted], and "no
     obligation recorded here at all" every one produce the panic-surface
     error, with the same text the syntactic ban used.  Fail-closed on the
     absent case matters most: a call the refinement walk never visited would
     otherwise compile clean inside a capability that promises it cannot
     panic.  [Trusted] is on the error side deliberately — it is an unchecked
     user assertion, and honouring one inside a capability whose entire purpose
     is to GUARANTEE no panics would hollow out the guarantee.  (`cap verified`
     does accept it; that capability is about disclosure, this one is about a
     guarantee.)

   - No transitive blame.  A local helper making an unprovable call gets ONE
     error, at the real call site, the way [Division_safety] has always
     reported — not one per caller up the chain.  That is an intentional
     behaviour change; the covered names are also removed from what SEEDS
     [Typecheck.check_no_panic_module]'s fixpoint, since seeding it would
     reproduce the old chain-blaming even with the direct site proof-checked.
     `panic` and friends keep their fixpoint. *)

module A = March_ast.Ast
module Err = March_errors.Errors
module SS = Set.Make (String)

(* ── The covered set ───────────────────────────────────────────────────────
   Deliberately an ALIAS of [Typecheck.panic_surface_contracted], not a copy.
   The typechecker needs the same set (it bans these names syntactically
   whenever no proof-based pass will run — see [Typecheck.proof_based_panic_
   surface]), and two hand-maintained lists would be free to drift, which for
   this pair means a name banned in neither place: a call that can panic
   compiling clean inside a capability that promised it cannot.  Sharing one
   binding also makes "disjoint from the syntactic ban lists" structural.

   Every name in it carries a refinement precondition in the stdlib as shipped;
   see specs/progress/2026-08-05-no-panic-ban-list-audit.md for the audit that
   established which ones do. *)
let covered : SS.t =
  March_typecheck.Typecheck.StringSet.fold SS.add
    March_typecheck.Typecheck.panic_surface_contracted SS.empty

let is_covered (name : string) : bool = SS.mem name covered

(* ── Reading the verdict index ─────────────────────────────────────────────
   Deliberately NOT [Obligation.verdict_at]: that folds EVERY obligation kind
   recorded at a span down to the weakest verdict, which is the right answer
   for a report and the wrong one here.  A call site whose precondition is
   [Proved] but which shares a span with an unrelated [Division] obligation, or
   with another callee's, would fold to the weaker verdict and a provably-safe
   call would be REJECTED — a false positive, and this subsystem treats a false
   positive as its cardinal sin.

   So: filter to [Precondition] obligations raised for THIS callee, then apply
   the same weakest-wins fold over only those.  Weakest-wins still matters
   inside the filtered set: one call can raise one obligation per refined
   parameter, and "first proved, second skipped" is not a proof. *)
let verdict_for (span : A.span) (callee : string) : Obligation.verdict option =
  let rank = function
    | Obligation.Violated -> 0
    | Obligation.Skipped _ -> 1
    | Obligation.Trusted -> 2
    | Obligation.Proved -> 3
  in
  List.fold_left
    (fun acc (o : Obligation.t) ->
      if o.Obligation.kind <> Obligation.Precondition || o.Obligation.callee <> callee
      then acc
      else
        match acc with
        | Some v when rank v <= rank o.Obligation.verdict -> acc
        | _ -> Some o.Obligation.verdict)
    None
    (Obligation.obligations_at span)

(* The admission rule in one place: [Proved] and nothing else.  [None] ("the
   checker said nothing about this site") is NOT a proof. *)
let is_proved (span : A.span) (callee : string) : bool =
  verdict_for span callee = Some Obligation.Proved

(* ── Call collection ───────────────────────────────────────────────────────
   Structurally a copy of [Typecheck.calls_in_expr] — the same expression forms
   are descended into, so this pass sees exactly the call sites the syntactic
   ban used to see and no others — except that each site carries TWO spans:

   - [name_span], where the diagnostic's caret goes (what the syntactic ban
     reported at, kept so the error text and position are unchanged);
   - [app_span], the whole `EApp` node's span, which is the key
     [Obligation.record] filed the precondition under.  Keying the lookup on
     the callee NAME's span instead would silently never match. *)
let rec calls_in_expr (acc : (string * A.span * A.span) list) (e : A.expr)
  : (string * A.span * A.span) list =
  match e with
  | A.EApp (A.EVar fn_name, args, sp) ->
    let acc = (fn_name.A.txt, fn_name.A.span, sp) :: acc in
    List.fold_left calls_in_expr acc args
  | A.EApp (A.EField (A.EVar mod_name, fn_name, _), args, sp) ->
    let qname = mod_name.A.txt ^ "." ^ fn_name.A.txt in
    let acc = (qname, fn_name.A.span, sp) :: acc in
    List.fold_left calls_in_expr acc args
  | A.EApp (f, args, _) ->
    List.fold_left calls_in_expr (calls_in_expr acc f) args
  | A.ECon (_, args, _) -> List.fold_left calls_in_expr acc args
  | A.ELam (_, body, _) -> calls_in_expr acc body
  | A.EBlock (es, _) -> List.fold_left calls_in_expr acc es
  | A.ELet (b, _) -> calls_in_expr acc b.A.bind_expr
  | A.EMatch (scrut, arms, _) ->
    let acc = calls_in_expr acc scrut in
    List.fold_left
      (fun a (arm : A.branch) ->
        let a = Option.fold ~none:a ~some:(calls_in_expr a) arm.A.branch_guard in
        calls_in_expr a arm.A.branch_body)
      acc arms
  | A.ETuple (es, _) -> List.fold_left calls_in_expr acc es
  | A.ERecord (fields, _) ->
    List.fold_left (fun a (_, ex) -> calls_in_expr a ex) acc fields
  | A.ERecordUpdate (base, fields, _) ->
    let acc = calls_in_expr acc base in
    List.fold_left (fun a (_, ex) -> calls_in_expr a ex) acc fields
  | A.EField (inner, _, _) -> calls_in_expr acc inner
  | A.EIf (cond, then_, else_, _) ->
    calls_in_expr (calls_in_expr (calls_in_expr acc cond) then_) else_
  | A.ECond (arms, _) ->
    List.fold_left (fun a (ce, be) -> calls_in_expr (calls_in_expr a ce) be) acc arms
  | A.EPipe (a, b, _) -> calls_in_expr (calls_in_expr acc a) b
  | A.EAnnot (ex, _, _) -> calls_in_expr acc ex
  | A.EHole _ -> acc
  | A.EAtom (_, args, _) -> List.fold_left calls_in_expr acc args
  | A.ESend (a, b, _) -> calls_in_expr (calls_in_expr acc a) b
  | A.ESpawn (e, _) -> calls_in_expr acc e
  | A.EResultRef _ -> acc
  | A.EDbg (None, _) -> acc
  | A.EDbg (Some inner, _) -> calls_in_expr acc inner
  | A.ELetFn (_, _, _, body, _) -> calls_in_expr acc body
  | A.ELetQ (_, rhs, body, _) -> calls_in_expr (calls_in_expr acc rhs) body
  | A.EAssert (e, _) -> calls_in_expr acc e
  | A.ESigil (_, content, _) -> calls_in_expr acc content
  | A.ELit _ | A.EVar _ -> acc

(* ── Module walk ──────────────────────────────────────────────────────────
   Scoped to exactly what [Typecheck.check_no_panic_module] scanned: the `DFn`
   declarations directly in a `cap no_panic` module's decl list, recursing into
   nested `DMod`s (which re-derive their own `cap` directive — capabilities do
   not inherit inward, and bin/main.ml prepends the whole stdlib as sibling
   DMods).  Widening the scope here would be a second, unrelated behaviour
   change riding along with this one. *)
let rec check_decls (errctx : Err.ctx) (mod_name : string) (decls : A.decl list) : unit =
  let no_panic =
    List.exists (function A.DOpts (opts, _) -> List.mem "no_panic" opts | _ -> false) decls
  in
  List.iter
    (fun (d : A.decl) ->
      match d with
      | A.DFn (def, _) when no_panic ->
        let calls =
          List.fold_left
            (fun acc (clause : A.fn_clause) -> calls_in_expr acc clause.A.fc_body)
            [] def.A.fn_clauses
        in
        List.iter
          (fun (name, name_span, app_span) ->
            if is_covered name && not (is_proved app_span name) then
              Err.error errctx ~span:name_span
                (Printf.sprintf
                   "`%s` in `mod %s` (declared `cap no_panic`) calls `%s`, which can panic.%s"
                   def.A.fn_name.A.txt mod_name name
                   (March_typecheck.Typecheck.panic_surface_suggestion name)))
          (List.rev calls)
      | A.DMod (name, _, inner, _) -> check_decls errctx name.A.txt inner
      | _ -> ())
    decls

let check_module (errctx : Err.ctx) (m : A.module_) : unit =
  check_decls errctx m.A.mod_name.A.txt m.A.mod_decls
