(* Allocation checker for `cap no_alloc` modules.
   A post-typecheck pass that walks all function bodies in modules declared
   `cap no_alloc` and flags any heap-allocating expression.

   Heap-allocating expressions:
   - ETuple with non-empty items (unit tuple () is fine)
   - ERecord (any record literal)
   - ECon with non-empty args (boxed constructor: Some(x), Cons(h,t), ...)
   - ELam (closure allocation)

   The pass recurses into sub-expressions of everything else so that
   allocations nested inside if/match/let/etc. are caught. *)

module A = March_ast.Ast
module Err = March_errors.Errors

let rec check_expr (errctx : Err.ctx) (e : A.expr) : unit =
  let go = check_expr errctx in
  match e with
  | A.ETuple ([], _) -> () (* unit — not an allocation *)
  | A.ETuple (items, sp) ->
    Err.error errctx ~span:sp
      "tuple construction allocates in a `cap no_alloc` module.";
    List.iter go items
  | A.ERecord (_, sp) ->
    Err.error errctx ~span:sp
      "record construction allocates in a `cap no_alloc` module."
  | A.ECon (_, [], _) -> () (* nullary constructor — no heap allocation *)
  | A.ECon (_, args, sp) ->
    Err.error errctx ~span:sp
      "constructor application allocates in a `cap no_alloc` module.";
    List.iter go args
  | A.ELam (_, body, sp) ->
    Err.error errctx ~span:sp
      "lambda/closure construction allocates in a `cap no_alloc` module.";
    go body
  (* recurse into all other expressions *)
  | A.EApp (f, args, _) -> go f; List.iter go args
  | A.EBlock (es, _) -> List.iter go es
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.ELetFn (_, _, _, body, _) -> go body
  | A.ELetQ (_, rhs, body, _) -> go rhs; go body
  | A.EMatch (scrut, arms, _) ->
    go scrut;
    List.iter
      (fun (arm : A.branch) ->
        Option.iter go arm.A.branch_guard;
        go arm.A.branch_body)
      arms
  | A.EIf (c, t, e, _) -> go c; go t; go e
  | A.ECond (arms, _) -> List.iter (fun (c, b) -> go c; go b) arms
  | A.EField (inner, _, _) -> go inner
  | A.EAnnot (inner, _, _) -> go inner
  | A.ESpawn (inner, _) -> go inner
  | A.EAssert (inner, _) -> go inner
  | A.ESigil (_, inner, _) -> go inner
  | A.EDbg (Some inner, _) -> go inner
  | A.EDbg (None, _) -> ()
  | A.ESend (a, b, _) -> go a; go b
  | A.EPipe (a, b, _) -> go a; go b
  | A.ERecordUpdate (r, fields, _) -> go r; List.iter (fun (_, e) -> go e) fields
  | A.EAtom (_, args, _) -> List.iter go args
  (* safe: no allocation *)
  | A.EVar _ | A.ELit _ | A.EHole _ | A.EResultRef _ -> ()

let check_fn (errctx : Err.ctx) (fd : A.fn_def) : unit =
  List.iter
    (fun (clause : A.fn_clause) -> check_expr errctx clause.A.fc_body)
    fd.A.fn_clauses

let rec check_decls (errctx : Err.ctx) (decls : A.decl list) : unit =
  let no_alloc =
    List.exists
      (function A.DOpts (opts, _) -> List.mem "no_alloc" opts | _ -> false)
      decls
  in
  List.iter
    (function
      | A.DFn (fd, _) when no_alloc -> check_fn errctx fd
      | A.DMod (_, _, inner, _) -> check_decls errctx inner
      | _ -> ())
    decls

let check_module (errctx : Err.ctx) (m : A.module_) : unit =
  check_decls errctx m.A.mod_decls
