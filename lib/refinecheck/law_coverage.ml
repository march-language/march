(* Law coverage (specs/2026-11-04-law-coverage-design.md §4); see the .mli. *)

module A = March_ast.Ast
module RR = Refine_reflect

type status = Uncovered | Unproved_only of string list | Covered of string list | Higher_order

type entry = { e_module : string; e_name : string; e_public : bool; e_span : A.span; e_status : status }

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
  let by_fn = Hashtbl.create 64 in
  List.iter
    (fun (lq, (fd : A.fn_def), admitted) ->
      List.iter
        (fun h ->
          match resolve lq h with
          | Some q ->
            let a, u = Option.value ~default:([], []) (Hashtbl.find_opt by_fn q) in
            let l = last_segment lq in
            Hashtbl.replace by_fn q (if admitted then (a @ [ l ], u) else (a, u @ [ l ]))
          | None -> ())
        (theorem_calls fd))
    lemmas;
  let verdict_at = Hashtbl.create 64 in
  List.iter (fun (r : RR.row) -> if r.RR.r_top && is_user r.RR.r_span then Hashtbl.replace verdict_at r.RR.r_span r.RR.r_verdict) rows;
  List.filter_map
    (fun (q, prefix, (fd : A.fn_def)) ->
      if List.mem "lemma" fd.A.fn_attrs then None
      else
        let e_status =
          match Hashtbl.find_opt verdict_at fd.A.fn_name.A.span with
          | Some (RR.Reflected _) -> (
            match Hashtbl.find_opt by_fn q with
            | Some ((_ :: _ as a), _) -> Some (Covered a)
            | Some ([], (_ :: _ as u)) -> Some (Unproved_only u)
            | _ -> Some Uncovered)
          | Some (RR.Specialised _) -> Some Higher_order
          | _ -> None
        in
        Option.map
          (fun e_status ->
            let inner = strip_dot prefix in
            { e_module = (if inner = "" then file_mod else file_mod ^ "." ^ inner);
              e_name = fd.A.fn_name.A.txt;
              e_public = fd.A.fn_vis = A.Public;
              e_span = fd.A.fn_name.A.span;
              e_status })
          e_status)
    user

let loc (sp : A.span) = Printf.sprintf "%s:%d" (Filename.basename sp.A.file) sp.A.start_line

let report_lines (es : entry list) : string list =
  let modules = List.fold_left (fun acc e -> if List.mem e.e_module acc then acc else acc @ [ e.e_module ]) [] es in
  List.concat_map
    (fun md ->
      let es = List.filter (fun e -> e.e_module = md) es in
      let pick f = List.filter f es in
      let uncov_pub = pick (fun e -> e.e_status = Uncovered && e.e_public)
      and uncov_priv = pick (fun e -> e.e_status = Uncovered && not e.e_public)
      and unproved = pick (fun e -> match e.e_status with Unproved_only _ -> true | _ -> false)
      and covered = pick (fun e -> match e.e_status with Covered _ -> true | _ -> false)
      and ho = pick (fun e -> e.e_status = Higher_order) in
      let pure = List.length uncov_pub + List.length uncov_priv + List.length unproved + List.length covered in
      let more = if unproved = [] then "" else Printf.sprintf " (%d more only by unproved laws)" (List.length unproved) in
      let row label e laws =
        Printf.sprintf "  %s  %s  %s%s" label e.e_name (loc e.e_span)
          (match laws with [] -> "" | ls -> "  (" ^ String.concat ", " ls ^ ")")
      in
      let laws e = match e.e_status with Covered l | Unproved_only l -> l | _ -> [] in
      (Printf.sprintf "law coverage: %s: %d of %d pure functions have a law%s" md (List.length covered) pure more)
      :: List.map (fun e -> row "uncovered (public)" e []) uncov_pub
      @ List.map (fun e -> row "uncovered (private)" e []) uncov_priv
      @ List.map (fun e -> row "unproved only" e (laws e)) unproved
      @ List.map (fun e -> row "covered" e (laws e)) covered
      @ List.map (fun e -> row "higher-order (no laws possible yet)" e []) ho)
    modules
