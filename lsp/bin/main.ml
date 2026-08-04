(** march-lsp entry point.

    - [march-lsp]                : stdio LSP server (stdin/stdout)
    - [march-lsp query <...>]    : stateless one-shot query, JSON on stdout
*)

let run_server () =
  let server = new March_lsp_lib.Server.march_server in
  let conn =
    Linol_lwt.Jsonrpc2.create_stdio ~env:() server
  in
  (* `Jsonrpc2.run`'s `?shutdown` predicate is what ends the loop. Its default is
     `fun _ -> false`, so WITHOUT this the server handles the `exit`
     notification, returns to `read_msg`, and blocks on stdin forever — the
     client has said goodbye and is waiting for the process to go away, and
     instead the editor has to time out and kill it. linol's own documentation
     names this exact predicate. *)
  let task =
    Linol_lwt.Jsonrpc2.run
      ~shutdown:(fun () -> server#get_status = `ReceivedExit)
      conn
  in
  match Linol_lwt.run task with
  | () -> ()
  | exception exn ->
    let bt = Printexc.get_backtrace () in
    Printf.eprintf "march-lsp: fatal error: %s\n%s\n"
      (Printexc.to_string exn) bt;
    exit 1

let () =
  (* Without this, the backtrace printed on a fatal error is empty. *)
  Printexc.record_backtrace true;
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "query" then
    (* Drop the program name so argv starts at the "query" subcommand,
       matching Query_cli.run_to_string's [subcommand; feature; file; ...]. *)
    exit (March_lsp_lib.Query_cli.main
            (Array.sub Sys.argv 1 (Array.length Sys.argv - 1)))
  else
    run_server ()
