(* Capture sets: see capture_set.mli. *)

module A = March_ast.Ast

type scope = { kind : string; arg : string option }
type t = Unknown | Set of scope list  (* sorted, no element covered by another *)

let empty = Set []
let full = Set [ { kind = "IO"; arg = None } ]
let unknown = Unknown

let is_unknown = function Unknown -> true | Set _ -> false
let is_empty = function Set [] -> true | _ -> false
let scopes = function Unknown -> [] | Set l -> l

let host_covers (a : string) (b : string) : bool =
  match Host_scope.parse_decl (Some a), Host_scope.parse_decl (Some b) with
  | Ok da, Ok db ->
    let methods_ok =
      match da.Host_scope.methods, db.Host_scope.methods with
      | None, _ -> true
      | Some _, None -> false
      | Some ma, Some mb -> List.for_all (fun m -> List.mem m ma) mb
    in
    let rec is_prefix p q =
      match p, q with
      | [], _ -> true
      | x :: p', y :: q' -> x = y && is_prefix p' q'
      | _ :: _, [] -> false
    in
    let pat_covers (pa : Host_scope.pattern) (pb : Host_scope.pattern) =
      let host_ok =
        if pa.wildcard then
          let suffix = "." ^ pa.host in
          let n = String.length pb.host and k = String.length suffix in
          n > k && String.sub pb.host (n - k) k = suffix
        else (not pb.wildcard) && pa.host = pb.host
      in
      host_ok
      && (match pa.port, pb.port with
          | None, _ -> true
          | Some x, Some y -> x = y
          | Some _, None -> false)
      && (match pa.path, pb.path with
          | None, _ -> true
          | Some x, Some y -> is_prefix x y
          | Some _, None -> false)
    in
    methods_ok
    && ((not da.no_redirects) || db.no_redirects)
    && (da.patterns = []
        || (db.patterns <> []
            && List.for_all
                 (fun pb -> List.exists (fun pa -> pat_covers pa pb) da.patterns)
                 db.patterns))
  | _ -> a = b

let scope_covers (a : scope) (b : scope) : bool =
  Cap_lattice.cap_subsumes a.kind b.kind
  &&
  match a.arg, b.arg with
  | None, _ -> true
  | Some _, None -> false
  | Some sa, Some sb ->
    sa = sb
    ||
    if Cap_scope.is_host_scopable b.kind then host_covers sa sb
    else if Cap_scope.is_name_scopable b.kind then (
      match Name_scope.parse sa, Name_scope.parse sb with
      | Ok na, Ok nb -> Name_scope.subsumes (Some na) (Some nb)
      | _ -> false)
    else if Cap_scope.is_scopable b.kind then
      (* Both absolute or both relative: a relative scope is resolved against
         the working directory at run time, which is not known here. *)
      Cap_scope.is_absolute sa = Cap_scope.is_absolute sb
      && Cap_scope.scope_subsumes (Some sa) (Some sb)
    else false

let normalise (l : scope list) : scope list =
  let l = List.sort_uniq compare l in
  List.filter (fun x -> not (List.exists (fun y -> y <> x && scope_covers y x) l)) l

let of_scopes l = Set (normalise l)

let of_entries (es : Scope_expr.entry list) : t =
  of_scopes
    (List.map
       (fun ((path : A.name list), arg) ->
          { kind = String.concat "." (List.map (fun (n : A.name) -> n.A.txt) path); arg })
       es)

let equal a b = a = b

let union a b =
  match a, b with
  | Unknown, _ | _, Unknown -> Unknown
  | Set x, Set y -> if y = [] then a else if x = [] then b else Set (normalise (x @ y))

let covers ~sup s =
  match sup, s with
  | Unknown, _ -> true
  | Set _, Unknown -> false
  | Set big, Set small -> List.for_all (fun x -> List.exists (fun y -> scope_covers y x) big) small

let related (a : scope) (b : scope) =
  Cap_lattice.cap_subsumes a.kind b.kind || Cap_lattice.cap_subsumes b.kind a.kind

let narrow e ~by =
  match e, by with
  | Unknown, _ -> Unknown
  | _, Unknown -> e
  | Set xs, Set bs ->
    Set
      (normalise
         (List.concat_map
            (fun x ->
               if List.exists (fun b -> scope_covers b x) bs then [ x ]
               else
                 let rel = List.filter (related x) bs in
                 if rel = [] then []
                 else if x.arg = None then
                   List.map
                     (fun b ->
                        if Cap_lattice.cap_subsumes x.kind b.kind then b
                        else { kind = x.kind; arg = b.arg })
                     rel
                 else [ x ])
            xs))

let scope_to_string (s : scope) : string =
  let path =
    List.map
      (fun txt -> { A.txt; span = A.dummy_span })
      (String.split_on_char '.' s.kind)
  in
  March_ast.Cap_request.scoped_text (path, s.arg)

let to_string = function
  | Unknown -> "?"
  | Set l -> String.concat ", " (List.map scope_to_string l)
