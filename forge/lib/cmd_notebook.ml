(** forge notebook — thin OCaml shim that delegates to the Scroll tool.

    Two subcommands:
      forge notebook [FILE.scrollmd] [-o FILE.html]   -- batch render to HTML
      forge notebook serve [FILE.scrollmd] [--port N] -- live server with WebSocket UI

    FILE.scrollmd is optional for `serve`: if omitted, a new temp notebook is created.
    If FILE.scrollmd is given but does not exist, it is created with a starter template.

    The batch renderer lives in forge/tasks/notebook.march, embedded at build time.
    The live server is the Scroll tool (https://github.com/march-lang/scroll).
    Install it with: forge install scroll  *)

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
(* Find the scroll archive task (installed via `forge install scroll`) *)
(* ------------------------------------------------------------------ *)

(** Return (task_file, lib_paths) for the scroll.serve archive task, or None. *)
let find_scroll_task () =
  Archive_store.find_task "scroll.serve"

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
(* Batch render: forge notebook FILE.scrollmd [-o FILE.html]                *)
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
(* Starter template for new notebooks                                  *)
(* ------------------------------------------------------------------ *)

let starter_template name =
  let title = if name = "" then "Untitled Notebook" else name in
  Printf.sprintf {|# %s

```march
println("Hello, March!")
```
|} title

(* ------------------------------------------------------------------ *)
(* Open browser at a URL (best-effort, non-blocking)                   *)
(* ------------------------------------------------------------------ *)

let open_browser url =
  let cmd = match Sys.os_type with
    | "Win32" -> Printf.sprintf "start %s" url
    | _ ->
      (* macOS: open; Linux: xdg-open *)
      Printf.sprintf "(open %s 2>/dev/null || xdg-open %s 2>/dev/null) &" url url
  in
  ignore (Sys.command cmd)

(* ------------------------------------------------------------------ *)
(* Live server: forge notebook serve [FILE.scrollmd] [--port N]             *)
(* ------------------------------------------------------------------ *)

let run_serve ~input ~port ~no_open () =
  match find_scroll_task () with
  | None ->
    Error
      "scroll is not installed.\n\
       Install it with: forge install scroll@/path/to/scroll\n\
       or: forge install scroll@https://github.com/march-lang/scroll"
  | Some (task_file, lib_paths) ->
  (* Resolve the notebook path, creating the file if needed *)
  let (input_path, is_temp) = match input with
    | None ->
      (* No file given: create a temp notebook *)
      let tmp = Filename.temp_file "notebook_" ".scrollmd" in
      let oc = open_out tmp in
      output_string oc (starter_template "");
      close_out oc;
      (tmp, true)
    | Some p ->
      let abs = if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p in
      if not (Sys.file_exists abs) then begin
        (* Create with starter template using the base name as title *)
        let name = Filename.remove_extension (Filename.basename abs) in
        let oc = open_out abs in
        output_string oc (starter_template name);
        close_out oc;
        Printf.printf "created: %s\n%!" abs
      end;
      (abs, false)
  in
  let march = find_march () in
  let display_title = if is_temp then "Untitled Notebook" else Filename.basename input_path in
  let lib_path_env = match lib_paths with
    | [] -> ""
    | ps -> Printf.sprintf "MARCH_LIB_PATH=%s " (Filename.quote (String.concat ":" ps))
  in
  let nb_env =
    Printf.sprintf "FORGE_NB_INPUT=%s FORGE_NB_PORT=%d FORGE_NB_MARCH=%s FORGE_NB_TITLE=%s"
      (Filename.quote input_path)
      port
      (Filename.quote march)
      (Filename.quote display_title)
  in
  let cmd = Printf.sprintf "%s%s %s %s"
    lib_path_env nb_env (Filename.quote march) (Filename.quote task_file)
  in
  let url = Printf.sprintf "http://localhost:%d" port in
  if is_temp then begin
    Printf.printf "notebook:  Untitled (temp: %s)\n%!" input_path;
    Printf.printf "tip:       use Save in the browser to download, or Save As to write a .scrollmd file\n%!"
  end else
    Printf.printf "notebook:  %s\n%!" input_path;
  Printf.printf "open:      %s\n%!" url;
  if not no_open then begin
    (* Small delay so the server starts before the browser hits it *)
    Unix.sleepf 0.5;
    open_browser url
  end;
  let rc = Sys.command cmd in
  (* Do NOT delete the temp notebook — user may have saved work into it *)
  if rc = 0 then Ok ()
  else Error (Printf.sprintf "forge notebook serve exited with code %d" rc)
