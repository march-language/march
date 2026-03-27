(** Public API surface extraction and semver change classification.

    Parses .march source files to extract the public API surface:
      - Public function signatures: `pub fn name(params...) -> RetType`
      - Public type declarations: `pub type Name = ...`

    This is intentionally text-based (regex-free, simple heuristic parsing)
    rather than full AST-based, since forge does not link the march compiler.
    Full type-system-aware diffing (linearity annotation changes, generic
    constraint changes) requires compiler integration and is Phase 6 work.

    Change classification follows the plan's rules:
      MAJOR: remove a public fn or type, change a fn signature
      MINOR: add a new public fn or type
      PATCH: no API change

    Pre-1.0.0 packages skip enforcement entirely.
*)

(* ------------------------------------------------------------------ *)
(*  Surface representation                                             *)
(* ------------------------------------------------------------------ *)

(** A public function signature as extracted from source. *)
type fn_sig = {
  name       : string;
  params_raw : string;   (** raw parameter list as written (unparsed) *)
  return_raw : string;   (** raw return type annotation (empty if absent) *)
}

(** A public type declaration. *)
type type_decl = {
  type_name : string;
  body_raw  : string;   (** raw RHS of the type declaration (one line) *)
}

(** The public API surface of a package. *)
type surface = {
  fns   : fn_sig list;
  types : type_decl list;
}

let empty_surface = { fns = []; types = [] }

(* ------------------------------------------------------------------ *)
(*  Simple source parser                                               *)
(* ------------------------------------------------------------------ *)

let trim = String.trim

(** Check if a string starts with [prefix]. *)
let starts_with_prefix prefix s =
  let pl = String.length prefix and sl = String.length s in
  sl >= pl && String.sub s 0 pl = prefix

(** Extract everything after [prefix] from [s].  Assumes [starts_with_prefix]. *)
let after_prefix prefix s =
  trim (String.sub s (String.length prefix) (String.length s - String.length prefix))

(** Parse a `pub fn name(params) -> RetType` declaration from a line.
    Returns None if the line doesn't match the expected pattern.
    Handles:
      pub fn foo(x: Int, y: String) -> Bool
      pub fn bar()
      pub fn baz(x: Linear T) -> Unit
*)
let parse_fn_sig line =
  let s = trim line in
  if not (starts_with_prefix "pub fn " s) then None
  else begin
    let rest = after_prefix "pub fn " s in
    (* Find the function name: everything up to '(' *)
    match String.index_opt rest '(' with
    | None ->
      (* No parens: treat the whole thing as name with no params *)
      let name = trim rest in
      Some { name; params_raw = ""; return_raw = "" }
    | Some paren_pos ->
      let name = trim (String.sub rest 0 paren_pos) in
      (* Find matching closing paren *)
      let after_open = String.sub rest (paren_pos + 1)
          (String.length rest - paren_pos - 1) in
      (match String.index_opt after_open ')' with
       | None ->
         Some { name; params_raw = trim after_open; return_raw = "" }
       | Some close_pos ->
         let params_raw = trim (String.sub after_open 0 close_pos) in
         let after_close = trim (String.sub after_open (close_pos + 1)
             (String.length after_open - close_pos - 1)) in
         (* After ')' may be "-> RetType" or "do" or empty *)
         let return_raw =
           if starts_with_prefix "->" after_close then
             (* Extract up to " do" or end of line *)
             let rt = after_prefix "->" after_close in
             (match String.index_opt rt 'd' with
              | Some di when di > 0 &&
                             String.length rt > di + 1 &&
                             String.sub rt (di - 1) 3 = " do" ->
                trim (String.sub rt 0 (di - 1))
              | _ -> trim rt)
           else ""
         in
         Some { name; params_raw; return_raw })
  end

(** Parse a `pub type Name = ...` declaration from a line. *)
let parse_type_decl line =
  let s = trim line in
  if not (starts_with_prefix "pub type " s) then None
  else begin
    let rest = after_prefix "pub type " s in
    match String.index_opt rest '=' with
    | None ->
      (* Type with no body on this line (e.g. pub type Foo) *)
      Some { type_name = trim rest; body_raw = "" }
    | Some eq_pos ->
      let type_name = trim (String.sub rest 0 eq_pos) in
      let body_raw  = trim (String.sub rest (eq_pos + 1)
          (String.length rest - eq_pos - 1)) in
      Some { type_name; body_raw }
  end

(** Extract the public API surface from the contents of one .march file. *)
let extract_from_string content =
  let lines = String.split_on_char '\n' content in
  let fns   = ref [] in
  let types = ref [] in
  List.iter (fun line ->
      let s = trim line in
      (match parse_fn_sig s with
       | Some sig_ -> fns := sig_ :: !fns
       | None -> ());
      (match parse_type_decl s with
       | Some td -> types := td :: !types
       | None -> ())
    ) lines;
  { fns   = List.rev !fns;
    types = List.rev !types }

(** Recursively collect all .march files under a directory. *)
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

(** Extract the combined API surface of a package source tree. *)
let extract_from_directory root_dir =
  let files = march_files_under root_dir in
  List.fold_left (fun surf path ->
      let content =
        try
          let ic = open_in path in
          let n = in_channel_length ic in
          let buf = Bytes.create n in
          really_input ic buf 0 n;
          close_in ic;
          Bytes.to_string buf
        with Sys_error _ -> ""
      in
      let file_surf = extract_from_string content in
      { fns   = surf.fns   @ file_surf.fns;
        types = surf.types @ file_surf.types }
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
      (if old_f.return_raw = "" then "" else " -> " ^ old_f.return_raw)
      new_f.name new_f.params_raw
      (if new_f.return_raw = "" then "" else " -> " ^ new_f.return_raw)
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
