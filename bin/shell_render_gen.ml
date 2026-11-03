(* The remote shell's result renderer (R5.7 of
   specs/plans/2026-09-28-observe-recon-shell-plan.md).

   A shell input's fragment returns its result rendered as a String.  This
   module writes that renderer as March source, from the result's STATIC type
   (the client's typecheck of the input), into the fragment only; nothing on
   the node changes.  The combinators it calls are stdlib/shell_render.march's
   (ShellRender), which hold the rules and are unit-tested in March.

   - String, List, Array, Map, Set: `ShellRender.string/list/array/map/set`,
     each given the limit, and the element renderer as a closure, so the limit
     applies at every depth.  The other stdlib containers the same way, through
     their public `to_list`: HashMap, OrderedMap and SortedSet (records
     `{ cmp, tree }` over their trees), Deque, Queue, RRB.Vec, and the
     NativeArray families.  RingBuf and LinearMap are linear (their `to_list`
     consumes them), so they keep `to_string`.
   - Records, tuples and ADTs: one generated function per type (instantiated:
     `Option(Int)` and `Option(String)` are two), rendering field by field
     with constructor names, as derive Show would.  Recursive types recurse
     through these functions.  A type that derives Show is rendered this way
     too (a derived impl is mechanical, so the text is the same within the
     limit); a record type that derives Show keeps its `Name { f = v }` form,
     any other record renders as a record literal `{ f: v }`.
   - A type with a HAND-WRITTEN Show impl: its `show`, cut at 16 KiB
     (`ShellRender.show_cut`), since it cannot take a limit.
   - `()`: "()" (compiled `to_string(())` prints 0); a function: "<fn>", as
     the interpreter prints one (compiled `to_string` of a closure prints
     `#<tag:0>`).  Anything else (Int, Float, Pid, an opaque `ptype`, an
     unresolved type variable): the runtime's `to_string`.

   On-demand derive for a type declared in another module needs no
   re-typecheck of that module: the generated functions match on the type's
   constructors by their module-qualified names (`Json.Object(..)`), which
   the fragment's typecheck resolves like any other input.  A type whose
   constructors are private (`ptype`) cannot be matched from outside its
   module, so it falls back to `to_string`, as an opaque type does. *)

module Ast = March_ast.Ast
module TC = March_typecheck.Typecheck

(* The bare name of a possibly qualified type name. *)
let bare n = match String.rindex_opt n '.' with
  | Some i -> String.sub n (i + 1) (String.length n - i - 1)
  | None -> n

(** The type names with a Show impl in [decls] (stdlib and app, nested
    modules included), split into hand-written and derived.  A derived impl's
    method carries the synthetic file "<none>" (Desugar_derive.respan). *)
let show_impls (decls : Ast.decl list) : (string, bool) Hashtbl.t =
  let t = Hashtbl.create 16 in
  let rec go = function
    | Ast.DMod (_, _, ds, _) -> List.iter go ds
    | Ast.DImpl (idef, _) when idef.Ast.impl_iface.Ast.txt = "Show" ->
      (match idef.Ast.impl_ty with
       | Ast.TyCon (n, _) ->
         let derived = List.for_all (fun ((_ : Ast.name), (fd : Ast.fn_def)) ->
             fd.Ast.fn_name.Ast.span.Ast.file = "<none>") idef.Ast.impl_methods in
         let name = bare n.Ast.txt in
         (* hand-written wins if a name has both *)
         if not (derived && Hashtbl.mem t name) then Hashtbl.replace t name (not derived)
       | _ -> ())
    | _ -> () in
  List.iter go decls;
  t

type st = {
  env : TC.env;
  shows : (string, bool) Hashtbl.t;  (* type name -> has a hand-written Show *)
  program_name : string;
  memo : (string, string) Hashtbl.t; (* type key -> generated function *)
  fns : Buffer.t;
  mutable n : int;
  tag : int;                         (* the input number, in every generated name *)
}

let max_fns = 200

let rec norm t = match TC.repr t with
  | TC.TLin (_, t) | TC.TRefine (t, _, _) -> norm t
  | t -> t

(* A constructor's or record field's surface type, its parameters [subst]ed,
   as a typechecker type; [TError] for what the renderer does not need to
   tell apart (it renders those with to_string). *)
