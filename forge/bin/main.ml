(** forge — the March package manager and build tool *)

open Cmdliner
open March_forge

let handle = function
  | Ok ()   -> ()
  | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1

(* Same contract as [handle] for commands whose success carries a summary line. *)
let handle_msg = function
  | Ok msg  -> Printf.printf "%s\n%!" msg
  | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1

let known_builtin_names =
  [ "new"; "init"; "build"; "check"; "run"; "compile"; "test"; "lint"; "refactor"; "format";
    "refine"; "interactive"; "i"; "clean"; "deps"; "add"; "publish"; "retire";
    "install"; "uninstall"; "archives"; "update"; "verify";
    "toolchain"; "upgrade"; "watch"; "bench"; "version"; "release";
    "licenses"; "tree"; "outdated"; "why"; "search"; "notebook"; "doc"; "phases"; "cap"; "audit"; "ffi"; "fix"; "help";
    "completions"; "deploy"; "hot-reload" ]

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
      List.iter (fun (cmd, _, _) ->
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
    end;
    (* Intercept external forge-<cmd> binaries on PATH *)
    if cmd.[0] <> '-' then begin
      let path_lookup name =
        let path = try Sys.getenv "PATH" with Not_found -> "" in
        let dirs = String.split_on_char ':' path in
        List.find_map (fun dir ->
            let full = Filename.concat dir name in
            if Sys.file_exists full then Some full else None
          ) dirs
      in
      match Cli_ext.external_subcommand
              ~known:known_builtin_names ~argv1:cmd ~path_lookup with
      | Some exe ->
        let rest = Array.sub Sys.argv 2 (max 0 (Array.length Sys.argv - 2)) in
        let argv = Array.append [| exe |] rest in
        Unix.execv exe argv
      | None -> ()
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

let workspace_package_flag =
  Arg.(value & opt (some string) None &
       info ["p"; "package"] ~docv:"NAME"
         ~doc:"In a workspace, build only the member named NAME.")

let build_cmd =
  let release =
    Arg.(value & flag & info ["release"] ~doc:"Build in release mode")
  in
  let dump_phases =
    Arg.(value & flag & info ["dump-phases"]
           ~doc:"Serialize each compiler IR stage to march-phases/phases.json")
  in
  let frozen =
    Arg.(value & flag & info ["frozen"; "locked"]
           ~doc:"Fail (don't re-resolve) if forge.lock is out of date with forge.toml.")
  in
  let target =
    Arg.(value & opt (some string) None &
         info ["target"] ~docv:"TARGET"
           ~doc:"Compilation target: native (default), linux/amd64, linux/arm64, js, \
                 wasm32-unknown-unknown, wasm64-wasi, wasm32-wasi. The $(b,linux/*) targets \
                 cross-compile a dynamic-glibc Linux binary via $(b,zig cc). \
                 Use $(b,js) to emit an ES module (.mjs) for browsers and Node.js.")
  in
  let run r d f pkg tgt =
    let cwd = Sys.getcwd () in
    match Workspace.find_root cwd with
    | Some root when root = cwd ->
      let members = Workspace.members_from_root root in
      if members <> [] then
        (match Workspace.run_for_members ~root ~members ~package:pkg
                 (fun () ->
                    match Cmd_build.build ~release:r ~dump_phases:d ~frozen:f ?target:tgt () with
                    | Ok binary -> Printf.printf "built: %s\n%!" binary; Ok ()
                    | Error m   -> Error m) with
         | Ok ()   -> ()
         | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1)
      else begin
        match Cmd_build.build ~release:r ~dump_phases:d ~frozen:f ?target:tgt () with
        | Ok binary -> Printf.printf "built: %s\n%!" binary
        | Error m   -> Printf.eprintf "error: %s\n%!" m; exit 1
      end
    | _ ->
      match Cmd_build.build ~release:r ~dump_phases:d ~frozen:f ?target:tgt () with
      | Ok binary -> Printf.printf "built: %s\n%!" binary
      | Error m   -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "build" ~doc:"Build the current project")
    Term.(const run $ release $ dump_phases $ frozen $ workspace_package_flag $ target)

(* ----------------------------------------------------------------- forge check *)

let check_cmd =
  let run () =
    match Cmd_check.check () with
    | Ok msg  -> Printf.printf "%s\n%!" msg
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "check"
           ~doc:"Typecheck every .march file in the project without producing a binary")
    Term.(const run $ const ())

(* ------------------------------------------------------------------- forge fix *)

