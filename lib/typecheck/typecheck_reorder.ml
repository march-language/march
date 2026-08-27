(** Declaration dependency ordering — the pass that reorders each maximal
    contiguous run of top-level [DFn] declarations so a function is checked
    after the siblings it calls, and the analogous run-level ordering for
    [DMod] declarations.

    [dependency_order_dfn_run], [module_refs_in_decls],
    [unqualified_module_deps], [dependency_order_dmod_run] and [reorder_decls].
    Lifted verbatim out of [Typecheck] on 2026-08-27 (Target B, task B1); the
    band depends on no name defined elsewhere in [Typecheck], in either
    direction — only on the [Ast] and [StringSet] aliases that
    [Typecheck_types] carries.

    [include], not [open], at the call site: only [include] re-exports these
    names as part of [Typecheck]'s own surface, and consumers reach them
    through [let open] and through aliases (Tc., TC., T.) that no grep can
    see. *)

include Typecheck_types

(* Reorder each maximal contiguous run of top-level function declarations so a
   function is checked AFTER the sibling functions it calls (callee-before-caller,
   i.e. dependency order).  This lets a caller observe a callee's fully-inferred,
   generalized type rather than a pass-1 monomorphic placeholder.  Using the
   placeholder leaks an unresolved/over-generalized type variable into the
   caller — and because `generalize` copies the type with fresh refs, a later
   reconciliation can no longer reach it.  The leak miscompiles at runtime: a
   polymorphic list is reference-counted differently than its concrete instance,
   producing a use-after-free.

   Safety: only DFn decls are moved, and only relative to one another within a
   maximal contiguous run, so non-DFn decls (DLet, DType, …) keep their
   positions and any dependency on a module-level value/type is preserved.
   Runs containing duplicate function names (default-argument wrappers, which
   the checker requires to be processed full-arity-first) are left untouched.
   Cycles (mutual recursion) are tolerated by a DFS post-order that keeps SCC
   members grouped and relies on the pass-1 placeholder for the cyclic edges. *)
let dependency_order_dfn_run (run : Ast.decl list) : Ast.decl list =
  let info =
    List.filter_map (function
      | Ast.DFn (d, sp) -> Some (d.Ast.fn_name.txt, (d, sp))
      | _ -> None) run
  in
  let names = List.map fst info in
  let has_dup =
    let seen = ref StringSet.empty and dup = ref false in
    List.iter (fun n ->
        if StringSet.mem n !seen then dup := true else seen := StringSet.add n !seen)
      names;
    !dup
  in
  if has_dup then run
  else begin
    let name_set = List.fold_left (fun s n -> StringSet.add n s) StringSet.empty names in
    let by_name : (string, Ast.fn_def * Ast.span) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun (n, ds) -> Hashtbl.replace by_name n ds) info;
    (* Map a body reference to a local fn name.  A BARE name matches directly; a
       DOTTED name (`App.id`, produced by desugar's [qualify_module_refs] for an
       intra-nested-module reference) is mapped by its suffix after the last `.` —
       so a nested-module call to a sibling `id` is recognised as a dependency on
       the local `id`, and [dependency_order_dfn_run] orders the helper BEFORE its
       caller.  Without this, a forward reference (`fn attack() do need_str(id(x))`
       defined ABOVE `fn id`) left `App.id`'s prebind pinned to the caller's
       decoupled use, and the qualified-prebind reconciliation (see the DFn branch
       of [check_decl]) ran too late to un-erase the already-checked caller. *)
    let local_of n =
      if StringSet.mem n name_set then Some n
      else match String.rindex_opt n '.' with
        | Some i ->
          let suffix = String.sub n (i + 1) (String.length n - i - 1) in
          if StringSet.mem suffix name_set then Some suffix else None
        | None -> None
    in
    let deps_of (d : Ast.fn_def) =
      List.concat_map (fun (c : Ast.fn_clause) -> free_vars_expr [] c.Ast.fc_body)
        d.Ast.fn_clauses
      |> List.filter_map local_of
      |> List.filter (fun n -> n <> d.Ast.fn_name.txt)
    in
    let visited : (string, unit) Hashtbl.t = Hashtbl.create 16 in
    let out = ref [] in
    let rec visit name =
      if not (Hashtbl.mem visited name) then begin
        Hashtbl.replace visited name ();
        match Hashtbl.find_opt by_name name with
        | Some (d, sp) -> List.iter visit (deps_of d); out := Ast.DFn (d, sp) :: !out
        | None -> ()
      end
    in
    List.iter (fun n -> visit n) names;
    List.rev !out
  end