let rec of_surface st (subst : (string * TC.ty) list) (t : Ast.ty) : TC.ty =
  match t with
  | Ast.TyVar n -> Option.value (List.assoc_opt n.Ast.txt subst) ~default:TC.TError
  | Ast.TyCon (n, []) when List.mem_assoc n.Ast.txt subst -> List.assoc n.Ast.txt subst
  | Ast.TyCon (n, args) ->
    let args = List.map (of_surface st subst) args in
    (match TC.StrMap.find_opt n.Ast.txt st.env.TC.ty_aliases with
     | Some (ps, rhs) when List.length ps = List.length args ->
       of_surface st (List.combine ps args) rhs
     | _ ->
       (match TC.StrMap.find_opt n.Ast.txt st.env.TC.records with
        | Some (ps, fields) when List.length ps = List.length args ->
          let sub = List.combine ps args in
          TC.TRecord (List.map (fun (f, ft) -> (f, of_surface st sub ft)) fields)
        | _ -> TC.TCon (bare n.Ast.txt, args)))
  | Ast.TyTuple ts -> TC.TTuple (List.map (of_surface st subst) ts)
  | Ast.TyRecord fs -> TC.TRecord (List.map (fun (n, t) -> (n.Ast.txt, of_surface st subst t)) fs)
  | Ast.TyArrow (a, b) -> TC.TArrow (of_surface st subst a, of_surface st subst b)
  | Ast.TyLinear (_, t) | Ast.TyRefine (t, _, _) -> of_surface st subst t
  | Ast.TyNat _ | Ast.TyNatOp _ | Ast.TyChan _ -> TC.TError

(* The constructors of the type named [name], when the fragment can match on
   all of them: (pattern name, display name, info) in one module's type. *)
let ctors_of st name : (string * string * TC.ctor_info) list option =
  let all = TC.StrMap.fold (fun c infos acc ->
      if String.contains c '.' then acc
      else List.fold_left (fun acc (ci : TC.ctor_info) ->
          if ci.TC.ci_type = name && not ci.TC.ci_is_actor_msg
             && not (List.exists (fun (c', (ci' : TC.ctor_info)) ->
                 c' = c && ci'.TC.ci_module = ci.TC.ci_module) acc)
          then (c, ci) :: acc else acc) acc infos)
      st.env.TC.ctors [] in
  let modules = List.sort_uniq compare (List.map (fun (_, (ci : TC.ctor_info)) -> ci.TC.ci_module) all) in
  let pick = match modules with
    | [ m ] -> Some m
    | ms when List.mem st.program_name ms -> Some st.program_name
    | ms when List.mem "" ms -> Some ""
    | _ -> None in
  match pick with
  | None -> None
  | Some m ->
    let cs = List.filter (fun (_, (ci : TC.ctor_info)) -> ci.TC.ci_module = m) all in
    if cs = [] || List.exists (fun (_, (ci : TC.ctor_info)) -> ci.TC.ci_vis <> Ast.Public) cs then None
    else Some (List.map (fun (c, ci) -> ((if m = "" then c else m ^ "." ^ c), c, ci))
                 (List.sort (fun (a, _) (b, _) -> String.compare a b) cs))

(* Whether the type named [name] is stdlib module [m]'s.  The typechecker's
   type names are bare, so a program's own `Queue`, `Tree` or `Vec` would
   unify with the stdlib's, and rendering it through [m]'s `to_list` would
   read it as the wrong type.  So no other type may be named so:
   - no visible constructor of a type of that name from another module;
   - no type of that name qualified by another module in the session's type
     table, which lists the program's types (`Main.Item` and `Item`);
   - for a stdlib `ptype` (HashMap, Deque, RRB.Vec), whose constructors are
     hidden and whose name the table does not list, not even the bare name:
     a program type of that name, `ptype` or not, is listed bare. *)
let stdlib_type st name m =
  let mods = TC.StrMap.fold (fun _ infos acc ->
      List.fold_left (fun acc (ci : TC.ctor_info) ->
          if ci.TC.ci_type = name then ci.TC.ci_module :: acc else acc) acc infos)
      st.env.TC.ctors [] in
  let dotted = "." ^ name in
  let ends k = let n = String.length k and d = String.length dotted in
    n > d && String.sub k (n - d) d = dotted in
  List.for_all (( = ) m) mods
  && not (TC.StrMap.exists (fun k _ ->
      (ends k && k <> m ^ dotted) || (mods = [] && k = name)) st.env.TC.types)

