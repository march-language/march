(** forge — the March package manager and build tool *)

open Cmdliner
open March_forge

let handle = function
  | Ok ()   -> ()
  | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1

(* --------------------------------------------------------- pre-dispatch ---
   Archive tasks look like "bastion.new" — dotted namespaces not used by any
   built-in command.  We intercept these before cmdliner so unknown commands
   route to installed archives rather than producing a usage error. ---------- *)

let print_archive_help name =
  let entries = Archive_store.load_registry () in
  match List.assoc_opt name entries with
  | None ->
    Printf.eprintf "error: '%s' is not an installed archive\n%!" name;
    Printf.eprintf "hint:  forge install %s  to install it\n%!" name;
    exit 1
  | Some entry ->
    let archive_root = match entry.Archive_store.source with
      | Archive_store.Path p -> p
      | _ -> Archive_store.archive_dir name
    in
    let source_str = match entry.Archive_store.source with
      | Archive_store.Registry { version } -> Printf.sprintf "registry (%s)" version
      | Archive_store.Git { url; git_ref; rev } ->
        let ref_str = match git_ref with Some r -> r | None -> "default" in
        let rev_str = match rev with
          | Some r -> Printf.sprintf " @%s" (String.sub r 0 (min 8 (String.length r)))
          | None -> ""
        in
        Printf.sprintf "git %s (%s%s)" url ref_str rev_str
      | Archive_store.Path p -> Printf.sprintf "path %s" p
    in
    Printf.printf "Archive: %s\n" name;
    Printf.printf "Source:  %s\n" source_str;
    let tasks = Archive_store.list_archive_tasks archive_root in
    if tasks = [] then
      Printf.printf "Tasks:   (none declared)\n%!"
    else begin
      Printf.printf "Tasks:\n%!";
      List.iter (fun (cmd, _) ->
          Printf.printf "  forge %-30s\n%!" cmd
        ) tasks
    end

let () =
  if Array.length Sys.argv >= 2 then begin
    let cmd = Sys.argv.(1) in
    (* "forge help <archive>" — show tasks for a named archive *)
    if cmd = "help" && Array.length Sys.argv >= 3 then begin
      let topic = Sys.argv.(2) in
      let entries = Archive_store.load_registry () in
      if List.mem_assoc topic entries then begin
        print_archive_help topic;
        exit 0
      end
      (* else fall through to cmdliner's built-in help *)
    end;
    (* Intercept dotted namespace commands like "bastion.new" *)
    if String.length cmd > 0 && cmd.[0] <> '-' && String.contains cmd '.' then begin
      let args =
        if Array.length Sys.argv > 2 then
          Array.to_list (Array.sub Sys.argv 2 (Array.length Sys.argv - 2))
        else []
      in
      (match Archive_store.find_task cmd with
       | Some (task_file, lib_paths) ->
         exit (Archive_store.run_task task_file lib_paths args)
       | None ->
         let ns = String.sub cmd 0 (String.index cmd '.') in
         Printf.eprintf "error: unknown command '%s'\n%!" cmd;
         Printf.eprintf "hint:  install the %s archive with: forge install %s\n%!" ns ns;
         exit 1)
    end
  end

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
  let compiled =
    Arg.(value & flag & info ["compiled"]
           ~doc:"Compile via the LLVM pipeline first, then execute the resulting binary")
  in
  let run d c = handle (Cmd_run.run ~dump_phases:d ~compiled:c ()) in
  Cmd.v (Cmd.info "run" ~doc:"Build and run the current project")
    Term.(const run $ dump_phases $ compiled)

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

(* ------------------------------------------------------------------- forge add *)

let add_cmd =
  let name =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"NAME" ~doc:"Dependency name")
  in
  let git =
    Arg.(value & opt (some string) None &
         info ["git"] ~docv:"URL" ~doc:"Git repository URL")
  in
  let tag =
    Arg.(value & opt (some string) None &
         info ["tag"] ~docv:"TAG" ~doc:"Git tag (e.g. v1.0)")
  in
  let branch =
    Arg.(value & opt (some string) None &
         info ["branch"] ~docv:"BRANCH" ~doc:"Git branch (default: main)")
  in
  let rev =
    Arg.(value & opt (some string) None &
         info ["rev"] ~docv:"REV" ~doc:"Git revision (exact commit)")
  in
  let path =
    Arg.(value & opt (some string) None &
         info ["path"] ~docv:"PATH" ~doc:"Local filesystem path")
  in
  let dev =
    Arg.(value & flag & info ["dev"] ~doc:"Add as a dev dependency")
  in
  let force =
    Arg.(value & flag & info ["force"] ~doc:"Overwrite if dependency already exists")
  in
  let run n g t b r p d f =
    handle (Cmd_add.run ~name:n ~git:g ~tag:t ~branch:b ~rev:r ~path:p ~dev:d ~force:f ())
  in
  Cmd.v (Cmd.info "add" ~doc:"Add a dependency to forge.toml")
    Term.(const run $ name $ git $ tag $ branch $ rev $ path $ dev $ force)

