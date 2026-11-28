(** forge install <path|url> — build and install a March project as a CLI tool *)

let install_dir () =
  match Sys.getenv_opt "HOME" with
  | None -> failwith "HOME not set"
  | Some home ->
    let dir = Filename.concat home (Filename.concat ".march" "bin") in
    Project.mkdir_p dir;
    dir

let is_url s =
  let has_prefix p = String.length s >= String.length p
    && String.sub s 0 (String.length p) = p in
  has_prefix "http://" || has_prefix "https://"
  || has_prefix "git@" || has_prefix "ssh://"

let clone_to_tmp url =
  let tmp = Filename.concat (Filename.get_temp_dir_name ())
      ("forge-install-" ^ string_of_int (Random.int 1_000_000)) in
  let cmd = Printf.sprintf "git clone --depth 1 %s %s"
      (Filename.quote url) (Filename.quote tmp) in
  match Net_gate.command ~what:(Printf.sprintf "clone %s" url)
          ~remedy:"Install from a local path instead, or retry with network access." cmd with
  | Error e -> Error e
  | Ok rc ->
  if rc <> 0 then Error (Printf.sprintf "git clone failed (exit %d)" rc)
  else Ok tmp

let run source =
  let source_result =
    if is_url source then clone_to_tmp source
    else if Sys.file_exists source then Ok source
    else Error (Printf.sprintf "path not found: %s" source)
  in
  match source_result with
  | Error msg -> Error msg
  | Ok project_dir ->
    let abs_dir =
      if Filename.is_relative project_dir then
        Filename.concat (Sys.getcwd ()) project_dir
      else project_dir
    in
    (* Load the project to get its name *)
    let toml_path = Filename.concat abs_dir "forge.toml" in
    if not (Sys.file_exists toml_path) then
      Error (Printf.sprintf "no forge.toml found in %s" abs_dir)
    else begin
      let proj = Project.load_from abs_dir in
      (* Build in release mode *)
      let build_dir =
        Filename.concat abs_dir
          (Filename.concat ".march" (Filename.concat "build" "release"))
      in
      Project.mkdir_p build_dir;
      match Project.entry proj with
      | Error e -> Error e
      | Ok entry -> begin
        let output = Filename.concat build_dir proj.Project.name in
        match Cmd_build.deps_preflight ~scope:(Cmd_build.build_scope ~release:true proj) proj with
        | Error _ as error -> error
        | Ok () ->
        match Cmd_build.ffi_flags_full ~release:true proj with
        | Error _ as error -> error
        | Ok ffi_flags ->
        let cmd = Cmd_build.compile_command ~lib_path_env:(Cmd_build.lib_path_env ~release:true proj)
            ~ffi_flags ~output ~release:true ~dump_phases:false ~pin_main:proj.Project.pin_main entry in
        let rc = Sys.command cmd in
        if rc <> 0 then
          Error (Printf.sprintf "build failed (exit %d)" rc)
        else begin
          let dest_dir = install_dir () in
          let dest = Filename.concat dest_dir proj.Project.name in
          let cp_cmd = Printf.sprintf "cp %s %s"
              (Filename.quote output) (Filename.quote dest) in
          let cp_rc = Sys.command cp_cmd in
          if cp_rc <> 0 then
            Error "failed to copy binary to ~/.march/bin/"
          else begin
            Printf.printf "installed %s to %s\n%!" proj.Project.name dest;
            (* Clean up if we cloned *)
            if is_url source then begin
              let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote abs_dir)) in ()
            end;
            Ok ()
          end
        end
      end
    end