(* Collect the set of module-name prefixes referenced (qualified) anywhere in a
   list of declarations: qualified function/value uses ("Mod.f"), qualified
   constructors ("Mod.Ctor") and qualified type names ("Mod.T").  Used to order
   sibling modules so a module is checked AFTER the modules it depends on. *)
let module_refs_in_decls (decls : Ast.decl list) : StringSet.t =
  let acc = ref StringSet.empty in
  let add (s : string) =
    (* Record EVERY dotted prefix, not just the first segment: a sibling
       module can itself have a dotted name (`mod Depot.Schema`), so a
       reference "Depot.Schema.define" depends on "Depot.Schema", not only
       on "Depot" (often an empty namespace container).  The caller
       intersects with the actual sibling-name set, so non-module prefixes
       are dropped.  First-segment-only extraction left dotted siblings
       unordered relative to their callers, and every caller then unified
       against one shared pass-1 Mono placeholder — the first call site
       pinned the parameter types for all the others. *)
    let rec go i =
      match String.index_from_opt s i '.' with
      | Some j when j > 0 ->
        acc := StringSet.add (String.sub s 0 j) !acc;
        go (j + 1)
      | _ -> ()
    in
    go 0
  in
  let rec ty (t : Ast.ty) =
    match t with
    | Ast.TyCon (n, args) -> add n.Ast.txt; List.iter ty args
    | Ast.TyVar _ | Ast.TyNat _ -> ()
    | Ast.TyArrow (a, b) -> ty a; ty b
    | Ast.TyTuple ts -> List.iter ty ts
    | Ast.TyRecord flds -> List.iter (fun (_, t) -> ty t) flds
    | Ast.TyLinear (_, t) -> ty t
    | Ast.TyNatOp (_, a, b) -> ty a; ty b
    | Ast.TyChan (a, b) -> add a.Ast.txt; add b.Ast.txt
    | Ast.TyRefine (base, _, _) -> ty base
  in
  let oty = function Some t -> ty t | None -> () in
  let param (p : Ast.param) = oty p.Ast.param_ty in
  let rec ex (e : Ast.expr) =
    match e with
    | Ast.EVar n -> add n.Ast.txt
    | Ast.ELit _ | Ast.EHole _ | Ast.EResultRef _ | Ast.EDbg (None, _) -> ()
    | Ast.EDbg (Some i, _) -> ex i
    | Ast.EApp (f, args, _) -> ex f; List.iter ex args
    | Ast.ECon (n, args, _) -> add n.Ast.txt; List.iter ex args
    | Ast.ELam (ps, b, _) -> List.iter param ps; ex b
    | Ast.EBlock (es, _) -> List.iter ex es
    | Ast.ELet (b, _) -> ex b.Ast.bind_expr
    | Ast.EMatch (s, brs, _) ->
      ex s;
      List.iter (fun (br : Ast.branch) ->
          (match br.Ast.branch_guard with Some g -> ex g | None -> ());
          ex br.Ast.branch_body) brs
    | Ast.ETuple (es, _) -> List.iter ex es
    | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> ex e) fs
    | Ast.ERecordUpdate (b, fs, _) -> ex b; List.iter (fun (_, e) -> ex e) fs
    | Ast.EField (e, _, _) -> ex e
    | Ast.EIf (c, t, f, _) -> ex c; ex t; ex f
    | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> ex c; ex b) arms
    | Ast.EAnnot (e, t, _) -> ex e; ty t
    | Ast.EAtom (_, args, _) -> List.iter ex args
    | Ast.ESend (a, b, _) -> ex a; ex b
    | Ast.ESpawn (e, _) -> ex e
    | Ast.ELetFn (_, ps, rt, b, _) -> List.iter param ps; oty rt; ex b
    | Ast.ELetQ (_, r, c, _) | Ast.ELetStar (_, r, c, _) -> ex r; ex c
    | Ast.EPipe (l, r, _) -> ex l; ex r
    | Ast.EAssert (e, _) -> ex e
    | Ast.ESigil (_, c, _) -> ex c
  in
  let fn_param (fp : Ast.fn_param) =
    match fp with
    | Ast.FPNamed p -> oty p.Ast.param_ty
    | Ast.FPDefault (p, _) -> oty p.Ast.param_ty
    | Ast.FPPat _ -> ()
  in
  let decl (d : Ast.decl) =
    match d with
    | Ast.DFn (def, _) ->
      oty def.Ast.fn_ret_ty;
      List.iter (fun (c : Ast.fn_clause) ->
          List.iter fn_param c.Ast.fc_params;
          (match c.Ast.fc_guard with Some g -> ex g | None -> ());
          ex c.Ast.fc_body) def.Ast.fn_clauses
    | Ast.DLet (_, b, _) -> ex b.Ast.bind_expr
    | Ast.DType (_, _, _, td, _)
    | Ast.DAlwaysLinearType (_, _, _, td, _) ->
      (match td with
       | Ast.TDAlias t -> ty t
       | Ast.TDRecord flds -> List.iter (fun (f : Ast.field) -> ty f.Ast.fld_ty) flds
       | Ast.TDVariant vs ->
         List.iter (fun (v : Ast.variant) -> List.iter ty v.Ast.var_args) vs)
    | _ -> ()
  in
  List.iter decl decls;
  !acc

