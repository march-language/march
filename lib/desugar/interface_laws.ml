(** Interface laws (specs/todos/2026-11-02-lemma-uses-beyond-refinement.md
    idea 6): a law declared in an interface becomes one lemma per impl.

    {[
      interface Monoid(a) do
        fn combine : a -> a -> a
        @[lemma]
        fn combine_assoc(x : a, y : a, z : a)
          : {Unit | combine(combine(x, y), z) == combine(x, combine(y, z))}
      end
      impl Monoid(Int) do
        fn combine(x, y) do x + y end
      end
    ]}

    The refinement checker never reflects an impl method (dispatch picks it
    by type), so the theorem cannot talk about `combine` directly.  For each
    impl of an interface declared in the same file, this pass generates, next
    to the impl:

    - a copy of each impl method, [__law_<m>__<Iface>_<T>], with its parameter
      types from the interface signature at [a := T] and every call of a
      sibling method renamed to that sibling's copy: an ordinary top-level
      function, so it is reflected like any other;
    - for each law, a lemma [<law>__<Iface>_<T>] whose theorem is the law's
      with [a := T] and the method calls renamed to the copies.  Its body is
      the impl's own `@[lemma] fn <law>(..)` if it has one (its proof, taken
      out of the impl's methods), else `()`.

    The lemma is then checked, tested and erased like any lemma: proved,
    [lemma_unproved] (an error under `cap verified`), or
    [refinement_violated] with a counterexample.  [Lemma_erase] drops the
    copies with the lemmas.  Generated code gets fresh synthetic spans (no
    type-map collisions between impls); the lemma's name keeps a real span at
    the impl (its proof's name, else the impl's interface name), so its
    diagnostics point there. *)

open March_ast.Ast

let copy_prefix = "__law_"