(* An OrderedMap or a SortedSet: the record `{ cmp, tree }` over
   OrderedMap's `Tree(k, v)` or SortedSet's `AvlTree(a)`. *)
let sorted_tree st (fields : (string * TC.ty) list) =
  match List.sort compare (List.map fst fields), List.assoc_opt "tree" fields with
  | [ "cmp"; "tree" ], Some t ->
    (match norm t with
     | TC.TCon ("Tree", [ k; x ]) when stdlib_type st "Tree" "OrderedMap" -> Some (`Map (k, x))
     | TC.TCon ("AvlTree", [ a ]) when stdlib_type st "AvlTree" "SortedSet" -> Some (`Set a)
     | _ -> None)
  | _ -> None

let quote_lit s = "\"" ^ String.concat "\\\"" (String.split_on_char '"' s) ^ "\""

(* A March expression rendering the value of the expression [v] (a variable)
   of type [t], with the limit in scope as [__l]. *)
(* [outer]: [v] is the result itself, or the one argument of a constructor
   that is (an [Ok("{ n: 42 }")], say): a String there prints unquoted.
   Anywhere deeper (a list, a record, a tuple) strings are quoted. *)
let rec render ?(outer = false) st (t : TC.ty) (v : string) : string =
  let lam a = Printf.sprintf "fn __x -> %s" (render st a "__x") in
  match norm t with
  | TC.TTuple [] -> "\"()\""
  | TC.TArrow _ -> "\"<fn>\""
  | TC.TCon ("String", []) when outer -> Printf.sprintf "ShellRender.raw(%s, __l)" v
  | TC.TCon ("String", []) -> Printf.sprintf "ShellRender.string(%s, __l)" v
  | TC.TCon ("List", [ a ]) -> Printf.sprintf "ShellRender.list(%s, __l, %s)" v (lam a)
  | TC.TCon ("PVec", [ a ]) -> Printf.sprintf "ShellRender.array(%s, __l, %s)" v (lam a)
  | TC.TCon ("Set", [ a ]) -> Printf.sprintf "ShellRender.set(%s, __l, %s)" v (lam a)
  | TC.TCon ("Map", [ k; x ]) -> Printf.sprintf "ShellRender.map(%s, __l, %s, %s)" v (lam k) (lam x)
  | TC.TCon ("HashMap", [ k; x ]) when stdlib_type st "HashMap" "HashMap" ->
    Printf.sprintf "ShellRender.hash_map(%s, __l, %s, %s)" v (lam k) (lam x)
  | TC.TCon ("Deque", [ a ]) when stdlib_type st "Deque" "Deque" ->
    Printf.sprintf "ShellRender.deque(%s, __l, %s)" v (lam a)
  | TC.TCon ("Queue", [ a ]) when stdlib_type st "Queue" "Queue" ->
    Printf.sprintf "ShellRender.queue(%s, __l, %s)" v (lam a)
  | TC.TCon ("Vec", [ a ]) when stdlib_type st "Vec" "RRB" ->
    Printf.sprintf "ShellRender.rrb_vec(%s, __l, %s)" v (lam a)
  | TC.TCon (("NativeIntArr" | "NativeFloatArr" | "NativeF32Arr" | "NativeI32Arr"
             | "NativeU8Arr") as n, []) ->
    let fam = match n with
      | "NativeIntArr" -> "int" | "NativeFloatArr" -> "float" | "NativeF32Arr" -> "f32"
      | "NativeI32Arr" -> "i32" | _ -> "u8" in
    Printf.sprintf "ShellRender.native_array(NativeArray.to_list_%s(%s), __l, fn __x -> to_string(__x))"
      fam v
  | TC.TRecord fields when Option.is_some (sorted_tree st fields) ->
    (match sorted_tree st fields with
     | Some (`Map (k, x)) -> Printf.sprintf "ShellRender.ordered_map(%s, __l, %s, %s)" v (lam k) (lam x)
     | Some (`Set a) -> Printf.sprintf "ShellRender.sorted_set(%s, __l, %s)" v (lam a)
     | None -> assert false)
  | TC.TCon (name, _) when Hashtbl.find_opt st.shows name = Some true
                           && not (List.mem name [ "List"; "Option"; "Result" ]) ->
    Printf.sprintf "ShellRender.show_cut(show(%s))" v
  | TC.TTuple ts as t -> call st t v (fun () ->
      let vars = List.mapi (fun i _ -> Printf.sprintf "__a%d" i) ts in
      Printf.sprintf "    let (%s) = __v\n    ShellRender.tuple([%s])\n"
        (String.concat ", " vars)
        (String.concat ", " (List.map2 (fun x t -> render st t x) vars ts)))
  | TC.TRecord fields as t -> call st t v (fun () ->
      let sg = String.concat "," (List.sort compare (List.map fst fields)) in
      let derived = match Hashtbl.find_opt TC._record_names sg with
        | Some (Some n) when Hashtbl.find_opt st.shows (bare n) = Some false -> Some (bare n)
        | _ -> None in
      let parts = List.map (fun (f, ft) ->
          Printf.sprintf "%s ++ %s"
            (quote_lit (f ^ (if derived <> None then " = " else ": ")))
            (render st ft ("__v." ^ f))) fields in
      match derived with
      | Some n -> Printf.sprintf "    ShellRender.record(%s, [%s])\n" (quote_lit n) (String.concat ", " parts)
      | None -> Printf.sprintf "    ShellRender.anon_record([%s])\n" (String.concat ", " parts))
  | TC.TCon (name, args) as t ->
    (match ctors_of st name with
     | None -> Printf.sprintf "to_string(%s)" v
     | Some cs -> call ~outer st t v (fun () ->
         let arms = List.map (fun (pat, shown, (ci : TC.ctor_info)) ->
             let subst = if List.length ci.TC.ci_params = List.length args
               then List.combine ci.TC.ci_params args else [] in
             match ci.TC.ci_arg_tys with
             | [] -> Printf.sprintf "      %s -> %s\n" pat (quote_lit shown)
             | tys ->
               let vars = List.mapi (fun i _ -> Printf.sprintf "__a%d" i) tys in
               Printf.sprintf "      %s(%s) -> ShellRender.ctor(%s, [%s])\n" pat
                 (String.concat ", " vars) (quote_lit shown)
                 (String.concat ", " (List.map2 (fun x ty ->
                      render ~outer:(outer && List.length tys = 1) st (of_surface st subst ty) x)
                      vars tys)))
             cs in
         Printf.sprintf "    match __v do\n%s    end\n" (String.concat "" arms)))
  | _ -> Printf.sprintf "to_string(%s)" v

