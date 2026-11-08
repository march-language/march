(* Lemma erasure (specs/2026-10-29-refinement-reflection-design.md §4.5, I6).

   A `@[lemma]` function is a proof: it never runs.  Every path that turns
   source into something that runs calls this pass after typechecking (the
   refinement checker reads the un-erased program, which it needs for the
   lemma calls).  It depends only on the attribute, never on a proof verdict
   or on z3, so cold and warm builds, with or without a solver, emit the same
   program.

   What it removes:
   - every call of a lemma, replaced by `()` at the call's span (the
     typechecker recorded `Unit` there, which is what lowering reads);
   - every lemma body, replaced by `()`, so a call this pass could not
     resolve still runs nothing;
   - every lemma declaration that nothing refers to any more.

   Name resolution is deliberately conservative (plan ruling 2): this library
   cannot use the refinement checker's resolver, so a call is erased only
   when its name, as spelled (the last segment of a qualified name), is
   bound by nothing but lemma declarations anywhere in the program (stdlib
   included): no other function, `let`, extern, interface method, impl
   method, parameter, pattern or local function of that name, and no builtin
   ([reserved]).  Such a call cannot denote anything but a lemma.  A lemma
   whose name collides with something else keeps its calls (each now runs
   the empty body) and its declaration.  Erasing a call drops its
   arguments, which the refinement checker requires to be terms with no
   effect (`lemma_argument_impure`). *)

open March_ast.Ast

module SS = Set.Make (String)

type env = { erasable : SS.t }

let is_lemma (fd : fn_def) = List.mem "lemma" fd.fn_attrs

let last_segment (s : string) =
  match String.rindex_opt s '.' with Some i -> String.sub s (i + 1) (String.length s - i - 1) | None -> s

let rec pat_names (acc : SS.t) (p : pattern) : SS.t =
  match p with
  | PatWild _ | PatLit _ -> acc
  | PatVar n -> SS.add n.txt acc
  | PatCon (_, ps) | PatAtom (_, ps, _) | PatTuple (ps, _) | PatOr (ps, _) -> List.fold_left pat_names acc ps
  | PatRecord (fs, _) -> List.fold_left (fun acc (_, p) -> pat_names acc p) acc fs
  | PatAs (p, n, _) -> pat_names (SS.add n.txt acc) p

(* Every name an expression binds: parameters, patterns, `let`s, local fns. *)
let rec expr_binders (acc : SS.t) (e : expr) : SS.t =
  let go = expr_binders in
  let params acc (ps : param list) = List.fold_left (fun acc (p : param) -> SS.add p.param_name.txt acc) acc ps in
  match e with
  | ELit _ | EVar _ | EHole _ | EResultRef _ | EDbg (None, _) -> acc
  | EApp (f, args, _) -> List.fold_left go (go acc f) args
  | ECon (_, args, _) | ETuple (args, _) | EAtom (_, args, _) | EBlock (args, _) -> List.fold_left go acc args
  | ELam (ps, body, _) -> go (params acc ps) body
  | ELet (b, _) -> go (pat_names acc b.bind_pat) b.bind_expr
  | ELetFn (n, ps, _, body, _) -> go (params (SS.add n.txt acc) ps) body
  | ELetQ (p, a, b, _) | ELetStar (p, a, b, _) -> go (go (pat_names acc p) a) b
  | EMatch (s, brs, _) ->
    List.fold_left
      (fun acc (br : branch) ->
        let acc = pat_names acc br.branch_pat in
        let acc = match br.branch_guard with Some g -> go acc g | None -> acc in
        go acc br.branch_body)
      (go acc s) brs
  | ERecord (fs, _) -> List.fold_left (fun acc (_, x) -> go acc x) acc fs
  | ERecordUpdate (b, fs, _) -> List.fold_left (fun acc (_, x) -> go acc x) (go acc b) fs
  | EField (x, _, _) | EAnnot (x, _, _) | ESpawn (x, _) | EAssert (x, _) | ESigil (_, x, _) | EDbg (Some x, _) -> go acc x
  | EIf (c, t, f, _) -> go (go (go acc c) t) f
  | ECond (arms, _) -> List.fold_left (fun acc (c, b) -> go (go acc c) b) acc arms
  | EPipe (a, b, _) | ESend (a, b, _) -> go (go acc a) b
  | ERefineMsg (x, _, _) -> go acc x
  | EProof (p, _) -> List.fold_left go acc (proof_children p)