(* The name fragment for an impl's type: `List(Int)` -> `List_Int`. *)
let rec ty_tag (t : ty) : string =
  match t with
  | TyCon (n, []) -> String.map (fun c -> if c = '.' then '_' else c) n.txt
  | TyCon (n, args) -> String.concat "_" (ty_tag (TyCon (n, [])) :: List.map ty_tag args)
  | TyVar n -> n.txt
  | TyTuple ts -> String.concat "_" ("T" :: List.map ty_tag ts)
  | TyRefine (b, _, _) | TyLinear (_, b) -> ty_tag b
  | _ -> "T"

let bare s = match String.rindex_opt s '.' with Some i -> String.sub s (i + 1) (String.length s - i - 1) | None -> s

let rec subst_ty (a : string) (by : ty) (t : ty) : ty =
  match t with
  | TyVar n when n.txt = a -> by
  | TyCon (n, args) -> TyCon (n, List.map (subst_ty a by) args)
  | TyArrow (x, y) -> TyArrow (subst_ty a by x, subst_ty a by y)
  | TyTuple ts -> TyTuple (List.map (subst_ty a by) ts)
  | TyRecord fs -> TyRecord (List.map (fun (n, t) -> (n, subst_ty a by t)) fs)
  | TyLinear (l, t) -> TyLinear (l, subst_ty a by t)
  | TyRefine (b, x, p) -> TyRefine (subst_ty a by b, x, p)
  | t -> t

(* [g] applied bottom-up to every subexpression; spans kept. *)
let rec map_expr (g : expr -> expr) (e : expr) : expr =
  let r = map_expr g in
  g
  @@
  match e with
  | EApp (f, args, sp) -> EApp (r f, List.map r args, sp)
  | ECon (n, args, sp) -> ECon (n, List.map r args, sp)
  | ELam (ps, body, sp) -> ELam (ps, r body, sp)
  | EBlock (es, sp) -> EBlock (List.map r es, sp)
  | ELet (b, sp) -> ELet ({ b with bind_expr = r b.bind_expr }, sp)
  | EMatch (s, brs, sp) ->
    EMatch
      (r s, List.map (fun br -> { br with branch_guard = Option.map r br.branch_guard; branch_body = r br.branch_body }) brs, sp)
  | ETuple (es, sp) -> ETuple (List.map r es, sp)
  | ERecord (fs, sp) -> ERecord (List.map (fun (n, e) -> (n, r e)) fs, sp)
  | ERecordUpdate (e, fs, sp) -> ERecordUpdate (r e, List.map (fun (n, e) -> (n, r e)) fs, sp)
  | EField (e, n, sp) -> EField (r e, n, sp)
  | EIf (c, t, e, sp) -> EIf (r c, r t, r e, sp)
  | ECond (arms, sp) -> ECond (List.map (fun (c, b) -> (r c, r b)) arms, sp)
  | EPipe (a, b, sp) -> EPipe (r a, r b, sp)
  | EAnnot (e, t, sp) -> EAnnot (r e, t, sp)
  | EAtom (s, args, sp) -> EAtom (s, List.map r args, sp)
  | ELetFn (n, ps, rt, body, sp) -> ELetFn (n, ps, rt, r body, sp)
  | ELetQ (p, a, b, sp) -> ELetQ (p, r a, r b, sp)
  | ELetStar (p, a, b, sp) -> ELetStar (p, r a, r b, sp)
  | EAssert (e, sp) -> EAssert (r e, sp)
  | e -> e

(* Every variable (call heads included) renamed by [f]. *)
let rename (f : string -> string option) (e : expr) : expr =
  map_expr (function EVar n -> (match f n.txt with Some s -> EVar { n with txt = s } | None -> EVar n) | e -> e) e

let is_unit_ty = function TyCon ({ txt = "Unit"; _ }, []) | TyTuple [] -> true | _ -> false

(* A call of a copy taking `Unit` arguments, those arguments dropped: the
   logic has no `Unit` value, so `empty(())` becomes `empty()`.  [units]
   maps a copy's name to the positions of its `Unit` parameters. *)
let drop_unit_args (units : (string * int list) list) (e : expr) : expr =
  map_expr
    (function
      | EApp ((EVar n as h), args, sp) when List.mem_assoc n.txt units ->
        let drop = List.assoc n.txt units in
        EApp (h, List.filteri (fun i _ -> not (List.mem i drop)) args, sp)
      | e -> e)
    e

(* `a -> b -> c` as ([a; b], c). *)
let rec arrows (t : ty) : ty list * ty =
  match t with
  | TyArrow (x, y) ->
    let xs, ret = arrows y in
    (x :: xs, ret)
  | t -> ([], t)

let params_of (fd : fn_def) : fn_param list = match fd.fn_clauses with c :: _ -> c.fc_params | [] -> []

let param_name = function
  | FPNamed p | FPDefault (p, _) -> Some p.param_name.txt
  | FPPat (PatVar n) -> Some n.txt
  | FPPat _ -> None

let generate (ifaces : (string * interface_def) list) (idef : impl_def) (impl_sp : span) : impl_def * decl list =
  match List.assoc_opt (bare idef.impl_iface.txt) ifaces with
  | None -> (idef, [])
  | Some iface when iface.iface_laws = [] -> (idef, [])
  | Some iface ->
    let tag = bare iface.iface_name.txt ^ "_" ^ ty_tag idef.impl_ty in
    let sub = subst_ty iface.iface_param.txt idef.impl_ty in
    let law_names = List.map (fun (l : fn_def) -> l.fn_name.txt) iface.iface_laws in
    let proofs, methods =
      List.partition (fun ((n : name), (fd : fn_def)) -> List.mem "lemma" fd.fn_attrs && List.mem n.txt law_names) idef.impl_methods
    in
    let method_names = List.map (fun (m : method_decl) -> m.md_name.txt) iface.iface_methods in
    (* A default the impl takes (an impl in another file never had it
       injected): a function built from the default's lambda. *)
    let defaults =
      List.filter_map
        (fun (md : method_decl) ->
          match md.md_default with
          | Some (ELam (ps, body, sp)) when not (List.exists (fun ((n : name), _) -> n.txt = md.md_name.txt) methods) ->
            Some
              ( md.md_name,
                { fn_name = md.md_name; fn_vis = Private; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
                  fn_clauses =
                    [ { fc_params = List.map (fun p -> FPNamed p) ps; fc_guard = None; fc_body = body; fc_span = sp;
                        fc_params_span = sp } ];
                  fn_bounds = []; fn_attr_args = []; fn_needs = None } )
          | _ -> None)
        iface.iface_methods
    in
    let methods_all = methods @ defaults in
    let defined = List.filter_map (fun ((n : name), _) -> if List.mem n.txt method_names then Some n.txt else None) methods_all in
    let copy m = copy_prefix ^ m ^ "__" ^ tag in
    let to_copy s = if List.mem (bare s) defined then Some (copy (bare s)) else None in
    let law_name l = l ^ "__" ^ tag in
    (* Each copy's `Unit` parameter positions, from the signature. *)
    let units =
      List.filter_map
        (fun (md : method_decl) ->
          let args, _ = arrows md.md_ty in
          let pos = List.concat (List.mapi (fun i t -> if is_unit_ty t then [ i ] else []) args) in
          if pos <> [] && List.mem md.md_name.txt defined then Some (copy md.md_name.txt, pos) else None)
        iface.iface_methods
    in
    let rewrite f e = drop_unit_args units (rename f e) in
    (* The impl's methods as top-level functions, typed from the signature. *)
    let copies =
      List.filter_map
        (fun ((n : name), (fd : fn_def)) ->
          match List.find_opt (fun (m : method_decl) -> m.md_name.txt = n.txt) iface.iface_methods with
          | None -> None
          | Some md ->
            let args, ret = arrows (sub md.md_ty) in
            let typed i fp =
              match fp with
              | FPNamed p when p.param_ty = None -> (
                match List.nth_opt args i with Some t -> FPNamed { p with param_ty = Some t } | None -> fp)
              | fp -> fp
            in
            let unit_pos = Option.value ~default:[] (List.assoc_opt (copy n.txt) units) in
            let fd =
              { fd with
                fn_name = { n with txt = copy n.txt };
                fn_vis = Private;
                fn_attrs = [ "no_warn_recursion" ];
                fn_ret_ty = (match fd.fn_ret_ty with Some t -> Some t | None -> Some ret);
                fn_clauses =
                  List.map
                    (fun c ->
                      { c with
                        fc_params = List.filteri (fun i _ -> not (List.mem i unit_pos)) (List.mapi typed c.fc_params);
                        fc_body = rewrite to_copy c.fc_body })
                    fd.fn_clauses }
            in
            Some (DFn (fd, impl_sp)))
        methods_all
    in
    let lemmas =
      List.mapi
        (fun k (law : fn_def) ->
          let proof = List.assoc_opt law.fn_name.txt (List.map (fun ((n : name), fd) -> (n.txt, fd)) proofs) in
          (* The theorem and the body speak of the proof's parameter names
             when there is a proof. *)
          let law_params = List.filter_map param_name (params_of law) in
          let names =
            match proof with
            | Some pf ->
              let pn = List.filter_map param_name (params_of pf) in
              if List.length pn = List.length law_params then pn else law_params
            | None -> law_params
          in
          let to_proof s = match List.find_index (( = ) s) law_params with Some i -> List.nth_opt names i | None -> None in
          let to_law s = if List.mem s law_names && Option.is_some proof then Some (law_name s) else None in
          let theorem_rename s =
            match to_proof s with Some n -> Some n | None -> to_copy s
          in
          let ret =
            match law.fn_ret_ty with
            | Some (TyRefine (b, x, p)) -> Some (TyRefine (b, x, rewrite theorem_rename p))
            | t -> t
          in
          let params =
            List.mapi
              (fun i fp ->
                match fp with
                | FPNamed p ->
                  FPNamed
                    { p with
                      param_name = { p.param_name with txt = Option.value ~default:p.param_name.txt (List.nth_opt names i) };
                      param_ty = Option.map sub p.param_ty }
                | fp -> fp)
              (params_of law)
          in
          let body =
            match proof with
            | Some pf -> (
              match pf.fn_clauses with
              | c :: _ -> rewrite (fun s -> match to_law s with Some n -> Some n | None -> to_copy s) c.fc_body
              | [] -> ETuple ([], impl_sp))
            | None -> ETuple ([], impl_sp)
          in
          let clause = match law.fn_clauses with c :: _ -> c | [] -> assert false in
          let name_span =
            match proof with
            | Some pf -> pf.fn_name.span
            | None ->
              (* Unique per law: the impl's interface name, widened by the
                 law's index (span-keyed tables must not share it). *)
              let s = idef.impl_iface.span in
              { s with end_col = s.end_col + k }
          in
          let fd =
            { law with
              fn_name = { law.fn_name with txt = law_name law.fn_name.txt };
              fn_vis = Private;
              fn_ret_ty = ret;
              fn_clauses = [ { clause with fc_params = params; fc_body = body; fc_guard = None } ] }
          in
          (fd, name_span))
        iface.iface_laws
    in
    let respanned =
      List.map Desugar_derive.respan_derived_decl copies
      @ List.map
          (fun (fd, name_span) ->
            match Desugar_derive.respan_derived_decl (DFn (fd, impl_sp)) with
            | DFn (fd, sp) -> DFn ({ fd with fn_name = { fd.fn_name with span = name_span } }, sp)
            | d -> d)
          lemmas
    in
    ({ idef with impl_methods = methods }, respanned)

let rec collect_ifaces (ds : decl list) : (string * interface_def) list =
  List.concat_map
    (function
      | DInterface (i, _) when i.iface_laws <> [] -> [ (i.iface_name.txt, i) ]
      | DMod (_, _, inner, _) -> collect_ifaces inner
      | _ -> [])
    ds

(* Was this impl already expanded (its first law's lemma is a sibling)? *)
let expanded (ifaces : (string * interface_def) list) (siblings : decl list) (idef : impl_def) : bool =
  match List.assoc_opt (bare idef.impl_iface.txt) ifaces with
  | Some ({ iface_laws = l :: _; _ } as iface) ->
    let name = l.fn_name.txt ^ "__" ^ bare iface.iface_name.txt ^ "_" ^ ty_tag idef.impl_ty in
    List.exists (function DFn (fd, _) -> fd.fn_name.txt = name | _ -> false) siblings
  | _ -> false

let expand_with (ifaces : (string * interface_def) list) (decls : decl list) : decl list =
  if ifaces = [] then decls
  else
    let rec go ds =
      List.concat_map
        (function
          | DImpl (idef, sp) when not (expanded ifaces ds idef) ->
            let idef, extra = generate ifaces idef sp in
            DImpl (idef, sp) :: extra
          | DMod (n, v, inner, sp) -> [ DMod (n, v, go inner, sp) ]
          | d -> [ d ])
        ds
    in
    go decls

(** Each impl of a lawful interface of [decls] followed by its generated
    copies and lemmas; [decls] unchanged when no interface has a law.  One
    file, inside [Desugar.desugar_module]. *)
let expand (decls : decl list) : decl list = expand_with (collect_ifaces decls) decls

(** The whole program: impls in one file of an interface declared in another
    ([context] is the other files' declarations when the caller keeps them
    apart).  An impl the per-file [expand] already handled is left alone. *)
let expand_program ?(context : decl list = []) (decls : decl list) : decl list =
  expand_with (collect_ifaces (context @ decls)) decls
