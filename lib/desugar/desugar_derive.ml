(** Derive expansion — [derive <Iface> for <Type>] and [satisfy] expansion.

    Holds [derive_impl] (the per-interface code generator for Eq, Show, Json,
    Hash, …), the [satisfy] expander, and the span-uniquification machinery
    every derived node depends on: derived AST nodes would otherwise all carry
    the same [dummy_span], which breaks error attribution.

    Moved VERBATIM out of [Desugar] (finding 3 of
    [specs/2026-08-25-file-decomposition-analysis.md]).  The band was
    self-contained in BOTH directions — it referenced nothing defined
    elsewhere in [desugar.ml] and nothing below it — which is why it could
    move without the forward-ref hook that the [~H] sigil cluster would have
    needed.  Six names are re-exported from [Desugar] so external callers and
    [desugar.mli] are unchanged.

    [derive_impl] itself is private: its only call site is [expand_derive],
    below, in this file. *)

open March_ast.Ast
module Err = March_errors.Errors

(* ── Derive expansion ──────────────────────────────────────────────────── *)

(** Collect DType definitions: name → (type_params, type_def). *)
let collect_type_defs (decls : decl list) : (string * (name list * type_def)) list =
  List.filter_map (function
    | DType (_, name, tparams, td, _) -> Some (name.txt, (tparams, td))
    | _ -> None
  ) decls

(** Make a name with a dummy span. *)
let mk_name txt = { txt; span = dummy_span }

(** Make a single-clause fn_def with named params and a body expression. *)
let mk_fn_def name params body : fn_def =
  { fn_name   = mk_name name;
    fn_vis     = Private;
    fn_doc     = None;
    fn_attrs   = [];
    fn_ret_ty  = None;
    fn_bounds  = [];
    fn_clauses = [{
      fc_params = List.map (fun p ->
        FPNamed { param_name = mk_name p; param_ty = None; param_lin = Unrestricted }
      ) params;
      fc_guard  = None;
      fc_body   = body;
      fc_span   = dummy_span;
      fc_params_span = dummy_span;
    }] }

(* ── Derive-expansion span uniquification ──────────────────────────────

   Every AST node minted by [derive_impl] used to carry the SAME [dummy_span].
   The typechecker records inferred types keyed by span ([env.type_map],
   [Hashtbl.replace] — last write wins) and TIR lowering reads them back
   ([Lower_state.ty_of_span]), so a shared span made every derived node
   collide on ONE table entry: lowering saw arbitrary garbage types for
   derived params and body exprs (e.g. [Ord$Wrap.compare(a : (Wrap) -> Int)]),
   and the LLVM backend then picked the wrong representation strategy for the
   receiver match — SIGSEGV / non-exhaustive panic on Newtype-repr variant
   types (P1 in specs/todos.md).  Rewriting every span inside the generated
   decls to a fresh structurally-unique key gives each node its own type_map
   entry, so derived methods typecheck+lower exactly like hand-written impls.
   The file stays "<none>" so span-based synthetic-code filters (coverage's
   file check, the LSP's [= dummy_span] checks compare the whole record and
   never map "<none>" spans onto a document) keep treating derived code as
   synthetic. *)

let _synthetic_span_counter = ref 0

let fresh_synthetic_span () : span =
  incr _synthetic_span_counter;
  { file = "<none>"; start_line = !_synthetic_span_counter; start_col = 0;
    end_line = !_synthetic_span_counter; end_col = 0 }

let respan_name (n : name) : name = { n with span = fresh_synthetic_span () }

let rec respan_pat (p : pattern) : pattern =
  match p with
  | PatWild _            -> PatWild (fresh_synthetic_span ())
  | PatVar n             -> PatVar (respan_name n)
  | PatCon (n, subs)     -> PatCon (respan_name n, List.map respan_pat subs)
  | PatAtom (s, subs, _) -> PatAtom (s, List.map respan_pat subs, fresh_synthetic_span ())
  | PatTuple (subs, _)   -> PatTuple (List.map respan_pat subs, fresh_synthetic_span ())
  | PatLit (l, _)        -> PatLit (l, fresh_synthetic_span ())
  | PatRecord (fs, _)    ->
    PatRecord (List.map (fun (n, p) -> (respan_name n, respan_pat p)) fs,
               fresh_synthetic_span ())
  | PatAs (p, n, _)      -> PatAs (respan_pat p, respan_name n, fresh_synthetic_span ())
  | PatOr (ps, _)        -> PatOr (List.map respan_pat ps, fresh_synthetic_span ())

let rec respan_ty (t : ty) : ty =
  match t with
  | TyCon (n, args)      -> TyCon (respan_name n, List.map respan_ty args)
  | TyVar n              -> TyVar (respan_name n)
  | TyArrow (a, b)       -> TyArrow (respan_ty a, respan_ty b)
  | TyTuple ts           -> TyTuple (List.map respan_ty ts)
  | TyRecord fs          -> TyRecord (List.map (fun (n, t) -> (respan_name n, respan_ty t)) fs)
  | TyLinear (l, t)      -> TyLinear (l, respan_ty t)
  | TyNat _ as t         -> t
  | TyNatOp (op, a, b)   -> TyNatOp (op, respan_ty a, respan_ty b)
  | TyChan (a, b)        -> TyChan (respan_name a, respan_name b)
  | TyRefine (t, n, e)   -> TyRefine (respan_ty t, Option.map respan_name n, respan_expr e)

and respan_expr (e : expr) : expr =
  match e with
  | ELit (l, _)          -> ELit (l, fresh_synthetic_span ())
  | EVar n               -> EVar (respan_name n)
  | EApp (f, args, _)    -> EApp (respan_expr f, List.map respan_expr args, fresh_synthetic_span ())
  | ECon (n, args, _)    -> ECon (respan_name n, List.map respan_expr args, fresh_synthetic_span ())
  | ELam (ps, body, _)   -> ELam (List.map respan_param ps, respan_expr body, fresh_synthetic_span ())
  | EBlock (es, _)       -> EBlock (List.map respan_expr es, fresh_synthetic_span ())
  | ELet (b, _)          -> ELet (respan_binding b, fresh_synthetic_span ())
  | EMatch (s, brs, _)   -> EMatch (respan_expr s, List.map respan_branch brs, fresh_synthetic_span ())
  | ETuple (es, _)       -> ETuple (List.map respan_expr es, fresh_synthetic_span ())
  | ERecord (fs, _)      ->
    ERecord (List.map (fun (n, e) -> (respan_name n, respan_expr e)) fs, fresh_synthetic_span ())
  | ERecordUpdate (e, fs, _) ->
    ERecordUpdate (respan_expr e,
                   List.map (fun (n, e) -> (respan_name n, respan_expr e)) fs,
                   fresh_synthetic_span ())
  | EField (e, n, _)     -> EField (respan_expr e, respan_name n, fresh_synthetic_span ())
  | EIf (c, t, f, _)     -> EIf (respan_expr c, respan_expr t, respan_expr f, fresh_synthetic_span ())
  | ECond (arms, _)      ->
    ECond (List.map (fun (c, b) -> (respan_expr c, respan_expr b)) arms, fresh_synthetic_span ())
  | EPipe (a, b, _)      -> EPipe (respan_expr a, respan_expr b, fresh_synthetic_span ())
  | EAnnot (e, t, _)     -> EAnnot (respan_expr e, respan_ty t, fresh_synthetic_span ())
  | EHole (n, _)         -> EHole (Option.map respan_name n, fresh_synthetic_span ())
  | EAtom (s, args, _)   -> EAtom (s, List.map respan_expr args, fresh_synthetic_span ())
  | ESend (a, b, _)      -> ESend (respan_expr a, respan_expr b, fresh_synthetic_span ())
  | ESpawn (e, _)        -> ESpawn (respan_expr e, fresh_synthetic_span ())
  | EResultRef _ as e    -> e
  | EDbg (e, _)          -> EDbg (Option.map respan_expr e, fresh_synthetic_span ())
  | ELetFn (n, ps, rt, body, _) ->
    ELetFn (respan_name n, List.map respan_param ps, Option.map respan_ty rt,
            respan_expr body, fresh_synthetic_span ())
  | ELetQ (p, e1, e2, _) -> ELetQ (respan_pat p, respan_expr e1, respan_expr e2, fresh_synthetic_span ())
  | ELetStar (p, e1, e2, _) -> ELetStar (respan_pat p, respan_expr e1, respan_expr e2, fresh_synthetic_span ())
  | EAssert (e, _)       -> EAssert (respan_expr e, fresh_synthetic_span ())
  | ESigil (s, e, _)     -> ESigil (s, respan_expr e, fresh_synthetic_span ())

