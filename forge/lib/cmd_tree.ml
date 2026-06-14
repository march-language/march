(** forge tree / forge why — show the dependency graph.

    forge.lock stores a flat list of resolved packages with no edges, so the
    graph is reconstructed by reading each installed dependency's own
    forge.toml. Git/registry deps live under <root>/.march/cas/deps/<name>;
    path deps are relative to the forge.toml that declares them. Dependencies
    that aren't installed (or can't be read) show as leaves. *)

let cas_deps_dir root =
  Filename.concat root (Filename.concat ".march" (Filename.concat "cas" "deps"))

let dep_dir ~root ~base ~name ~dep =
  match dep with
  | Project.PathDep p ->
    if Filename.is_relative p then Filename.concat base p else p
  | _ -> Filename.concat (cas_deps_dir root) name

(* Walk the installed dependency dirs from [proj], building a name -> child
   names adjacency table. Returns (root_name, deps_of). *)
let build_adjacency proj =
  let root = proj.Project.root in
  let tbl = Hashtbl.create 32 in
  let rec visit ~base ~name ~dep_opt =
    if not (Hashtbl.mem tbl name) then begin
      let dir = match dep_opt with
        | None     -> root
        | Some dep -> dep_dir ~root ~base ~name ~dep
      in
      let deps =
        match Project.load_from_dir dir with
        | Ok p    -> p.Project.deps
        | Error _ -> []
      in
      Hashtbl.replace tbl name (List.map fst deps);
      List.iter (fun (cname, cdep) -> visit ~base:dir ~name:cname ~dep_opt:(Some cdep)) deps
    end
  in
  visit ~base:root ~name:proj.Project.name ~dep_opt:None;
  (proj.Project.name, fun name -> Option.value ~default:[] (Hashtbl.find_opt tbl name))

let run_tree () =
  match Project.load () with
  | Error e -> Error e
  | Ok proj ->
    let (root, deps_of) = build_adjacency proj in
    List.iter print_endline (Deptree.render_tree ~root ~deps_of);
    Ok ()

let run_why name =
  match Project.load () with
  | Error e -> Error e
  | Ok proj ->
    let (root, deps_of) = build_adjacency proj in
    match Deptree.why ~root ~deps_of ~target:name with
    | [] -> Printf.printf "%s is not a dependency of %s\n" name root; Ok ()
    | paths ->
      List.iter (fun path -> print_endline (String.concat " -> " path)) paths;
      Ok ()