let fn_binders (acc : SS.t) (fd : fn_def) : SS.t =
  List.fold_left
    (fun acc (c : fn_clause) ->
      let acc =
        List.fold_left
          (fun acc -> function
            | FPPat p -> pat_names acc p
            | FPNamed p -> SS.add p.param_name.txt acc
            | FPDefault (p, d) -> expr_binders (SS.add p.param_name.txt acc) d)
          acc c.fc_params
      in
      let acc = match c.fc_guard with Some g -> expr_binders acc g | None -> acc in
      expr_binders acc c.fc_body)
    acc fd.fn_clauses

(* (lemma names, every other name the program binds). *)
let rec scan acc (decls : decl list) =
  List.fold_left
    (fun (lemmas, others) d ->
      match d with
      | DFn (fd, _) when is_lemma fd -> (SS.add fd.fn_name.txt lemmas, fn_binders others fd)
      | DFn (fd, _) -> (lemmas, fn_binders (SS.add fd.fn_name.txt others) fd)
      | DLet (_, b, _) -> (lemmas, expr_binders (pat_names others b.bind_pat) b.bind_expr)
      | DMod (_, _, inner, _) | DDescribe (_, inner, _) -> scan (lemmas, others) inner
      | DImpl (idef, _) ->
        ( lemmas,
          List.fold_left (fun acc (n, fd) -> fn_binders (SS.add n.txt acc) fd) others idef.impl_methods )
      | DInterface (idef, _) ->
        ( lemmas,
          List.fold_left
            (fun acc (m : method_decl) ->
              let acc = SS.add m.md_name.txt acc in
              match m.md_default with Some e -> expr_binders acc e | None -> acc)
            others idef.iface_methods )
      | DExtern (ext, _) -> (lemmas, List.fold_left (fun acc (f : extern_fn) -> SS.add f.ef_name.txt acc) others ext.ext_fns)
      | DActor (_, _, a, _) ->
        let others = List.fold_left (fun acc (p : param) -> SS.add p.param_name.txt acc) others a.actor_init_params in
        let others = expr_binders others a.actor_init in
        let handler acc (h : actor_handler) =
          expr_binders (List.fold_left (fun acc (p : param) -> SS.add p.param_name.txt acc) acc h.ah_params) h.ah_body
        in
        let others = List.fold_left handler others a.actor_handlers in
        (lemmas, Option.fold ~none:others ~some:(handler others) a.actor_on_stop)
      | DTest (t, _) -> (lemmas, expr_binders others t.test_body)
      | DSetup (e, _) | DSetupAll (e, _) -> (lemmas, expr_binders others e)
      | DApp (a, _) ->
        let others = expr_binders others a.app_body in
        let others = Option.fold ~none:others ~some:(expr_binders others) a.app_on_start in
        (lemmas, Option.fold ~none:others ~some:(expr_binders others) a.app_on_stop)
      | _ -> (lemmas, others))
    acc decls

(* A lemma name a builtin also spells, bare or as the last segment of a
   qualified builtin (`Supervisor.which_children`; soundness review F2):
   erasure matches a call by its last segment, so such a name is never
   erased. *)
let reserved_by (builtins : string list) : string -> bool =
  let tbl = Hashtbl.create 512 in
  List.iter (fun k -> Hashtbl.replace tbl (last_segment k) ()) builtins;
  Hashtbl.mem tbl

let env_of_decls ?(reserved : string -> bool = fun _ -> false) (decls : decl list) : env =
  let lemmas, others = scan (SS.empty, SS.empty) decls in
  { erasable = SS.filter (fun n -> not (SS.mem n others || reserved n)) lemmas }

let erasable_call (env : env) (f : expr) =
  match f with EVar n -> SS.mem (last_segment n.txt) env.erasable | _ -> false

let unit_at (sp : span) = ETuple ([], sp)