and respan_param (p : param) : param =
  { param_name = respan_name p.param_name;
    param_ty   = Option.map respan_ty p.param_ty;
    param_lin  = p.param_lin }

and respan_binding (b : binding) : binding =
  { bind_pat  = respan_pat b.bind_pat;
    bind_ty   = Option.map respan_ty b.bind_ty;
    bind_lin  = b.bind_lin;
    bind_expr = respan_expr b.bind_expr }

and respan_branch (br : branch) : branch =
  { branch_pat   = respan_pat br.branch_pat;
    branch_guard = Option.map respan_expr br.branch_guard;
    branch_body  = respan_expr br.branch_body }

let respan_fn_param : fn_param -> fn_param = function
  | FPPat p          -> FPPat (respan_pat p)
  | FPNamed p        -> FPNamed (respan_param p)
  | FPDefault (p, e) -> FPDefault (respan_param p, respan_expr e)

let respan_fn_def (fd : fn_def) : fn_def =
  { fd with
    fn_name    = respan_name fd.fn_name;
    fn_ret_ty  = Option.map respan_ty fd.fn_ret_ty;
    fn_bounds  = List.map (fun (n, t) -> (respan_name n, respan_ty t)) fd.fn_bounds;
    fn_clauses = List.map (fun c ->
        { fc_params = List.map respan_fn_param c.fc_params;
          fc_guard  = Option.map respan_expr c.fc_guard;
          fc_body   = respan_expr c.fc_body;
          fc_span   = fresh_synthetic_span ();
          fc_params_span = fresh_synthetic_span () }) fd.fn_clauses }

