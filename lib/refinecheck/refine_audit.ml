(** Refinement coverage audit — Task 1: enumerate every declared refinement
    occurrence. See the .mli for the public contract and design rationale.

    This is a FORK of the existing whole-type traversal in [Refine_check]
    ([warn_predicate_ty], [warn_predicate_expr_tys], [warn_predicate_decls],
    around [lib/refinecheck/refine_check.ml:668-936]), not a wrapper around
    it: that traversal emits diagnostics and deliberately skips two
    positions (a type definition's record fields and variant arguments, and
    an actor handler's parameter types) on grounds the design doc's nested-
    refinement todo falsifies. This traversal must cover both, so it is its
    own copy rather than a caller of the warning walk. Where the shapes
    coincide (decl and expr recursion) the structure is kept line-for-line
    with the original so the two do not silently drift apart. *)

module A = March_ast.Ast

type position =
  | Param of string * int
  | Return of string
  | Let_annot of string
  | Field of string * string
  | Variant_arg of string * string * int
  | Type_arg
  | Arrow_domain
  | Arrow_codomain
  | Lambda_param of int
  | Expr_annot
  | Sig_fn of string
  | Extern_fn of string
  | Iface_method of string
  | Actor_handler_param of string * int

type nesting = Outermost | Nested

type site = { span : A.span; predicate : string; position : position; nesting : nesting }

(* ── Span and name helpers ──────────────────────────────────────────────── *)

(* The span of a predicate expression, used as every site's [span] (see the
   .mli). Exhaustive over [A.expr] so a new expression form is forced to say
   what its span is here rather than silently falling through to a dummy
   one. [EResultRef] is the one constructor with no source span of its own
   at all — it is REPL-only magic ("v" / "v(N)") that the grammar reachable
   from [March_parser.Parser.module_] never produces, so it cannot appear in
   a refinement predicate parsed from source. [Ast.dummy_span] is the
   existing precedent for this exact case (see
   [lib/typecheck/typecheck_types.ml] and [lib/refactor/refactor.ml]), used
   here only because no real span exists to use, not as a shortcut around
   finding one. *)
let expr_span (e : A.expr) : A.span =
  match e with
  | A.ELit (_, sp)
  | A.EApp (_, _, sp)
  | A.ECon (_, _, sp)
  | A.ELam (_, _, sp)
  | A.EBlock (_, sp)
  | A.ELet (_, sp)
  | A.EMatch (_, _, sp)
  | A.ETuple (_, sp)
  | A.ERecord (_, sp)
  | A.ERecordUpdate (_, _, sp)
  | A.EField (_, _, sp)
  | A.EIf (_, _, _, sp)
  | A.ECond (_, sp)
  | A.EPipe (_, _, sp)
  | A.EAnnot (_, _, sp)
  | A.EHole (_, sp)
  | A.EAtom (_, _, sp)
  | A.ESend (_, _, sp)
  | A.ESpawn (_, sp)
  | A.EDbg (_, sp)
  | A.ELetFn (_, _, _, _, sp)
  | A.ELetQ (_, _, _, sp)
  | A.ELetStar (_, _, _, sp)
  | A.EAssert (_, sp)
  | A.ESigil (_, _, sp) -> sp
  | A.EVar n -> n.A.span
  | A.EResultRef _ -> A.dummy_span

(* A human-readable label for a binder pattern, used only for [Let_annot]'s
   name. The overwhelmingly common case is a bare variable; other patterns
   fall back to a placeholder rather than fabricating a name. *)
let pat_name (p : A.pattern) : string =
  match p with
  | A.PatVar n -> n.A.txt
  | A.PatWild _ -> "_"
  | A.PatCon (n, _) -> n.A.txt
  | A.PatAtom (a, _, _) -> ":" ^ a
  | A.PatAs (_, n, _) -> n.A.txt
  | A.PatTuple _ | A.PatLit _ | A.PatRecord _ | A.PatOr _ -> "<pattern>"

(* ── The type walk ──────────────────────────────────────────────────────── *)

(* Forks [warn_predicate_ty] (refine_check.ml). [pos] is the position label
   in force at this point of the recursion; [depth] is the traversal's own
   recursion depth WITHIN this declared type, 0 at the position's own top.
   [depth] is what [nesting] is derived from — never re-inspecting the type
   afterwards.

   Descending into a [TyCon] argument or either side of a [TyArrow]
   relabels [pos] to a structural tag ([Type_arg], [Arrow_domain],
   [Arrow_codomain]): once the traversal has left the outermost type form,
   the ORIGINAL declaration-level position (which function, which field...)
   is no longer the most useful label — what changed is the type's own
   shape, and that is what these three positions name. [TyTuple], the
   record-field case, and [TyLinear] have no such dedicated tag, so a
   refinement below one of those keeps the [pos] already in force; only its
   [nesting] moves to [Nested] once [depth > 0]. *)