(* ------------------------------------------------------------------ forge help *)

let help_cmd =
  let topic =
    Arg.(value & pos 0 (some string) None &
         info [] ~docv:"COMMAND" ~doc:"Command to show help for")
  in
  let run t =
    match t with
    | None ->
      (* Print installed archives after the standard help *)
      let entries = Archive_store.load_registry () in
      if entries <> [] then begin
        Printf.printf "\nInstalled archives (use 'forge help <name>' for task list):\n";
        List.iter (fun (name, entry) ->
            let root = match entry.Archive_store.source with
              | Archive_store.Path p -> p
              | _ -> Archive_store.archive_dir name
            in
            let tasks = Archive_store.list_archive_tasks root in
            let task_names = List.map fst tasks in
            Printf.printf "  %-12s  %s\n%!" name (String.concat ", " task_names)
          ) entries
      end;
      `Help (`Auto, None)
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

(* -------------------------------------------------------------- forge install *)

let install_cmd =
  let arg =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"NAME[@REF]"
           ~doc:"Archive to install. REF may be a version, local path, or git URL (with optional #branch).")
  in
  let force =
    Arg.(value & flag & info ["force"] ~doc:"Reinstall even if already installed")
  in
  let no_verify =
    Arg.(value & flag & info ["no-verify"] ~doc:"Skip checksum verification")
  in
  let run a f v = handle (Cmd_archive.run_install a ~force:f ~no_verify:v) in
  Cmd.v (Cmd.info "install" ~doc:"Install a forge archive globally")
    Term.(const run $ arg $ force $ no_verify)

(* ------------------------------------------------------------ forge uninstall *)

let uninstall_cmd =
  let name =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"NAME" ~doc:"Archive to remove")
  in
  let run n = handle (Cmd_archive.run_uninstall n) in
  Cmd.v (Cmd.info "uninstall" ~doc:"Remove a globally installed archive")
    Term.(const run $ name)

(* ------------------------------------------------------------- forge archives *)

let archives_cmd =
  Cmd.v (Cmd.info "archives" ~doc:"List installed forge archives")
    Term.(const (fun () -> Cmd_archive.run_list ()) $ const ())

(* --------------------------------------------------------------- forge update *)

let update_cmd =
  let name =
    Arg.(value & pos 0 (some string) None &
         info [] ~docv:"NAME" ~doc:"Archive to update (omit to update all)")
  in
  let run n = handle (Cmd_archive.run_update n) in
  Cmd.v (Cmd.info "update" ~doc:"Update one or all installed archives")
    Term.(const run $ name)

(* --------------------------------------------------------------- forge verify *)

let verify_cmd =
  let name =
    Arg.(value & pos 0 (some string) None &
         info [] ~docv:"NAME" ~doc:"Archive to verify (omit to verify all)")
  in
  let run n = handle (Cmd_archive.run_verify n) in
  Cmd.v (Cmd.info "verify" ~doc:"Verify integrity of installed archives")
    Term.(const run $ name)

(* ------------------------------------------------------------------ forge init *)

let init_cmd =
  Cmd.v (Cmd.info "init" ~doc:"Initialize a forge.toml in the current directory")
    Term.(const (fun () -> handle (Cmd_init.run ())) $ const ())

(* --------------------------------------------------------------- forge compile *)

let compile_cmd =
  let file =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"FILE" ~doc:"Path to the .march source file to compile")
  in
  let run f = handle (Cmd_compile.run ~file:f ()) in
  Cmd.v (Cmd.info "compile"
           ~doc:"Compile a single .march file and dump all compiler phases to trace/phases/phases.json")
    Term.(const run $ file)

(* ------------------------------------------------------------------- forge doc *)