(* Collect the sibling modules a module depends on through UNQUALIFIED type and
   constructor references (`List(Block)`, `Heading(..)`, `match .. Heading(x) ->`).
   [module_refs_in_decls] only sees qualified `Mod.x` references, so a module that
   uses another module's variant type or constructors by their bare name records
   no dependency and may be ordered — and therefore checked — before the defining
   module.  At that point the bare names are not yet exported into the outer
   scope, so the reference fails ("I cannot find `Block`").  Each bare type/ctor
   name is resolved to its owning sibling through the supplied owner maps.  Unlike
   pre-binding the bare names eagerly, fixing the ORDER keeps each constructor's
   resolved type identical to the single-entry (forge test) build, so it cannot
   perturb the constructor tags assigned during lowering. *)
let unqualified_module_deps
    ~(type_owner : (string, string) Hashtbl.t)
    ~(ctor_owner : (string, string) Hashtbl.t)
    (decls : Ast.decl list) : StringSet.t =
  let acc = ref StringSet.empty in
  let bare n = not (String.contains n '.') in
  let add tbl n =
    if bare n then
      match Hashtbl.find_opt tbl n with
      | Some m -> acc := StringSet.add m !acc
      | None -> ()
  in
  let rec ty (t : Ast.ty) =
    match t with
    | Ast.TyCon (n, args) -> add type_owner n.Ast.txt; List.iter ty args
    | Ast.TyArrow (a, b) -> ty a; ty b
    | Ast.TyTuple ts -> List.iter ty ts
    | Ast.TyRecord flds -> List.iter (fun (_, t) -> ty t) flds
    | Ast.TyLinear (_, t) -> ty t
    | Ast.TyNatOp (_, a, b) -> ty a; ty b
    | Ast.TyVar _ | Ast.TyNat _ | Ast.TyChan _ -> ()
    | Ast.TyRefine (base, _, _) -> ty base
  in
  let oty = function Some t -> ty t | None -> () in
  let rec pat (p : Ast.pattern) =
    match p with
    | Ast.PatCon (n, ps) -> add ctor_owner n.Ast.txt; List.iter pat ps
    | Ast.PatAtom (_, ps, _) -> List.iter pat ps
    | Ast.PatTuple (ps, _) -> List.iter pat ps
    | Ast.PatRecord (fs, _) -> List.iter (fun (_, p) -> pat p) fs
    | Ast.PatAs (p, _, _) -> pat p
    | Ast.PatOr (ps, _) -> List.iter pat ps
    | Ast.PatWild _ | Ast.PatVar _ | Ast.PatLit _ -> ()
  in
  let param (p : Ast.param) = oty p.Ast.param_ty in
  let fn_param (fp : Ast.fn_param) =
    match fp with
    | Ast.FPNamed p -> param p
    | Ast.FPDefault (p, _) -> param p
    | Ast.FPPat pp -> pat pp
  in
  let rec ex (e : Ast.expr) =
    match e with
    | Ast.ECon (n, args, _) -> add ctor_owner n.Ast.txt; List.iter ex args
    | Ast.EVar _ | Ast.ELit _ | Ast.EHole _ | Ast.EResultRef _
    | Ast.EDbg (None, _) -> ()
    | Ast.EDbg (Some i, _) -> ex i
    | Ast.EApp (f, args, _) -> ex f; List.iter ex args
    | Ast.ELam (ps, b, _) -> List.iter param ps; ex b
    | Ast.EBlock (es, _) -> List.iter ex es
    | Ast.ELet (b, _) -> pat b.Ast.bind_pat; ex b.Ast.bind_expr
    | Ast.EMatch (s, brs, _) ->
      ex s;
      List.iter (fun (br : Ast.branch) ->
          pat br.Ast.branch_pat;
          (match br.Ast.branch_guard with Some g -> ex g | None -> ());
          ex br.Ast.branch_body) brs
    | Ast.ETuple (es, _) -> List.iter ex es
    | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> ex e) fs
    | Ast.ERecordUpdate (b, fs, _) -> ex b; List.iter (fun (_, e) -> ex e) fs
    | Ast.EField (e, _, _) -> ex e
    | Ast.EIf (c, t, f, _) -> ex c; ex t; ex f
    | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> ex c; ex b) arms
    | Ast.EAnnot (e, t, _) -> ex e; ty t
    | Ast.EAtom (_, args, _) -> List.iter ex args
    | Ast.ESend (a, b, _) -> ex a; ex b
    | Ast.ESpawn (e, _) -> ex e
    | Ast.ELetFn (_, ps, rt, b, _) -> List.iter param ps; oty rt; ex b
    | Ast.ELetQ (_, r, c, _) | Ast.ELetStar (_, r, c, _) -> ex r; ex c
    | Ast.EPipe (l, r, _) -> ex l; ex r
    | Ast.EAssert (e, _) -> ex e
    | Ast.ESigil (_, c, _) -> ex c
  in
  let decl (d : Ast.decl) =
    match d with
    | Ast.DFn (def, _) ->
      oty def.Ast.fn_ret_ty;
      List.iter (fun (c : Ast.fn_clause) ->
          List.iter fn_param c.Ast.fc_params;
          (match c.Ast.fc_guard with Some g -> ex g | None -> ());
          ex c.Ast.fc_body) def.Ast.fn_clauses
    | Ast.DLet (_, b, _) -> pat b.Ast.bind_pat; ex b.Ast.bind_expr
    | Ast.DType (_, _, _, td, _)
    | Ast.DAlwaysLinearType (_, _, _, td, _) ->
      (match td with
       | Ast.TDAlias t -> ty t
       | Ast.TDRecord flds -> List.iter (fun (f : Ast.field) -> ty f.Ast.fld_ty) flds
       | Ast.TDVariant vs ->
         List.iter (fun (v : Ast.variant) -> List.iter ty v.Ast.var_args) vs)
    | _ -> ()
  in
  List.iter decl decls;
  !acc

