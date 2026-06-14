(** forge watch [build|test|run] — rerun an action whenever a source file
    changes. Polls file mtimes (dependency-free, cross-platform) via [Watcher]
    and never exits on a build/test failure — it reports and keeps watching.
    Ctrl-C stops it. *)

(* Every .march under lib/ src/ test/ config/, plus forge.toml. Re-globbed each
   poll so newly added (or removed) files are picked up. *)
let watched_files root =
  let from_dir d =
    let dir = Filename.concat root d in
    if Sys.file_exists dir then Cmd_build.find_march_files dir else []
  in
  let toml = Filename.concat root "forge.toml" in
  (if Sys.file_exists toml then [ toml ] else [])
  @ List.concat_map from_dir [ "lib"; "src"; "test"; "config" ]

let run_action ~action ~filter =
  let label, result =
    match action with
    | "test" -> "test", Result.map (fun () -> ()) (Cmd_test.run ~filter ())
    | "run"  -> "run",  Cmd_run.run ()
    | _      -> "build", Result.map (fun _ -> ()) (Cmd_build.build ~release:false ())
  in
  (match result with
   | Ok ()   -> Printf.printf "  \xe2\x9c\x93 %s ok\n%!" label
   | Error e -> Printf.printf "  \xe2\x9c\x97 %s failed: %s\n%!" label e)

let run ~action ~interval ~clear () =
  match Project.load () with
  | Error e -> Error e
  | Ok proj ->
    let root = proj.Project.root in
    let prev = ref (Watcher.snapshot_of (watched_files root)) in
    let once () =
      if clear then print_string "\027[2J\027[H";
      Printf.printf "[forge watch] running %s ...\n%!" action;
      run_action ~action ~filter:"";
    in
    Printf.printf "[forge watch] watching %s; press Ctrl-C to stop\n%!" root;
    once ();   (* run once up front *)
    let delay = Float.max 0.05 (float_of_int interval /. 1000.) in
    let rec loop () =
      Unix.sleepf delay;
      let cur = Watcher.snapshot_of (watched_files root) in
      if Watcher.changed ~prev:!prev ~cur then (prev := cur; once ());
      loop ()
    in
    loop ()