let fix_cmd =
  let dry =
    Arg.(value & flag & info ["dry-run"; "n"]
           ~doc:"Show what would change without writing any files") in
  let run d =
    match Cmd_fix.run ~dry_run:d () with
    | Ok msg  -> Printf.printf "%s\n%!" msg
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "fix"
           ~doc:"Apply safe auto-fixes for compiler diagnostics (missing needs, unused params, redundant arms)")
    Term.(const run $ dry)

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
  let target =
    Arg.(value & opt (some string) None &
         info ["target"] ~docv:"TARGET"
           ~doc:"Compilation target when using $(b,--compiled): native (default) or js. \
                 With $(b,js), builds an .mjs module then runs it with node.")
  in
  let files =
    Arg.(value & pos_all string [] &
         info [] ~docv:"FILE"
           ~doc:"A single .march file to run, followed by any arguments for the \
                 program itself (separate them with $(b,--)). Omit FILE to run \
                 the project's entry point. A file named here still sees the \
                 surrounding project's modules and FFI shims when there is one.")
  in
  let run d c tgt fs =
    (* The first positional is always the FILE; everything after it belongs to
       the program.  There is deliberately no spelling that passes arguments to
       the PROJECT entry: cmdliner records the positionals but not where `--`
       sat, so `forge run -- a b` cannot be told apart from a file `a` with one
       argument, and guessing (e.g. "it's a file if it exists") is worse than
       not offering it. *)
    let (file, args) = match fs with
      | []          -> (None, [])
      | f :: rest   -> (Some f, rest)
    in
    handle (Cmd_run.run ~dump_phases:d ~compiled:c ?target:tgt ?file ~args ())
  in
  Cmd.v (Cmd.info "run" ~doc:"Build and run the current project, or a single file")
    Term.(const run $ dump_phases $ compiled $ target $ files)

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
  let seed =
    Arg.(value & opt string "" &
         info ["seed"] ~docv:"SEED" ~doc:"Deterministic seed for property tests (see stdlib/check.march)")
  in
  let skip_props =
    Arg.(value & flag & info ["skip-properties"] ~doc:"Skip property-based tests (Check.all)")
  in
  let release =
    Arg.(value & flag & info ["release"]
           ~doc:"Compile test binary with -O2 instead of the default -O0 (slower build, faster test runtime)")
  in
  let files =
    Arg.(value & pos_all string [] &
         info [] ~docv:"FILE" ~doc:"Test files to run (default: all test files under test/)")
  in
  let run v c f s sp r fs pkg =
    let cwd = Sys.getcwd () in
    match Workspace.find_root cwd with
    | Some root when root = cwd ->
      let members = Workspace.members_from_root root in
      if members <> [] then
        handle (Workspace.run_for_members ~root ~members ~package:pkg
                  (fun () -> Cmd_test.run ~verbose:v ~coverage:c ~filter:f ~seed:s ~skip_properties:sp ~release:r ~files:fs ()))
      else
        handle (Cmd_test.run ~verbose:v ~coverage:c ~filter:f ~seed:s ~skip_properties:sp ~release:r ~files:fs ())
    | _ ->
      handle (Cmd_test.run ~verbose:v ~coverage:c ~filter:f ~seed:s ~skip_properties:sp ~release:r ~files:fs ())
  in
  Cmd.v (Cmd.info "test" ~doc:"Run the test suite")
    Term.(const run $ verbose $ coverage $ filter $ seed $ skip_props $ release $ files $ workspace_package_flag)

(* ------------------------------------------------------------------ forge lint *)

let lint_cmd =
  let strict =
    Arg.(value & flag &
         info ["strict"] ~doc:"Treat warnings as errors; exit 1 on any warning or error")
  in
  let all =
    Arg.(value & flag &
         info ["all"] ~doc:"Also report hint-severity findings (off by default)")
  in
  let run s a pkg =
    let cwd = Sys.getcwd () in
    match Workspace.find_root cwd with
    | Some root when root = cwd ->
      let members = Workspace.members_from_root root in
      if members <> [] then
        handle (Workspace.run_for_members ~root ~members ~package:pkg
                  (fun () -> Cmd_lint.run ~strict:s ~all:a ()))
      else
        handle (Cmd_lint.run ~strict:s ~all:a ())
    | _ ->
      handle (Cmd_lint.run ~strict:s ~all:a ())
  in
  Cmd.v (Cmd.info "lint" ~doc:"Run the coding-standard rule checker")
    Term.(const run $ strict $ all $ workspace_package_flag)

(* ---------------------------------------------------------------- forge refine *)

let refine_cmd =
  let target =
    Arg.(value & pos 0 string "" & info [] ~docv:"FN"
           ~doc:"Function to refine; a bare or qualified name (Module.fn)") in
  let all =
    Arg.(value & flag & info ["all"]
           ~doc:"Sweep every function in the project instead of one named function") in
  let apply =
    Arg.(value & flag & info ["apply"]
           ~doc:"Write the proposed annotations into the source (default: print only)") in
  let budget =
    Arg.(value & opt int Cmd_refine.default_budget &
         info ["budget"] ~docv:"N"
           ~doc:"Cap the hypothesis re-checks the inference may spend per function") in
  let fixpoint =
    Arg.(value & flag & info ["fixpoint"]
           ~doc:"With --apply, repeat until a round applies nothing. A contract only \
                 becomes visible to a caller once the callee carries it, so each round \
                 propagates one call hop.") in
  let postconditions =
    Arg.(value & flag & info ["postconditions"]
           ~doc:"Propose RETURN refinements instead: the contract that lets a \
                 function's CALLERS discharge their obligations. Preconditions \
                 propagate up the call graph; postconditions propagate down.") in
  let run t a ap fx po b =
    if t = "" && not a then begin
      Printf.eprintf "error: forge refine needs a function name, or --all\n%!";
      exit 1
    end;
    handle_msg (Cmd_refine.run ~all:a ~apply:ap ~fixpoint:fx ~postconditions:po ~budget:b ~target:t ())
  in
  Cmd.v
    (Cmd.info "refine"
       ~doc:"Suggest a refinement type for a function's parameters"
       ~man:[ `S Manpage.s_description;
              `P "Proposes the parameter refinement that discharges the \
                  refinement obligations a function's body leaves unproven. \
                  A suggestion is only made when the checker itself proves the \
                  obligations under it, so `march check` after --apply agrees \
                  with what was printed." ])
    Term.(const run $ target $ all $ apply $ fixpoint $ postconditions $ budget)