let rec erase_expr (env : env) (e : expr) : expr =
  let ex = erase_expr env in
  match e with
  | EApp (f, _, sp) when erasable_call env f -> unit_at sp
  | EApp (f, args, sp) -> EApp (ex f, List.map ex args, sp)
  | ELam (ps, body, sp) -> ELam (ps, ex body, sp)
  | EBlock (es, sp) -> EBlock (List.map ex es, sp)
  | ELet (b, sp) -> ELet ({ b with bind_expr = ex b.bind_expr }, sp)
  | ELetFn (n, ps, ret, body, sp) -> ELetFn (n, ps, ret, ex body, sp)
  | ELetQ (p, a, b, sp) -> ELetQ (p, ex a, ex b, sp)
  | ELetStar (p, a, b, sp) -> ELetStar (p, ex a, ex b, sp)
  | EMatch (s, brs, sp) ->
    EMatch
      ( ex s,
        List.map (fun br -> { br with branch_body = ex br.branch_body; branch_guard = Option.map ex br.branch_guard }) brs,
        sp )
  | ECon (n, args, sp) -> ECon (n, List.map ex args, sp)
  | ETuple (es, sp) -> ETuple (List.map ex es, sp)
  | ERecord (fs, sp) -> ERecord (List.map (fun (n, x) -> (n, ex x)) fs, sp)
  | ERecordUpdate (b, fs, sp) -> ERecordUpdate (ex b, List.map (fun (n, x) -> (n, ex x)) fs, sp)
  | EField (x, n, sp) -> EField (ex x, n, sp)
  | EIf (c, t, f, sp) -> EIf (ex c, ex t, ex f, sp)
  | ECond (arms, sp) -> ECond (List.map (fun (c, b) -> (ex c, ex b)) arms, sp)
  | EPipe (l, r, sp) -> EPipe (ex l, ex r, sp)
  | EAnnot (x, t, sp) -> EAnnot (ex x, t, sp)
  | EDbg (Some x, sp) -> EDbg (Some (ex x), sp)
  | ESend (c, m, sp) -> ESend (ex c, ex m, sp)
  | ESpawn (x, sp) -> ESpawn (ex x, sp)
  | EAssert (x, sp) -> EAssert (ex x, sp)
  | EAtom (a, args, sp) -> EAtom (a, List.map ex args, sp)
  | ESigil (s, x, sp) -> ESigil (s, ex x, sp)
  | ERefineMsg (x, msg, sp) -> ERefineMsg (ex x, msg, sp)
  (* Proof hints are ghost: gone before anything runs.  A `with fuel` body is
     ordinary code and stays, as a block. *)
  | EProof (PWithFuel (_, _, body), sp) -> EBlock (List.map ex body, sp)
  | EProof (_, sp) -> unit_at sp
  | ELit _ | EVar _ | EHole _ | EResultRef _ | EDbg (None, _) -> e

let erase_fn env (fd : fn_def) : fn_def =
  if is_lemma fd then
    { fd with
      fn_clauses =
        List.map (fun (c : fn_clause) -> { c with fc_guard = None; fc_body = unit_at c.fc_span }) fd.fn_clauses }
  else
    { fd with
      fn_clauses =
        List.map
          (fun (c : fn_clause) ->
            { c with
              fc_body = erase_expr env c.fc_body;
              fc_guard = Option.map (erase_expr env) c.fc_guard;
              fc_params =
                List.map (function FPDefault (p, d) -> FPDefault (p, erase_expr env d) | fp -> fp) c.fc_params })
          fd.fn_clauses }

let rec erase_decls env (decls : decl list) : decl list =
  let ex = erase_expr env in
  let handler (h : actor_handler) = { h with ah_body = ex h.ah_body } in
  List.map
    (fun d ->
      match d with
      | DFn (fd, sp) -> DFn (erase_fn env fd, sp)
      | DLet (v, b, sp) -> DLet (v, { b with bind_expr = ex b.bind_expr }, sp)
      | DMod (n, v, inner, sp) -> DMod (n, v, erase_decls env inner, sp)
      | DDescribe (s, inner, sp) -> DDescribe (s, erase_decls env inner, sp)
      | DImpl (idef, sp) -> DImpl ({ idef with impl_methods = List.map (fun (n, f) -> (n, erase_fn env f)) idef.impl_methods }, sp)
      | DInterface (idef, sp) ->
        DInterface
          ({ idef with iface_methods = List.map (fun m -> { m with md_default = Option.map ex m.md_default }) idef.iface_methods },
           sp)
      | DActor (v, n, a, sp) ->
        DActor
          ( v, n,
            { a with
              actor_init = ex a.actor_init;
              actor_handlers = List.map handler a.actor_handlers;
              actor_on_stop = Option.map handler a.actor_on_stop;
              actor_invariant = Option.map ex a.actor_invariant },
            sp )
      | DTest (t, sp) -> DTest ({ t with test_body = ex t.test_body }, sp)
      | DSetup (e, sp) -> DSetup (ex e, sp)
      | DSetupAll (e, sp) -> DSetupAll (ex e, sp)
      | DApp (a, sp) ->
        DApp
          ({ a with app_body = ex a.app_body; app_on_start = Option.map ex a.app_on_start; app_on_stop = Option.map ex a.app_on_stop },
           sp)
      | _ -> d)
    decls

