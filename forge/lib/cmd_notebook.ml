(** forge notebook — thin OCaml shim that runs the March notebook runner.

    The real implementation lives in forge/tasks/notebook.march.
    This shim embeds that source as a string, writes it to a temp file,
    and invokes the March interpreter with appropriate env vars. *)

(* The notebook.march source is embedded at build time by the dune rule below.
   At runtime this gives us [Notebook_march_src.content : string]. *)

(* ------------------------------------------------------------------ *)
(* Stdlib / march binary discovery                                     *)
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

let find_march () =
  let exe_dir = Filename.dirname Sys.executable_name in
  let sibling = Filename.concat exe_dir "march" in
  if Sys.file_exists sibling then sibling
  else "march"

(* ------------------------------------------------------------------ *)
(* Write embedded March source to a temp file                          *)
(* ------------------------------------------------------------------ *)

let write_temp_march () =
  let tmp = Filename.temp_file "forge_notebook_" ".march" in
  let oc = open_out tmp in
  output_string oc Notebook_march_src.content;
  close_out oc;
  tmp

(* ------------------------------------------------------------------ *)
(* Command                                                             *)
(* ------------------------------------------------------------------ *)

let run ~input ~output () =
  let input_path =
    if Filename.is_relative input then Filename.concat (Sys.getcwd ()) input
    else input
  in
  if not (Sys.file_exists input_path) then
    Error (Printf.sprintf "notebook file not found: %s" input_path)
  else begin
    let march = find_march () in
    let tmp   = write_temp_march () in
    let output_path = match output with
      | Some p -> p
      | None   ->
        let base = Filename.remove_extension input_path in
        base ^ ".html"
    in
    let stdlib_opt = find_stdlib_dir () in
    let lib_path_env = match stdlib_opt with
      | None   -> ""
      | Some d -> Printf.sprintf "MARCH_LIB_PATH=%s " (Filename.quote d)
    in
    let nb_env =
      Printf.sprintf "FORGE_NB_INPUT=%s FORGE_NB_OUTPUT=%s FORGE_NB_MARCH=%s"
        (Filename.quote input_path)
        (Filename.quote output_path)
        (Filename.quote march)
    in
    let cmd = Printf.sprintf "%s%s %s %s"
      lib_path_env nb_env (Filename.quote march) (Filename.quote tmp)
    in
    let rc = Sys.command cmd in
    (try Sys.remove tmp with Sys_error _ -> ());
    if rc = 0 then Ok ()
    else Error (Printf.sprintf "forge notebook exited with code %d" rc)
  end