(** Uniquify every span inside a derive-generated decl (the decl's own
    top-level span — the derive site — is kept: it is a real user span used
    for error attribution).  [derive_impl] only emits [DImpl] and [DFn]
    (Json); any other decl kind passes through unchanged, which merely keeps
    today's shared-dummy-span behavior for it. *)
let respan_derived_decl (d : decl) : decl =
  match d with
  | DImpl (idef, sp) ->
    DImpl ({ impl_iface       = respan_name idef.impl_iface;
             impl_ty          = respan_ty idef.impl_ty;
             impl_constraints = List.map (fun (n, tys) ->
                 (respan_name n, List.map respan_ty tys)) idef.impl_constraints;
             impl_assoc_types = List.map (fun (n, t) ->
                 (respan_name n, respan_ty t)) idef.impl_assoc_types;
             impl_methods     = List.map (fun (n, fd) ->
                 (respan_name n, respan_fn_def fd)) idef.impl_methods },
           sp)
  | DFn (fd, sp) -> DFn (respan_fn_def fd, sp)
  | d -> d

(** Build derived declarations for one interface on [type_name].
    Returns a list of [decl] — usually one [DImpl], but [Json] produces
    two standalone [DFn] declarations (to_json / from_json).
    [iface_span] is the span of the interface name in the source, used for
    error reporting when the interface is unknown. *)
let derive_impl (errors : Err.ctx) (type_name : name) (sp : span)
    (iface : string) (iface_span : span) (tparams : name list) (td : type_def) : decl list =
  (* Type annotation for the type being implemented *)
  let self_ty : ty =
    if tparams = [] then TyCon (type_name, [])
    else TyCon (type_name, List.map (fun tp -> TyVar tp) tparams)
  in
  (* Helper: build an impl_def with a single method *)
  let impl_one meth_name fn_body_params fn_body =
    let fn_def = mk_fn_def meth_name fn_body_params fn_body in
    let idef : impl_def = {
      impl_iface       = mk_name iface;
      impl_ty          = self_ty;
      impl_constraints = [];
      impl_assoc_types = [];
      impl_methods     = [(mk_name meth_name, fn_def)];
    } in
    DImpl (idef, sp)
  in
  match iface with
  | "Eq" ->
    (* derive Eq: structural comparison using == on each field/variant.
       For variant types: match on pairs of constructors.
       For records: compare field-by-field.
       For aliases: delegate to the aliased type. *)
    let body = match td with
      | TDVariant variants ->
        (* match (a, b) with | (CtorA(args...), CtorA(args...)) -> all args eq | _ -> false *)
        let pair = ETuple ([EVar (mk_name "a"); EVar (mk_name "b")], dummy_span) in
        let branches = List.mapi (fun _i (v : variant) ->
            let n = List.length v.var_args in
            if n = 0 then
              (* no-arg ctor: Red, Red -> true *)
              { branch_pat = PatTuple (
                    [PatCon (v.var_name, []); PatCon (v.var_name, [])], dummy_span);
                branch_guard = None;
                branch_body  = ELit (LitBool true, dummy_span) }
            else begin
              (* ctor with args: Wrap(a0), Wrap(b0) -> a0 == b0 && ... *)
              let avar_names = List.init n (fun i -> Printf.sprintf "_da%d" i) in
              let bvar_names = List.init n (fun i -> Printf.sprintf "_db%d" i) in
              let pats_a = List.map (fun s -> PatVar (mk_name s)) avar_names in
              let pats_b = List.map (fun s -> PatVar (mk_name s)) bvar_names in
              let eq_exprs = List.map2 (fun sa sb ->
                  EApp (EVar (mk_name "=="),
                        [EVar (mk_name sa); EVar (mk_name sb)],
                        dummy_span)
                ) avar_names bvar_names in
              let body_expr = List.fold_right (fun eq_e acc ->
                  EApp (EVar (mk_name "&&"), [eq_e; acc], dummy_span)
                ) (List.rev (List.tl (List.rev eq_exprs)))
                  (List.nth eq_exprs (List.length eq_exprs - 1))
              in
              { branch_pat = PatTuple (
                    [PatCon (v.var_name, pats_a); PatCon (v.var_name, pats_b)], dummy_span);
                branch_guard = None;
                branch_body  = body_expr }
            end
          ) variants
        in
        (* wildcard arm: _ -> false *)
        let wild_branch = {
          branch_pat  = PatWild dummy_span;
          branch_guard = None;
          branch_body  = ELit (LitBool false, dummy_span);
        } in
        EMatch (pair, branches @ [wild_branch], dummy_span)
      | TDRecord fields ->
        (* compare each field: a.f == b.f && a.g == b.g && ... *)
        (match fields with
         | [] -> ELit (LitBool true, dummy_span)
         | [f] ->
           EApp (EVar (mk_name "=="),
                 [EField (EVar (mk_name "a"), f.fld_name, dummy_span);
                  EField (EVar (mk_name "b"), f.fld_name, dummy_span)],
                 dummy_span)
         | f :: rest ->
           let field_eq fld =
             EApp (EVar (mk_name "=="),
                   [EField (EVar (mk_name "a"), fld.fld_name, dummy_span);
                    EField (EVar (mk_name "b"), fld.fld_name, dummy_span)],
                   dummy_span)
           in
           List.fold_left (fun acc fld ->
               EApp (EVar (mk_name "&&"), [acc; field_eq fld], dummy_span)
             ) (field_eq f) rest)
      | TDAlias _ ->
        (* Delegate to the underlying type's eq *)
        EApp (EVar (mk_name "=="), [EVar (mk_name "a"); EVar (mk_name "b")], dummy_span)
    in
    [impl_one "eq" ["a"; "b"] body]

  | "Show" ->
    let body = match td with
      | TDVariant variants ->
        let branches = List.map (fun (v : variant) ->
            let n = List.length v.var_args in
            if n = 0 then
              { branch_pat  = PatCon (v.var_name, []);
                branch_guard = None;
                branch_body  = ELit (LitString v.var_name.txt, dummy_span) }
            else begin
              let arg_names = List.init n (fun i -> Printf.sprintf "_sv%d" i) in
              let pats = List.map (fun s -> PatVar (mk_name s)) arg_names in
              (* "Ctor(" ++ show(a0) ++ ", " ++ show(a1) ++ ... ++ ")" *)
              let parts = List.mapi (fun i s ->
                  let show_e = EApp (EVar (mk_name "show"), [EVar (mk_name s)], dummy_span) in
                  if i = 0 then show_e
                  else EApp (EVar (mk_name "++"),
                             [ELit (LitString ", ", dummy_span); show_e],
                             dummy_span)
                ) arg_names
              in
              let inner = List.fold_left (fun acc p ->
                  EApp (EVar (mk_name "++"), [acc; p], dummy_span)
                ) (ELit (LitString (v.var_name.txt ^ "("), dummy_span)) parts
              in
              let full = EApp (EVar (mk_name "++"),
                               [inner; ELit (LitString ")", dummy_span)],
                               dummy_span)
              in
              { branch_pat  = PatCon (v.var_name, pats);
                branch_guard = None;
                branch_body  = full }
            end
          ) variants
        in
        EMatch (EVar (mk_name "x"), branches, dummy_span)
      | TDRecord fields ->
        (* "TypeName { f1 = " ++ show(x.f1) ++ ", f2 = " ++ show(x.f2) ++ " }" *)
        let field_strs = List.mapi (fun i f ->
            let prefix = if i = 0 then f.fld_name.txt ^ " = " else ", " ^ f.fld_name.txt ^ " = " in
            let show_e = EApp (EVar (mk_name "show"),
                               [EField (EVar (mk_name "x"), f.fld_name, dummy_span)],
                               dummy_span)
            in
            EApp (EVar (mk_name "++"),
                  [ELit (LitString prefix, dummy_span); show_e],
                  dummy_span)
          ) fields
        in
        let header = ELit (LitString (type_name.txt ^ " { "), dummy_span) in
        let mid = List.fold_left (fun acc e ->
            EApp (EVar (mk_name "++"), [acc; e], dummy_span)
          ) header field_strs
        in
        EApp (EVar (mk_name "++"), [mid; ELit (LitString " }", dummy_span)], dummy_span)
      | TDAlias _ ->
        EApp (EVar (mk_name "show"), [EVar (mk_name "x")], dummy_span)
    in
    [impl_one "show" ["x"] body]

  | "Hash" ->
    (* Avoid calling hash() recursively (check_fn shadows the polymorphic binding).
       For variants: return the constructor index directly (stable hash).
       For records: use int_hash(field) via the builtin int hashing path. *)
    let body = match td with
      | TDVariant variants ->
        let branches = List.mapi (fun i (v : variant) ->
            let n = List.length v.var_args in
            let pats = List.init n (fun _ -> PatWild dummy_span) in
            { branch_pat  = PatCon (v.var_name, pats);
              branch_guard = None;
              branch_body  = ELit (LitInt i, dummy_span) }
          ) variants
        in
        EMatch (EVar (mk_name "x"), branches, dummy_span)
      | TDRecord fields ->
        (match fields with
         | [] -> ELit (LitInt 0, dummy_span)
         | fields ->
           (* Combine field hashes: fold over fields, mixing with prime *)
           let hash_field fld =
             (* Use the polymorphic hash for each field's value.
                Note: field values may be any type — hash is safe here since
                it's called on field values, not on x: Color. *)
             EApp (EVar (mk_name "hash"),
                   [EField (EVar (mk_name "x"), fld.fld_name, dummy_span)],
                   dummy_span)
           in
           (match fields with
            | [] -> ELit (LitInt 0, dummy_span)
            | [f] -> hash_field f
            | f :: rest ->
              List.fold_left (fun acc fld ->
                  EApp (EVar (mk_name "+"),
                        [EApp (EVar (mk_name "*"), [acc; ELit (LitInt 31, dummy_span)], dummy_span);
                         hash_field fld],
                        dummy_span)
                ) (hash_field f) rest))
      | TDAlias _ ->
        EApp (EVar (mk_name "hash"), [EVar (mk_name "x")], dummy_span)
    in
    [impl_one "hash" ["x"] body]

  | "Ord" ->
    (* derive Ord: compare constructors by their declaration index.
       For records: compare field by field lexicographically. *)
    let body = match td with
      | TDVariant variants ->
        (* fn compare(a, b) -> compare(ctor_index(a), ctor_index(b)) *)
        let index_of_branches var_name_for arg_count =
          List.mapi (fun i (v : variant) ->
              let n = List.length v.var_args in
              let pats = List.init n (fun _ -> PatWild dummy_span) in
              { branch_pat  = PatCon (v.var_name, pats);
                branch_guard = None;
                branch_body  = ELit (LitInt i, dummy_span) }
            ) variants
          |> (fun branches ->
               EMatch (EVar (mk_name var_name_for), branches, dummy_span))
          |> (fun e -> ignore arg_count; e)
        in
        let ai = index_of_branches "a" (List.length variants) in
        let bi = index_of_branches "b" (List.length variants) in
        (* let _ai = ...; let _bi = ...; compare(_ai, _bi) *)
        EBlock ([
          ELet ({ bind_pat = PatVar (mk_name "_oi_a"); bind_ty = None;
                  bind_lin = Unrestricted; bind_expr = ai }, dummy_span);
          ELet ({ bind_pat = PatVar (mk_name "_oi_b"); bind_ty = None;
                  bind_lin = Unrestricted; bind_expr = bi }, dummy_span);
          EApp (EVar (mk_name "-"),
                [EVar (mk_name "_oi_a"); EVar (mk_name "_oi_b")],
                dummy_span);
        ], dummy_span)
      | TDRecord fields ->
        (* Compare field by field; return first non-zero *)
        (match fields with
         | [] -> ELit (LitInt 0, dummy_span)
         | [f] ->
           EApp (EVar (mk_name "compare"),
                 [EField (EVar (mk_name "a"), f.fld_name, dummy_span);
                  EField (EVar (mk_name "b"), f.fld_name, dummy_span)],
                 dummy_span)
         | fields ->
           let stmts = List.mapi (fun i f ->
               let cmp_e =
                 EApp (EVar (mk_name "compare"),
                       [EField (EVar (mk_name "a"), f.fld_name, dummy_span);
                        EField (EVar (mk_name "b"), f.fld_name, dummy_span)],
                       dummy_span)
               in
               let name = Printf.sprintf "_cmp%d" i in
               ELet ({ bind_pat = PatVar (mk_name name); bind_ty = None;
                       bind_lin = Unrestricted; bind_expr = cmp_e }, dummy_span)
             ) fields
           in
           let final_cmp name i =
             if i = List.length fields - 1 then EVar (mk_name name)
             else
               EIf (EApp (EVar (mk_name "!="),
                          [EVar (mk_name name); ELit (LitInt 0, dummy_span)],
                          dummy_span),
                    EVar (mk_name name),
                    EVar (mk_name (Printf.sprintf "_cmp%d" (i + 1))),
                    dummy_span)
           in
           let last_name = Printf.sprintf "_cmp%d" (List.length fields - 1) in
           let result =
             List.fold_right (fun (i, f) acc ->
                 ignore f;
                 let cname = Printf.sprintf "_cmp%d" i in
                 if i = List.length fields - 1 then EVar (mk_name last_name)
                 else
                   EIf (EApp (EVar (mk_name "!="),
                              [EVar (mk_name cname); ELit (LitInt 0, dummy_span)],
                              dummy_span),
                        EVar (mk_name cname),
                        acc,
                        dummy_span)
               ) (List.mapi (fun i f -> (i, f)) fields |> List.rev |> List.tl |> List.rev)
               (EVar (mk_name last_name))
           in
           ignore result;
           ignore final_cmp;
           EBlock (stmts @ [
             List.fold_right (fun (i, _f) acc ->
                 let cname = Printf.sprintf "_cmp%d" i in
                 if i = List.length fields - 1 then EVar (mk_name cname)
                 else EIf (EApp (EVar (mk_name "!="),
                                 [EVar (mk_name cname); ELit (LitInt 0, dummy_span)],
                                 dummy_span),
                           EVar (mk_name cname), acc, dummy_span)
               ) (List.mapi (fun i f -> (i, f)) fields |> List.rev) (ELit (LitInt 0, dummy_span))
           ], dummy_span))
      | TDAlias _ ->
        EApp (EVar (mk_name "compare"), [EVar (mk_name "a"); EVar (mk_name "b")], dummy_span)
    in
    [impl_one "compare" ["a"; "b"] body]

  | "Json" when March_caps.Cap_surface_ty.caps_in_type_def td <> [] ->
    (* Capability unforgeability (R3).  A capability may be received and
       narrowed, never constructed; a derived Json codec over a `Cap` position
       is a construction route, so the derive is refused outright rather than
       generated with a hole in it.

       Why this is caught HERE and not by the generated code failing to
       typecheck: `encoder_for_ty` and `decode_value_at` below both fall back
       to "assume the nested type also derives Json" for any type they do not
       recognise.  `Cap(X)` is not recognised, so the codec was generated over
       the capability position without complaint and the decoder ran far
       enough to return a Json.DecodeError — a runtime failure that looks like
       bad input rather than a refused operation.

       Rejecting at the `derive` declaration also puts the diagnostic on a
       real span.  Every declaration this branch generates carries
       `dummy_span`, so an error raised from inside the generated codec would
       have nowhere useful to point.

       Both directions are refused together (see the message): a rule that
       rejected only decoding would leave `derive Json` half-expanded, with a
       working encoder beside a refused decoder. *)
    let caps = March_caps.Cap_surface_ty.caps_in_type_def td in
    let cap = List.hd caps in
    Err.error errors ~span:iface_span
      (Printf.sprintf
         "`Cap(%s)` cannot be deserialized — a capability may only be \
          received, never constructed, so `%s` cannot derive Json.\n\
          hint: hold the capability in a separate value and pass it as a \
          parameter, keeping `%s` free of capability fields."
         cap type_name.txt type_name.txt);
    []

  | "Json" ->
    (* derive Json: generate standalone to_json and from_json functions.
       to_json(x : T) : JsonValue   — structural encoding to JSON
       from_json(v : JsonValue) : Result(T, String) — decoding from JSON *)
    let sp = dummy_span in
    (* Helper: encode a field value based on its type annotation *)
    let encoder_for_ty (ty : ty) (value_expr : expr) : expr =
      match ty with
      | TyCon ({txt = "String"; _}, []) ->
        EApp (EVar (mk_name "Json.encode_string"), [value_expr], sp)
      | TyCon ({txt = "Int"; _}, []) ->
        EApp (EVar (mk_name "Json.encode_int"), [value_expr], sp)
      | TyCon ({txt = "Float"; _}, []) ->
        EApp (EVar (mk_name "Json.encode_number"), [value_expr], sp)
      | TyCon ({txt = "Bool"; _}, []) ->
        EApp (EVar (mk_name "Json.encode_bool"), [value_expr], sp)
      | _ ->
        (* Assume nested type also derives Json — call to_json recursively *)
        EApp (EVar (mk_name "to_json"), [value_expr], sp)
    in
    (* ── to_json ────────────────────────────────────────────── *)
    let to_json_body = match td with
      | TDRecord fields ->
        (* Json.encode_object([("f1", encode(x.f1)), ("f2", encode(x.f2)), ...]) *)
        let pair_exprs = List.map (fun (f : field) ->
            let field_access = EField (EVar (mk_name "x"), f.fld_name, sp) in
            let encoded = encoder_for_ty f.fld_ty field_access in
            ETuple ([ELit (LitString f.fld_name.txt, sp); encoded], sp)
          ) fields
        in
        let pairs_list = List.fold_right (fun e acc ->
            ECon (mk_name "Cons", [e; acc], sp)
          ) pair_exprs (ECon (mk_name "Nil", [], sp))
        in
        EApp (EVar (mk_name "Json.encode_object"), [pairs_list], sp)
      | TDVariant variants ->
        (* match x with
           | Ctor0 -> encode_object([("tag", encode_string("Ctor0"))])
           | Ctor1(v0) -> encode_object([("tag", ...), ("0", encode(v0))]) *)
        let branches = List.map (fun (v : variant) ->
            let n = List.length v.var_args in
            let arg_names = List.init n (fun i -> Printf.sprintf "_jv%d" i) in
            let pats = List.map (fun s -> PatVar (mk_name s)) arg_names in
            let tag_pair = ETuple ([
                ELit (LitString "tag", sp);
                EApp (EVar (mk_name "Json.encode_string"),
                      [ELit (LitString v.var_name.txt, sp)], sp)
              ], sp) in
            let arg_pairs = List.mapi (fun i arg_name ->
                let ty = List.nth v.var_args i in
                ETuple ([
                    ELit (LitString (string_of_int i), sp);
                    encoder_for_ty ty (EVar (mk_name arg_name))
                  ], sp)
              ) arg_names
            in
            let all_pairs = tag_pair :: arg_pairs in
            let pairs_list = List.fold_right (fun e acc ->
                ECon (mk_name "Cons", [e; acc], sp)
              ) all_pairs (ECon (mk_name "Nil", [], sp))
            in
            { branch_pat = PatCon (v.var_name, pats);
              branch_guard = None;
              branch_body = EApp (EVar (mk_name "Json.encode_object"), [pairs_list], sp) }
          ) variants
        in
        EMatch (EVar (mk_name "x"), branches, sp)
      | TDAlias _ ->
        EApp (EVar (mk_name "to_json"), [EVar (mk_name "x")], sp)
    in
    (* ── from_json ──────────────────────────────────────────── *)
    (* Shared helpers for the TDRecord decoder: build a Json.DecodeError
       whose path is a single JPathField(key) step (or Nil for the
       root-level "expected an object" case), so every failure names the
       field that caused it instead of one opaque wildcard error. *)
    let jpath_field_step (key : string) : expr =
      ECon (mk_name "Json.JPathField", [ELit (LitString key, sp)], sp)
    in
    let nil_path : expr = ECon (mk_name "Nil", [], sp) in
    let single_step_path (key : string) : expr =
      ECon (mk_name "Cons", [jpath_field_step key; nil_path], sp)
    in
    let mk_decode_err (msg : string) (path : expr) : expr =
      ECon (mk_name "Json.DecodeError",
            [ELit (LitString msg, sp); path; ELit (LitInt (-1), sp)], sp)
    in
    let err_at_field (msg : string) (key : string) : expr =
      ECon (mk_name "Err", [mk_decode_err msg (single_step_path key)], sp)
    in
    (* Variant-decoding counterparts of the above: a positional argument's
       path step is JPathIndex(i) rather than JPathField(key), so an argument
       error renders as `$[0]: expected Int` instead of `$.field: ...`. *)
    let jpath_index_step (i : int) : expr =
      ECon (mk_name "Json.JPathIndex", [ELit (LitInt i, sp)], sp)
    in
    let single_index_path (i : int) : expr =
      ECon (mk_name "Cons", [jpath_index_step i; nil_path], sp)
    in
    let err_at_path (msg : string) (path : expr) : expr =
      ECon (mk_name "Err", [mk_decode_err msg path], sp)
    in
    let mk_decode_err_expr (msg_expr : expr) (path : expr) : expr =
      ECon (mk_name "Json.DecodeError", [msg_expr; path; ELit (LitInt (-1), sp)], sp)
    in
    let cat2 (a : expr) (b : expr) : expr =
      EApp (EVar (mk_name "++"), [a; b], sp)
    in
    (* Decode a single field's raw JsonValue (bound to [fv]) according to its
       declared type, then invoke [k] with the expression for the decoded
       (already-converted) value. For a nested derive-Json type, recurse via
       from_json and prepend this field's step to the inner error — this one
       line (Json.decode_error_under) is what makes a path like `$.inner.id`
       compose across a record boundary without threading a cursor through
       user code. *)
    (* Generic version: decode a raw JsonValue (bound to [fv]) according to
       its declared type, given the path [step] to prepend to a nested error
       (via Json.decode_error_under) and the full [single_path] to use for a
       directly-observed type-mismatch at this position. Record fields use
       JPathField(key) for both; variant arguments use JPathIndex(i). *)
    let decode_value_at (ty : ty) (fv : name) (step : expr) (single_path : expr)
        (k : expr -> expr) : expr =
      let scalar_case (ctor : string) (msg : string)
          (conv : expr -> expr) : expr =
        let bound = mk_name (fv.txt ^ "_v") in
        EMatch (EVar fv, [
            { branch_pat = PatCon (mk_name ctor, [PatVar bound]);
              branch_guard = None;
              branch_body = k (conv (EVar bound)) };
            { branch_pat = PatWild sp;
              branch_guard = None;
              branch_body = err_at_path msg single_path };
          ], sp)
      in
      match ty with
      | TyCon ({txt = "String"; _}, []) ->
        scalar_case "Str" "expected String" (fun e -> e)
      | TyCon ({txt = "Int"; _}, []) ->
        scalar_case "Number" "expected Int"
          (fun e -> EApp (EVar (mk_name "float_to_int"), [e], sp))
      | TyCon ({txt = "Float"; _}, []) ->
        scalar_case "Number" "expected Float" (fun e -> e)
      | TyCon ({txt = "Bool"; _}, []) ->
        scalar_case "Bool" "expected Bool" (fun e -> e)
      | _ ->
        let inner_ok = mk_name (fv.txt ^ "_ok") in
        let inner_err = mk_name (fv.txt ^ "_err") in
        EMatch (EApp (EVar (mk_name "from_json"), [EVar fv], sp), [
            { branch_pat = PatCon (mk_name "Ok", [PatVar inner_ok]);
              branch_guard = None;
              branch_body = k (EVar inner_ok) };
            { branch_pat = PatCon (mk_name "Err", [PatVar inner_err]);
              branch_guard = None;
              branch_body = ECon (mk_name "Err",
                [EApp (EVar (mk_name "Json.decode_error_under"),
                       [step; EVar inner_err], sp)], sp) };
          ], sp)
    in
    let decode_field_value (ty : ty) (fv : name) (key : string)
        (k : expr -> expr) : expr =
      decode_value_at ty fv (jpath_field_step key) (single_step_path key) k
    in
    let decode_arg_value (ty : ty) (fv : name) (i : int)
        (k : expr -> expr) : expr =
      decode_value_at ty fv (jpath_index_step i) (single_index_path i) k
    in
    (* Build the right-nested per-field chain (Step 4 of the design):
         match Json.get_field(kvs, "f1") do
         None -> Err(DecodeError("missing field", [JPathField("f1")], -1))
         Some(fv1) -> match fv1 do
           <ok-pattern> -> <recurse into rest, or Ok({...}) at the end>
           _ -> Err(DecodeError("expected <Ty>", [JPathField("f1")], -1))
           end
         end
       Fields are looked up by name one at a time and never enumerated, so
       unmentioned/unknown JSON keys are silently ignored for free — no
       separate handling is needed for "unknown fields are ignored". *)
    let rec build_field_chain (fields : field list)
        (decoded : (name * expr) list) : expr =
      match fields with
      | [] -> ECon (mk_name "Ok", [ERecord (List.rev decoded, sp)], sp)
      | f :: rest ->
        let key = f.fld_name.txt in
        let fv = mk_name (Printf.sprintf "_jf_%s" key) in
        let get_expr = EApp (EVar (mk_name "Json.get_field"),
                             [EVar (mk_name "kvs"); ELit (LitString key, sp)], sp)
        in
        let some_body = decode_field_value f.fld_ty fv key (fun value_expr ->
            build_field_chain rest ((f.fld_name, value_expr) :: decoded))
        in
        EMatch (get_expr, [
            { branch_pat = PatCon (mk_name "None", []);
              branch_guard = None;
              branch_body = err_at_field "missing field" key };
            { branch_pat = PatCon (mk_name "Some", [PatVar fv]);
              branch_guard = None;
              branch_body = some_body };
          ], sp)
    in
    let from_json_body = match td with
      | TDRecord fields ->
        let kvs = mk_name "kvs" in
        let object_branch = {
          branch_pat = PatCon (mk_name "Object", [PatVar kvs]);
          branch_guard = None;
          branch_body = build_field_chain fields [];
        } in
        let not_object_branch = {
          branch_pat = PatWild sp;
          branch_guard = None;
          branch_body = ECon (mk_name "Err",
            [mk_decode_err "expected an object" nil_path], sp);
        } in
        EMatch (EVar (mk_name "v"), [object_branch; not_object_branch], sp)
      | TDVariant variants ->
        (* match v do
             Object(kvs) -> match Json.get_field(kvs, "tag") do
               None -> Err(DecodeError("missing field", [JPathField("tag")], -1))
               Some(tagv) -> match tagv do
                 Str("Ctor0") -> Ok(Ctor0)
                 Str("Ctor1") -> <build_arg_chain over kvs, keys "0","1",...>
                 Str(tagstr) -> Err(DecodeError("unknown variant `" ++ tagstr ++ "`", [JPathField("tag")], -1))
                 _ -> Err(DecodeError("expected String", [JPathField("tag")], -1))
               end
             end
             _ -> Err(DecodeError("expected an object", Nil, -1))
           end
           Each argument is looked up positionally by string key ("0", "1", ...)
           out of the same object, mirroring the wire shape the encoder above
           produces (tag + numeric-string keys), and its error is tagged with
           JPathIndex(i) rather than JPathField(key) so it renders as
           `$[i]: ...` — see decode_arg_value/build_arg_chain. *)
        let kvs = mk_name "kvs" in
        let tagv = mk_name "tagv" in
        let tagstr = mk_name "_tagstr" in
        let tag_path = single_step_path "tag" in
        let rec build_arg_chain (ctor_name : name) (arg_tys : ty list)
            (idx : int) (decoded : expr list) : expr =
          match arg_tys with
          | [] -> ECon (mk_name "Ok", [ECon (ctor_name, List.rev decoded, sp)], sp)
          | ty :: rest ->
            let key = string_of_int idx in
            let fv = mk_name (Printf.sprintf "_ja_%d" idx) in
            let get_expr = EApp (EVar (mk_name "Json.get_field"),
                                 [EVar kvs; ELit (LitString key, sp)], sp)
            in
            let some_body = decode_arg_value ty fv idx (fun value_expr ->
                build_arg_chain ctor_name rest (idx + 1) (value_expr :: decoded))
            in
            EMatch (get_expr, [
                { branch_pat = PatCon (mk_name "None", []);
                  branch_guard = None;
                  branch_body = err_at_path "missing field" (single_index_path idx) };
                { branch_pat = PatCon (mk_name "Some", [PatVar fv]);
                  branch_guard = None;
                  branch_body = some_body };
              ], sp)
        in
        let tag_branches = List.map (fun (variant_def : variant) ->
            { branch_pat = PatCon (mk_name "Str",
                [PatLit (LitString variant_def.var_name.txt, sp)]);
              branch_guard = None;
              branch_body = build_arg_chain variant_def.var_name variant_def.var_args 0 [] }
          ) variants
        in
        let unknown_variant_branch = {
          branch_pat = PatCon (mk_name "Str", [PatVar tagstr]);
          branch_guard = None;
          branch_body = ECon (mk_name "Err",
            [mk_decode_err_expr
               (cat2 (cat2 (ELit (LitString "unknown variant `", sp)) (EVar tagstr))
                     (ELit (LitString "`", sp)))
               tag_path], sp);
        } in
        let tag_not_string_branch = {
          branch_pat = PatWild sp;
          branch_guard = None;
          branch_body = err_at_path "expected String" tag_path;
        } in
        let tagv_match = EMatch (EVar tagv,
            tag_branches @ [unknown_variant_branch; tag_not_string_branch], sp)
        in
        let object_branch = {
          branch_pat = PatCon (mk_name "Object", [PatVar kvs]);
          branch_guard = None;
          branch_body = EMatch (
            EApp (EVar (mk_name "Json.get_field"),
                  [EVar kvs; ELit (LitString "tag", sp)], sp),
            [ { branch_pat = PatCon (mk_name "None", []);
                branch_guard = None;
                branch_body = err_at_field "missing field" "tag" };
              { branch_pat = PatCon (mk_name "Some", [PatVar tagv]);
                branch_guard = None;
                branch_body = tagv_match } ], sp);
        } in
        let not_object_branch = {
          branch_pat = PatWild sp;
          branch_guard = None;
          branch_body = ECon (mk_name "Err",
            [mk_decode_err "expected an object" nil_path], sp);
        } in
        EMatch (EVar (mk_name "v"), [object_branch; not_object_branch], sp)
      | TDAlias _ ->
        EApp (EVar (mk_name "from_json"), [EVar (mk_name "v")], sp)
    in
    (* Generate two DImpl blocks with pseudo-interfaces "JsonTo" and "JsonFrom".
       This allows impl_tbl dispatch for variant types, while also binding
       to_json/from_json in the local env for record types. *)
    let to_json_fn = mk_fn_def "to_json" ["x"] to_json_body in
    let from_json_fn = mk_fn_def "from_json" ["v"] from_json_body in
    let mk_json_impl iface_name meth_name fn_body =
      let idef : impl_def = {
        impl_iface       = mk_name iface_name;
        impl_ty          = self_ty;
        impl_constraints = [];
        impl_assoc_types = [];
        impl_methods     = [(mk_name meth_name, fn_body)];
      } in
      DImpl (idef, sp)
    in
    (* ── from_json_events (Task 7 / Phase B) ───────────────────────────
       A second, event-consuming decoder, generated ONLY for TDRecord
       types (task-7-brief.md's Step 2 illustrates a record-specific state
       machine; TDVariant/TDAlias keep only the tree-based to_json/
       from_json above -- extending the event path to variants is
       explicitly out of this task's scope).

       from_json_events(events : List(JsonStream.Event))
         : Result((T, List(JsonStream.Event)), Json.DecodeError)

       consumes exactly the events belonging to one value of type T off
       the FRONT of [events] and returns the decoded value paired with
       whatever events remain -- this is what lets a nested derived-Json
       field recurse by calling its own from_json_events on the same
       stream and threading the remainder back out, without ever
       building a JsonValue tree. This mirrors the "JsonFrom"/"JsonTo"
       pseudo-interface trick above: iface name "JsonFromEvents" starts
       with "Json", so eval.ml's/typecheck.ml's [is_json_iface]/
       [is_json_derive] prefix checks treat it exactly like from_json --
       skip interface-existence validation, bind the bare method name in
       the local env (not impl_tbl-dispatched), self-recursive closure --
       with NO changes needed to either file. This also means
       from_json_events inherits the SAME cross-type shadowing caveat as
       bare from_json (lib/eval/eval.ml's DImpl handling name-binds it
       per-derive, so the LAST type to derive Json in a module owns the
       bare name) -- a known, separately-tracked issue, not a new one.

       Two helpers are generated as LOCAL recursive functions (`ELetFn`,
       scoped to this from_json_events body) rather than extra top-level
       `pfn` declarations, so that two types deriving Json in the same
       module never collide on a shared top-level helper name -- unlike
       the shared bare `from_json`/`to_json` names (which tolerate
       last-wins shadowing by design), a stray collision on an internal
       helper would be a new, gratuitous bug.

       - skip(events, depth): unknown-field subtree skip. Tracks
         container depth EXPLICITLY (EvObjStart/EvArrStart increment,
         EvObjEnd/EvArrEnd decrement) and stops only when depth returns
         to the level it started at -- see task-7-brief.md's Step 3 for
         why counting only "the next event" would silently desynchronize
         the stream instead of erroring.
       - loop(events, slot_f1, slot_f2, ...): one Option slot per field
         (all None initially). On EvKey(k) matching a field whose slot is
         still None, decode that field's value and recurse with the slot
         filled; on EvKey(k) matching a field whose slot is ALREADY Some
         (a duplicate key) or matching no field at all (an unknown key),
         skip the value via `skip` and recurse UNCHANGED --
         first-occurrence-wins for duplicates, matching the tree
         decoder's Json.get_field/Json.parse behavior (the capability
         map), which the oracle in test_json_typed.march requires the two
         decoders to agree on. On EvObjEnd, every slot must be Some, else
         `DecodeError("missing field", ...)`. *)
    let from_json_events_impl : decl option =
      match td with
      | TDRecord fields ->
        let ev_field_slots = List.mapi (fun i (f : field) ->
            (i, f, mk_name (Printf.sprintf "_evf_%s" f.fld_name.txt))
          ) fields
        in
        let skip_name = mk_name "_ev_skip" in
        let loop_name = mk_name "_ev_loop" in
        let sk_events = mk_name "_sk_events" in
        let sk_depth  = mk_name "_sk_depth" in
        let sk_rest   = mk_name "_sk_rest" in
        let depth_e = EVar sk_depth in
        let depth_plus1  = EApp (EVar (mk_name "+"), [depth_e; ELit (LitInt 1, sp)], sp) in
        let depth_minus1 = EApp (EVar (mk_name "-"), [depth_e; ELit (LitInt 1, sp)], sp) in
        let depth_eq n = EApp (EVar (mk_name "=="), [depth_e; ELit (LitInt n, sp)], sp) in
        let sk_recurse events_e depth_e2 =
          EApp (EVar skip_name, [events_e; depth_e2], sp)
        in
        let sk_ok_rest = ECon (mk_name "Ok", [EVar sk_rest], sp) in
        let sk_close_branch =
          EIf (depth_eq 1, sk_ok_rest, sk_recurse (EVar sk_rest) depth_minus1, sp)
        in
        let skip_body =
          EMatch (EVar sk_events, [
              { branch_pat = PatCon (mk_name "Nil", []);
                branch_guard = None;
                branch_body = ECon (mk_name "Err",
                  [mk_decode_err "truncated while skipping an unknown field's value" nil_path], sp) };
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvObjStart", []); PatVar sk_rest]);
                branch_guard = None;
                branch_body = sk_recurse (EVar sk_rest) depth_plus1 };
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvArrStart", []); PatVar sk_rest]);
                branch_guard = None;
                branch_body = sk_recurse (EVar sk_rest) depth_plus1 };
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvObjEnd", []); PatVar sk_rest]);
                branch_guard = None;
                branch_body = sk_close_branch };
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvArrEnd", []); PatVar sk_rest]);
                branch_guard = None;
                branch_body = sk_close_branch };
              { branch_pat = PatCon (mk_name "Cons", [PatWild sp; PatVar sk_rest]);
                branch_guard = None;
                branch_body = EIf (depth_eq 0, sk_ok_rest, sk_recurse (EVar sk_rest) depth_e, sp) };
            ], sp)
        in
        let skip_fn_letfn =
          ELetFn (skip_name,
            [ { param_name = sk_events; param_ty = None; param_lin = Unrestricted };
              { param_name = sk_depth;  param_ty = None; param_lin = Unrestricted } ],
            None, skip_body, sp)
        in
        (* Decode one field's value out of the events immediately
           following its EvKey, mirroring decode_value_at above but
           consuming events instead of a JsonValue -- see
           decode_value_at's comment for why a nested derived-Json field
           recurses via decode_error_under. Returns
           Result((value, remaining_events), DecodeError). *)
        let decode_field_from_events (fty : ty) (events_e : expr)
            (step : expr) (single_path : expr) : expr =
          let scalar_case (ctor : string) (msg : string) (conv : expr -> expr) : expr =
            let bound = mk_name "_evsv" in
            let rest3 = mk_name "_evsrest" in
            EMatch (events_e, [
                { branch_pat = PatCon (mk_name "Cons",
                    [PatCon (mk_name ctor, [PatVar bound]); PatVar rest3]);
                  branch_guard = None;
                  branch_body = ECon (mk_name "Ok",
                    [ETuple ([conv (EVar bound); EVar rest3], sp)], sp) };
                { branch_pat = PatWild sp;
                  branch_guard = None;
                  branch_body = ECon (mk_name "Err", [mk_decode_err msg single_path], sp) };
              ], sp)
          in
          match fty with
          | TyCon ({txt = "String"; _}, []) ->
            scalar_case "EvStr" "expected String" (fun e -> e)
          | TyCon ({txt = "Int"; _}, []) ->
            scalar_case "EvNum" "expected Int"
              (fun e -> EApp (EVar (mk_name "float_to_int"), [e], sp))
          | TyCon ({txt = "Float"; _}, []) ->
            scalar_case "EvNum" "expected Float" (fun e -> e)
          | TyCon ({txt = "Bool"; _}, []) ->
            scalar_case "EvBool" "expected Bool" (fun e -> e)
          | _ ->
            (* Assume the field's type also derives Json and recurses via
               ITS OWN generated from_json_events, threading the
               remaining-events tuple straight through on success and
               prefixing this field's path step on failure. *)
            let inner_ok = mk_name "_evok" in
            let inner_rest = mk_name "_evokrest" in
            let inner_err = mk_name "_everr" in
            EMatch (EApp (EVar (mk_name "from_json_events"), [events_e], sp), [
                { branch_pat = PatCon (mk_name "Ok",
                    [PatTuple ([PatVar inner_ok; PatVar inner_rest], sp)]);
                  branch_guard = None;
                  branch_body = ECon (mk_name "Ok",
                    [ETuple ([EVar inner_ok; EVar inner_rest], sp)], sp) };
                { branch_pat = PatCon (mk_name "Err", [PatVar inner_err]);
                  branch_guard = None;
                  branch_body = ECon (mk_name "Err",
                    [EApp (EVar (mk_name "Json.decode_error_under"),
                           [step; EVar inner_err], sp)], sp) };
              ], sp)
        in
        let cursor = mk_name "_ev_cursor" in
        let all_slots = List.map (fun (_, _, s) -> s) ev_field_slots in
        let slots_as_evars = List.map (fun s -> EVar s) all_slots in
        let key_v = mk_name "_evk" in
        let after_key_v = mk_name "_evrestk" in
        let tail_v = mk_name "_evtail" in
        (* Skip one whole value (unknown key, or a duplicate of a
           known key), then resume the loop with the slots UNCHANGED. *)
        let skip_and_continue (events_after_e : expr) (slot_args : expr list) : expr =
          let sk2_ok = mk_name "_evskrest" in
          let sk2_err = mk_name "_evskerr" in
          EMatch (EApp (EVar skip_name, [events_after_e; ELit (LitInt 0, sp)], sp), [
              { branch_pat = PatCon (mk_name "Ok", [PatVar sk2_ok]);
                branch_guard = None;
                branch_body = EApp (EVar loop_name, EVar sk2_ok :: slot_args, sp) };
              { branch_pat = PatCon (mk_name "Err", [PatVar sk2_err]);
                branch_guard = None;
                branch_body = ECon (mk_name "Err", [EVar sk2_err], sp) };
            ], sp)
        in
        let is_some_expr (e : expr) : expr =
          EMatch (e, [
              { branch_pat = PatCon (mk_name "Some", [PatWild sp]);
                branch_guard = None; branch_body = ELit (LitBool true, sp) };
              { branch_pat = PatWild sp;
                branch_guard = None; branch_body = ELit (LitBool false, sp) };
            ], sp)
        in
        let rec build_key_chain (remaining : (int * field * name) list) : expr =
          match remaining with
          | [] ->
            (* No field matched this key: unknown field. *)
            skip_and_continue (EVar after_key_v) slots_as_evars
          | (i, f, slot) :: rest ->
            let key_eq = EApp (EVar (mk_name "=="),
              [EVar key_v; ELit (LitString f.fld_name.txt, sp)], sp) in
            let decode_and_set =
              let decoded = decode_field_from_events f.fld_ty (EVar after_key_v)
                  (jpath_field_step f.fld_name.txt) (single_step_path f.fld_name.txt) in
              let dv = mk_name "_evdv" in
              let drest = mk_name "_evdrest" in
              let derr = mk_name "_evderr" in
              EMatch (decoded, [
                  { branch_pat = PatCon (mk_name "Ok",
                      [PatTuple ([PatVar dv; PatVar drest], sp)]);
                    branch_guard = None;
                    branch_body =
                      let new_args = List.mapi (fun j s ->
                          if j = i then ECon (mk_name "Some", [EVar dv], sp)
                          else EVar s) all_slots in
                      EApp (EVar loop_name, EVar drest :: new_args, sp) };
                  { branch_pat = PatCon (mk_name "Err", [PatVar derr]);
                    branch_guard = None;
                    branch_body = ECon (mk_name "Err", [EVar derr], sp) };
                ], sp)
            in
            EIf (key_eq,
              (* Duplicate key (slot already filled): first-wins, so skip
                 this occurrence's value instead of overwriting. *)
              EIf (is_some_expr (EVar slot),
                   skip_and_continue (EVar after_key_v) slots_as_evars,
                   decode_and_set, sp),
              build_key_chain rest, sp)
        in
        let rec build_finish_chain (remaining : (int * field * name) list)
            (decoded : (name * expr) list) (tail_e : expr) : expr =
          match remaining with
          | [] -> ECon (mk_name "Ok",
              [ETuple ([ERecord (List.rev decoded, sp); tail_e], sp)], sp)
          | (_, f, slot) :: rest ->
            let bv = mk_name (Printf.sprintf "_evfv_%s" f.fld_name.txt) in
            EMatch (EVar slot, [
                { branch_pat = PatCon (mk_name "Some", [PatVar bv]);
                  branch_guard = None;
                  branch_body = build_finish_chain rest
                    ((f.fld_name, EVar bv) :: decoded) tail_e };
                { branch_pat = PatCon (mk_name "None", []);
                  branch_guard = None;
                  branch_body = err_at_field "missing field" f.fld_name.txt };
              ], sp)
        in
        let loop_body =
          EMatch (EVar cursor, [
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvObjEnd", []); PatVar tail_v]);
                branch_guard = None;
                branch_body = build_finish_chain ev_field_slots [] (EVar tail_v) };
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvKey", [PatVar key_v]); PatVar after_key_v]);
                branch_guard = None;
                branch_body = build_key_chain ev_field_slots };
              { branch_pat = PatCon (mk_name "Nil", []);
                branch_guard = None;
                branch_body = ECon (mk_name "Err",
                  [mk_decode_err "truncated while decoding an object" nil_path], sp) };
              { branch_pat = PatWild sp;
                branch_guard = None;
                branch_body = ECon (mk_name "Err",
                  [mk_decode_err "expected a field name or end of object" nil_path], sp) };
            ], sp)
        in
        let loop_params =
          { param_name = cursor; param_ty = None; param_lin = Unrestricted }
          :: List.map (fun s -> { param_name = s; param_ty = None; param_lin = Unrestricted }) all_slots
        in
        let loop_fn_letfn = ELetFn (loop_name, loop_params, None, loop_body, sp) in
        let rest0 = mk_name "_ev_rest0" in
        let all_none_args = List.map (fun _ -> ECon (mk_name "None", [], sp)) all_slots in
        let top_body =
          EMatch (EVar (mk_name "events"), [
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvObjStart", []); PatVar rest0]);
                branch_guard = None;
                branch_body = EApp (EVar loop_name, EVar rest0 :: all_none_args, sp) };
              { branch_pat = PatWild sp;
                branch_guard = None;
                branch_body = ECon (mk_name "Err",
                  [mk_decode_err "expected an object" nil_path], sp) };
            ], sp)
        in
        let full_body = EBlock ([skip_fn_letfn; loop_fn_letfn; top_body], sp) in
        let from_json_events_fn = mk_fn_def "from_json_events" ["events"] full_body in
        Some (mk_json_impl "JsonFromEvents" "from_json_events" from_json_events_fn)
      | TDVariant _ | TDAlias _ -> None
    in
    [mk_json_impl "JsonTo" "to_json" to_json_fn;
     mk_json_impl "JsonFrom" "from_json" from_json_fn]
    @ (match from_json_events_impl with Some d -> [d] | None -> [])

  | _ ->
    Err.error errors ~span:iface_span
      (Printf.sprintf
         "Unknown derive target `%s` for type `%s`.\n\
          Supported interfaces: Eq, Show, Hash, Ord, Json"
         iface type_name.txt);
    []