(* -------------------------------------------------------------- forge refactor *)

let refactor_cmd =
  let dry =
    Arg.(value & flag &
         info ["dry-run"; "n"] ~doc:"Preview changes without writing any files") in
  let kind =
    Arg.(value & opt string "any" &
         info ["kind"] ~docv:"K"
           ~doc:"Restrict rename to one category: fn, type, ctor, module, field, var, or any") in
  let rename =
    let old_ = Arg.(required & pos 0 (some string) None & info [] ~docv:"OLD") in
    let new_ = Arg.(required & pos 1 (some string) None & info [] ~docv:"NEW") in
    let pat =
      Arg.(value & flag &
           info ["pattern"; "p"] ~doc:"Treat OLD as a regex; NEW may use \\1 backreferences") in
    let run o n k p d = handle (Cmd_refactor.rename ~old_name:o ~new_name:n ~kind:k ~pattern:p ~dry_run:d ()) in
    Cmd.v (Cmd.info "rename" ~doc:"Rename a symbol and all its references project-wide")
      Term.(const run $ old_ $ new_ $ kind $ pat $ dry)
  in
  let move =
    let decl = Arg.(required & pos 0 (some string) None & info [] ~docv:"DECL") in
    let dest = Arg.(required & pos 1 (some string) None & info [] ~docv:"DEST.march") in
    let run dc ds d = handle (Cmd_refactor.move ~decl:dc ~dest:ds ~dry_run:d ()) in
    Cmd.v (Cmd.info "move" ~doc:"Move a top-level declaration to another file")
      Term.(const run $ decl $ dest $ dry)
  in
  let replace =
    let p = Arg.(required & pos 0 (some string) None & info [] ~docv:"PATTERN") in
    let t = Arg.(required & pos 1 (some string) None & info [] ~docv:"TEMPLATE") in
    let run pp tt d = handle (Cmd_refactor.replace ~pat:pp ~tmpl:tt ~dry_run:d ()) in
    Cmd.v (Cmd.info "replace"
             ~doc:"Structural find-and-replace; PATTERN/TEMPLATE use \\$metavariables, e.g. 'f(\\$a, \\$b)' 'g(\\$b, \\$a)'")
      Term.(const run $ p $ t $ dry)
  in
  let fix =
    let run d = handle (Cmd_refactor.fix ~dry_run:d ()) in
    Cmd.v (Cmd.info "fix" ~doc:"Apply safe naming-convention fixes (snake_case functions) project-wide")
      Term.(const run $ dry)
  in
  let bundle =
    let fn = Arg.(required & pos 0 (some string) None & info [] ~docv:"FN") in
    let record =
      Arg.(value & opt string "" &
           info ["record"; "r"] ~docv:"NAME"
             ~doc:"Name for the generated record type (default: <Fn>Args)") in
    let run f r d = handle (Cmd_refactor.bundle ~fn_name:f ~record:r ~dry_run:d ()) in
    Cmd.v (Cmd.info "bundle"
             ~doc:"Introduce a parameter object: bundle FN's parameters into a generated record, rewriting the function and all call sites")
      Term.(const run $ fn $ record $ dry)
  in
  Cmd.group (Cmd.info "refactor" ~doc:"Project-wide, parser-based refactorings")
    [ rename; move; replace; fix; bundle ]

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
    Arg.(value & flag & info ["dev"] ~doc:"Add to [dev-deps] (dev + test)")
  in
  let dev_only =
    Arg.(value & flag & info ["dev-only"] ~doc:"Add to [dev-only-deps] (dev only, not test)")
  in
  let test_dep =
    Arg.(value & flag & info ["test"] ~doc:"Add to [test-deps] (test only, not dev)")
  in
  let force =
    Arg.(value & flag & info ["force"] ~doc:"Overwrite if dependency already exists")
  in
  let run n g t b r p d do_ td f =
    handle (Cmd_add.run ~name:n ~git:g ~tag:t ~branch:b ~rev:r ~path:p
              ~dev:d ~dev_only:do_ ~test_dep:td ~force:f ())
  in
  Cmd.v (Cmd.info "add" ~doc:"Add a dependency to forge.toml")
    Term.(const run $ name $ git $ tag $ branch $ rev $ path $ dev $ dev_only $ test_dep $ force)

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
            let task_names = List.map (fun (cmd, _, _) -> cmd) tasks in
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
  let callers =
    Arg.(value & opt string "" &
         info ["callers"] ~docv:"NAME" ~doc:"Find call sites that reference NAME (reverse-reference search)")
  in
  let limit =
    Arg.(value & opt int 20 &
         info ["limit"; "n"] ~docv:"N" ~doc:"Maximum number of results (default 20)")
  in
  let as_json =
    Arg.(value & flag & info ["json"] ~doc:"Output results as JSON (for tooling)")
  in
  let plain =
    Arg.(value & flag & info ["plain"] ~doc:"Plain text output, no colors (for piping or LLM use)")
  in
  let rebuild =
    Arg.(value & flag & info ["rebuild"] ~doc:"Rebuild the search index before searching")
  in
  let run q t d c n j p r =
    Cmd_search.run ~query:q ~type_sig:t ~doc_query:d ~callers:c ~limit:n ~as_json:j ~plain:p ~rebuild:r ()
  in
  Cmd.v
    (Cmd.info "search"
       ~doc:"Search stdlib and dependencies for functions, types, and constructors")
    Term.(const run $ query $ type_sig $ doc_query $ callers $ limit $ as_json $ plain $ rebuild)

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
  let registry =
    Arg.(value & opt (some string) None &
         info ["registry"] ~docv:"URL"
           ~doc:"Registry base URL (default: $(b,FORGE_REGISTRY) env var, or https://forgepm.org)")
  in
  let insecure =
    Arg.(value & flag & info ["insecure"]
           ~doc:"Allow a http:// registry (local dev only)")
  in
  let run o d r ins = handle (Cmd_publish.run ~old_source_dir:o ~dry_run:d ~registry:r ~insecure:ins ()) in
  Cmd.v (Cmd.info "publish" ~doc:"Validate and publish the current package")
    Term.(const run $ old_source $ dry_run $ registry $ insecure)

