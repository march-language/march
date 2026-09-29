(** Give same-named nested actors distinct names.

    Every backend keys an actor by its BARE declared name: the typechecker's
    constructor table ([Box] and the [Box_Msg] message type), the
    interpreter's [actor_defs_tbl], and the TIR glue ([Box_spawn],
    [Box_dispatch], [Box_Msg], [Box_Actor]).  Two actors called [Box] in
    sibling modules therefore collapsed into one: the interpreter spawned the
    same definition for both and the compiler emitted one dispatch function
    for both (or, with different message constructors, died with an internal
    error).  See specs/progress/2026-09-28-nested-actors-same-name-collide.md.

    This pass renames ONLY the actors whose bare name is declared more than
    once in the file's module tree, before anything else sees them, so every
    backend agrees without learning about module paths:

    - an actor at the file's root level keeps its bare name;
    - every nested actor in a colliding group becomes its module path joined
      with ["__"] (actor [Box] in [mod A] -> [A__Box]; in [mod A] inside
      [mod P] -> [P__A__Box]).

    A nested actor with a unique name, and every root-level actor, keeps its
    name byte-for-byte, so the spawn symbol, the dispatch table and the
    hot-code-reload manifest spell it exactly as before.

    References are resolved lexically from the module they appear in (the
    innermost enclosing module that declares the name wins) and only the last
    segment is replaced, so [spawn(Box)] inside [A] becomes [spawn(A__Box)]
    and [spawn(A.Box)] from the parent becomes [spawn(A.A__Box)]; the
    qualified-reference paths of the backends are unchanged.  Rewritten
    positions: the [spawn] target, a supervise child's type, and a
    [<Actor>.Msg] type anywhere a type is written.  A reference this pass
    does not rewrite names an actor that no longer exists under that name, so
    it fails to typecheck rather than binding to the wrong actor.

    Two actors with the same name in the SAME module are rejected here: no
    reference could tell them apart. *)

open March_ast.Ast

module Err = March_errors.Errors

module Key = struct
  type t = string list * string   (* module path from the root, bare name *)
  let compare = compare
end

module KMap = Map.Make (Key)

let split_dots s = String.split_on_char '.' s

(** Every actor declared in [decls], with its module path from the root. *)
let collect (decls : decl list) : (string list * name) list =
  let rec go path acc decls =
    List.fold_left (fun acc d -> match d with
        | DActor (_, n, _, _) -> (path, n) :: acc
        | DMod (m, _, inner, _) -> go (path @ [m.txt]) acc inner
        | _ -> acc) acc decls
  in
  List.rev (go [] [] decls)

(** [renames] maps each renamed actor's (path, bare name) to its new name;
    [declared] holds every actor, renamed or not, so an inner declaration
    shadows an outer one during resolution. *)
type table = {
  renames  : string KMap.t;
  declared : unit KMap.t;
}

let build errors (actors : (string list * name) list) : table =
  let declared = List.fold_left (fun m (p, (n : name)) ->
      if KMap.mem (p, n.txt) m then begin
        Err.error errors ~span:n.span
          (Printf.sprintf
             "actor `%s` is declared more than once in %s; \
              rename one of them"
             n.txt
             (if p = [] then "this module"
              else "module `" ^ String.concat "." p ^ "`"));
        m
      end else KMap.add (p, n.txt) () m) KMap.empty actors in
  let count name =
    KMap.fold (fun (_, n) () k -> if n = name then k + 1 else k) declared 0 in
  let taken = Hashtbl.create 16 in
  KMap.iter (fun (_, n) () -> Hashtbl.replace taken n ()) declared;
  let renames = KMap.fold (fun (p, n) () acc ->
      if p <> [] && count n > 1 then begin
        (* Never mint a name another actor already has. *)
        let base = String.concat "__" (p @ [n]) in
        let rec fresh s = if Hashtbl.mem taken s then fresh (s ^ "_") else s in
        let s = fresh base in
        Hashtbl.replace taken s ();
        KMap.add (p, n) s acc
      end else acc) declared KMap.empty in
  { renames; declared }

(** Resolve reference [r] (["Box"] or ["A.Box"]) written in module [cur] to
    its new spelling, or [None] when it names no renamed actor. *)
