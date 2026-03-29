(** cmd_bastion_server.ml — forge bastion server

    Starts the Bastion dev server with file-watching and auto-restart.

    Behaviour:
    - Forks a child that runs [march <entry>] with MARCH_ENV=dev.
    - Parent polls [lib/] and [config/] every second for mtime changes.
    - On any change: prints which file changed, SIGTERMs child, waits, forks
      a new child.  BastionDev's SSE live-reload endpoint reconnects and
      triggers a browser reload automatically.
    - On SIGINT/SIGTERM: kills child, exits cleanly. *)

(* ------------------------------------------------------------------ mtime scan *)

(** Collect all .march file mtimes under [dir] into [tbl]. *)
let collect_mtimes dir tbl =
  let rec walk d =
    if not (Sys.file_exists d) then ()
    else if not (Sys.is_directory d) then ()
    else
      Array.iter (fun name ->
          let path = Filename.concat d name in
          if Sys.is_directory path then walk path
          else if Filename.check_suffix name ".march" then begin
            (try
               let st = Unix.stat path in
               Hashtbl.replace tbl path st.Unix.st_mtime
             with Unix.Unix_error _ -> ())
          end
        ) (Sys.readdir d)
  in
  walk dir

(** Snapshot mtimes for lib/ and config/ *)
let snapshot lib_dir config_dir =
  let tbl = Hashtbl.create 64 in
  collect_mtimes lib_dir tbl;
  collect_mtimes config_dir tbl;
  tbl

(** Return [Some path] for the first changed/new file, [None] if nothing changed. *)
let first_change prev curr =
  let found = ref None in
  Hashtbl.iter (fun path mtime ->
      if !found = None then
        match Hashtbl.find_opt prev path with
        | None           -> found := Some path   (* new file *)
        | Some old_mtime -> if mtime <> old_mtime then found := Some path
    ) curr;
  !found

(* ------------------------------------------------------------------ process *)

(** Merge new key=value pairs into the inherited environment, overriding
    existing keys. *)
let build_env overrides =
  let tbl = Hashtbl.create 64 in
  Array.iter (fun pair ->
      let key = match String.index_opt pair '=' with
        | Some i -> String.sub pair 0 i
        | None   -> pair
      in
      Hashtbl.replace tbl key pair
    ) (Unix.environment ());
  List.iter (fun (k, v) -> Hashtbl.replace tbl k (k ^ "=" ^ v)) overrides;
  Array.of_seq (Seq.map snd (Hashtbl.to_seq tbl))

(** Locate the [march] binary by scanning PATH entries. *)
let find_march_exe () =
  let path_dirs =
    match Sys.getenv_opt "PATH" with
    | None   -> ["/usr/local/bin"; "/usr/bin"; "/bin"]
    | Some p -> String.split_on_char ':' p
  in
  match List.find_opt (fun d ->
      Sys.file_exists (Filename.concat d "march")
    ) path_dirs with
  | Some d -> Filename.concat d "march"
  | None   -> "march"   (* will fail at execve, but let the OS report it *)

(** Fork a child that execs [march <entry>] with the given env.
    Returns the child PID (parent only). *)
let start_child march_exe entry env_arr =
  let pid = Unix.fork () in
  if pid = 0 then begin
    (try Unix.execve march_exe [| march_exe; entry |] env_arr
     with e ->
       Printf.eprintf "forge: failed to exec march: %s\n%!"
         (Printexc.to_string e);
       exit 1)
  end else
    pid

(* ---------------------------------------------------------- esbuild watcher *)

(** Locate esbuild in PATH (returns None if not found). *)
let find_esbuild_opt () =
  let path_dirs =
    match Sys.getenv_opt "PATH" with
    | None   -> ["/usr/local/bin"; "/usr/bin"; "/bin"]
    | Some p -> String.split_on_char ':' p
  in
  List.find_opt (fun d ->
      Sys.file_exists (Filename.concat d "esbuild")
    ) path_dirs
  |> Option.map (fun d -> Filename.concat d "esbuild")

(** Fork a child that runs esbuild --watch.  Returns the child PID or -1 on
    any error.  Silently skips if esbuild is not installed or assets don't
    exist — the server still works, assets just aren't rebuilt automatically. *)
let maybe_start_esbuild root =
  let js_entry  = Filename.concat root "assets/js/app.js" in
  let css_entry = Filename.concat root "assets/css/app.css" in
  let out_dir   = Filename.concat root "priv/static/assets" in
  let has_assets = Sys.file_exists js_entry || Sys.file_exists css_entry in
  if not has_assets then -1
  else
    match find_esbuild_opt () with
    | None ->
      Printf.printf "    Assets:    esbuild not found — run `forge assets build` manually\n%!";
      -1
    | Some esbuild ->
      (* Ensure output directory exists before watching *)
      let _ = Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote out_dir)) in
      let entries =
        List.filter Sys.file_exists [js_entry; css_entry]
        |> List.map Filename.quote
        |> String.concat " "
      in
      let args = [| esbuild; entries; "--bundle";
                    "--outdir=" ^ out_dir; "--sourcemap"; "--watch" |] in
      let pid = Unix.fork () in
      if pid = 0 then begin
        (* Redirect esbuild stdout/stderr to /dev/null to avoid cluttering
           server output.  esbuild --watch prints its own status lines. *)
        (try Unix.execve esbuild args (Unix.environment ())
         with e ->
           Printf.eprintf "forge: failed to exec esbuild: %s\n%!" (Printexc.to_string e);
           exit 1)
      end else begin
        Printf.printf "    Assets:    esbuild --watch (pid %d)\n%!" pid;
        pid
      end

