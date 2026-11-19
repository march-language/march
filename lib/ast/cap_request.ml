(** `needs` entries written back as source text, and `main`'s launch request
    (ocap phase 4, decision 3).

    The run-time policy ([stdlib/authority.march]) parses the `needs` surface
    grammar, so the request handed to [Authority.launch_init] is source text:
    each entry printed as written.  The formatter prints a module [needs]
    line through [scoped_text] too, so the two cannot drift apart.

    Lives in [march_ast] because the interpreter (which does not link the
    typechecker) computes the request as well; [Typecheck.launch_request]
    re-exports [launch_request]. *)

open Ast

(** [s] as a double-quoted string literal that both the March lexer and
    [Authority.parse] read back as [s]: backslash, quote, and the three
    control escapes both understand. *)
let quote (s : string) : string =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (function
      | '\\' -> Buffer.add_string b {|\\|}
      | '"' -> Buffer.add_string b {|\"|}
      | '\n' -> Buffer.add_string b {|\n|}
      | '\t' -> Buffer.add_string b {|\t|}
      | '\r' -> Buffer.add_string b {|\r|}
      | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"';
  Buffer.contents b

(** The dotted capability path, [IO.FileRead]. *)
let path_text (p : name list) : string =
  String.concat "." (List.map (fun (n : name) -> n.txt) p)

(** One `needs` entry as written: [IO.Console], [IO.FileRead("/srv/")],
    [IO.NetConnect("api.x.com", methods(get), no_redirects)].

    Options ride in the scope string as "<scope>;<option>;..." (parser.mly,
    [scoped_cap_path]); they are split on ';' and printed back in the one
    surface form the parser accepts for each encoding (ocap p2b ruling R16:
    identifiers only in `methods(...)`, no `name(...)` option, no `;` in a
    string, no empty first string before more), so this reproduces exactly
    what was parsed.  [quote] lets the formatter use its own literal
    printer. *)
let scoped_text ?(quote = quote) ((p, scope) : name list * string option) : string =
  let path = path_text p in
  match scope with
  | None -> path
  | Some sc ->
    let show_opt o =
      match String.index_opt o '=' with
      | None -> o
      | Some i ->
        let k = String.sub o 0 i
        and v = String.sub o (i + 1) (String.length o - i - 1) in
        if k = "name" then quote v
        else if k = "methods" then
          Printf.sprintf "%s(%s)" k (String.concat ", " (String.split_on_char ',' v))
        else Printf.sprintf "%s(%s)" k (quote v)
    in
    (* Split on ';' directly: string-valued options (`name=`, `prefix=`) can
       hold characters Host_scope.split_options' word check refuses. *)
    let key_ok o =
      let k = match String.index_opt o '=' with
        | Some i -> String.sub o 0 i | None -> o in
      k <> "" && String.for_all (fun c -> (c >= 'a' && c <= 'z') || c = '_') k
    in
    (match (match String.split_on_char ';' sc with
            | s :: (_ :: _ as opts) when List.for_all key_ok opts -> (s, opts)
            | _ -> (sc, [])) with
     | s, (_ :: _ as opts) ->
       let os = String.concat ", " (List.map show_opt opts) in
       if s = "" then Printf.sprintf "%s(%s)" path os
       else Printf.sprintf "%s(%s, %s)" path (quote s) os
     | _ -> Printf.sprintf "%s(%s)" path (quote sc))

(** The capability paths named by [Cap(P)] in a parameter type, left to
    right (a [Cap] applied to anything but a bare constructor path names
    none).  The same reading as [Cap_surface_ty.caps_in_ty] on a parameter,
    restricted to the shapes `main` may take ([Desugar.check_main_signature]
    requires every `main` parameter to be a `Cap(P)`). *)
let rec cap_params_of_ty (t : ty) : string list =
  match t with
  | TyCon ({ txt = "Cap"; _ }, [ arg ]) -> (
    match arg with
    | TyCon (n, []) -> [ n.txt ]
    | _ -> [])
  | TyCon (_, args) -> List.concat_map cap_params_of_ty args
  | _ -> []

let dedup xs =
  List.rev (List.fold_left (fun acc x -> if List.mem x acc then acc else x :: acc) [] xs)

(** A `needs` list as a request: entries printed as written, joined by
    [", "], and whether any carries a scope. *)
let request_of_entries (entries : (name list * string option) list) : string * bool =
  ( String.concat ", " (dedup (List.map (fun e -> scoped_text e) entries)),
    List.exists (fun (_, sc) -> sc <> None) entries )

let needs_of (decls : decl list) : (name list * string option) list =
  List.concat_map (function DNeeds (caps, _) -> caps | _ -> []) decls

(** The program's entry `main`: a top-level [main] if there is one, else the
    last [main] of a (nested) module, in declaration order.  The AST twin of
    [Tir_names.entry_main_of_names], the rule every backend applies to the
    lowered fns.  Returns its qualified name ([main], [App.main]), its
    definition, and the `needs` line of the module that declares it. *)
let entry_main (m : module_) :
    (string * fn_def * (name list * string option) list) option =
  let top =
    List.find_map
      (function
        | DFn (def, _) when def.fn_name.txt = "main" -> Some ("main", def, needs_of m.mod_decls)
        | _ -> None)
      m.mod_decls
  in
  match top with
  | Some _ -> top
  | None ->
    let rec walk prefix decls acc =
      List.fold_left
        (fun acc d ->
           match d with
           | DMod (n, _, inner, _) ->
             let p = prefix ^ n.txt ^ "." in
             let acc =
               match
                 List.find_map
                   (function
                     | DFn (def, _) when def.fn_name.txt = "main" -> Some def
                     | _ -> None)
                   inner
               with
               | Some def -> Some (p ^ "main", def, needs_of inner)
               | None -> acc
             in
             walk p inner acc
           | _ -> acc)
        acc decls
    in
    walk "" m.mod_decls None

(** The request of an entry [def] declared in a module whose `needs` line
    is [module_needs] (decision 3): its legacy [Cap(P)] parameters, then
    its `needs` clause, in source order, duplicates dropped.  A clause,
    even [needs ()], is the request; only with neither a clause nor a [Cap]
    parameter is it the module's `needs` line. *)
let request_of_main (def : fn_def) (module_needs : (name list * string option) list) :
    string * bool =
  let params =
    match def.fn_clauses with
    | clause :: _ ->
      List.concat_map
        (function
          | FPNamed p | FPDefault (p, _) -> (
            match p.param_ty with Some ty -> cap_params_of_ty ty | None -> [])
          | FPPat _ -> [])
        clause.fc_params
    | [] -> []
  in
  match params, def.fn_needs with
  | [], None -> request_of_entries module_needs
  | _, None -> (String.concat ", " (dedup params), false)
  | _, Some (caps, _) ->
    ( String.concat ", " (dedup (params @ List.map (fun e -> scoped_text e) caps)),
      List.exists (fun (_, sc) -> sc <> None) caps )

(** `main`'s launch request (decision 3) as source text, and whether any
    entry carries a scope: [request_of_main] of the [entry_main].  With no
    `main`, the module's `needs` line.  Not used for a test file (see
    [test_request]). *)
let launch_request (m : module_) : string * bool =
  match entry_main m with
  | Some (_, def, module_needs) -> request_of_main def module_needs
  | None -> request_of_entries (needs_of m.mod_decls)

(** A test file's request: its module's `needs` line (design §21), whatever
    `main` it may also declare. *)
let test_request (m : module_) : string * bool = request_of_entries (needs_of m.mod_decls)
