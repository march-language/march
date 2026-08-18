(** Public API surface extraction and semver change classification.

    Parses each .march source file with the real March parser
    ([March_parser.Parser.module_]) and walks the resulting AST to extract a
    package's public API surface:
      - Public function signatures: `fn name(params...) : RetType`
      - Public type declarations: `type Name = ...` /
        `always_linear type Name = ...`

    Visibility in March is `fn` (public) / `pfn` (private) — `type` is public
    by default. There is no `pub` keyword. An earlier version of this module
    scanned source text line-by-line for an invented `pub fn ... -> T`
    dialect that March does not have, which made [extract_from_directory]
    return an empty surface for every real package (silently — no parse
    error, just nothing found). See
    specs/progress/2026-08-03-forge-api-surface-parser-wrong-syntax.md.

    Reading the surface off the AST (rather than off source text) also means
    multi-head clauses, default arguments, and signatures wrapped across
    lines are captured for free — a line scanner cannot see any of those.

    Change classification follows the plan's rules:
      MAJOR: remove a public fn or type, change a fn signature
      MINOR: add a new public fn or type
      PATCH: no API change

    Pre-1.0.0 packages skip enforcement entirely.
*)

module Ast = March_ast.Ast
module Fmt = March_format.Format

(* ------------------------------------------------------------------ *)
(*  Surface representation                                             *)
(* ------------------------------------------------------------------ *)

(** A public function signature as read off the AST. *)
type fn_sig = {
  name       : string;
  params_raw : string;   (** rendered parameter list, e.g. "x : Int, y : Int".
                              A multi-head function's clauses are joined with
                              " | ", each parenthesized, so a change to any
                              head shows up in the diff. *)
  return_raw : string;   (** rendered return type annotation (empty if absent) *)
}

(** A public type declaration. *)
type type_decl = {
  type_name : string;
  body_raw  : string;   (** rendered RHS of the type declaration *)
}

(** The public API surface of a package. *)
type surface = {
  fns   : fn_sig list;
  types : type_decl list;
}

let empty_surface = { fns = []; types = [] }

(* ------------------------------------------------------------------ *)
(*  Rendering (surface-syntax text, for diffing/display purposes only) *)
(* ------------------------------------------------------------------ *)

let render_clause_params (clause : Ast.fn_clause) =
  String.concat ", " (List.map Fmt.fmt_fn_param clause.Ast.fc_params)