(* ---------------------------------------------------------------- forge retire *)

let retire_cmd =
  let version_arg =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"VERSION" ~doc:"Version to retire, e.g. 1.2.3")
  in
  let reason =
    Arg.(value & opt string "" &
         info ["reason"] ~docv:"TEXT" ~doc:"Retirement reason (stored on the registry)")
  in
  let registry =
    Arg.(value & opt (some string) None &
         info ["registry"] ~docv:"URL"
           ~doc:"Registry base URL (default: $(b,FORGE_REGISTRY) env var, or https://forgepm.org)")
  in
  let insecure =
    Arg.(value & flag & info ["insecure"]
           ~doc:"Allow a http:// registry (local dev only)")
  in
  let run v r reg ins = handle (Cmd_retire.run ~version:v ~reason:r ~registry:reg ~insecure:ins ()) in
  Cmd.v (Cmd.info "retire" ~doc:"Retire a published version of the current package")
    Term.(const run $ version_arg $ reason $ registry $ insecure)

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

(* ------------------------------------------------------------- forge toolchain *)

let toolchain_cmd =
  let install_sub =
    let version =
      Arg.(value & pos 0 (some string) None &
           info [] ~docv:"VERSION"
             ~doc:"Release to install: a tag ($(b,v0.1.0), $(b,nightly-YYYYMMDD)), \
                   $(b,nightly) for the latest nightly, or omit for the latest stable.")
    in
    let run v = handle (Toolchain.install v) in
    Cmd.v (Cmd.info "install" ~doc:"Download and install a March toolchain")
      Term.(const run $ version)
  in
  let use_sub =
    let version =
      Arg.(required & pos 0 (some string) None &
           info [] ~docv:"VERSION" ~doc:"Installed toolchain to activate")
    in
    let run v = handle (Toolchain.use v) in
    Cmd.v (Cmd.info "use" ~doc:"Switch the active March toolchain")
      Term.(const run $ version)
  in
  let list_sub =
    let remote =
      Arg.(value & flag &
           info ["remote"] ~doc:"List versions available to install from GitHub releases")
    in
    let run r = handle (if r then Toolchain.list_remote () else Toolchain.list ()) in
    Cmd.v (Cmd.info "list" ~doc:"List installed March toolchains ($(b,--remote): installable versions)")
      Term.(const run $ remote)
  in
  let uninstall_sub =
    let version =
      Arg.(required & pos 0 (some string) None &
           info [] ~docv:"VERSION" ~doc:"Toolchain to remove")
    in
    let run v = handle (Toolchain.uninstall v) in
    Cmd.v (Cmd.info "uninstall" ~doc:"Remove an installed March toolchain")
      Term.(const run $ version)
  in
  let pin_sub =
    let version =
      Arg.(required & pos 0 (some string) None &
           info [] ~docv:"VERSION" ~doc:"Version to pin for this project (writes .march-version)")
    in
    let run v = handle (Toolchain.pin v) in
    Cmd.v (Cmd.info "pin" ~doc:"Pin a March version for this project via .march-version")
      Term.(const run $ version)
  in
  let which_sub =
    Cmd.v (Cmd.info "which" ~doc:"Show which toolchain a build here resolves to")
      Term.(const (fun () -> handle (Toolchain.which ())) $ const ())
  in
  Cmd.group (Cmd.info "toolchain" ~doc:"Manage installed March compiler versions")
    [ install_sub; use_sub; list_sub; uninstall_sub; pin_sub; which_sub ]

