(** forge doc — thin OCaml shim that runs the March doc generator.

    The real implementation lives in forge/tasks/doc.march.
    This shim embeds that source as a string, writes it to a temp file,
    and invokes the March interpreter with appropriate env vars. *)

(* The doc.march source is embedded at build time by the dune rule below.
   At runtime this gives us [Doc_march_src.content : string]. *)

(* ------------------------------------------------------------------ *)
(* Stdlib finder (mirrors search.ml)                                   *)
(* ------------------------------------------------------------------ *)

let find_stdlib_dir () =
  let exe = Sys.executable_name in
  let candidates = [
    "stdlib";
    Filename.concat (Filename.dirname exe) "../stdlib";
    Filename.concat (Filename.dirname exe) "../../stdlib";
    Filename.concat (Filename.dirname exe) "../../../stdlib";
  ] in
  List.find_opt Sys.file_exists candidates

(* ------------------------------------------------------------------ *)
(* Locate the march binary                                             *)
(* ------------------------------------------------------------------ *)

(** Find the march binary: prefer the one next to the forge binary so
    we pick up the development build rather than an installed copy. *)
let find_march () =
  (* Prefer sibling binary from same dune _build output *)
  let exe_dir = Filename.dirname Sys.executable_name in
  let sibling = Filename.concat exe_dir "march" in
  if Sys.file_exists sibling then sibling
  else "march"   (* fall back to PATH *)

(* ------------------------------------------------------------------ *)
(* Write the embedded March source to a temp file                      *)
(* ------------------------------------------------------------------ *)

let write_temp_march () =
  let tmp = Filename.temp_file "forge_doc_" ".march" in
  let oc = open_out tmp in
  output_string oc Doc_march_src.content;
  close_out oc;
  tmp

(* ------------------------------------------------------------------ *)
(* Project source dirs                                                 *)
(* ------------------------------------------------------------------ *)

let project_src_dirs () =
  match Project.load () with
  | Error _ -> []
  | Ok p ->
    let root = p.Project.root in
    List.filter Sys.file_exists
      [ Filename.concat root "src";
        Filename.concat root "lib" ]

(* ------------------------------------------------------------------ *)
(* Command                                                             *)
(* ------------------------------------------------------------------ *)

let run ?(output_dir = "doc") ?(include_private = false) ?(stdlib_only = false) () =
  let march = find_march () in
  let tmp   = write_temp_march () in
  let stdlib_env = match find_stdlib_dir () with
    | None    -> []
    | Some d  -> [ Printf.sprintf "FORGE_DOC_STDLIB=%s" d ]
  in
  let src_env =
    if stdlib_only then []
    else
      let dirs = project_src_dirs () in
      if dirs = [] then []
      else [ Printf.sprintf "FORGE_DOC_SRC=%s" (String.concat ":" dirs) ]
  in
  let private_env =
    if include_private then [ "FORGE_DOC_PRIVATE=true" ] else []
  in
  let output_env = [ Printf.sprintf "FORGE_DOC_OUTPUT=%s" output_dir ] in
  (* Build env prefix: KEY=val KEY=val march tmp.march *)
  let env_prefix =
    String.concat " "
      (List.map (fun kv -> Printf.sprintf "%s" (Filename.quote kv))
         (stdlib_env @ src_env @ private_env @ output_env))
  in
  let lib_path_env = match find_stdlib_dir () with
    | None   -> ""
    | Some d -> Printf.sprintf "MARCH_LIB_PATH=%s " (Filename.quote d)
  in
  let cmd = Printf.sprintf "env %s %s%s %s"
    env_prefix lib_path_env (Filename.quote march) (Filename.quote tmp)
  in
  let rc = Sys.command cmd in
  (try Sys.remove tmp with Sys_error _ -> ());
  if rc = 0 then Ok ()
  else Error (Printf.sprintf "forge doc exited with code %d" rc)
