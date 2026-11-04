(* Law coverage (specs/2026-11-04-law-coverage-design.md §4); see the .mli. *)

module A = March_ast.Ast
module RR = Refine_reflect

type status = Uncovered | Unproved_only of string list | Covered of string list | Higher_order

type entry = {
  e_module : string;
  e_name : string;
  e_public : bool;
  e_span : A.span;
  e_status : status;
  e_impl : (string * string) option;
  e_qname : string;
  e_fd : A.fn_def;
  e_laws : string list;
}

(* A call head as written: `f`, or `M.f` for a qualified call (parsed either as
   a dotted variable or as a field of a constructor/variable path). *)
let rec dotted (e : A.expr) : string option =
  match e with
  | A.EVar n -> Some n.A.txt
  | A.ECon (n, [], _) -> Some n.A.txt
  | A.EField (e, n, _) -> Option.map (fun p -> p ^ "." ^ n.A.txt) (dotted e)
  | _ -> None

let theorem_calls (fd : A.fn_def) : string list =
  match Refine_check.lemma_post fd with
  | Error _ -> []
  | Ok (_, p) ->
    let acc = ref [] in
    let rec walk (e : A.expr) =
      (match e with
       | A.EApp (f, _, _) -> (
         match dotted f with Some h when not (List.mem h !acc) -> acc := h :: !acc | _ -> ())
       | _ -> ());
      List.iter walk (Refine_encode.children e)
    in
    walk p;
    List.rev !acc

(* Every function of [ds] by qualified name relative to the module that holds
   [ds] (`Inner.inc`), as the reflection rows and the lemma table name them. *)
let rec fns ?(prefix = "") (ds : A.decl list) : (string * string * A.fn_def) list =
  List.concat_map
    (function
      | A.DFn (fd, _) -> [ (prefix ^ fd.A.fn_name.A.txt, prefix, fd) ]
      | A.DMod (n, _, inner, _) -> fns ~prefix:(prefix ^ n.A.txt ^ ".") inner
      | _ -> [])
    ds

let strip_dot p = if p = "" then "" else String.sub p 0 (String.length p - 1)

(* `A.B.` -> [ "A.B."; "A."; "" ]: the scopes a name is looked up in, innermost first. *)
let prefixes (p : string) : string list =
  let parts = String.split_on_char '.' (strip_dot p) |> List.filter (( <> ) "") in
  let rec go = function [] -> [ "" ] | l -> (String.concat "." l ^ ".") :: go (List.rev (List.tl (List.rev l))) in
  go parts

let last_segment s = match String.rindex_opt s '.' with Some i -> String.sub s (i + 1) (String.length s - i - 1) | None -> s

(* The generated names of [lib/desugar/interface_laws.ml]: an impl method's copy
   is `__law_<m>__<tag>`, a law's lemma `<law>__<tag>`, with <tag> =
   `<Iface>_<type tag>`.  Mirrored here (refinecheck does not depend on desugar). *)
let rec ty_tag (t : A.ty) : string =
  match t with
  | A.TyCon (n, []) -> String.map (fun c -> if c = '.' then '_' else c) n.A.txt
  | A.TyCon (n, args) -> String.concat "_" (ty_tag (A.TyCon (n, [])) :: List.map ty_tag args)
  | A.TyVar n -> n.A.txt
  | A.TyTuple ts -> String.concat "_" ("T" :: List.map ty_tag ts)
  | A.TyRefine (b, _, _) | A.TyLinear (_, b) -> ty_tag b
  | _ -> "T"

let rec ty_text (t : A.ty) : string =
  match t with
  | A.TyCon (n, []) -> n.A.txt
  | A.TyCon (n, args) -> n.A.txt ^ "(" ^ String.concat ", " (List.map ty_text args) ^ ")"
  | A.TyVar n -> n.A.txt
  | A.TyTuple ts -> "(" ^ String.concat ", " (List.map ty_text ts) ^ ")"
  | A.TyRefine (b, _, _) | A.TyLinear (_, b) -> ty_text b
  | _ -> "_"

