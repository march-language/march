(** forge refactor — project-wide, parser-based refactorings.

    Thin wrapper over [March_refactor.Refactor]: resolves the project root and
    renders the engine's per-file outcome. The actual transforms live in
    lib/refactor. *)

module Refactor = March_refactor.Refactor

let with_root f =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj -> f proj.Project.root

let print_outcome ~dry_run (o : Refactor.outcome) =
  List.iter (fun (c : Refactor.file_change) ->
      Printf.printf "%s %s (%d edit%s)\n"
        (if dry_run then "would change" else "changed")
        c.Refactor.fc_path c.Refactor.fc_count
        (if c.Refactor.fc_count = 1 then "" else "s"))
    o.Refactor.changes;
  List.iter (fun (p, r) -> Printf.printf "skipped %s: %s\n" p r) o.Refactor.skipped;
  let n = List.length o.Refactor.changes in
  if n = 0 && o.Refactor.skipped = [] then Printf.printf "no matches found\n%!"
  else Printf.printf "%d file%s %s%s\n%!"
      n (if n = 1 then "" else "s")
      (if dry_run then "would be changed" else "changed")
      (if dry_run then " (dry run — nothing written)" else "")

let rename ~old_name ~new_name ~kind ~pattern ~dry_run () =
  with_root (fun root ->
      let o =
        if pattern then
          Refactor.rename_pattern ~root ~regex:old_name ~replacement:new_name ~kind ~dry_run
        else
          Refactor.rename_symbol ~root ~old_name ~new_name ~kind ~dry_run
      in
      print_outcome ~dry_run o; Ok ())

let fix ~dry_run () =
  with_root (fun root ->
      let o = Refactor.fix_project ~root ~dry_run in
      print_outcome ~dry_run o; Ok ())

let move ~decl ~dest ~dry_run () =
  with_root (fun root ->
      let dest = if Filename.is_relative dest then Filename.concat root dest else dest in
      match Refactor.move_decl ~root ~decl_name:decl ~dest ~dry_run with
      | Ok o -> print_outcome ~dry_run o; Ok ()
      | Error e -> Error e)

let replace ~pat ~tmpl ~dry_run () =
  with_root (fun root ->
      match Refactor.replace_project ~root ~pat ~tmpl ~dry_run with
      | Ok o -> print_outcome ~dry_run o; Ok ()
      | Error e -> Error e)

let bundle ~fn_name ~record ~dry_run () =
  with_root (fun root ->
      let record_name = if record = "" then None else Some record in
      match Refactor.bundle_fn ~root ~fn_name ?record_name ~dry_run () with
      | Ok o -> print_outcome ~dry_run o; Ok ()
      | Error e -> Error e)