(* Does any expression of [decls] still name [n] (as spelled, last segment)? *)
let rec mentions (n : string) (decls : decl list) : bool =
  let found = ref false in
  let rec ex (e : expr) =
    if not !found then
      match e with
      | EVar v -> if last_segment v.txt = n then found := true
      | _ -> List.iter ex (children e)
  and children (e : expr) : expr list =
    match e with
    | ELit _ | EVar _ | EHole _ | EResultRef _ | EDbg (None, _) -> []
    | EApp (f, args, _) -> f :: args
    | ECon (_, args, _) | ETuple (args, _) | EAtom (_, args, _) | EBlock (args, _) -> args
    | ELam (_, b, _) | ELetFn (_, _, _, b, _) -> [ b ]
    | ELet (b, _) -> [ b.bind_expr ]
    | ELetQ (_, a, b, _) | ELetStar (_, a, b, _) | EPipe (a, b, _) | ESend (a, b, _) -> [ a; b ]
    | EMatch (s, brs, _) ->
      s :: List.concat_map (fun br -> br.branch_body :: Option.to_list br.branch_guard) brs
    | ERecord (fs, _) -> List.map snd fs
    | ERecordUpdate (b, fs, _) -> b :: List.map snd fs
    | EField (x, _, _) | EAnnot (x, _, _) | ESpawn (x, _) | EAssert (x, _) | ESigil (_, x, _) | EDbg (Some x, _) -> [ x ]
    | EIf (c, t, f, _) -> [ c; t; f ]
    | ECond (arms, _) -> List.concat_map (fun (c, b) -> [ c; b ]) arms
    | ERefineMsg (x, _, _) -> [ x ]
    | EProof (p, _) -> proof_children p
  in
  let fn (fd : fn_def) =
    List.iter
      (fun (c : fn_clause) ->
        ex c.fc_body;
        Option.iter ex c.fc_guard;
        List.iter (function FPDefault (_, d) -> ex d | _ -> ()) c.fc_params)
      fd.fn_clauses
  in
  List.iter
    (function
      | DFn (fd, _) -> fn fd
      | DLet (_, b, _) -> ex b.bind_expr
      | DMod (_, _, inner, _) | DDescribe (_, inner, _) -> if mentions n inner then found := true
      | DImpl (idef, _) -> List.iter (fun (_, f) -> fn f) idef.impl_methods
      | DInterface (idef, _) -> List.iter (fun m -> Option.iter ex m.md_default) idef.iface_methods
      | DActor (_, _, a, _) ->
        ex a.actor_init;
        List.iter (fun (h : actor_handler) -> ex h.ah_body) a.actor_handlers;
        Option.iter (fun (h : actor_handler) -> ex h.ah_body) a.actor_on_stop;
        Option.iter ex a.actor_invariant
      | DTest (t, _) -> ex t.test_body
      | DSetup (e, _) | DSetupAll (e, _) -> ex e
      | DApp (a, _) ->
        ex a.app_body;
        Option.iter ex a.app_on_start;
        Option.iter ex a.app_on_stop
      | _ -> ())
    decls;
  !found

let rec drop_unreferenced (whole : decl list) (decls : decl list) : decl list =
  List.filter_map
    (fun d ->
      match d with
      | DFn (fd, _) when is_lemma fd && not (mentions fd.fn_name.txt whole) -> None
      (* An impl method's copy for an interface law ([Interface_laws]): only
         its lemmas used it. *)
      | DFn (fd, _) when String.starts_with ~prefix:Interface_laws.copy_prefix fd.fn_name.txt -> None
      | DMod (n, v, inner, sp) -> Some (DMod (n, v, drop_unreferenced whole inner, sp))
      | DDescribe (s, inner, sp) -> Some (DDescribe (s, drop_unreferenced whole inner, sp))
      | d -> Some d)
    decls

let erase_module_with (env : env) (decls : decl list) : decl list =
  let erased = erase_decls env decls in
  drop_unreferenced erased erased

let erase_module ?(reserved : string -> bool = fun _ -> false) (decls : decl list) : decl list =
  (* Scoped proofs also occur in modules with no lemma declarations. *)
  erase_module_with (env_of_decls ~reserved decls) decls

(* One declaration at a time (the REPLs): a lemma keeps its declaration, for
   later inputs that call it, but its body becomes `()`, so no call ever runs
   a proof. *)
let blank_lemma_decl (d : decl) : decl =
  match erase_decls { erasable = SS.empty } [d] with
  | [d] -> d
  | _ -> d

(* Every lemma body in [decls] becomes `()`, nested modules included; calls
   and declarations stay (the REPLs, where a later input may call a lemma). *)
let blank_lemmas (decls : decl list) : decl list = erase_decls { erasable = SS.empty } decls