let copy_prefix = "__law_"

(* Every impl of [ds]: (module prefix, interface (bare), impl type, its non-lemma methods). *)
let rec impls ?(prefix = "") (ds : A.decl list) : (string * string * A.ty * (A.name * A.fn_def) list) list =
  List.concat_map
    (function
      | A.DImpl (idef, _) ->
        [ (prefix, last_segment idef.A.impl_iface.A.txt, idef.A.impl_ty,
           List.filter (fun (_, (fd : A.fn_def)) -> not (List.mem "lemma" fd.A.fn_attrs)) idef.A.impl_methods) ]
      | A.DMod (n, _, inner, _) -> impls ~prefix:(prefix ^ n.A.txt ^ ".") inner
      | _ -> [])
    ds

let entries ~file_mod ~(rows : RR.row list) ~lemmas ~decls ~is_user : entry list =
  let all = fns decls in
  let user = List.filter (fun (_, _, (fd : A.fn_def)) -> is_user fd.A.fn_name.A.span) all in
  let universe = Hashtbl.create 256 in
  List.iter (fun (q, _, _) -> Hashtbl.replace universe q ()) all;
  let user_names = List.map (fun (q, _, _) -> q) user in
  (* A theorem call [h] in the lemma named [lq]: the first scope of the
     lemma's own module path that defines it, then the name as written; a
     bare name that resolves nowhere falls back to the one user function of
     that name, if there is exactly one (a `use`-imported call). *)
  let resolve lq h =
    let scope = match String.rindex_opt lq '.' with Some i -> String.sub lq 0 (i + 1) | None -> "" in
    match List.find_opt (fun p -> Hashtbl.mem universe (p ^ h)) (prefixes scope) with
    | Some p -> Some (p ^ h)
    | None -> (
      if String.contains h '.' then None
      else match List.filter (fun q -> last_segment q = h) user_names with [ q ] -> Some q | _ -> None)
  in
  let impl_list = impls decls in
  (* tag -> interface, for naming a generated law `<law> (via <Iface>)` *)
  let law_tags = Hashtbl.create 8 in
  List.iter (fun (_, iface, ty, _) -> Hashtbl.replace law_tags (iface ^ "_" ^ ty_tag ty) iface) impl_list;
  (* `<law>__<Iface>_<T>` -> `<law> (via <Iface>)`, for a generated law. *)
  let law_display b =
    let n = String.length b in
    let rec find i = if i + 1 >= n then None else if b.[i] = '_' && b.[i + 1] = '_' then Some i else find (i + 1) in
    match find 1 with
    | Some i -> (
      match Hashtbl.find_opt law_tags (String.sub b (i + 2) (n - i - 2)) with
      | Some iface -> Printf.sprintf "%s (via %s)" (String.sub b 0 i) iface
      | None -> b)
    | None -> b
  in
  let by_fn = Hashtbl.create 64 in
  let law_q = Hashtbl.create 64 in
  List.iter
    (fun (lq, (fd : A.fn_def), admitted) ->
      List.iter
        (fun h ->
          match resolve lq h with
          | Some q ->
            let a, u = Option.value ~default:([], []) (Hashtbl.find_opt by_fn q) in
            let l = law_display (last_segment lq) in
            Hashtbl.replace by_fn q (if admitted then (a @ [ l ], u) else (a, u @ [ l ]));
            if admitted then Hashtbl.replace law_q q (Option.value ~default:[] (Hashtbl.find_opt law_q q) @ [ lq ])
          | None -> ())
        (theorem_calls fd))
    lemmas;
  let verdict_at = Hashtbl.create 64 in
  (* Every top-level verdict, by span: an impl method's copy has a synthetic
     span (file `<none>`), and whether its row is user code is decided by the
     impl method's own span below. *)
  List.iter (fun (r : RR.row) -> if r.RR.r_top then Hashtbl.replace verdict_at r.RR.r_span r.RR.r_verdict) rows;
  let status_of q (fd : A.fn_def) =
    match Hashtbl.find_opt verdict_at fd.A.fn_name.A.span with
    | Some (RR.Reflected _) -> (
      match Hashtbl.find_opt by_fn q with
      | Some ((_ :: _ as a), _) -> Some (Covered a)
      | Some ([], (_ :: _ as u)) -> Some (Unproved_only u)
      | _ -> Some Uncovered)
    | Some (RR.Specialised _) -> Some Higher_order
    | _ -> None
  in
  let module_of prefix = let inner = strip_dot prefix in if inner = "" then file_mod else file_mod ^ "." ^ inner in
  (* An impl method appears only through its copy, which exists only for an
     interface that declares laws. *)
  let impl_entries =
    List.concat_map
      (fun (prefix, iface, ty, methods) ->
        List.filter_map
          (fun ((mn : A.name), (mfd : A.fn_def)) ->
            if not (is_user mfd.A.fn_name.A.span || is_user mn.A.span) then None
            else
              let cq = prefix ^ copy_prefix ^ mn.A.txt ^ "__" ^ iface ^ "_" ^ ty_tag ty in
              match List.find_opt (fun (q, _, _) -> q = cq) all with
              | None -> None
              | Some (_, _, cfd) ->
                Option.map
                  (fun e_status ->
                    { e_module = module_of prefix; e_name = mn.A.txt; e_public = true; e_span = mn.A.span; e_status;
                      e_impl = Some (iface, ty_text ty); e_qname = cq; e_fd = cfd;
                      e_laws = Option.value ~default:[] (Hashtbl.find_opt law_q cq) })
                  (status_of cq cfd))
          methods)
      impl_list
  in
  let is_copy (fd : A.fn_def) = String.starts_with ~prefix:copy_prefix fd.A.fn_name.A.txt in
  List.filter_map
    (fun (q, prefix, (fd : A.fn_def)) ->
      if List.mem "lemma" fd.A.fn_attrs || is_copy fd then None
      else
        let e_status = status_of q fd in
        Option.map
          (fun e_status ->
            { e_module = module_of prefix;
              e_name = fd.A.fn_name.A.txt;
              e_public = fd.A.fn_vis = A.Public;
              e_span = fd.A.fn_name.A.span;
              e_status;
              e_impl = None;
              e_qname = q;
              e_fd = fd;
              e_laws = Option.value ~default:[] (Hashtbl.find_opt law_q q) })
          e_status)
    user
  @ impl_entries

let loc (sp : A.span) = Printf.sprintf "%s:%d" (Filename.basename sp.A.file) sp.A.start_line

let strength_lines (v : Law_strength.verdict) : string list =
  let open Law_strength in
  if v.v_no_gen then [ "    strength: not run (no input generator)" ]
  else
    let head =
      match v.v_partial with
      | Some (n, m) -> Printf.sprintf "    strength: partial (budget), %d of %d edits judged" n m
      | None ->
        Printf.sprintf "    strength: %d of %d edits survive%s" (List.length v.v_survivors) v.v_total
          (if v.v_undecided = 0 then "" else Printf.sprintf " (%d undecided)" v.v_undecided)
    in
    head :: List.map (fun e -> Printf.sprintf "    survives: %s  %s" e.ed_desc (loc e.ed_span)) v.v_survivors

let report_lines ?(strength = fun _ -> None) (es : entry list) : string list =
  let modules = List.fold_left (fun acc e -> if List.mem e.e_module acc then acc else acc @ [ e.e_module ]) [] es in
  List.concat_map
    (fun md ->
      let all_es = List.filter (fun e -> e.e_module = md) es in
      let es = List.filter (fun e -> e.e_impl = None) all_es in
      let impl_es = List.filter (fun e -> e.e_impl <> None) all_es in
      let pick f = List.filter f es in
      let uncov_pub = pick (fun e -> e.e_status = Uncovered && e.e_public)
      and uncov_priv = pick (fun e -> e.e_status = Uncovered && not e.e_public)
      and unproved = pick (fun e -> match e.e_status with Unproved_only _ -> true | _ -> false)
      and covered = pick (fun e -> match e.e_status with Covered _ -> true | _ -> false)
      and ho = pick (fun e -> e.e_status = Higher_order) in
      let pure = List.length uncov_pub + List.length uncov_priv + List.length unproved + List.length covered in
      let more = if unproved = [] then "" else Printf.sprintf " (%d more only by unproved laws)" (List.length unproved) in
      let row ?(sep = "  ") label e laws =
        Printf.sprintf "  %s%s%s  %s%s" label sep e.e_name (loc e.e_span)
          (match laws with [] -> "" | ls -> "  (" ^ String.concat ", " ls ^ ")")
      in
      let laws e = match e.e_status with Covered l | Unproved_only l -> l | _ -> [] in
      let under e = match strength e with Some v -> strength_lines v | None -> [] in
      (Printf.sprintf "law coverage: %s: %d of %d pure functions have a law%s" md (List.length covered) pure more)
      :: List.map (fun e -> row "uncovered (public)" e []) uncov_pub
      @ List.map (fun e -> row "uncovered (private)" e []) uncov_priv
      @ List.map (fun e -> row "unproved only" e (laws e)) unproved
      @ List.concat_map (fun e -> row "covered" e (laws e) :: under e) covered
      @ List.concat_map
          (fun e ->
            let i, t = Option.get e.e_impl in
            row ~sep:" " (Printf.sprintf "impl %s for %s:" i t) e (laws e) :: under e)
          impl_es
      @ List.map (fun e -> row "higher-order (no laws possible yet)" e []) ho)
    modules

let json_lines ?(strength = fun _ -> None) (es : entry list) : string list =
  let str = Infer_json.str and arr = Infer_json.arr in
  List.map
    (fun e ->
      let status, cov, unp =
        match e.e_status with
        | Uncovered -> ("uncovered", [], [])
        | Unproved_only u -> ("unproved-only", [], u)
        | Covered c -> ("covered", c, [])
        | Higher_order -> ("higher-order", [], [])
      in
      let status = if e.e_impl <> None then "impl-method" else status in
      Printf.sprintf
        "{\"kind\":\"law-coverage\",\"module\":%s,\"fn\":%s,\"public\":%b,\"file\":%s,\"line\":%d,\"status\":%s,\"covered_by\":%s,\"unproved_by\":%s,\"impl\":%s,\"strength\":%s}"
        (str e.e_module) (str e.e_name) e.e_public (str e.e_span.A.file) e.e_span.A.start_line (str status)
        (arr (List.map str cov)) (arr (List.map str unp))
        (match e.e_impl with
         | None -> "null"
         | Some (i, t) -> Printf.sprintf "{\"interface\":%s,\"type\":%s}" (str i) (str t))
        (match strength e with
         | None -> "null"
         | Some v ->
           let open Law_strength in
           Printf.sprintf "{\"total\":%d,\"survivors\":%s,\"undecided\":%d,\"partial\":%s,\"no_generator\":%b}" v.v_total
             (arr
                (List.map
                   (fun ed -> Printf.sprintf "{\"desc\":%s,\"line\":%d}" (str ed.ed_desc) ed.ed_span.A.start_line)
                   v.v_survivors))
             v.v_undecided
             (match v.v_partial with
              | None -> "null"
              | Some (n, m) -> Printf.sprintf "{\"judged\":%d,\"of\":%d}" n m)
             v.v_no_gen))
    es