let resolve tbl ~root (cur : string list) (r : string) : string option =
  let segs = split_dots r in
  (* A reference may spell the file's own root module (`Outer.A.Box`). *)
  let segs_variants = match segs with
    | h :: (_ :: _ as rest) when h = root -> [segs; rest]
    | _ -> [segs] in
  let rec init_last = function
    | [] -> None
    | [x] -> Some ([], x)
    | x :: rest ->
      Option.map (fun (i, l) -> (x :: i, l)) (init_last rest) in
  let try_segs segs =
    match init_last segs with
    | None -> None
    | Some (qual, last) ->
      let rec up scope =
        let key = (scope @ qual, last) in
        if KMap.mem key tbl.declared then
          Some (Option.map (fun s -> String.concat "." (qual @ [s]))
                  (KMap.find_opt key tbl.renames))
        else match List.rev scope with
          | [] -> None
          | _ :: rev_parent -> up (List.rev rev_parent)
      in
      up cur
  in
  (* The first spelling that names a declared actor decides; that actor
     may or may not be one of the renamed ones. *)
  List.fold_left (fun found segs ->
      match found with Some _ -> found | None -> try_segs segs)
    None segs_variants
  |> Option.join

let msg_sfx = ".Msg"

let rename_ty tbl ~root cur =
  let rec ty t = match t with
    | TyCon (n, args) ->
      let args = List.map ty args in
      let s = n.txt in
      let len = String.length s and k = String.length msg_sfx in
      let n' =
        if len > k && String.sub s (len - k) k = msg_sfx then
          match resolve tbl ~root cur (String.sub s 0 (len - k)) with
          | Some a -> { n with txt = a ^ msg_sfx }
          | None -> n
        else n in
      TyCon (n', args)
    | TyArrow (a, b) -> TyArrow (ty a, ty b)
    | TyTuple ts -> TyTuple (List.map ty ts)
    | TyRecord fs -> TyRecord (List.map (fun (n, t) -> (n, ty t)) fs)
    | TyLinear (l, t) -> TyLinear (l, ty t)
    | TyNatOp (o, a, b) -> TyNatOp (o, ty a, ty b)
    | TyRefine (t, b, e) -> TyRefine (ty t, b, e)
    | TyVar _ | TyNat _ | TyChan _ -> t
  in
  ty

let rename_expr tbl ~root cur =
  let ty = rename_ty tbl ~root cur in
  let param (p : param) = { p with param_ty = Option.map ty p.param_ty } in
  let rec ex e = match e with
    | ESpawn (ECon (n, args, csp), sp) ->
      let n' = match resolve tbl ~root cur n.txt with
        | Some s -> { n with txt = s } | None -> n in
      ESpawn (ECon (n', List.map ex args, csp), sp)
    | ESpawn (EVar n, sp) ->
      (match resolve tbl ~root cur n.txt with
       | Some s -> ESpawn (EVar { n with txt = s }, sp)
       | None -> e)
    | ESpawn ((EField (head, n, fsp) as inner), sp) ->
      (* `spawn(A.Box)` before desugar: a field access on the module path. *)
      let rec path = function
        | ECon (m, [], _) | EVar m -> Some m.txt
        | EField (h, m, _) -> Option.map (fun p -> p ^ "." ^ m.txt) (path h)
        | _ -> None in
      (match path head with
       | Some p ->
         (match resolve tbl ~root cur (p ^ "." ^ n.txt) with
          | Some s ->
            let last = match String.rindex_opt s '.' with
              | Some i -> String.sub s (i + 1) (String.length s - i - 1)
              | None -> s in
            ESpawn (EField (head, { n with txt = last }, fsp), sp)
          | None -> e)
       | None -> ESpawn (ex inner, sp))
    | ESpawn (inner, sp) -> ESpawn (ex inner, sp)
    | ELam (ps, body, sp) -> ELam (List.map param ps, ex body, sp)
    | EBlock (es, sp) -> EBlock (List.map ex es, sp)
    | ELet (b, sp) -> ELet (bind b, sp)
    | ELetFn (nm, ps, ret, body, sp) ->
      ELetFn (nm, List.map param ps, Option.map ty ret, ex body, sp)
    | ELetQ (p, r, c, sp) -> ELetQ (p, ex r, ex c, sp)
    | ELetStar (p, r, c, sp) -> ELetStar (p, ex r, ex c, sp)
    | EMatch (s, brs, sp) ->
      EMatch (ex s, List.map (fun br ->
          { br with branch_body = ex br.branch_body;
                    branch_guard = Option.map ex br.branch_guard }) brs, sp)
    | EApp (f, args, sp) -> EApp (ex f, List.map ex args, sp)
    | ECon (n, args, sp) -> ECon (n, List.map ex args, sp)
    | ETuple (es, sp) -> ETuple (List.map ex es, sp)
    | ERecord (fs, sp) -> ERecord (List.map (fun (n, x) -> (n, ex x)) fs, sp)
    | ERecordUpdate (b, fs, sp) ->
      ERecordUpdate (ex b, List.map (fun (n, x) -> (n, ex x)) fs, sp)
    | EField (x, n, sp) -> EField (ex x, n, sp)
    | EIf (c, t, f, sp) -> EIf (ex c, ex t, ex f, sp)
    | ECond (arms, sp) -> ECond (List.map (fun (c, b) -> (ex c, ex b)) arms, sp)
    | EPipe (l, r, sp) -> EPipe (ex l, ex r, sp)
    | EAnnot (x, t, sp) -> EAnnot (ex x, ty t, sp)
    | EDbg (Some x, sp) -> EDbg (Some (ex x), sp)
    | ESend (c, m, sp) -> ESend (ex c, ex m, sp)
    | EAssert (x, sp) -> EAssert (ex x, sp)
    | EAtom (a, args, sp) -> EAtom (a, List.map ex args, sp)
    | ESigil (s, x, sp) -> ESigil (s, ex x, sp)
    | ELit _ | EVar _ | EHole _ | EResultRef _ | EDbg (None, _) -> e
  and bind b =
    { b with bind_ty = Option.map ty b.bind_ty; bind_expr = ex b.bind_expr }
  in
  (ex, ty, param, bind)

let rename_fn_def ex ty param (def : fn_def) : fn_def =
  let fparam = function
    | FPPat p -> FPPat p
    | FPNamed p -> FPNamed (param p)
    | FPDefault (p, d) -> FPDefault (param p, ex d) in
  { def with
    fn_ret_ty = Option.map ty def.fn_ret_ty;
    fn_clauses = List.map (fun c ->
        { c with fc_params = List.map fparam c.fc_params;
                 fc_body = ex c.fc_body;
                 fc_guard = Option.map ex c.fc_guard }) def.fn_clauses }

let rec rename_decls tbl ~root cur (decls : decl list) : decl list =
  let (ex, ty, param, bind) = rename_expr tbl ~root cur in
  let fn_def = rename_fn_def ex ty param in
  let field (f : field) = { f with fld_ty = ty f.fld_ty } in
  let type_def = function
    | TDAlias t -> TDAlias (ty t)
    | TDVariant vs ->
      TDVariant (List.map (fun v -> { v with var_args = List.map ty v.var_args }) vs)
    | TDRecord fs -> TDRecord (List.map field fs) in
  let handler (h : actor_handler) =
    { h with ah_params = List.map param h.ah_params; ah_body = ex h.ah_body } in
  let child_ty t = match t with
    | TyCon (n, args) ->
      (match resolve tbl ~root cur n.txt with
       | Some s -> TyCon ({ n with txt = s }, args)
       | None -> ty t)
    | _ -> ty t in
  List.map (fun d -> match d with
      | DFn (def, sp) -> DFn (fn_def def, sp)
      | DLet (v, b, sp) -> DLet (v, bind b, sp)
      | DType (v, n, ps, td, sp) -> DType (v, n, ps, type_def td, sp)
      | DAlwaysLinearType (v, n, ps, td, sp) ->
        DAlwaysLinearType (v, n, ps, type_def td, sp)
      | DActor (v, n, a, sp) ->
        let n' = match KMap.find_opt (cur, n.txt) tbl.renames with
          | Some s -> { n with txt = s } | None -> n in
        let a' = { a with
                   actor_state = List.map field a.actor_state;
                   actor_init_params = List.map param a.actor_init_params;
                   actor_init = ex a.actor_init;
                   actor_handlers = List.map handler a.actor_handlers;
                   actor_on_stop = Option.map handler a.actor_on_stop;
                   actor_invariant = Option.map ex a.actor_invariant;
                   actor_supervise = Option.map (fun sc ->
                       { sc with sc_fields = List.map (fun sf ->
                             { sf with sf_ty = child_ty sf.sf_ty;
                                       sf_init_args = List.map ex sf.sf_init_args })
                             sc.sc_fields }) a.actor_supervise } in
        DActor (v, n', a', sp)
      | DMod (m, v, inner, sp) ->
        DMod (m, v, rename_decls tbl ~root (cur @ [m.txt]) inner, sp)
      | DImpl (idef, sp) ->
        DImpl ({ idef with impl_methods =
                             List.map (fun (n, f) -> (n, fn_def f)) idef.impl_methods }, sp)
      | DTest (t, sp) -> DTest ({ t with test_body = ex t.test_body }, sp)
      | DDescribe (s, inner, sp) -> DDescribe (s, rename_decls tbl ~root cur inner, sp)
      | DSetup (e, sp) -> DSetup (ex e, sp)
      | DSetupAll (e, sp) -> DSetupAll (ex e, sp)
      | DApp (a, sp) ->
        DApp ({ a with app_body = ex a.app_body;
                       app_on_start = Option.map ex a.app_on_start;
                       app_on_stop = Option.map ex a.app_on_stop }, sp)
      | DProtocol _ | DSig _ | DInterface _ | DExtern _ | DUse _ | DAlias _
      | DNeeds _ | DProofCap _ | DOpts _ | DTransitions _ | DDeriving _
      | DSatisfy _ -> d
    ) decls

(** Entry point: [root] is the file's own top-level module name. *)
let expand errors ~(root : string) (decls : decl list) : decl list =
  let tbl = build errors (collect decls) in
  if KMap.is_empty tbl.renames then decls
  else rename_decls tbl ~root [] decls
