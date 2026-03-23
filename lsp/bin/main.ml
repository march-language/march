(** march-lsp entry point.

    Starts a stdio-based LSP server for the March language.
    Usage: march-lsp   (no arguments; communicates via stdin/stdout)
*)

let () =
  let server = new March_lsp_lib.Server.march_server in
  let conn =
    Linol_lwt.Jsonrpc2.create_stdio ~env:() server
  in
  let task = Linol_lwt.Jsonrpc2.run conn in
  match Linol_lwt.run task with
  | () -> ()
  | exception exn ->
    let bt = Printexc.get_backtrace () in
    Printf.eprintf "march-lsp: fatal error: %s\n%s\n"
      (Printexc.to_string exn) bt;
    exit 1
