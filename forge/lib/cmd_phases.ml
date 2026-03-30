(** forge phases — serve the phase viewer + march-phases/phases.json *)

let phases_file = "march-phases/phases.json"

let respond fd status content_type body =
  let len = String.length body in
  let msg = Printf.sprintf
    "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s"
    status content_type len body
  in
  let _ = Unix.write_substring fd msg 0 (String.length msg) in
  ()

let read_file path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

let handle_request client req_line =
  let path =
    match String.split_on_char ' ' req_line with
    | _ :: p :: _ -> (match String.split_on_char '?' p with p :: _ -> p | [] -> "/")
    | _ -> "/"
  in
  match path with
  | "/" | "/index.html" ->
    respond client "200 OK" "text/html; charset=utf-8" Phase_viewer_html.content
  | "/phases.json" ->
    if Sys.file_exists phases_file then
      respond client "200 OK" "application/json" (read_file phases_file)
    else
      respond client "404 Not Found" "text/plain"
        "march-phases/phases.json not found.\nRun: march --dump-phases --compile yourfile.march"
  | _ ->
    respond client "404 Not Found" "text/plain" "Not found"

let run ~port () =
  let addr = Unix.ADDR_INET (Unix.inet_addr_loopback, port) in
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  (try Unix.bind sock addr
   with Unix.Unix_error (Unix.EADDRINUSE, _, _) ->
     Printf.eprintf "error: port %d is already in use\n%!" port; exit 1);
  Unix.listen sock 5;
  let url = Printf.sprintf "http://localhost:%d" port in
  Printf.printf "Phase viewer at %s\n%!" url;
  if not (Sys.file_exists phases_file) then
    Printf.printf "  (no phases.json yet — run: march --dump-phases --compile yourfile.march)\n%!";
  (* Try to open browser *)
  let _ = Sys.command (Printf.sprintf
    "open '%s' 2>/dev/null || xdg-open '%s' 2>/dev/null || true" url url) in
  while true do
    let (client, _) = Unix.accept sock in
    let buf = Bytes.create 4096 in
    let n = (try Unix.read client buf 0 4096 with Unix.Unix_error _ -> 0) in
    if n > 0 then begin
      let req = Bytes.sub_string buf 0 n in
      let req_line = match String.split_on_char '\n' req with l :: _ -> String.trim l | [] -> "" in
      handle_request client req_line
    end;
    (try Unix.close client with Unix.Unix_error _ -> ())
  done