(* ------------------------------------------------------------- forge upgrade *)

let upgrade_cmd =
  Cmd.v (Cmd.info "upgrade" ~doc:"Install the latest March and make it the active toolchain")
    Term.(const (fun () -> handle (Toolchain.upgrade ())) $ const ())

(* ------------------------------------------------------------- forge watch *)

let watch_cmd =
  let action =
    Arg.(value & pos 0 string "build" &
         info [] ~docv:"ACTION" ~doc:"What to rerun on change: $(b,build), $(b,test), or $(b,run).")
  in
  let interval =
    Arg.(value & opt int 300 & info ["interval"] ~docv:"MS" ~doc:"Poll interval in milliseconds.")
  in
  let clear =
    Arg.(value & flag & info ["clear"] ~doc:"Clear the screen before each run.")
  in
  let target =
    Arg.(value & opt (some string) None &
         info ["target"] ~docv:"TARGET"
           ~doc:"Compilation target: native (default), js, wasm32-unknown-unknown. \
                 Use $(b,js) to rebuild an ES module (.mjs) on each change.")
  in
  let run a i c tgt = handle (Cmd_watch.run ~action:a ~interval:i ~clear:c ?target:tgt ()) in
  Cmd.v (Cmd.info "watch" ~doc:"Rebuild/retest/rerun on source changes")
    Term.(const run $ action $ interval $ clear $ target)

(* ---------------------------------------------------------- forge licenses *)

let licenses_cmd =
  let json = Arg.(value & flag & info ["json"] ~doc:"Emit as JSON.") in
  let strict = Arg.(value & flag & info ["strict"] ~doc:"Exit non-zero if any dependency has no license.") in
  let run j s = handle (Cmd_licenses.run ~json:j ~strict:s ()) in
  Cmd.v (Cmd.info "licenses" ~doc:"List each dependency and its declared license")
    Term.(const run $ json $ strict)

(* --------------------------------------------------- forge version / release *)

let version_cmd =
  let spec =
    Arg.(value & pos 0 string "" &
         info [] ~docv:"BUMP" ~doc:"$(b,patch), $(b,minor), $(b,major), or an explicit $(b,X.Y.Z); omit to print the current version.")
  in
  let tag = Arg.(value & flag & info ["tag"] ~doc:"Commit the bump and create a git tag $(b,vX.Y.Z).") in
  let run s t = handle (Cmd_version.run ~spec:s ~tag:t ()) in
  Cmd.v (Cmd.info "version" ~doc:"Print or bump the project version")
    Term.(const run $ spec $ tag)

let release_cmd =
  let bump =
    Arg.(value & opt string "patch" &
         info ["bump"] ~docv:"KIND" ~doc:"Version bump for the release: patch|minor|major.")
  in
  let run b = handle (Cmd_release.run ~bump:b ()) in
  Cmd.v (Cmd.info "release" ~doc:"Guarded release: clean tree -> build -> test -> bump + tag")
    Term.(const run $ bump)

(* ------------------------------------------------------------- forge bench *)

let bench_cmd =
  let name =
    Arg.(value & pos 0 string "" &
         info [] ~docv:"NAME" ~doc:"Run only benchmarks whose name contains this substring.")
  in
  let json = Arg.(value & flag & info ["json"] ~doc:"Emit timings as JSON.") in
  let run n j = handle (Cmd_bench.run ~filter:n ~json:j ()) in
  Cmd.v (Cmd.info "bench" ~doc:"Compile and run benchmarks under bench/")
    Term.(const run $ name $ json)

(* --------------------------------------------------------- forge tree / why *)

let tree_cmd =
  Cmd.v (Cmd.info "tree" ~doc:"Print the project dependency tree")
    Term.(const (fun () -> handle (Cmd_tree.run_tree ())) $ const ())

let outdated_cmd =
  Cmd.v (Cmd.info "outdated"
           ~doc:"Show dependencies that have a newer version available in the registry")
    Term.(const (fun () -> handle (Cmd_outdated.run ())) $ const ())

let why_cmd =
  let name =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"PACKAGE" ~doc:"Dependency to explain")
  in
  let run n = handle (Cmd_tree.run_why n) in
  Cmd.v (Cmd.info "why" ~doc:"Show why a package is in the dependency graph")
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

(* --------------------------------------------------------------- forge cap *)

let cap_query_cmd =
  let dir =
    Arg.(value & opt (some string) None &
         info ["dir"] ~docv:"DIR"
           ~doc:"Root directory to scan (defaults to project root).")
  in
  let run d =
    match Cmd_cap.query ~dir:d () with
    | Ok () -> ()
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "query"
           ~doc:"Print a capability and typestate summary for all .march files")
    Term.(const run $ dir)

