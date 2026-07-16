(** forge outdated — report dependencies that have a newer version available.

    Reads forge.lock for each dependency's currently-locked version, queries the
    registry (FORGE_REGISTRY / forgepm.org) for its available versions, and
    reports which REGISTRY deps have a newer non-retired release.  Git/path deps
    track a branch or commit and carry no semver version, so they are listed for
    reference (with their short commit) but never flagged as outdated. *)

module RV = Resolver_version
module RQ = Registry_query
module LF = Resolver_lockfile

type status =
  | Up_to_date
  | Outdated of string            (* newest available version *)
  | Not_versioned                 (* git/path dep — no semver to compare *)
  | Fetch_failed of string        (* registry unreachable / parse error *)

(** Newest non-retired, parseable version in [versions], by semver order.
    Pure — the core comparison logic, unit-tested independently of the network. *)
let pick_latest (versions : RQ.reg_version list) : string option =
  versions
  |> List.filter (fun (v : RQ.reg_version) -> not v.RQ.rv_retired)
  |> List.filter_map (fun (v : RQ.reg_version) ->
       match RV.parse v.RQ.rv_version with Ok _ -> Some v.RQ.rv_version | Error _ -> None)
  |> List.fold_left (fun acc vs ->
       match acc with
       | None -> Some vs
       | Some best ->
         (match RV.parse best, RV.parse vs with
          | Ok b, Ok c -> if RV.compare c b > 0 then Some vs else acc
          | _ -> acc)) None

(** Compare the locked [current] version against the registry [versions]. Pure. *)
let classify_registry ~current (versions : RQ.reg_version list) : status =
  match pick_latest versions with
  | None -> Fetch_failed "no comparable versions in registry metadata"
  | Some latest ->
    (match RV.parse current, RV.parse latest with
     | Ok c, Ok l -> if RV.compare l c > 0 then Outdated latest else Up_to_date
     | _ -> Up_to_date)

(** Build one report row for a lock entry.  [binary] is the compiled registry
    client (unused for git/path deps). *)
let entry_row ~binary ~registry (e : LF.entry) =
  match e.LF.version with
  | Some current ->
    (match RQ.available_versions ~binary ~registry e.LF.name with
     | Error msg -> (e.LF.name, current, Fetch_failed msg)
     | Ok versions -> (e.LF.name, current, classify_registry ~current versions))
  | None ->
    let cur = match e.LF.commit with
      | Some c when String.length c >= 7 -> String.sub c 0 7
      | Some c -> c
      | None -> "-" in
    (e.LF.name, cur, Not_versioned)

let status_string = function
  | Up_to_date        -> "up to date"
  | Outdated l        -> Printf.sprintf "OUTDATED -> %s" l
  | Not_versioned     -> "git/path (not version-tracked)"
  | Fetch_failed m    -> Printf.sprintf "unknown (%s)" m

let run () =
  match Project.load () with
  | Error e -> Error e
  | Ok proj ->
    let lock_path = Filename.concat proj.Project.root "forge.lock" in
    (match LF.read lock_path with
     | Error e -> Error (Printf.sprintf "%s — run `forge deps` first" e)
     | Ok ([], _) ->
       print_endline "No dependencies in forge.lock.";
       Ok ()
     | Ok (entries, _manifest_hash) ->
       let registry = RQ.registry_base_url () in
       let has_reg = List.exists (fun (e : LF.entry) -> e.LF.version <> None) entries in
       let binary_res = if has_reg then RQ.compile_client () else Ok "" in
       (match binary_res with
        | Error e -> Error (Printf.sprintf "registry client: %s" e)
        | Ok binary ->
          Fun.protect
            ~finally:(fun () ->
              if binary <> "" then (try Sys.remove binary with Sys_error _ -> ()))
            (fun () ->
              let rows = List.map (entry_row ~binary ~registry) entries in
              let name_w = List.fold_left (fun m (n,_,_) -> max m (String.length n)) 4 rows in
              let cur_w  = List.fold_left (fun m (_,c,_) -> max m (String.length c)) 7 rows in
              Printf.printf "%-*s  %-*s  %s\n" name_w "NAME" cur_w "CURRENT" "STATUS";
              let n_outdated = ref 0 in
              List.iter (fun (n, c, st) ->
                  (match st with Outdated _ -> incr n_outdated | _ -> ());
                  Printf.printf "%-*s  %-*s  %s\n" name_w n cur_w c (status_string st))
                rows;
              if !n_outdated = 0 then
                print_endline "\nAll registry dependencies are up to date."
              else
                Printf.printf
                  "\n%d dependenc%s outdated. Update the version in forge.toml, then run `forge deps` to upgrade.\n"
                  !n_outdated (if !n_outdated = 1 then "y is" else "ies are");
              Ok ())))
