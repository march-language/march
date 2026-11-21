(* Scope expressions (ocap phase 5, decision 3).  See scope_expr.mli. *)

module A = March_ast.Ast

type entry = A.name list * string option

type form =
  | Literal of entry list
  | Computed of { kind : string; strings : A.expr list; options : string list }
  | Not_scope

let is_cap_path (name : string) : bool =
  name = "IO" || String.starts_with ~prefix:"IO." name

(* The options the `needs` grammar writes as a call ([methods(get)],
   [prefix("w.")]) and bare ([no_redirects]).  Anything else in an argument
   position is a string expression. *)
let call_options = [ "methods"; "prefix" ]
let bare_options = [ "no_redirects" ]

(* An argument as an option, encoded as the parser encodes it
   ([scope_option]): [Some (Ok text)] for a literal option, [Some (Error ())]
   for an option-shaped argument that is not literal, [None] for a string
   argument. *)
let option_of (e : A.expr) : (string, unit) result option =
  match e with
  | A.EVar { A.txt; _ } when List.mem txt bare_options -> Some (Ok txt)
  | A.EApp (A.EVar { A.txt = "methods"; _ }, (_ :: _ as args), _) ->
    let names =
      List.map (function A.EVar { A.txt; _ } when txt <> "" && txt.[0] >= 'a' && txt.[0] <= 'z' -> Some txt | _ -> None) args
    in
    if List.for_all Option.is_some names then
      Some (Ok ("methods=" ^ String.concat "," (List.filter_map Fun.id names)))
    else Some (Error ())
  | A.EApp (A.EVar { A.txt; _ }, args, _) when List.mem txt call_options ->
    (match args with
     | [ A.ELit (A.LitString s, _) ] -> Some (Ok (txt ^ "=" ^ s))
     | _ -> Some (Error ()))
  | _ -> None

let path_names (n : A.name) : A.name list =
  List.map (fun txt -> { A.txt; span = n.A.span }) (String.split_on_char '.' n.A.txt)

(* An [ECon] of a capability path: its strings (in order), then its options. *)
let classify_con (n : A.name) (args : A.expr list) : form =
  let rec split strings = function
    | [] -> Some (List.rev strings, [])
    | a :: rest ->
      (match option_of a with
       | None -> split (a :: strings) rest
       | Some _ ->
         (* Options from here on; a string after an option is refused, as
            the parser refuses it in a `needs` line. *)
         let opts = List.map option_of (a :: rest) in
         if List.for_all (function Some (Ok _) -> true | _ -> false) opts then
           Some (List.rev strings,
                 List.filter_map (function Some (Ok o) -> Some o | _ -> None) opts)
         else None)
  in
  match split [] args with
  | None -> Not_scope
  | Some (strings, options) ->
    let lits =
      List.map (function A.ELit (A.LitString s, _) -> Some s | _ -> None) strings
    in
    if List.for_all Option.is_some lits then begin
      let lits = List.filter_map Fun.id lits in
      match lits, options with
      | [], [] -> Literal [ (path_names n, None) ]
      | [], _ -> Literal [ (path_names n, Some (";" ^ String.concat ";" options)) ]
      | "" :: _ :: _, _ | "" :: _, _ :: _ -> Not_scope
      | s :: more, _ ->
        Literal
          [ (path_names n,
             Some (String.concat ";" ((s :: List.map (fun m -> "name=" ^ m) more) @ options))) ]
    end
    else Computed { kind = n.A.txt; strings; options }

let rec classify (e : A.expr) : form =
  match e with
  | A.ETuple ([], _) -> Literal []
  | A.ECon (n, args, _) when is_cap_path n.A.txt -> classify_con n args
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ a; b ], _) ->
    (match classify a, classify b with
     | Literal x, Literal y -> Literal (x @ y)
     | _ -> Not_scope)
  | _ -> Not_scope

let restrict_entries (es : A.expr list) : entry list option =
  let rec go acc = function
    | [] -> Some (List.concat (List.rev acc))
    | e :: rest ->
      (match classify e with
       | Literal xs -> go (xs :: acc) rest
       | Computed _ | Not_scope -> None)
  in
  go [] es

let restrict_text (es : A.expr list) : string option =
  Option.map
    (fun entries ->
       match fst (March_ast.Cap_request.request_of_entries entries) with
       | "" -> "()"
       | t -> t)
    (restrict_entries es)
