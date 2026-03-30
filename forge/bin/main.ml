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
  let dump_phases =
    Arg.(value & flag & info ["dump-phases"]
           ~doc:"Serialize each compiler IR stage to march-phases/phases.json")
  in
  let run r d =
    match Cmd_build.build ~release:r ~dump_phases:d () with
    | Ok binary -> Printf.printf "built: %s\n%!" binary
    | Error m   -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "build" ~doc:"Build the current project")
    Term.(const run $ release $ dump_phases)

(* ------------------------------------------------------------------- forge run *)

let run_cmd =
  let dump_phases =
    Arg.(value & flag & info ["dump-phases"]
           ~doc:"Serialize each compiler IR stage to march-phases/phases.json")
  in
  let run d = handle (Cmd_run.run ~dump_phases:d ()) in
  Cmd.v (Cmd.info "run" ~doc:"Build and run the current project")
    Term.(const run $ dump_phases)

(* ------------------------------------------------------------------ forge test *)

let test_cmd =
  let verbose =
    Arg.(value & flag & info ["v"; "verbose"] ~doc:"Show each test name as it runs")
  in
  let coverage =
    Arg.(value & flag & info ["coverage"] ~doc:"Collect and report test coverage")
  in
  let filter =
    Arg.(value & opt string "" &
         info ["filter"] ~docv:"PATTERN" ~doc:"Only run tests whose name matches PATTERN")
  in
  let files =
    Arg.(value & pos_all string [] &
         info [] ~docv:"FILE" ~doc:"Test files to run (default: all test files under test/)")
  in
  let run v c f fs = handle (Cmd_test.run ~verbose:v ~coverage:c ~filter:f ~files:fs ()) in
  Cmd.v (Cmd.info "test" ~doc:"Run the test suite")
    Term.(const run $ verbose $ coverage $ filter $ files)

(* ---------------------------------------------------------------- forge format *)

let format_cmd =
  let check =
    Arg.(value & flag & info ["check"] ~doc:"Check formatting only, no writes")
  in
  let stdin =
    Arg.(value & flag & info ["stdin"] ~doc:"Read from stdin, write formatted output to stdout (for editor integration)")
  in
  let run c s = handle (Cmd_format.run ~check:c ~stdin:s) in
  Cmd.v (Cmd.info "format" ~doc:"Format all .march source files")
    Term.(const run $ check $ stdin)

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

(* --------------------------------------------------------------- forge install *)

let install_cmd =
  let source =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"PATH_OR_URL" ~doc:"Local path or git URL of the project to install")
  in
  let run s =
    match Cmd_install.run s with
    | Ok ()  -> ()
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "install" ~doc:"Build and install a March project as a CLI tool")
    Term.(const run $ source)

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

(* --------------------------------------------------------------- forge search *)

let search_cmd =
  let query =
    Arg.(value & pos 0 string "" &
         info [] ~docv:"QUERY" ~doc:"Name to search for (fuzzy/substring)")
  in
  let type_sig =
    Arg.(value & opt string "" &
         info ["type"; "t"] ~docv:"TYPE" ~doc:"Type signature to search for")
  in
  let doc_query =
    Arg.(value & opt string "" &
         info ["doc"; "d"] ~docv:"KEYWORDS" ~doc:"Keywords to search in doc strings")
  in
  let limit =
    Arg.(value & opt int 20 &
         info ["limit"; "n"] ~docv:"N" ~doc:"Maximum number of results (default 20)")
  in
  let as_json =
    Arg.(value & flag & info ["json"] ~doc:"Output results as JSON")
  in
  let pretty =
    Arg.(value & flag & info ["pretty"; "p"] ~doc:"Output results as a colored, aligned table")
  in
  let rebuild =
    Arg.(value & flag & info ["rebuild"] ~doc:"Rebuild the search index before searching")
  in
  let run q t d n j p r =
    Cmd_search.run ~query:q ~type_sig:t ~doc_query:d ~limit:n ~as_json:j ~pretty:p ~rebuild:r ()
  in
  Cmd.v
    (Cmd.info "search"
       ~doc:"Search stdlib and dependencies for functions, types, and constructors")
    Term.(const run $ query $ type_sig $ doc_query $ limit $ as_json $ pretty $ rebuild)

