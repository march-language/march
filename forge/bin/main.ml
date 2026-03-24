(** forge — the March package manager and build tool *)

open Cmdliner
open March_forge

let handle = function
  | Ok ()   -> ()
  | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1

(* ------------------------------------------------------------------ forge new *)

let new_cmd =
  let name =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"NAME" ~doc:"Project name")
  in
  let app_flag  = Arg.(value & flag & info ["app"]  ~doc:"Application project (default)") in
  let lib_flag  = Arg.(value & flag & info ["lib"]  ~doc:"Library project") in
  let tool_flag = Arg.(value & flag & info ["tool"] ~doc:"CLI tool project") in
  let run name _is_app is_lib is_tool =
    let pt =
      if is_lib  then Project.Lib
      else if is_tool then Project.Tool
      else Project.App
    in
    (match Scaffold.scaffold name pt with
     | Ok () ->
       Printf.printf "created %s project '%s'\n%!"
         (Project.project_type_to_string pt) name
     | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1)
  in
  Cmd.v (Cmd.info "new" ~doc:"Create a new March project")
    Term.(const run $ name $ app_flag $ lib_flag $ tool_flag)

(* ----------------------------------------------------------------- forge build *)

let build_cmd =
  let release =
    Arg.(value & flag & info ["release"] ~doc:"Build in release mode")
  in
  let run r =
    match Cmd_build.build ~release:r with
    | Ok binary -> Printf.printf "built: %s\n%!" binary
    | Error m   -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "build" ~doc:"Build the current project")
    Term.(const run $ release)

(* ------------------------------------------------------------------- forge run *)

let run_cmd =
  Cmd.v (Cmd.info "run" ~doc:"Build and run the current project")
    Term.(const (fun () -> handle (Cmd_run.run ())) $ const ())

(* ------------------------------------------------------------------ forge test *)

let test_cmd =
  let verbose =
    Arg.(value & flag & info ["v"; "verbose"] ~doc:"Show each test name as it runs")
  in
  let filter =
    Arg.(value & opt string "" &
         info ["filter"] ~docv:"PATTERN" ~doc:"Only run tests whose name matches PATTERN")
  in
  let files =
    Arg.(value & pos_all string [] &
         info [] ~docv:"FILE" ~doc:"Test files to run (default: all test files under test/)")
  in
  let run v f fs = handle (Cmd_test.run ~verbose:v ~filter:f ~files:fs ()) in
  Cmd.v (Cmd.info "test" ~doc:"Run the test suite")
    Term.(const run $ verbose $ filter $ files)

(* ---------------------------------------------------------------- forge format *)

let format_cmd =
  let check =
    Arg.(value & flag & info ["check"] ~doc:"Check formatting only, no writes")
  in
  let run c = handle (Cmd_format.run ~check:c) in
  Cmd.v (Cmd.info "format" ~doc:"Format all .march source files")
    Term.(const run $ check)

(* ---------------------------------------------------------- forge interactive *)

let interactive_cmd =
  Cmd.v (Cmd.info "interactive" ~doc:"Launch the March REPL with project context")
    Term.(const (fun () -> handle (Cmd_interactive.run ())) $ const ())

let i_cmd =
  Cmd.v (Cmd.info "i" ~doc:"Alias for 'interactive'")
    Term.(const (fun () -> handle (Cmd_interactive.run ())) $ const ())

(* ----------------------------------------------------------------- forge clean *)

let clean_cmd =
  let cas =
    Arg.(value & flag & info ["cas"] ~doc:"Also remove .march/cas/")
  in
  let all =
    Arg.(value & flag & info ["all"] ~doc:"Remove the entire .march/ directory")
  in
  let run c a = handle (Cmd_clean.run ~cas:c ~all:a) in
  Cmd.v (Cmd.info "clean" ~doc:"Remove build artifacts")
    Term.(const run $ cas $ all)

(* ------------------------------------------------------------------ forge deps *)

let deps_update_cmd =
  let name =
    Arg.(value & pos 0 (some string) None &
         info [] ~docv:"NAME" ~doc:"Dependency to update (omit to update all)")
  in
  let run n = handle (Cmd_deps.run_update n) in
  Cmd.v (Cmd.info "update" ~doc:"Update one or all dependencies")
    Term.(const run $ name)

let deps_cmd =
  let install_term =
    Term.(const (fun () -> handle (Cmd_deps.run ())) $ const ())
  in
  Cmd.group ~default:install_term
    (Cmd.info "deps" ~doc:"Install and manage project dependencies")
    [deps_update_cmd]

(* ------------------------------------------------------------------ forge help *)

let help_cmd =
  let topic =
    Arg.(value & pos 0 (some string) None &
         info [] ~docv:"COMMAND" ~doc:"Command to show help for")
  in
  let run t =
    match t with
    | None   -> `Help (`Auto, None)
    | Some c -> `Help (`Auto, Some c)
  in
  Cmd.v (Cmd.info "help" ~doc:"Show help for forge or a specific command")
    Term.(ret (const run $ topic))

(* ------------------------------------------------------------------ forge init *)

let init_cmd =
  Cmd.v (Cmd.info "init" ~doc:"Initialize a forge.toml in the current directory")
    Term.(const (fun () -> handle (Cmd_init.run ())) $ const ())

(* --------------------------------------------------------------------- root *)

let default_term =
  Term.(const (fun () ->
    match Cmd_build.build ~release:false with
    | Ok binary -> Printf.printf "built: %s\n%!" binary
    | Error m   -> Printf.eprintf "error: %s\n%!" m; exit 1
  ) $ const ())

let () =
  let cmds =
    [ new_cmd; init_cmd; build_cmd; run_cmd; test_cmd; format_cmd;
      interactive_cmd; i_cmd; clean_cmd; deps_cmd; help_cmd ]
  in
  let main =
    Cmd.group ~default:default_term
      (Cmd.info "forge" ~version:"0.1.0"
         ~doc:"The March package manager and build tool")
      cmds
  in
  exit (Cmd.eval main)