(** Render a function's full parameter surface across all of its clauses. *)
let render_fn_params (fn : Ast.fn_def) =
  match fn.Ast.fn_clauses with
  | [clause] -> render_clause_params clause
  | clauses  ->
    String.concat " | "
      (List.map (fun c -> "(" ^ render_clause_params c ^ ")") clauses)

let render_return (fn : Ast.fn_def) =
  match fn.Ast.fn_ret_ty with
  | None    -> ""
  | Some ty -> Fmt.fmt_ty ty

let render_type_def (tdef : Ast.type_def) =
  match tdef with
  | Ast.TDAlias ty -> Fmt.fmt_ty ty
  | Ast.TDVariant variants ->
    let var_str (v : Ast.variant) =
      match v.Ast.var_args with
      | []  -> v.Ast.var_name.Ast.txt
      | tys -> Printf.sprintf "%s(%s)" v.Ast.var_name.Ast.txt (Fmt.fmt_tys tys)
    in
    String.concat " | " (List.map var_str variants)
  | Ast.TDRecord fields ->
    let fld_str (f : Ast.field) =
      Printf.sprintf "%s%s : %s"
        (Fmt.fmt_lin f.Ast.fld_lin) f.Ast.fld_name.Ast.txt (Fmt.fmt_ty f.Ast.fld_ty)
    in
    "{ " ^ String.concat ", " (List.map fld_str fields) ^ " }"

(* ------------------------------------------------------------------ *)
(*  Parsing                                                             *)
(* ------------------------------------------------------------------ *)

(** Parse a .march file with the real parser, the same way
    [Cmd_cap.parse_file] does for `forge cap`. *)
let parse_file path : (Ast.decl list, string) result =
  try
    let ic  = open_in path in
    let src = really_input_string ic (in_channel_length ic) in
    close_in ic;
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    let m = March_parser.Parser.module_
        (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    Ok m.Ast.mod_decls
  with
  | Sys_error msg -> Error msg
  | exn -> Error (Printexc.to_string exn)

(** Parse a string of March source (a whole module body) and return its
    declarations. Used by [extract_from_string] and by tests. *)
let parse_string ?(fname = "<string>") src : (Ast.decl list, string) result =
  try
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = fname };
    let m = March_parser.Parser.module_
        (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    Ok m.Ast.mod_decls
  with exn -> Error (Printexc.to_string exn)

(* ------------------------------------------------------------------ *)
(*  Extraction                                                         *)
(* ------------------------------------------------------------------ *)

(** Walk [decls], accumulating every public `fn`/`type`/`always_linear type`,
    descending into nested `mod ... end` blocks. Private (`pfn`) declarations
    and anything inside `describe`/`test` blocks are not part of the public
    surface and are skipped. *)
let rec extract_decls decls surf =
  List.fold_left extract_one surf decls

and extract_one surf (d : Ast.decl) =
  match d with
  | Ast.DFn (fn, _) ->
    (match fn.Ast.fn_vis with
     | Ast.Private -> surf
     | Ast.Public ->
       let s = { name       = fn.Ast.fn_name.Ast.txt;
                 params_raw = render_fn_params fn;
                 return_raw = render_return fn } in
       { surf with fns = surf.fns @ [s] })
  | Ast.DType (Ast.Private, _, _, _, _) -> surf
  | Ast.DType (Ast.Public, name, _params, tdef, _) ->
    let t = { type_name = name.Ast.txt; body_raw = render_type_def tdef } in
    { surf with types = surf.types @ [t] }
  | Ast.DAlwaysLinearType (Ast.Private, _, _, _, _) -> surf
  | Ast.DAlwaysLinearType (Ast.Public, name, _params, tdef, _) ->
    let t = { type_name = name.Ast.txt; body_raw = render_type_def tdef } in
    { surf with types = surf.types @ [t] }
  | Ast.DMod (_, _, inner, _) ->
    extract_decls inner surf
  | _ -> surf

(** Extract the public API surface from a string of March source
    (a single module body — no `mod ... do ... end` wrapper needed, since
    [March_parser.Parser.module_] accepts a bare sequence of declarations). *)
let extract_from_string src =
  match parse_string src with
  | Error _   -> empty_surface
  | Ok decls  -> extract_decls decls empty_surface

(** Recursively collect all .march files under a directory, in sorted order
    for deterministic output. *)
let march_files_under root =
  let files = ref [] in
  let rec walk dir =
    (try
       let entries = Sys.readdir dir in
       Array.iter (fun name ->
           let path = Filename.concat dir name in
           if Sys.is_directory path then walk path
           else if Filename.check_suffix name ".march" then
             files := path :: !files
         ) entries
     with Sys_error _ -> ())
  in
  walk root;
  List.sort String.compare !files

(** Extract the combined API surface of a package source tree. A file that
    fails to parse is skipped (with a warning on stderr) rather than aborting
    the whole extraction — but note this is where the fix's own failure mode
    lives: skip silently and the surface goes quiet again. See the
    non-emptiness regression test in test_api_surface.ml. *)
let extract_from_directory root_dir =
  let files = march_files_under root_dir in
  List.fold_left (fun surf path ->
      match parse_file path with
      | Error msg ->
        Printf.eprintf "forge: api-surface: %s: %s\n%!" path msg;
        surf
      | Ok decls -> extract_decls decls surf
    ) empty_surface files

(* ------------------------------------------------------------------ *)
(*  Change classification                                              *)
(* ------------------------------------------------------------------ *)

type change_kind =
  | Major  (** breaking: removed or changed signature *)
  | Minor  (** additive: new public item *)
  | Patch  (** no API change *)

type change =
  | RemovedFn    of fn_sig             (* Major *)
  | ChangedFn    of fn_sig * fn_sig    (* Major: old, new *)
  | AddedFn      of fn_sig             (* Minor *)
  | RemovedType  of type_decl          (* Major *)
  | ChangedType  of type_decl * type_decl  (* Major: old, new *)
  | AddedType    of type_decl          (* Minor *)

let change_kind_of = function
  | RemovedFn _    -> Major
  | ChangedFn _    -> Major
  | RemovedType _  -> Major
  | ChangedType _  -> Major
  | AddedFn _      -> Minor
  | AddedType _    -> Minor

(** Compute the required semver bump from a list of changes. *)
let required_bump changes =
  if List.exists (fun c -> change_kind_of c = Major) changes then Major
  else if List.exists (fun c -> change_kind_of c = Minor) changes then Minor
  else Patch

(** Diff two API surfaces and return the list of changes. *)
let diff ~old_ ~new_ =
  let changes = ref [] in
  (* Check for removed or changed functions *)
  List.iter (fun old_fn ->
      match List.find_opt (fun f -> f.name = old_fn.name) new_.fns with
      | None ->
        changes := RemovedFn old_fn :: !changes
      | Some new_fn ->
        if old_fn.params_raw <> new_fn.params_raw ||
           old_fn.return_raw <> new_fn.return_raw then
          changes := ChangedFn (old_fn, new_fn) :: !changes
    ) old_.fns;
  (* Check for added functions *)
  List.iter (fun new_fn ->
      if not (List.exists (fun f -> f.name = new_fn.name) old_.fns) then
        changes := AddedFn new_fn :: !changes
    ) new_.fns;
  (* Check for removed or changed types *)
  List.iter (fun old_ty ->
      match List.find_opt (fun t -> t.type_name = old_ty.type_name) new_.types with
      | None ->
        changes := RemovedType old_ty :: !changes
      | Some new_ty ->
        if old_ty.body_raw <> new_ty.body_raw then
          changes := ChangedType (old_ty, new_ty) :: !changes
    ) old_.types;
  (* Check for added types *)
  List.iter (fun new_ty ->
      if not (List.exists (fun t -> t.type_name = new_ty.type_name) old_.types) then
        changes := AddedType new_ty :: !changes
    ) new_.types;
  List.rev !changes

(* ------------------------------------------------------------------ *)
(*  Semver enforcement (for forge publish)                            *)
(* ------------------------------------------------------------------ *)

(** Result of checking whether the declared semver bump is sufficient. *)
type semver_check =
  | Ok                   (** declared bump is correct or conservative *)
  | UnderBumped of {
      required    : change_kind;
      declared    : change_kind;
      breaking    : change list;
    }

(** Check whether [declared_bump] is sufficient for [changes].
    Returns Ok if the declared bump ≥ required bump, UnderBumped otherwise.
    Always returns Ok for pre-1.0.0 packages. *)
let check_semver_bump ~old_version ~new_version ~changes =
  let open Resolver_version in
  let old_v = match parse old_version with Ok v -> v | Error _ -> zero in
  (* Pre-1.0.0: skip enforcement *)
  if old_v.major = 0 then Ok
  else begin
    let new_v = match parse new_version with Ok v -> v | Error _ -> zero in
    let declared =
      if new_v.major > old_v.major then Major
      else if new_v.minor > old_v.minor then Minor
      else Patch
    in
    let required = required_bump changes in
    match required, declared with
    | Major, (Minor | Patch) ->
      let breaking = List.filter (fun c -> change_kind_of c = Major) changes in
      UnderBumped { required; declared; breaking }
    | Minor, Patch ->
      let additive = List.filter (fun c -> change_kind_of c = Minor) changes in
      UnderBumped { required; declared; breaking = additive }
    | _ -> Ok
  end

(* ------------------------------------------------------------------ *)
(*  Human-readable output                                             *)
(* ------------------------------------------------------------------ *)

let string_of_change_kind = function
  | Major -> "MAJOR"
  | Minor -> "MINOR"
  | Patch -> "PATCH"

let string_of_change = function
  | RemovedFn f ->
    Printf.sprintf "  • Removed function `%s`" f.name
  | ChangedFn (old_f, new_f) ->
    Printf.sprintf "  • Function `%s` signature changed:\n\
                    \      was: fn %s(%s)%s\n\
                    \      now: fn %s(%s)%s"
      old_f.name
      old_f.name old_f.params_raw
      (if old_f.return_raw = "" then "" else " : " ^ old_f.return_raw)
      new_f.name new_f.params_raw
      (if new_f.return_raw = "" then "" else " : " ^ new_f.return_raw)
  | AddedFn f ->
    Printf.sprintf "  • Added function `%s`" f.name
  | RemovedType t ->
    Printf.sprintf "  • Removed type `%s`" t.type_name
  | ChangedType (old_t, new_t) ->
    Printf.sprintf "  • Type `%s` changed:\n\
                    \      was: %s\n\
                    \      now: %s"
      old_t.type_name old_t.body_raw new_t.body_raw
  | AddedType t ->
    Printf.sprintf "  • Added type `%s`" t.type_name

let format_underBumped name old_ver new_ver required _declared breaking =
  Printf.sprintf
    "-- SEMVER VIOLATION -------------------------------- forge.toml\n\n\
     You are publishing `%s %s` but your changes require a %s version bump.\n\n\
     %s changes detected:\n\n\
     %s\n\n\
     To publish this change, bump the version to `%s` in forge.toml.\n"
    name new_ver
    (string_of_change_kind required)
    (string_of_change_kind required)
    (String.concat "\n" (List.map string_of_change breaking))
    (match required with
     | Major ->
       let v = match Resolver_version.parse old_ver with
         | Ok v  -> Printf.sprintf "%d.0.0" (v.Resolver_version.major + 1)
         | Error _ -> "NEXT_MAJOR.0.0"
       in v
     | Minor ->
       let v = match Resolver_version.parse old_ver with
         | Ok v  ->
           Printf.sprintf "%d.%d.0" v.Resolver_version.major (v.Resolver_version.minor + 1)
         | Error _ -> "MAJOR.NEXT_MINOR.0"
       in v
     | Patch -> new_ver)
