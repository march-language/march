(** cmd_depot.ml — forge depot migrate/rollback/migrations/reset/gen.migration

    Migration runner for Depot. Discovers migration files in
    priv/depot/migrations/, shells out to the march compiler to execute
    up/0 and down/0 functions, and tracks applied versions via a local
    .march/depot/migrations.log file. *)

(* ------------------------------------------------------------------ *)
(* Helpers                                                             *)
(* ------------------------------------------------------------------ *)

let migration_dir = Filename.concat "priv" (Filename.concat "depot" "migrations")
let log_dir       = Filename.concat ".march" "depot"
let log_file      = Filename.concat log_dir "migrations.log"

let mkdir_p dir =
  let parts = String.split_on_char '/' dir in
  let _ =
    List.fold_left
      (fun acc p ->
        let path = if acc = "" then p else acc ^ "/" ^ p in
        (if path <> "" && not (Sys.file_exists path) then
           Unix.mkdir path 0o755);
        path)
      "" parts
  in
  ()

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let read_file path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

(* ------------------------------------------------------------------ *)
(* Migration log — flat file of applied version timestamps             *)
(* ------------------------------------------------------------------ *)

(** Read applied versions from log file. Returns sorted list of ints. *)
let read_applied () =
  if not (Sys.file_exists log_file) then []
  else
    let content = read_file log_file in
    let lines = String.split_on_char '\n' content in
    lines
    |> List.filter_map (fun line ->
         let trimmed = String.trim line in
         if trimmed = "" then None
         else match int_of_string_opt trimmed with
           | Some v -> Some v
           | None -> None)
    |> List.sort compare

(** Append a version to the log file. *)
let record_applied version =
  mkdir_p log_dir;
  let oc = open_out_gen [Open_append; Open_creat; Open_text] 0o644 log_file in
  Printf.fprintf oc "%d\n" version;
  close_out oc

(** Remove a version from the log file. *)
let remove_applied version =
  if Sys.file_exists log_file then begin
    let applied = read_applied () in
    let remaining = List.filter (fun v -> v <> version) applied in
    let content =
      remaining
      |> List.map string_of_int
      |> String.concat "\n"
    in
    write_file log_file (content ^ "\n")
  end

(* ------------------------------------------------------------------ *)
(* Migration file discovery                                            *)
(* ------------------------------------------------------------------ *)

(** A discovered migration file. *)
type migration = {
  version   : int;
  name      : string;
  path      : string;
}

(** Extract the timestamp version from a migration filename.
    Expected format: <TIMESTAMP>_<name>.march *)
let parse_migration_file path =
  let basename = Filename.basename path in
  if not (Filename.check_suffix basename ".march") then None
  else
    let without_ext = Filename.chop_suffix basename ".march" in
    match String.index_opt without_ext '_' with
    | None -> None
    | Some idx ->
      let ts_str = String.sub without_ext 0 idx in
      let name = String.sub without_ext (idx + 1)
          (String.length without_ext - idx - 1) in
      match int_of_string_opt ts_str with
      | Some version -> Some { version; name; path }
      | None -> None

(** Discover all migration files, sorted by version ascending. *)
let discover_migrations () =
  if not (Sys.file_exists migration_dir) then []
  else
    Sys.readdir migration_dir
    |> Array.to_list
    |> List.map (Filename.concat migration_dir)
    |> List.filter_map parse_migration_file
    |> List.sort (fun a b -> compare a.version b.version)

(* ------------------------------------------------------------------ *)
(* Migration execution — shell out to march                            *)
(* ------------------------------------------------------------------ *)

(** Extract the full module name from a migration file.
    Scans for "mod <Name> do" and returns the module name. *)
let extract_module_name path =
  let content = read_file path in
  let lines = String.split_on_char '\n' content in
  let rec find = function
    | [] -> None
    | line :: rest ->
      let trimmed = String.trim line in
      if String.length trimmed > 4
         && String.sub trimmed 0 4 = "mod "
      then begin
        (* Extract "mod Foo.Bar do" -> "Foo.Bar" *)
        let after_mod = String.sub trimmed 4 (String.length trimmed - 4) in
        let parts = String.split_on_char ' ' (String.trim after_mod) in
        match parts with
        | name :: _ -> Some name
        | [] -> find rest
      end
      else find rest
  in
  find lines

(** Build a runner .march file that includes the migration source
    inline and calls mod_name.fn_name() from main(). *)
let make_runner_source migration_path mod_name fn_name =
  let content = read_file migration_path in
  Printf.sprintf
    {|-- Auto-generated migration runner

mod MigrationRunner do

%s

fn main() do
  let result = %s.%s()
  result
end

end
|}
    content mod_name fn_name