(* ------------------------------------------------------------------ banner *)

let print_banner app_name port has_assets =
  Printf.printf "\n";
  Printf.printf "==> Bastion dev server starting\n%!";
  Printf.printf "    App:       %s\n%!"  app_name;
  Printf.printf "    URL:       http://localhost:%d\n%!"   port;
  Printf.printf "    Dashboard: http://localhost:%d/_bastion\n%!" port;
  Printf.printf "    Env:       dev\n%!";
  Printf.printf "    Watching:  lib/  config/\n%!";
  (if has_assets then
     Printf.printf "    Assets:    assets/ -> priv/static/assets/ (esbuild)\n%!");
  Printf.printf "    Press Ctrl+C to stop.\n\n%!"

(* ------------------------------------------------------------------ run *)

let run ~port_override () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let root       = proj.Project.root in
    let lib_dir    = Filename.concat root "lib" in
    let config_dir = Filename.concat root "config" in
    let entry      = Filename.concat lib_dir (proj.Project.name ^ ".march") in
    if not (Sys.file_exists entry) then
      Error (Printf.sprintf "entry point not found: %s" entry)
    else begin
      (* Build MARCH_LIB_PATH the same way cmd_run does *)
      let dep_lib_paths = List.filter_map (fun (_, dep) ->
          match dep with
          | Project.PathDep rel ->
            let abs = if Filename.is_relative rel
              then Filename.concat root rel else rel
            in
            let d = Filename.concat abs "lib" in
            if Sys.file_exists d then Some d else None
          | _ -> None
        ) proj.Project.deps
      in
      let all_lib_paths =
        dep_lib_paths @ [lib_dir]
        @ (if Sys.file_exists config_dir then [config_dir] else [])
      in
      let lib_path_str = String.concat ":" all_lib_paths in
      let port = Option.value ~default:4000 port_override in
      let env_arr = build_env [
          "MARCH_ENV",      "dev";
          "MARCH_LIB_PATH", lib_path_str;
          "BASTION_PORT",   string_of_int port;
        ] in
      let march_exe  = find_march_exe () in
      let has_assets = Sys.file_exists (Filename.concat root "assets") in
      print_banner proj.Project.name port has_assets;

      (* Optionally spawn esbuild --watch for the assets pipeline *)
      let esbuild_pid = ref (maybe_start_esbuild root) in

      (* child_pid ref shared with SIGINT handler *)
      let child_pid = ref (start_child march_exe entry env_arr) in

      (* Clean shutdown on Ctrl-C — kill both server and esbuild *)
      Sys.set_signal Sys.sigint (Sys.Signal_handle (fun _ ->
          if !child_pid > 0 then begin
            (try Unix.kill !child_pid Sys.sigterm with Unix.Unix_error _ -> ());
            (try let _ = Unix.waitpid [] !child_pid in ()
             with Unix.Unix_error _ -> ())
          end;
          if !esbuild_pid > 0 then begin
            (try Unix.kill !esbuild_pid Sys.sigterm with Unix.Unix_error _ -> ());
            (try let _ = Unix.waitpid [] !esbuild_pid in ()
             with Unix.Unix_error _ -> ())
          end;
          Printf.printf "\n--> Stopped.\n%!";
          exit 0
        ));

      let prev = ref (snapshot lib_dir config_dir) in

      (* Watch loop — runs forever until SIGINT *)
      while true do
        (* Sleep ~1s using Unix.select (avoids busy-wait, interruptible) *)
        (try let _ = Unix.select [] [] [] 1.0 in () with Unix.Unix_error _ -> ());

        (* Check if server child exited unexpectedly *)
        (match (try Unix.waitpid [Unix.WNOHANG] !child_pid
                with Unix.Unix_error _ -> (0, Unix.WEXITED 0)) with
         | (pid, _) when pid = !child_pid ->
           Printf.printf "--> Server exited unexpectedly. Restarting in 1s...\n%!";
           (try let _ = Unix.select [] [] [] 1.0 in () with Unix.Unix_error _ -> ());
           child_pid := start_child march_exe entry env_arr;
           prev := snapshot lib_dir config_dir
         | _ -> ());

        (* Check if esbuild exited unexpectedly (it shouldn't in --watch mode) *)
        (if !esbuild_pid > 0 then
           match (try Unix.waitpid [Unix.WNOHANG] !esbuild_pid
                  with Unix.Unix_error _ -> (0, Unix.WEXITED 0)) with
           | (pid, _) when pid = !esbuild_pid ->
             Printf.printf "--> esbuild exited unexpectedly. Restarting...\n%!";
             esbuild_pid := maybe_start_esbuild root
           | _ -> ());

        (* Check for file changes *)
        let curr = snapshot lib_dir config_dir in
        (match first_change !prev curr with
         | None -> ()
         | Some changed ->
           let short = Filename.basename changed in
           Printf.printf "--> change detected in %s, restarting...\n%!" short;
           (try Unix.kill !child_pid Sys.sigterm
            with Unix.Unix_error _ -> ());
           (try let _ = Unix.waitpid [] !child_pid in ()
            with Unix.Unix_error _ -> ());
           child_pid := start_child march_exe entry env_arr;
           (* brief pause so the new server can bind the port before next check *)
           (try let _ = Unix.select [] [] [] 0.1 in () with Unix.Unix_error _ -> ());
           prev := snapshot lib_dir config_dir
        );
        prev := curr
      done;
      Ok ()   (* unreachable — loop exits via SIGINT *)
    end