let cap_coverage_cmd =
  let dir =
    Arg.(value & opt (some string) None &
         info ["dir"] ~docv:"DIR"
           ~doc:"Root directory to scan (defaults to project root).")
  in
  let run d =
    match Cmd_cap.coverage ~dir:d () with
    | Ok () -> ()
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "coverage"
           ~doc:"Report which declared capabilities have test coverage (static analysis)")
    Term.(const run $ dir)

let cap_inspect_cmd =
  let bin =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"BINARY"
           ~doc:"Compiled March executable to audit.")
  in
  let json =
    Arg.(value & flag &
         info ["json"] ~doc:"Machine-readable output (coverage is always included).")
  in
  let deny =
    Arg.(value & opt_all string [] &
         info ["deny"] ~docv:"CAP"
           ~doc:"Fail if the binary holds CAP or anything it subsumes (repeatable).")
  in
  let allow_only =
    Arg.(value & opt (some (list string)) None &
         info ["allow-only"] ~docv:"CAPS"
           ~doc:"Fail if the binary holds any capability outside this comma-separated set.")
  in
  let allow_foreign =
    Arg.(value & flag &
         info ["allow-foreign"]
           ~doc:"Let the gate pass on a binary containing foreign (FFI) code. \
                 Without this, --deny/--allow-only fail closed on any binary \
                 whose coverage is not full.")
  in
  let strict =
    Arg.(value & flag &
         info ["strict"]
           ~doc:"Re-check the capability ceiling from the artifact: fail if \
                 any module uses a capability it did not declare. Fails \
                 closed on a binary that carries no attribution.")
  in
  let run bin json deny allow_only allow_foreign strict =
    match Cmd_cap.inspect ~bin ~json ~deny ~allow_only ~allow_foreign ~strict () with
    | Ok () -> ()
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "inspect"
           ~doc:"List the capabilities of a compiled March executable")
    Term.(const run $ bin $ json $ deny $ allow_only $ allow_foreign $ strict)

let cap_run_cmd =
  let bin =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"BINARY" ~doc:"Compiled March executable to run.")
  in
  let args =
    Arg.(value & pos_right 0 string [] &
         info [] ~docv:"ARGS" ~doc:"Arguments passed to the program.")
  in
  let allow_only =
    Arg.(value & opt (some (list string)) None &
         info ["allow-only"] ~docv:"CAPS"
           ~doc:"Grant only these capabilities, overriding the binary's own \
                 claim. Use this for untrusted code: a policy derived from the \
                 binary defeats under-claiming only, since a hostile binary is \
                 free to over-claim.")
  in
  let run bin args allow_only =
    match Cmd_cap.cap_run ~bin ~args ~allow_only () with
    | Ok () -> ()
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "run"
           ~doc:"Run a compiled binary under an OS-enforced capability sandbox")
    Term.(const run $ bin $ args $ allow_only)

let cap_cmd =
  Cmd.group (Cmd.info "cap"
               ~doc:"Capability and typestate inspection")
    [cap_query_cmd; cap_coverage_cmd; cap_inspect_cmd; cap_run_cmd]

(* ------------------------------------------------------------- forge audit *)

