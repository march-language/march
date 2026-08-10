(** forge licenses — list each dependency and its declared license.

    Also hosts [frozen_error], the shared `--frozen` gate (a lockfile drift is a
    hard error under --frozen instead of a re-resolve). *)

(* --- pure helpers (unit-tested) --- *)

(* A [row] is (name, version option, license option). *)
let license_str = function Some s when String.trim s <> "" -> Some (String.trim s) | _ -> None

let any_missing rows = List.exists (fun (_, _, l) -> license_str l = None) rows

let frozen_error ~drifted ~frozen = drifted && frozen

let format rows ~json =
  if json then
    let item (n, v, l) =
      Printf.sprintf "  {\"name\": %S, \"version\": %s, \"license\": %s}" n
        (match v with Some x -> Printf.sprintf "%S" x | None -> "null")
        (match license_str l with Some x -> Printf.sprintf "%S" x | None -> "null")
    in
    "[\n" ^ String.concat ",\n" (List.map item rows) ^ "\n]"
  else
    let row (n, v, l) =
      Printf.sprintf "  %-24s %-10s %s" n
        (Option.value ~default:"-" v)
        (match license_str l with Some x -> x | None -> "MISSING")
    in
    String.concat "\n" (List.map row rows)

(* --- dependency enumeration (IO) --- *)

(* Git/registry deps are installed under [~/.march/cas/deps/<name>] (see
   [Project.dep_root_dir]) — NOT under the project root. [base] is the
   directory of the project that DECLARED [dep], needed to resolve a
   relative PathDep. *)
let dep_dir ~base ~name ~dep =
  match Project.dep_root_dir ~project_root:base (name, dep) with
  | Some d -> d
  | None -> Filename.concat base name

(* Walk every (transitive) dependency, reading version + license from its
   forge.toml; deps that can't be read are listed with no metadata. *)
let collect proj =
  let root = proj.Project.root in
  let tbl = Hashtbl.create 32 in
  let rec visit ~base ~name ~dep =
    if not (Hashtbl.mem tbl name) then begin
      let dir = dep_dir ~base ~name ~dep in
      match Project.load_from_dir dir with
      | Ok p ->
        Hashtbl.replace tbl name (Some p.Project.version, p.Project.license);
        List.iter (fun (cn, cd) -> visit ~base:dir ~name:cn ~dep:cd) p.Project.deps
      | Error _ -> Hashtbl.replace tbl name (None, None)
    end
  in
  List.iter (fun (n, d) -> visit ~base:root ~name:n ~dep:d) proj.Project.deps;
  Hashtbl.fold (fun n (v, l) acc -> (n, v, l) :: acc) tbl [] |> List.sort compare

let run ?(json = false) ?(strict = false) () =
  match Project.load () with
  | Error e -> Error e
  | Ok proj ->
    match collect proj with
    | [] -> Printf.printf "no dependencies\n"; Ok ()
    | rows ->
      print_string (format rows ~json);
      print_newline ();
      if strict && any_missing rows then Error "some dependencies declare no license"
      else Ok ()