(* Reorder a maximal run of sibling module declarations so a module is checked
   AFTER the sibling modules it references.  Same rationale as the function-level
   ordering: a caller module that is checked before a callee module sees the
   callee's qualified names as pass-1 placeholders, leaking an unresolved type
   variable that later miscompiles into a use-after-free.  Auto-discovered
   project modules are otherwise ordered by a namespace-depth heuristic that does
   not reflect actual dependencies, so flat (single-segment) module sets end up
   alphabetical. *)
let dependency_order_dmod_run (run : Ast.decl list) : Ast.decl list =
  let info =
    List.filter_map (function
      | Ast.DMod (n, _, decls, _) as dm -> Some (n.Ast.txt, (decls, dm))
      | _ -> None) run
  in
  let names = List.map fst info in
  let has_dup =
    let seen = ref StringSet.empty and dup = ref false in
    List.iter (fun n ->
        if StringSet.mem n !seen then dup := true else seen := StringSet.add n !seen)
      names;
    !dup
  in
  if has_dup then begin
    if Sys.getenv_opt "MARCH_DEBUG_ORDER" <> None then
      Printf.eprintf "[order] has_dup=true, skipping reorder of %d-mod run: %s\n%!"
        (List.length names) (String.concat "," names);
    run
  end
  else begin
    let name_set = List.fold_left (fun s n -> StringSet.add n s) StringSet.empty names in
    let by_name : (string, Ast.decl list * Ast.decl) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun (n, ds) -> Hashtbl.replace by_name n ds) info;
    (* Map each public type / constructor name to the sibling module that defines
       it, so a module referencing them UNQUALIFIED records a dependency on the
       definer (see [unqualified_module_deps]). *)
    let type_owner : (string, string) Hashtbl.t = Hashtbl.create 64 in
    let ctor_owner : (string, string) Hashtbl.t = Hashtbl.create 64 in
    List.iter (fun (modname, (decls, _)) ->
        List.iter (function
          | Ast.DType (Ast.Public, tname, _, td, _)
          | Ast.DAlwaysLinearType (Ast.Public, tname, _, td, _) ->
            if not (Hashtbl.mem type_owner tname.Ast.txt) then
              Hashtbl.replace type_owner tname.Ast.txt modname;
            (match td with
             | Ast.TDVariant vs ->
               List.iter (fun (v : Ast.variant) ->
                   if v.Ast.var_vis = Ast.Public
                      && not (Hashtbl.mem ctor_owner v.Ast.var_name.Ast.txt) then
                     Hashtbl.replace ctor_owner v.Ast.var_name.Ast.txt modname) vs
             | _ -> ())
          | _ -> ()) decls
      ) info;
    (* [hard_deps] (unqualified bare ctor/type refs) are a correctness
       requirement: a bare name is only visible in [env] once the defining
       sibling's DMod has actually been processed by [check_decl] (its ctors
       are exported at that point — see the [new_ctors]/[qual_ctors] merge in
       the [DMod] case of [check_decl]).  There is no pass-1 placeholder for
       bare ctor names the way there is for qualified "Mod.fn" names, so
       violating a hard dependency is a hard failure ("I cannot find
       `Ctor`"), not just an imprecise type.
       [module_refs_in_decls] (qualified "Mod.fn"/"Mod.Ctor" refs) is only a
       precision nicety: those names ARE pre-bound as pass-1 placeholders
       regardless of order (see [prebind_mod_members]), so ordering by them
       just avoids callers unifying against a still-generalizing Mono
       placeholder — never required for resolution to succeed.
       Sibling modules commonly form real reference cycles through qualified
       calls (e.g. a facade module delegating to an internal one, which in
       turn bare-pattern-matches a type owned by the facade's module). A
       single DFS over the union of both kinds of edges lets a soft
       (qualified) cycle silently reorder a hard (bare) dependency the wrong
       way — whichever edge the traversal happens to reach the ancestor
       through "wins", independent of which one is actually load-bearing.
       So: compute the preferred order via the existing combined-edge DFS
       (unchanged — this is what every existing case, including cycle-free
       ones, already relies on for precision), then verify it against the
       hard edges ALONE.  If it already satisfies every hard edge (the
       common case: no hard/soft cycle exists) return it unchanged.  Only
       when a hard edge is actually violated do we recompute a corrected
       order via Kahn's algorithm restricted to hard edges, using the
       preferred order purely as a tie-break — this guarantees every hard
       dependency is satisfied while still respecting the soft-edge
       preference everywhere it doesn't conflict. *)
    let hard_deps_of decls = unqualified_module_deps ~type_owner ~ctor_owner decls in
    let visited : (string, unit) Hashtbl.t = Hashtbl.create 16 in
    let out = ref [] in
    let dbg = Sys.getenv_opt "MARCH_DEBUG_ORDER" <> None in
    let rec visit name =
      if not (Hashtbl.mem visited name) then begin
        Hashtbl.replace visited name ();
        match Hashtbl.find_opt by_name name with
        | Some (decls, dm) ->
          let deps =
            StringSet.remove name
              (StringSet.inter name_set
                 (StringSet.union
                    (module_refs_in_decls decls)
                    (hard_deps_of decls)))
          in
          if dbg then
            Printf.eprintf "[order] visit %s deps=[%s]\n%!" name
              (String.concat "," (StringSet.elements deps));
          StringSet.iter visit deps;
          out := dm :: !out
        | None -> ()
      end
    in
    List.iter (fun n -> visit n) names;
    let preferred = List.rev !out in
    (* Hard-dependency graph, restricted to sibling names, self-edges removed. *)
    let hard_graph : (string, StringSet.t) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun (modname, (decls, _)) ->
        let deps = StringSet.remove modname (StringSet.inter name_set (hard_deps_of decls)) in
        Hashtbl.replace hard_graph modname deps)
      info;
    let pos : (string, int) Hashtbl.t = Hashtbl.create 16 in
    List.iteri (fun i d -> match d with
        | Ast.DMod (n, _, _, _) -> Hashtbl.replace pos n.Ast.txt i
        | _ -> ())
      preferred;
    let satisfies_hard_deps order =
      let p = Hashtbl.create 16 in
      List.iteri (fun i n -> Hashtbl.replace p n i) order;
      List.for_all (fun n ->
          let deps = Option.value ~default:StringSet.empty (Hashtbl.find_opt hard_graph n) in
          StringSet.for_all (fun d ->
              match Hashtbl.find_opt p d, Hashtbl.find_opt p n with
              | Some pd, Some pn -> pd < pn
              | _ -> true)
            deps)
        names
    in
    let preferred_names =
      List.filter_map (function Ast.DMod (n, _, _, _) -> Some n.Ast.txt | _ -> None) preferred
    in
    let final =
      if satisfies_hard_deps preferred_names then preferred
      else begin
        if dbg then
          Printf.eprintf
            "[order] hard-dependency violation in combined order — falling back to \
             hard-edge Kahn's-algorithm order for: %s\n%!"
            (String.concat "," preferred_names);
        (* Kahn's algorithm over [hard_graph], breaking ties by [pos]
           (the combined-edge DFS's preferred order) so behavior stays as
           close to the previous output as the hard constraints allow. *)
        let in_degree : (string, int) Hashtbl.t = Hashtbl.create 16 in
        let enables : (string, string list) Hashtbl.t = Hashtbl.create 16 in
        List.iter (fun n ->
            let deps = Option.value ~default:StringSet.empty (Hashtbl.find_opt hard_graph n) in
            Hashtbl.replace in_degree n (StringSet.cardinal deps);
            StringSet.iter (fun d ->
                Hashtbl.replace enables d (n :: Option.value ~default:[] (Hashtbl.find_opt enables d)))
              deps)
          names;
        let ready = ref (List.filter (fun n -> Hashtbl.find in_degree n = 0) names) in
        let by_pos a b =
          compare (Option.value ~default:max_int (Hashtbl.find_opt pos a))
                  (Option.value ~default:max_int (Hashtbl.find_opt pos b))
        in
        let corrected = ref [] in
        let remaining = ref (List.length names) in
        while !remaining > 0 do
          match List.sort by_pos !ready with
          | [] ->
            (* Genuine hard cycle: no way to satisfy every constraint.
               Emit whatever is left in preferred order (best effort,
               matches the previous behavior for irreducible cycles). *)
            List.iter (fun n ->
                if not (List.mem n !corrected) then corrected := n :: !corrected)
              preferred_names;
            remaining := 0
          | n :: _ ->
            ready := List.filter (fun x -> x <> n) !ready;
            corrected := n :: !corrected;
            decr remaining;
            List.iter (fun dependent ->
                let d = Hashtbl.find in_degree dependent - 1 in
                Hashtbl.replace in_degree dependent d;
                if d = 0 then ready := dependent :: !ready)
              (Option.value ~default:[] (Hashtbl.find_opt enables n))
        done;
        (* [corrected] was built by prepending as each node finished, so its
           head is the LAST node processed — reverse to restore the actual
           topological (processing) order before mapping back to decls. *)
        List.map (fun n -> snd (Hashtbl.find by_name n)) (List.rev !corrected)
      end
    in
    if dbg then
      Printf.eprintf "[order] final order (%d mods): %s\n%!"
        (List.length final)
        (String.concat ","
           (List.filter_map (function Ast.DMod (n, _, _, _) -> Some n.Ast.txt | _ -> None) final));
    final
  end

(* Reorder both function runs (by call dependency) and module runs (by module
   dependency) within [decls], leaving every other declaration in place. *)
let reorder_decls (decls : Ast.decl list) : Ast.decl list =
  let is_dfn = function Ast.DFn _ -> true | _ -> false in
  let is_dmod = function Ast.DMod _ -> true | _ -> false in
  let take pred ds =
    let rec go acc = function
      | x :: xs when pred x -> go (x :: acc) xs
      | rest -> (List.rev acc, rest)
    in
    go [] ds
  in
  let rec go = function
    | [] -> []
    | d :: _ as ds when is_dfn d ->
      let run, rest = take is_dfn ds in
      dependency_order_dfn_run run @ go rest
    | d :: _ as ds when is_dmod d ->
      let run, rest = take is_dmod ds in
      dependency_order_dmod_run run @ go rest
    | d :: rest -> d :: go rest
  in
  go decls