(** Run a migration's up() or down() function by shelling out to march. *)
let run_migration migration fn_name =
  match extract_module_name migration.path with
  | None ->
    Error (Printf.sprintf "cannot find module declaration in %s" migration.path)
  | Some mod_name ->
    let runner_source = make_runner_source migration.path mod_name fn_name in
    let runner_file = Filename.temp_file "forge_migration_" ".march" in
    write_file runner_file runner_source;
    let cmd = Printf.sprintf "march %s 2>&1" (Filename.quote runner_file) in
    let rc = Sys.command cmd in
    (try Sys.remove runner_file with _ -> ());
    if rc = 0 then Ok ()
    else Error (Printf.sprintf "migration %d (%s) %s() failed with exit code %d"
                  migration.version migration.name fn_name rc)

(* ------------------------------------------------------------------ *)
(* Commands                                                            *)
(* ------------------------------------------------------------------ *)

(** forge depot migrate — apply all pending migrations in order. *)
let run_migrate () =
  let all = discover_migrations () in
  let applied = read_applied () in
  let pending =
    all |> List.filter (fun m -> not (List.mem m.version applied))
  in
  if pending = [] then begin
    Printf.printf "Already up to date. No pending migrations.\n%!";
    Ok ()
  end else begin
    Printf.printf "Running %d migration(s)...\n%!" (List.length pending);
    let result =
      List.fold_left (fun acc m ->
          match acc with
          | Error _ -> acc
          | Ok () ->
            Printf.printf "  * migrating %d_%s... " m.version m.name;
            match run_migration m "up" with
            | Ok () ->
              record_applied m.version;
              Printf.printf "done\n%!";
              Ok ()
            | Error msg ->
              Printf.printf "FAILED\n%!";
              Error msg
        ) (Ok ()) pending
    in
    match result with
    | Ok () ->
      Printf.printf "Migrations complete. %d applied.\n%!" (List.length pending);
      Ok ()
    | Error _ as e -> e
  end

(** forge depot rollback [--step N] — roll back the last N migrations. *)
let run_rollback step =
  let all = discover_migrations () in
  let applied = read_applied () in
  (* Sort applied descending to rollback most recent first *)
  let applied_desc = List.sort (fun a b -> compare b a) applied in
  let to_rollback =
    let rec take n lst = match n, lst with
      | 0, _ | _, [] -> []
      | n, x :: rest -> x :: take (n - 1) rest
    in
    take step applied_desc
  in
  if to_rollback = [] then begin
    Printf.printf "Nothing to roll back.\n%!";
    Ok ()
  end else begin
    Printf.printf "Rolling back %d migration(s)...\n%!" (List.length to_rollback);
    let result =
      List.fold_left (fun acc version ->
          match acc with
          | Error _ -> acc
          | Ok () ->
            (* Find the migration file for this version *)
            match List.find_opt (fun m -> m.version = version) all with
            | None ->
              Printf.printf "  * rolling back %d... MISSING FILE (skipped)\n%!" version;
              remove_applied version;
              Ok ()
            | Some m ->
              Printf.printf "  * rolling back %d_%s... " m.version m.name;
              match run_migration m "down" with
              | Ok () ->
                remove_applied m.version;
                Printf.printf "done\n%!";
                Ok ()
              | Error msg ->
                Printf.printf "FAILED\n%!";
                Error msg
        ) (Ok ()) to_rollback
    in
    match result with
    | Ok () ->
      Printf.printf "Rollback complete.\n%!";
      Ok ()
    | Error _ as e -> e
  end

(** forge depot migrations — show migration status. *)
let run_migrations () =
  let all = discover_migrations () in
  let applied = read_applied () in
  if all = [] then begin
    Printf.printf "No migrations found in %s/\n%!" migration_dir;
    Ok ()
  end else begin
    Printf.printf "Migration status:\n\n%!";
    Printf.printf "  %-14s  %-8s  %s\n%!" "Version" "Status" "Name";
    Printf.printf "  %-14s  %-8s  %s\n%!" "--------------" "--------" "----";
    List.iter (fun m ->
        let status =
          if List.mem m.version applied then "\027[32m  up  \027[0m"
          else "\027[33m down \027[0m"
        in
        Printf.printf "  %-14d  %s  %s\n%!" m.version status m.name
      ) all;
    let n_applied = List.length (List.filter (fun m -> List.mem m.version applied) all) in
    let n_pending = List.length all - n_applied in
    Printf.printf "\n  %d applied, %d pending\n%!" n_applied n_pending;
    Ok ()
  end

(** forge depot reset — rollback everything then migrate all. *)
let run_reset () =
  let applied = read_applied () in
  let n = List.length applied in
  if n > 0 then begin
    Printf.printf "Resetting: rolling back %d migration(s)...\n%!" n;
    match run_rollback n with
    | Error _ as e -> e
    | Ok () ->
      Printf.printf "\n%!";
      run_migrate ()
  end else
    run_migrate ()

(** forge depot gen migration <name> — generate a timestamped migration stub. *)
let run_gen_migration name =
  mkdir_p migration_dir;
  let timestamp = int_of_float (Unix.time ()) in
  let snake_name = String.lowercase_ascii name in
  let filename =
    Printf.sprintf "%d_%s.march" timestamp snake_name
  in
  let filepath = Filename.concat migration_dir filename in
  (* Convert snake_case name to PascalCase for module name *)
  let pascal_name =
    String.split_on_char '_' name
    |> List.map (fun p ->
         if String.length p = 0 then ""
         else String.capitalize_ascii p)
    |> String.concat ""
  in
  let content =
    Printf.sprintf
      {|-- Migration: %s
-- Generated by forge depot gen migration

mod Migrations.%s do

fn up() do
  -- TODO: write your migration here
  -- Example:
  --   Depot.Migration.create_table("table_name", {
  --     id = ("UUID", { primary_key = true }),
  --     name = ("String", { null = false })
  --   })
  ()
end

fn down() do
  -- TODO: write the rollback for up()
  -- Example:
  --   Depot.Migration.drop_table("table_name")
  ()
end

fn version() do
  %d
end

end
|}
      snake_name pascal_name timestamp
  in
  write_file filepath content;
  Printf.printf "* creating %s\n%!" filepath;
  Ok ()