let rec walk_ty (sites : site list ref) (pos : position) (depth : int) (t : A.ty) : unit =
  match t with
  | A.TyRefine (base, _binder, pred) ->
    let nesting = if depth = 0 then Outermost else Nested in
    sites :=
      { span = expr_span pred; predicate = A.show_expr pred; position = pos; nesting } :: !sites;
    walk_ty sites pos (depth + 1) base
  | A.TyCon (_, args) -> List.iter (walk_ty sites Type_arg (depth + 1)) args
  | A.TyArrow (a, b) ->
    walk_ty sites Arrow_domain (depth + 1) a;
    walk_ty sites Arrow_codomain (depth + 1) b
  | A.TyTuple ts -> List.iter (walk_ty sites pos (depth + 1)) ts
  | A.TyRecord fs -> List.iter (fun (_, t) -> walk_ty sites pos (depth + 1) t) fs
  | A.TyLinear (_, t) -> walk_ty sites pos (depth + 1) t
  | A.TyChan _ | A.TyVar _ | A.TyNat _ | A.TyNatOp _ -> ()

(* ── The expression walk ────────────────────────────────────────────────── *)

(* Forks [warn_predicate_expr_tys] (refine_check.ml) line-for-line: same
   traversal, but every leaf that walk feeds to [warn_predicate_ty] this one
   feeds to [walk_ty] with an appropriate top-level [position] instead. *)
let rec walk_expr (sites : site list ref) (e : A.expr) : unit =
  let ge = walk_expr sites in
  match e with
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ -> ()
  | A.EApp (f, args, _) -> ge f; List.iter ge args
  | A.ECon (_, es, _) | A.EAtom (_, es, _) | A.ETuple (es, _) -> List.iter ge es
  | A.ELam (ps, body, _) ->
    List.iteri
      (fun idx (p : A.param) -> Option.iter (walk_ty sites (Lambda_param idx) 0) p.A.param_ty)
      ps;
    ge body
  | A.EBlock (es, _) -> List.iter ge es
  | A.ELet (b, _) ->
    Option.iter (walk_ty sites (Let_annot (pat_name b.A.bind_pat)) 0) b.A.bind_ty;
    ge b.A.bind_expr
  | A.EMatch (e, brs, _) ->
    ge e;
    List.iter
      (fun (br : A.branch) ->
        Option.iter ge br.A.branch_guard;
        ge br.A.branch_body)
      brs
  | A.ERecord (fs, _) -> List.iter (fun (_, e) -> ge e) fs
  | A.ERecordUpdate (e, fs, _) -> ge e; List.iter (fun (_, e) -> ge e) fs
  | A.EField (e, _, _) -> ge e
  | A.EIf (c, t, e, _) -> ge c; ge t; ge e
  | A.ECond (arms, _) -> List.iter (fun (c, b) -> ge c; ge b) arms
  | A.EPipe (a, b, _) -> ge a; ge b
  | A.EAnnot (e, t, _) -> ge e; walk_ty sites Expr_annot 0 t
  | A.ESend (a, b, _) -> ge a; ge b
  | A.ESpawn (e, _) -> ge e
  | A.EDbg (eo, _) -> Option.iter ge eo
  | A.ELetFn (n, ps, ret_ty, body, _) ->
    (* A block-level named function. There is no dedicated position for
       this in the design's [position] type, so it reuses [Param]/[Return]
       under the local function's own name, exactly as a top-level [DFn]
       would — qualitatively the same position, just reached through an
       expression rather than a decl. *)
    List.iteri
      (fun idx (p : A.param) -> Option.iter (walk_ty sites (Param (n.A.txt, idx)) 0) p.A.param_ty)
      ps;
    Option.iter (walk_ty sites (Return n.A.txt) 0) ret_ty;
    ge body
  | A.ELetQ (_, e1, e2, _) | A.ELetStar (_, e1, e2, _) -> ge e1; ge e2
  | A.EAssert (e, _) -> ge e
  | A.ESigil (_, e, _) -> ge e

(* ── The type-definition walk (the first hole this module fills) ─────────── *)

(* [warn_predicate_decls] skips [DType]/[DAlwaysLinearType] entirely, on the
   ground that a refinement in a type definition is checked where it is
   used — the ground the design's nested-refinement todo falsifies. This
   walks a [type_def]'s record fields and variant arguments.

   [TDAlias] is deliberately NOT walked: the [position] type this module
   implements has no tag for "the target of a type alias", only [Field] and
   [Variant_arg] (matching the two positions the plan's Shared facts names
   as what the enumerator must add). A refinement written as a bare type
   alias's target (`type Pos = {Int | _ > 0}`) is therefore out of scope for
   this task, not silently mis-tagged as one of the two covered forms. *)
let walk_type_def (sites : site list ref) (type_name : string) (td : A.type_def) : unit =
  match td with
  | A.TDAlias _ -> ()
  | A.TDRecord fields ->
    List.iter
      (fun (f : A.field) -> walk_ty sites (Field (type_name, f.A.fld_name.A.txt)) 0 f.A.fld_ty)
      fields
  | A.TDVariant variants ->
    List.iter
      (fun (v : A.variant) ->
        List.iteri
          (fun idx arg_ty ->
            walk_ty sites (Variant_arg (type_name, v.A.var_name.A.txt, idx)) 0 arg_ty)
          v.A.var_args)
      variants

