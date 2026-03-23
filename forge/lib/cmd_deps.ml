(** forge deps — resolve and install project dependencies *)

let home_dir () =
  try Sys.getenv "HOME"
  with Not_found -> failwith "HOME not set"

let cas_deps_dir () =
  Filename.concat (home_dir ())
    (Filename.concat ".march" (Filename.concat "cas" "deps"))

let write_lock lock_path lock_lines =
  let oc = open_out lock_path in
  List.iter (fun line -> output_string oc line; output_char oc '\n') lock_lines;
  close_out oc

let install_dep name dep =
  match dep with
  | Project.GitDep { url; rev } ->
    let deps_dir = cas_deps_dir () in
    Project.mkdir_p deps_dir;
    let dest = Filename.concat deps_dir name in
    if Sys.file_exists dest then begin
      Printf.printf "  %s: already installed\n%!" name;
      Ok (Printf.sprintf "%s = { git = \"%s\", rev = \"%s\", path = \"%s\" }"
            name url rev dest)
    end else begin
      Printf.printf "  %s: cloning %s @ %s...\n%!" name url rev;
      let cmd = Printf.sprintf "git clone --depth 1 --branch %s %s %s"
          (Filename.quote rev) (Filename.quote url) (Filename.quote dest) in
      let rc = Sys.command cmd in
      if rc = 0 then
        Ok (Printf.sprintf "%s = { git = \"%s\", rev = \"%s\", path = \"%s\" }"
              name url rev dest)
      else
        Error (Printf.sprintf "failed to clone %s (exit %d)" url rc)
    end
  | Project.PathDep path ->
    if Sys.file_exists path then begin
      Printf.printf "  %s: found at %s\n%!" name path;
      Ok (Printf.sprintf "%s = { path = \"%s\" }" name path)
    end else
      Error (Printf.sprintf "path dep '%s' not found: %s" name path)

let update_dep name dep =
  match dep with
  | Project.GitDep { url; rev } ->
    let dest = Filename.concat (cas_deps_dir ()) name in
    if Sys.file_exists dest then begin
      Printf.printf "  %s: pulling %s...\n%!" name rev;
      let cmd = Printf.sprintf
          "git -C %s fetch --depth 1 origin %s && git -C %s checkout FETCH_HEAD"
          (Filename.quote dest) (Filename.quote rev) (Filename.quote dest) in
      let rc = Sys.command cmd in
      if rc = 0 then Ok ()
      else Error (Printf.sprintf "failed to update %s" name)
    end else begin
      let _ = install_dep name (Project.GitDep { url; rev }) in
      Ok ()
    end
  | Project.PathDep _ ->
    Printf.printf "  %s: path dep, nothing to update\n%!" name;
    Ok ()

let run () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    if proj.Project.deps = [] then begin
      Printf.printf "no dependencies declared\n%!";
      Ok ()
    end else begin
      Printf.printf "installing %d dependencies...\n%!" (List.length proj.Project.deps);
      let results = List.map (fun (n, d) -> install_dep n d) proj.Project.deps in
      let errors = List.filter_map (function Error e -> Some e | Ok _ -> None) results in
      let lines  = List.filter_map (function Ok l -> Some l   | Error _ -> None) results in
      write_lock (Filename.concat proj.Project.root "forge.lock") lines;
      if errors = [] then Ok ()
      else Error (String.concat "\n" errors)
    end

let run_update name_opt =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let to_update = match name_opt with
      | None   -> proj.Project.deps
      | Some n ->
        (match List.assoc_opt n proj.Project.deps with
         | None   -> []
         | Some d -> [(n, d)])
    in
    if to_update = [] then begin
      (match name_opt with
       | Some n -> Printf.printf "dependency '%s' not found\n%!" n
       | None   -> Printf.printf "no dependencies to update\n%!");
      Ok ()
    end else begin
      let results = List.map (fun (n, d) -> update_dep n d) to_update in
      let errors  = List.filter_map (function Error e -> Some e | Ok _ -> None) results in
      if errors = [] then Ok ()
      else Error (String.concat "\n" errors)
    end