let audit_cmd =
  let record =
    Arg.(value & flag &
         info ["record"]
           ~doc:"Record the current capability set as the baseline \
                 (writes forge.caps.lock). Use this to accept a reviewed change.")
  in
  let inferred =
    Arg.(value & flag &
         info ["inferred"]
           ~doc:"Infer each dependency's capability set from its code instead \
                 of reading its $(b,needs) declarations. Catches a capability \
                 builtin called directly in a body with no matching \
                 $(b,needs) — which the compiler only warns about — at the \
                 cost of requiring each dependency to typecheck cleanly. \
                 Neither mode covers capabilities reached through FFI; \
                 $(b,forge cap inspect <binary>) is the sound check for a \
                 built artifact.")
  in
  let run r inferred =
    match Cmd_audit.run ~record_mode:r ~inferred () with
    | Ok code -> exit code
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "audit"
           ~doc:"Diff dependency capabilities against the recorded baseline"
           ~man:[
             `S Manpage.s_description;
             `P "Every March package declares the capabilities it needs, and the \
                 compiler enforces those declarations — so the authority a \
                 dependency holds is readable from its source rather than \
                 guessed at.";
             `P "$(b,forge audit) extracts the capability set of every transitive \
                 dependency and compares it against the baseline in \
                 $(b,forge.caps.lock). It exits non-zero when a dependency asks \
                 for a capability it did not previously hold, so CI can gate a \
                 dependency update on it.";
             `P "A dependency that stops asking for a capability is reported but \
                 does not fail the audit.";
             `S "TYPICAL USE";
             `P "forge audit --record   # accept the current set, commit forge.caps.lock";
             `P "forge audit            # in CI: fail if a dependency gained authority";
           ])
    Term.(const run $ record $ inferred)

(* --------------------------------------------------------- forge ffi -------- *)

let ffi_gen_c_cmd =
  let file =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"FILE.march" ~doc:"March file containing the extern block(s).")
  in
  let out =
    Arg.(value & opt (some string) None &
         info ["o"; "output"] ~docv:"OUT.c" ~doc:"Write the C skeleton here (default: stdout).")
  in
  let run f o =
    match Cmd_ffi.run ~file:f ~out:o with
    | Ok () -> ()
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "gen-c"
           ~doc:"Generate a C shim skeleton from a March extern block")
    Term.(const run $ file $ out)

let ffi_add_rust_cmd =
  let name =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"NAME" ~doc:"Crate name for the Rust binding.")
  in
  let dir =
    Arg.(value & opt string "native" &
         info ["dir"] ~docv:"DIR" ~doc:"Parent directory for the crate (default: native).")
  in
  let march_path =
    Arg.(value & opt string "PATH/TO/march" &
         info ["march-path"] ~docv:"PATH"
           ~doc:"Path to the `march` runtime crate (rust/march in the compiler repo).")
  in
  let run n d mp =
    match Cmd_ffi.add_rust ~name:n ~dir:d ~march_path:mp with
    | Ok () -> ()
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "add-rust"
           ~doc:"Scaffold a Rust binding crate that uses the `march` crate")
    Term.(const run $ name $ dir $ march_path)

let ffi_cmd =
  Cmd.group (Cmd.info "ffi" ~doc:"FFI binding tooling")
    [ffi_gen_c_cmd; ffi_add_rust_cmd]

(* ---------------------------------------------------------- forge deploy hot *)

let deploy_hot_cmd =
  let output =
    Arg.(value & opt string "" &
         info ["o"; "output"] ~docv:"PATH"
           ~doc:"Output path prefix for the .so and manifest (default: .march/<name>_hot)")
  in
  let so =
    Arg.(value & opt string "" &
         info ["so"] ~docv:"FILE.so"
           ~doc:"Use a pre-built .so instead of rebuilding (manifest is <FILE.so>.hcr_manifest). \
                 Useful when the target host differs from the build host (e.g. cross-compiled via Docker).")
  in
  let env_name =
    Arg.(value & opt string "" &
         info ["env"] ~docv:"NAME"
           ~doc:"Deploy to the named [[hot-reload.env]] group in forge.toml.")
  in
  let canary =
    Arg.(value & opt int 0 &
         info ["canary"] ~docv:"N"
           ~doc:"Deploy to the first N servers as canary, health-check, then roll out to the rest.")
  in
  let timeout =
    Arg.(value & opt int 30000 &
         info ["timeout"] ~docv:"MS"
           ~doc:"Canary health-check window in milliseconds (default: 30000).")
  in
  let grant_cap =
    Arg.(value & opt_all string [] &
         info ["grant-cap"] ~docv:"CAP"
           ~doc:"Authorize a specific capability widening (repeatable). Each occurrence \
                 permits one capability (or anything it subsumes) that the running \
                 version did not previously hold.")
  in
  let no_cap_gate =
    Arg.(value & flag &
         info ["no-cap-gate"]
           ~doc:"Escape hatch (Phase 5C Part C): force the legacy ACTIVATE3 protocol, \
                 skipping cap_root/capability admission entirely. Use this to deploy \
                 against a server that predates capability admission, or to \
                 deliberately bypass the gate.")
  in
  let run o s e c t grant_caps no_cap_gate =
    let result =
      if e = "" && c = 0 then
        (* Single-server fast path (backward compat) *)
        Cmd_deploy_hot.deploy ~output:o ~so:s ~grant_caps ~no_cap_gate ()
      else
        Cmd_deploy_hot.deploy_env ~output:o ~so:s ~env:e ~canary:c ~timeout_ms:t
          ~grant_caps ~no_cap_gate ()
    in
    match result with
    | Ok () -> ()
    | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1
  in
  Cmd.v (Cmd.info "hot"
           ~doc:"Build and hot-deploy changed functions to a running server (or fleet)")
    Term.(const run $ output $ so $ env_name $ canary $ timeout $ grant_cap $ no_cap_gate)

let deploy_cmd =
  Cmd.group (Cmd.info "deploy" ~doc:"Deploy project to a target environment")
    [deploy_hot_cmd]

(* -------------------------------------------------------- forge hot-reload *)

let hot_reload_keygen_cmd =
  let rotate =
    Arg.(value & flag & info ["rotate"] ~doc:"Generate a versioned rotation keypair")
  in
  let run r =
    if r then Cmd_hot_reload.run_keygen_rotate ()
    else Cmd_hot_reload.run_keygen ()
  in
  Cmd.v (Cmd.info "keygen"
           ~doc:"Generate an ed25519 keypair for forge deploy hot signing (--rotate for key rotation)")
    Term.(const run $ rotate)

let hot_reload_show_pubkey_cmd =
  Cmd.v (Cmd.info "show-pubkey"
           ~doc:"Print the public key from the saved ed25519 secret key")
    Term.(const Cmd_hot_reload.run_show_pubkey $ const ())

let hot_reload_use_key_cmd =
  let path =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"KEY_FILE" ~doc:"Path to the versioned secret key file to activate")
  in
  Cmd.v (Cmd.info "use-key"
           ~doc:"Switch forge deploy hot to sign with a different key file")
    Term.(const Cmd_hot_reload.run_use_key $ path)

let hot_reload_init_cmd =
  let lookback =
    Arg.(value & opt int 90 & info ["lookback"] ~docv:"DAYS"
           ~doc:"Number of days of git history to analyse (default: 90)")
  in
  let threshold =
    Arg.(value & opt int 3 & info ["threshold"] ~docv:"N"
           ~doc:"Files with fewer than N commits are candidates for exclusion (default: 3)")
  in
  Cmd.v (Cmd.info "init"
           ~doc:"Analyse git history and suggest hot-reload exclude list for forge.toml")
    Term.(const (fun lb thr -> Cmd_hot_reload.run_init ~lookback_days:lb ~threshold:thr ())
          $ lookback $ threshold)

let hot_reload_status_cmd =
  let env_name =
    Arg.(value & opt string "" &
         info ["env"] ~docv:"NAME"
           ~doc:"Query only the named [[hot-reload.env]] group (default: all).")
  in
  Cmd.v (Cmd.info "status"
           ~doc:"Show version + epoch status across all registered hot-reload functions")
    Term.(const (fun e ->
      match Cmd_deploy_hot.run_status ~env:e () with
      | Ok () -> ()
      | Error m -> Printf.eprintf "error: %s\n%!" m; exit 1) $ env_name)

let hot_reload_cmd =
  Cmd.group (Cmd.info "hot-reload" ~doc:"Hot code reload key management and status")
    [ hot_reload_keygen_cmd; hot_reload_show_pubkey_cmd; hot_reload_use_key_cmd;
      hot_reload_init_cmd; hot_reload_status_cmd ]

(* --------------------------------------------------------- forge completions *)

let completions_cmd =
  let shell =
    Arg.(required & pos 0 (some string) None &
         info [] ~docv:"SHELL" ~doc:"Shell to generate completions for: $(b,bash), $(b,zsh), or $(b,fish).")
  in
  let run sh =
    print_string (Cli_ext.completion_script ~shell:sh ~subcommands:known_builtin_names)
  in
  Cmd.v (Cmd.info "completions" ~doc:"Print a shell completion script")
    Term.(const run $ shell)

(* --------------------------------------------------------------------- root *)

(* The current project's own [archive.task.*] entries, if any — separate
   from the registry loop below, since a project is never registered as
   its own installed archive (see find_task's matching fix). *)
let self_man_blocks () =
  match Project.find_forge_toml () with
  | None -> []
  | Some project_root ->
    let self_name =
      try (Project.load_from project_root).Project.name
      with Sys_error _ | Failure _ | Toml.Parse_error _ -> ""
    in
    if self_name = "" then []
    else
      let tasks = Archive_store.list_archive_tasks project_root in
      if tasks = [] then []
      else
        [`S (String.uppercase_ascii self_name ^ " TASKS")]
        @ List.map (fun (cmd, _, doc) ->
            let desc = if doc = "" then " " else doc in
            `I ("$(b,forge " ^ cmd ^ ")", desc)
          ) tasks

let archive_man_blocks () =
  let entries = Archive_store.load_registry () in
  self_man_blocks () @
  List.concat (List.map (fun (name, entry) ->
      let root = match entry.Archive_store.source with
        | Archive_store.Path p -> p
        | _ -> Archive_store.archive_dir name
      in
      let tasks = Archive_store.list_archive_tasks root in
      if tasks = [] then []
      else
        [`S (String.uppercase_ascii name ^ " TASKS")]
        @ List.map (fun (cmd, _, doc) ->
            let desc = if doc = "" then " " else doc in
            `I ("$(b,forge " ^ cmd ^ ")", desc)
          ) tasks
        @ [`P ("See $(b,forge help " ^ name ^ ") for details.")]
    ) entries)

