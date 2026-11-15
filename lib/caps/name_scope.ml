(* Name scopes on IO.Mut and IO.Registry.  See name_scope.mli. *)

type t = { names : string list; prefixes : string list }

let starts_with ~prefix s =
  let lp = String.length prefix in
  String.length s >= lp && String.sub s 0 lp = prefix

(* `;` separates the encoding's parts and `=` its option values; `,` would be
   read as a list separator by the shared option shape (`methods=get,head`).
   A name holding one of them could be confused with the encoding. *)
let bad_char s = List.find_opt (fun c -> String.contains s c) [ ';'; '='; ',' ]

let check_text what s =
  if s = "" then Error (Printf.sprintf "%s cannot be empty" what)
  else
    match bad_char s with
    | Some c -> Error (Printf.sprintf "%s `%s` contains `%c`" what s c)
    | None -> Ok s

(* Decoded directly rather than through Host_scope.split_options, whose word
   check refuses option values holding digits or dots (a name or prefix
   holds either). *)
let parse (enc : string) : (t, string) result =
  match String.split_on_char ';' enc with
  | [] -> Error "a name scope cannot be empty"
  | first :: opts ->
    let ( let* ) = Result.bind in
    let* names =
      if first = "" && opts <> [] then Ok []
      else Result.map (fun n -> [ n ]) (check_text "a name" first)
    in
    let rec go acc = function
      | [] -> Ok acc
      | o :: rest -> (
        match String.index_opt o '=' with
        | Some i -> (
          let k = String.sub o 0 i
          and v = String.sub o (i + 1) (String.length o - i - 1) in
          match k with
          | "name" ->
            let* n = check_text "a name" v in
            go { acc with names = acc.names @ [ n ] } rest
          | "prefix" ->
            let* p = check_text "a prefix" v in
            go { acc with prefixes = acc.prefixes @ [ p ] } rest
          | _ ->
            Error
              (Printf.sprintf
                 "`%s(...)` is not an option a name scope takes; it takes \
                  names and `prefix(\"...\")`"
                 k))
        | None ->
          Error
            (Printf.sprintf
               "`%s` is not an option a name scope takes; it takes names and \
                `prefix(\"...\")`"
               o))
    in
    go { names; prefixes = [] } opts

let admits (s : t) (n : string) : bool =
  List.mem n s.names || List.exists (fun prefix -> starts_with ~prefix n) s.prefixes

let subsumes (a : t option) (b : t option) : bool =
  match (a, b) with
  | None, _ -> true
  | Some _, None -> false
  | Some sa, Some sb ->
    List.for_all (admits sa) sb.names
    && List.for_all
         (fun pb -> List.exists (fun pa -> starts_with ~prefix:pa pb) sa.prefixes)
         sb.prefixes

let quote (s : string) : string =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\t' -> Buffer.add_string b "\\t"
      | '\r' -> Buffer.add_string b "\\r"
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let to_surface (cap : string) (s : t) : string =
  Printf.sprintf "%s(%s)" cap
    (String.concat ", "
       (List.map quote s.names
        @ List.map (fun p -> Printf.sprintf "prefix(%s)" (quote p)) s.prefixes))