let doc_cmd =
  let output =
    Arg.(value & opt string "doc" &
         info ["o"; "output"] ~docv:"DIR"
           ~doc:"Output directory for generated HTML (default: doc)")
  in
  let private_ =
    Arg.(value & flag & info ["private"] ~doc:"Include private functions in output")
  in
  let stdlib_only =
    Arg.(value & flag & info ["stdlib"] ~doc:"Document stdlib only (skip project sources)")
  in
  let run o p s = handle (Cmd_doc.run ~output_dir:o ~include_private:p ~stdlib_only:s ()) in
  Cmd.v (Cmd.info "doc" ~doc:"Generate HTML documentation from March source files")
    Term.(const run $ output $ private_ $ stdlib_only)

(* --------------------------------------------------------------- forge notebook *)

let notebook_serve_cmd =
  let input =
    Arg.(value & pos 0 (some string) None &
         info [] ~docv:"FILE.scrollmd"
           ~doc:"Notebook file to open or create. \
                 Omit to start a fresh temporary notebook.")
  in
  let port =
    Arg.(value & opt int 4040 &
         info ["port"; "p"] ~docv:"PORT"
           ~doc:"Port to serve on (default: 4040)")
  in
  let no_open =
    Arg.(value & flag &
         info ["no-open"]
           ~doc:"Do not automatically open the browser")
  in
  let run i p n = handle (Cmd_notebook.run_serve ~input:i ~port:p ~no_open:n ()) in
  Cmd.v (Cmd.info "serve"
           ~doc:"Start a live notebook server (FILE.scrollmd optional — \
                 creates a fresh notebook if omitted)")
    Term.(const run $ input $ port $ no_open)

let notebook_cmd =
  let input =
    Arg.(value & pos 0 (some string) None &
         info [] ~docv:"FILE.scrollmd" ~doc:"Path to the .scrollmd notebook file")
  in
  let output =
    Arg.(value & opt (some string) None &
         info ["o"; "output"] ~docv:"FILE.html"
           ~doc:"Output HTML path (default: <input>.html)")
  in
  let serve_flag =
    Arg.(value & flag & info ["serve"; "s"] ~doc:"Start the live server instead of rendering")
  in
  let port =
    Arg.(value & opt int 4040 &
         info ["port"; "p"] ~docv:"PORT" ~doc:"Port for --serve (default: 4040)")
  in
  let no_open =
    Arg.(value & flag & info ["no-open"] ~doc:"Do not automatically open the browser (with --serve)")
  in
  let run i o s p n =
    if s then handle (Cmd_notebook.run_serve ~input:i ~port:p ~no_open:n ())
    else match i with
      | None ->
        (* No file and no --serve: default to serve mode *)
        handle (Cmd_notebook.run_serve ~input:None ~port:p ~no_open:n ())
      | Some f -> handle (Cmd_notebook.run_render ~input:f ~output:o ())
  in
  let render_term = Term.(const run $ input $ output $ serve_flag $ port $ no_open) in
  Cmd.group ~default:render_term
    (Cmd.info "notebook"
       ~doc:"Open or create a March notebook. \
             With no arguments, starts a live notebook server (like Livebook). \
             With FILE.scrollmd, renders to HTML or starts the live server with --serve.")
    [notebook_serve_cmd]

(* ------------------------------------------------------------------ forge phases *)

let phases_cmd =
  let port =
    Arg.(value & opt int 7777 &
         info ["port"; "p"] ~docv:"PORT" ~doc:"Port to serve on (default: 7777)")
  in
  let run p = Cmd_phases.run ~port:p () in
  Cmd.v (Cmd.info "phases"
           ~doc:"Serve the phase viewer for --dump-phases output at http://localhost:PORT")
    Term.(const run $ port)

(* --------------------------------------------------------------------- root *)

let default_term =
  Term.(const (fun () ->
    match Cmd_build.build ~release:false () with
    | Ok binary -> Printf.printf "built: %s\n%!" binary
    | Error m   -> Printf.eprintf "error: %s\n%!" m; exit 1
  ) $ const ())

let () =
  let cmds =
    [ new_cmd; init_cmd; build_cmd; run_cmd; compile_cmd; test_cmd; format_cmd;
      interactive_cmd; i_cmd; clean_cmd; deps_cmd; add_cmd; publish_cmd;
      install_cmd; uninstall_cmd; archives_cmd; update_cmd; verify_cmd;
      search_cmd; notebook_cmd; doc_cmd; phases_cmd; help_cmd ]
  in
  let main =
    Cmd.group ~default:default_term
      (Cmd.info "forge" ~version:"0.1.0"
         ~doc:"The March package manager and build tool")
      cmds
  in
  exit (Cmd.eval main)