(** Expand a [DDeriving] into zero or more [DImpl] blocks.
    Emits an error for unknown interfaces and for unknown target types. *)
let expand_derive
    (errors : Err.ctx)
    (type_defs : (string * (name list * type_def)) list)
    (type_name : name)
    (ifaces : name list)
    (sp : span)
  : decl list =
  match List.assoc_opt type_name.txt type_defs with
  | None ->
    Err.error errors ~span:type_name.span
      (Printf.sprintf
         "Unknown type `%s` in `derive` — is it declared in this module?"
         type_name.txt);
    []
  | Some (tparams, td) ->
    List.concat_map (fun (iface_name : name) ->
        derive_impl errors type_name sp iface_name.txt iface_name.span tparams td
        |> List.map respan_derived_decl
      ) ifaces

(** Collect top-level function definitions for satisfy expansion. *)
let collect_fns (decls : decl list) : (string * fn_def) list =
  List.filter_map (function
    | DFn (def, _) -> Some (def.fn_name.txt, def)
    | _ -> None
  ) decls

(** Expand a [DSatisfy] into [DImpl] blocks by matching existing functions to
    interface methods by name.  Emits an error if the interface is not found or
    a required method is missing. *)
let expand_satisfy
    (errors : Err.ctx)
    (interfaces : (string * interface_def) list)
    (fns : (string * fn_def) list)
    (iface_names : name list)
    (type_names : name list)
    (sp : span)
  : decl list =
  List.concat_map (fun (iface_n : name) ->
    List.concat_map (fun (type_n : name) ->
      match List.assoc_opt iface_n.txt interfaces with
      | None ->
        Err.error errors ~span:iface_n.span
          (Printf.sprintf "Unknown interface `%s` in satisfy declaration." iface_n.txt);
        []
      | Some iface ->
        let methods = List.filter_map (fun (md : method_decl) ->
          match List.assoc_opt md.md_name.txt fns with
          | None ->
            Err.error errors ~span:sp
              (Printf.sprintf
                 "satisfy %s for %s: no function `%s` found in scope."
                 iface_n.txt type_n.txt md.md_name.txt);
            None
          | Some fn_def ->
            Some (md.md_name, fn_def)
        ) iface.iface_methods in
        if List.length methods < List.length iface.iface_methods then []
        else begin
          let impl_ty = TyCon (type_n, []) in
          let idef : impl_def = {
            impl_iface       = iface_n;
            impl_ty          = impl_ty;
            impl_constraints = [];
            impl_assoc_types = [];
            impl_methods     = methods;
          } in
          [DImpl (idef, sp)]
        end
    ) type_names
  ) iface_names
