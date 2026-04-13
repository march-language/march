(** forge notebook — thin OCaml shim that runs the March notebook runner/server.

    Two subcommands:
      forge notebook FILE.mnb [-o FILE.html]   -- batch render to HTML
      forge notebook serve FILE.mnb [--port N] -- live server with WebSocket UI

    The real implementations live in forge/tasks/notebook.march and
    forge/tasks/notebook_server.march, embedded as strings at build time. *)

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

let write_temp content suffix =
  let tmp = Filename.temp_file "forge_notebook_" suffix in
  let oc = open_out tmp in
  output_string oc content;
  close_out oc;
  tmp

(* ------------------------------------------------------------------ *)
(* Build the environment prefix for the march invocation               *)
(* ------------------------------------------------------------------ *)

let lib_path_prefix () =
  match find_stdlib_dir () with
  | None   -> ""
  | Some d -> Printf.sprintf "MARCH_LIB_PATH=%s " (Filename.quote d)

(* ------------------------------------------------------------------ *)
(* Batch render: forge notebook FILE.mnb [-o FILE.html]                *)
(* ------------------------------------------------------------------ *)

let run_render ~input ~output () =
  let input_path =
    if Filename.is_relative input then Filename.concat (Sys.getcwd ()) input
    else input
  in
  if not (Sys.file_exists input_path) then
    Error (Printf.sprintf "notebook file not found: %s" input_path)
  else begin
    let march = find_march () in
    let tmp   = write_temp Notebook_march_src.content ".march" in
    let output_path = match output with
      | Some p -> p
      | None   ->
        let base = Filename.remove_extension input_path in
        base ^ ".html"
    in
    let nb_env =
      Printf.sprintf "FORGE_NB_INPUT=%s FORGE_NB_OUTPUT=%s FORGE_NB_MARCH=%s"
        (Filename.quote input_path)
        (Filename.quote output_path)
        (Filename.quote march)
    in
    let cmd = Printf.sprintf "%s%s %s %s"
      (lib_path_prefix ()) nb_env (Filename.quote march) (Filename.quote tmp)
    in
    let rc = Sys.command cmd in
    (try Sys.remove tmp with Sys_error _ -> ());
    if rc = 0 then Ok ()
    else Error (Printf.sprintf "forge notebook exited with code %d" rc)
  end

(* ------------------------------------------------------------------ *)
(* Live server: forge notebook serve FILE.mnb [--port N]               *)
(* ------------------------------------------------------------------ *)

let run_serve ~input ~port () =
  let input_path =
    if Filename.is_relative input then Filename.concat (Sys.getcwd ()) input
    else input
  in
  if not (Sys.file_exists input_path) then
    Error (Printf.sprintf "notebook file not found: %s" input_path)
  else begin
    let march = find_march () in
    let tmp   = write_temp Notebook_server_march_src.content ".march" in
    let nb_env =
      Printf.sprintf "FORGE_NB_INPUT=%s FORGE_NB_PORT=%d FORGE_NB_MARCH=%s"
        (Filename.quote input_path)
        port
        (Filename.quote march)
    in
    let cmd = Printf.sprintf "%s%s %s %s"
      (lib_path_prefix ()) nb_env (Filename.quote march) (Filename.quote tmp)
    in
    let rc = Sys.command cmd in
    (try Sys.remove tmp with Sys_error _ -> ());
    if rc = 0 then Ok ()
    else Error (Printf.sprintf "forge notebook serve exited with code %d" rc)
  end