(* ── A function definition (shared by [DFn] and [DImpl]) ─────────────────── *)

let walk_fn (sites : site list ref) (fd : A.fn_def) : unit =
  let fn_name = fd.A.fn_name.A.txt in
  Option.iter (walk_ty sites (Return fn_name) 0) fd.A.fn_ret_ty;
  List.iter
    (fun (c : A.fn_clause) ->
      List.iteri
        (fun idx (p : A.fn_param) ->
          match p with
          | A.FPNamed p | A.FPDefault (p, _) ->
            Option.iter (walk_ty sites (Param (fn_name, idx)) 0) p.A.param_ty
          | A.FPPat _ -> ())
        c.A.fc_params;
      walk_expr sites c.A.fc_body)
    fd.A.fn_clauses

(* ── The declaration walk ─────────────────────────────────────────────────
   Exhaustive over [A.decl] with no wildcard, mirroring [warn_predicate_decls]'s
   own discipline: a new decl form must break this build, not silently drop
   out of the audit. The "not walked" block below is genuinely inert — none
   of those forms carries a type annotation or expression that could hold a
   refinement predicate — same list [warn_predicate_decls] arrived at after
   probing [DSig]/[DExtern] out of it. *)
let rec walk_decls (sites : site list ref) (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DFn (fd, _) -> walk_fn sites fd
      | A.DMod (_, _, ds, _) -> walk_decls sites ds
      | A.DDescribe (_, ds, _) -> walk_decls sites ds
      | A.DImpl (idf, _) -> List.iter (fun (_, fd) -> walk_fn sites fd) idf.A.impl_methods
      | A.DInterface (idf, _) ->
        List.iter
          (fun (m : A.method_decl) ->
            walk_ty sites (Iface_method m.A.md_name.A.txt) 0 m.A.md_ty;
            Option.iter (walk_expr sites) m.A.md_default)
          idf.A.iface_methods
      | A.DLet (_, b, _) ->
        Option.iter (walk_ty sites (Let_annot (pat_name b.A.bind_pat)) 0) b.A.bind_ty;
        walk_expr sites b.A.bind_expr
      (* The first hole this module fills: [DType]/[DAlwaysLinearType] were
         entirely absent from [warn_predicate_decls]'s walk. *)
      | A.DType (_, n, _, td, _) -> walk_type_def sites n.A.txt td
      | A.DAlwaysLinearType (_, n, _, td, _) -> walk_type_def sites n.A.txt td
      | A.DActor (_, _, ad, _) ->
        walk_expr sites ad.A.actor_init;
        List.iter
          (fun (h : A.actor_handler) ->
            (* The second hole this module fills: [warn_predicate_decls]
               walks [ah_body] but never [ah_params]. *)
            List.iteri
              (fun idx (p : A.param) ->
                Option.iter
                  (walk_ty sites (Actor_handler_param (h.A.ah_msg.A.txt, idx)) 0)
                  p.A.param_ty)
              h.A.ah_params;
            walk_expr sites h.A.ah_body)
          ad.A.actor_handlers;
        Option.iter (walk_expr sites) ad.A.actor_invariant
      | A.DApp (app, _) ->
        walk_expr sites app.A.app_body;
        Option.iter (walk_expr sites) app.A.app_on_start;
        Option.iter (walk_expr sites) app.A.app_on_stop
      | A.DTest (t, _) -> walk_expr sites t.A.test_body
      | A.DSetup (e, _) | A.DSetupAll (e, _) -> walk_expr sites e
      | A.DSig (_, sd, _) ->
        List.iter
          (fun ((fn_name : A.name), (t : A.ty)) -> walk_ty sites (Sig_fn fn_name.A.txt) 0 t)
          sd.A.sig_fns
      | A.DExtern (ed, _) ->
        List.iter
          (fun (ef : A.extern_fn) ->
            let name = ef.A.ef_name.A.txt in
            (* Both params and return share ONE position tag: the [position]
               type gives [Extern_fn] a single string, no per-parameter
               index, matching [warn_extern_fn_refinement]'s own treatment
               of the whole extern signature as one inert unit. *)
            List.iter (fun (_, t) -> walk_ty sites (Extern_fn name) 0 t) ef.A.ef_params;
            walk_ty sites (Extern_fn name) 0 ef.A.ef_ret_ty)
          ed.A.ext_fns
      (* ── Not walked. Named so a new decl form breaks the build. ──
         Genuinely inert: none of these carries a type annotation or
         expression that can hold a refinement predicate. [DDeriving] and
         [DSatisfy] are desugared into [DImpl] before this ever runs. ── *)
      | A.DProtocol _ | A.DTransitions _
      | A.DNeeds _ | A.DProofCap _ | A.DOpts _
      | A.DDeriving _ | A.DSatisfy _
      | A.DUse _ | A.DAlias _ -> ())
    decls

let sites (decls : A.decl list) : site list =
  let acc = ref [] in
  walk_decls acc decls;
  List.rev !acc