(* --------------------------------------------------------------- forge publish *)

let publish_cmd =
  let old_source =
    Arg.(value & opt (some string) None &
         info ["old-source"] ~docv:"DIR"
           ~doc:"Path to the previous version's source tree for semver checking")
  in
  let dry_run =
    Arg.(value & flag & info ["dry-run"]
           ~doc:"Validate only; do not submit to registry")
  in
  let run o d = handle (Cmd_publish.run ~old_source_dir:o ~dry_run:d ()) in
  Cmd.v (Cmd.info "publish" ~doc:"Validate and publish the current package")
    Term.(const run $ old_source $ dry_run)

(* ------------------------------------------------------------------ forge init *)

let init_cmd =
  Cmd.v (Cmd.info "init" ~doc:"Initialize a forge.toml in the current directory")
    Term.(const (fun () -> handle (Cmd_init.run ())) $ const ())

(* --------------------------------------------------------------- forge assets *)

let assets_build_cmd =
  Cmd.v (Cmd.info "build" ~doc:"Bundle assets for development (esbuild, with sourcemaps)")
    Term.(const (fun () ->
        match Cmd_assets.build () with
        | Ok () -> ()
        | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
      ) $ const ())

let assets_deploy_cmd =
  Cmd.v (Cmd.info "deploy" ~doc:"Bundle and minify assets for production, with digest fingerprinting")
    Term.(const (fun () ->
        match Cmd_assets.deploy () with
        | Ok () -> ()
        | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
      ) $ const ())

let assets_watch_cmd =
  Cmd.v (Cmd.info "watch" ~doc:"Watch assets for changes and rebuild automatically (esbuild --watch)")
    Term.(const (fun () ->
        match Cmd_assets.watch () with
        | Ok () -> ()
        | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
      ) $ const ())

let assets_cmd =
  Cmd.group
    (Cmd.info "assets" ~doc:"Asset pipeline commands (build, deploy, watch) powered by esbuild")
    [assets_build_cmd; assets_deploy_cmd; assets_watch_cmd]

(* --------------------------------------------------------------- forge bastion *)

let bastion_new_cmd =
  let name =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"NAME" ~doc:"Application name (snake_case)")
  in
  let run n =
    match Cmd_bastion_new.run n with
    | Ok () -> ()
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "new" ~doc:"Scaffold a new Bastion web application")
    Term.(const run $ name)

let bastion_server_cmd =
  let port =
    Arg.(value & opt (some int) None &
         info ["port"; "p"] ~docv:"PORT"
           ~doc:"Override the HTTP port (default: read from Config.endpoint_port, fallback 4000)")
  in
  let run p =
    match Cmd_bastion_server.run ~port_override:p () with
    | Ok () -> ()
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "server" ~doc:"Start the Bastion dev server with live-reload")
    Term.(const run $ port)

let bastion_routes_cmd =
  Cmd.v (Cmd.info "routes" ~doc:"List all routes defined in the router")
    Term.(const (fun () ->
        match Cmd_bastion_routes.run () with
        | Ok () -> ()
        | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
      ) $ const ())

let bastion_cmd =
  Cmd.group
    (Cmd.info "bastion" ~doc:"Bastion web framework commands (server, new, routes)")
    [bastion_new_cmd; bastion_server_cmd; bastion_routes_cmd]

(* --------------------------------------------------------------------- root *)

let default_term =
  Term.(const (fun () ->
    match Cmd_build.build ~release:false () with
    | Ok binary -> Printf.printf "built: %s\n%!" binary
    | Error m   -> Printf.eprintf "error: %s\n%!" m; exit 1
  ) $ const ())

let () =
  let cmds =
    [ new_cmd; init_cmd; build_cmd; run_cmd; test_cmd; format_cmd;
      interactive_cmd; i_cmd; clean_cmd; deps_cmd; install_cmd; publish_cmd;
      search_cmd; assets_cmd; bastion_cmd; help_cmd ]
  in
  let main =
    Cmd.group ~default:default_term
      (Cmd.info "forge" ~version:"0.1.0"
         ~doc:"The March package manager and build tool")
      cmds
  in
  exit (Cmd.eval main)