let default_term =
  Term.(const (fun () ->
    match Cmd_build.build ~release:false () with
    | Ok binary -> Printf.printf "built: %s\n%!" binary
    | Error m   -> Printf.eprintf "error: %s\n%!" m; exit 1
  ) $ const ())

let () =
  let cmds =
    [ new_cmd; init_cmd; build_cmd; check_cmd; fix_cmd; run_cmd; compile_cmd; test_cmd; lint_cmd; refine_cmd; refactor_cmd; format_cmd;
      interactive_cmd; i_cmd; clean_cmd; deps_cmd; add_cmd; publish_cmd; retire_cmd;
      install_cmd; uninstall_cmd; archives_cmd; update_cmd; verify_cmd;
      toolchain_cmd; upgrade_cmd; watch_cmd; bench_cmd; version_cmd; release_cmd;
      licenses_cmd; tree_cmd; outdated_cmd; why_cmd; search_cmd; notebook_cmd; doc_cmd; phases_cmd;
      cap_cmd; audit_cmd; ffi_cmd; deploy_cmd; hot_reload_cmd; completions_cmd; help_cmd ]
  in
  let main =
    Cmd.group ~default:default_term
      (Cmd.info "forge" ~version:Version.version
         ~doc:"The March package manager and build tool"
         ~man:(archive_man_blocks ()))
      cmds
  in
  exit (Cmd.eval main)