(* A call of the generated function for [t] on [v], generating it (its body
   from [body]) the first time [t] is seen. *)
and call ?(outer = false) st t v (body : unit -> string) =
  let key = (if outer then "outer " else "") ^ TC.pp_ty t in
  match Hashtbl.find_opt st.memo key with
  | Some f -> Printf.sprintf "%s(%s, __l)" f v
  | None when st.n >= max_fns -> Printf.sprintf "to_string(%s)" v
  | None ->
    st.n <- st.n + 1;
    let f = Printf.sprintf "__shell_render%d_%d" st.tag st.n in
    Hashtbl.replace st.memo key f;
    let b = body () in
    Buffer.add_string st.fns
      (Printf.sprintf "  @[no_warn_recursion]\n  pfn %s(__v, __l) do\n%s  end\n" f b);
    Printf.sprintf "%s(%s, __l)" f v

(** The renderer for a result of type [ty] held in [var]: the functions to
    declare in the fragment module, and the expression (the limit in scope
    as [__l]).  [tag] (the input number) goes into every generated name:
    Repl_jit.shell_compile keeps an input's non-entry functions in the
    session's lowered program, by name, so two inputs' renderers with one
    name would collide (the second input then ran the first's renderer on
    its own value and crashed the node). *)
let generate ~env ~shows ~program_name ~tag (ty : TC.ty) (var : string) : string * string =
  let st = { env; shows; program_name; memo = Hashtbl.create 8; fns = Buffer.create 256; n = 0; tag } in
  let e = render ~outer:true st ty var in
  (Buffer.contents st.fns, e)
