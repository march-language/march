(* ocap phase 4, Task 2 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md,
   decision 1): the run-time policy is written once, in March
   (stdlib/authority.march: [Authority.parse] and [Authority.admits]), while
   the compiler's static checks use lib/caps.  The two must agree.

   Each row is (scope text, kind, target, cwd).  The OCaml verdict parses the
   scope text with the real March parser (as a module `needs` line, so the
   scope string is exactly the encoding the compiler sees) and judges it with
   [Cap_lattice] / [Cap_scope] / [Host_scope] / [Name_scope]:

   - an entry admits when its capability is the row's kind or a lattice
     ancestor of it, and either it is unscoped, or the kind takes that kind of
     scope and the target matches it;
   - paths: the target and any relative scope are resolved against [cwd],
     then compared segment by segment ([Cap_scope.within]);
   - hosts: the target is `host:port` (split at the last `:`; no port reads
     as port 0), judged by [Host_scope.permits];
   - names: [Name_scope.admits].

   The March verdict comes from ONE interpreted program that prints
   [Authority.admits] for every row.  They must agree row for row. *)

module L = March_caps.Cap_lattice
module CS = March_caps.Cap_scope
module HS = March_caps.Host_scope
module NS = March_caps.Name_scope

let rows : (string * string * string * string) list = [
  (* lattice ancestry, unscoped *)
  ("IO", "IO.Clock", "", "/");
  ("IO", "IO.FileRead", "/etc/passwd", "/");
  ("IO.Console", "IO.Console", "stdout", "/");
  ("IO.Console", "IO.Clock", "", "/");
  ("IO.FileSystem", "IO.FileWrite", "/tmp/x", "/");
  ("IO.FileRead", "IO.FileSystem", "/tmp/x", "/");
  ("IO.FileRead", "IO.FileWrite", "/tmp/x", "/");
  ("IO.Network", "IO.Database", "db:5432", "/");
  ("IO.NetConnect", "IO.NetConnect.TLS", "", "/");
  ("IO.NetConnect", "IO.NetListen", "8080", "/");
  ("IO.Foreign", "IO.Foreign.Blocking", "", "/");
  ("IO.Clock, IO.Random", "IO.Random", "", "/");
  ("IO.Clock, IO.Random", "IO.Spawn", "", "/");
  ("LibC", "LibC", "", "/");
  ("LibC", "IO", "", "/");
  ("IO", "LibC", "", "/");
  (* paths *)
  ("IO.FileRead(\"/srv/a/\")", "IO.FileRead", "/srv/a/b.txt", "/");
  ("IO.FileRead(\"/srv/a/\")", "IO.FileRead", "/srv/a", "/");
  ("IO.FileRead(\"/srv/a/\")", "IO.FileRead", "/srv/ab", "/");
  ("IO.FileRead(\"/srv/a/\")", "IO.FileRead", "/srv", "/");
  ("IO.FileRead(\"/srv/a/\")", "IO.FileWrite", "/srv/a/b", "/");
  ("IO.FileRead(\"/srv/a/\")", "IO.FileRead", "/srv/a/../b", "/");
  ("IO.FileRead(\"/srv/a/\")", "IO.FileRead", "/srv/a/./c//d", "/");
  ("IO.FileRead(\"/srv/a/\")", "IO.FileRead", "b/c", "/srv/a");
  ("IO.FileRead(\"/srv/a/\")", "IO.FileRead", "../a/c", "/srv/a");
  ("IO.FileRead(\"/srv/a/\")", "IO.FileRead", "../x", "/srv/a");
  ("IO.FileRead(\"/srv/a/\")", "IO.FileRead", "c", "/");
  ("IO.FileSystem(\"/srv\")", "IO.FileRead", "/srv/x", "/");
  ("IO.FileSystem(\"/srv\")", "IO.FileWrite", "/srvx", "/");
  ("IO.FileSystem(\"/srv\")", "IO.Console", "stdout", "/");
  ("IO.FileWrite(\"/\")", "IO.FileWrite", "/anything/at/all", "/");
  ("IO.FileRead(\"data/\")", "IO.FileRead", "data/x.csv", "/home/u");
  ("IO.FileRead(\"data/\")", "IO.FileRead", "/home/u/data/x.csv", "/home/u");
  ("IO.FileRead(\"data/\")", "IO.FileRead", "/home/v/data/x.csv", "/home/u");
  ("IO.FileRead(\"/a/\"), IO.FileRead(\"/b/\")", "IO.FileRead", "/b/c", "/");
  ("IO.FileRead(\"/a/\"), IO.FileRead", "IO.FileRead", "/z", "/");
  ("IO.FileRead(\"/a/\"), IO.Console", "IO.FileRead", "/z", "/");
  ("IO.FileRead(\"/a/\"), IO", "IO.FileRead", "/z", "/");
  (* hosts *)
  ("IO.NetConnect(\"api.x.com\")", "IO.NetConnect", "api.x.com:443", "/");
  ("IO.NetConnect(\"api.x.com\")", "IO.NetConnect", "API.X.COM.:80", "/");
  ("IO.NetConnect(\"api.x.com\")", "IO.NetConnect", "evil.com:443", "/");
  ("IO.NetConnect(\"api.x.com\")", "IO.NetConnect", "api.x.com.evil.com:443", "/");
  ("IO.NetConnect(\"api.x.com:8443\")", "IO.NetConnect", "api.x.com:8443", "/");
  ("IO.NetConnect(\"api.x.com:8443\")", "IO.NetConnect", "api.x.com:443", "/");
  ("IO.NetConnect(\"api.x.com:8443\")", "IO.NetConnect", "api.x.com", "/");
  ("IO.NetConnect(\"*.x.com\")", "IO.NetConnect", "a.x.com:443", "/");
  ("IO.NetConnect(\"*.x.com\")", "IO.NetConnect", "a.b.x.com:443", "/");
  ("IO.NetConnect(\"*.x.com\")", "IO.NetConnect", "x.com:443", "/");
  ("IO.NetConnect(\"*.x.com\")", "IO.NetConnect", "ax.com:443", "/");
  ("IO.NetConnect(\"*.x.com:443\")", "IO.NetConnect", "a.x.com:80", "/");
  ("IO.NetConnect(\"api.x.com/v1/\", methods(get))", "IO.NetConnect", "api.x.com:443", "/");
  ("IO.NetConnect(\"api.x.com/v1/\", methods(get))", "IO.NetConnect", "b.x.com:443", "/");
  ("IO.NetConnect(no_redirects)", "IO.NetConnect", "anything.org:1", "/");
  ("IO.NetConnect(\"[::1]:8080\")", "IO.NetConnect", "[::1]:8080", "/");
  ("IO.NetConnect(\"[::1]:8080\")", "IO.NetConnect", "[::1]:8081", "/");
  ("IO.NetConnect(\"127.0.0.1\")", "IO.NetConnect", "127.0.0.1:5432", "/");
  ("IO.NetConnect(\"api.x.com\")", "IO.Database", "api.x.com:5432", "/");
  ("IO.NetConnect(\"api.x.com\")", "IO.NetConnect.TLS", "", "/");
  ("IO.NetConnect(\"api.x.com\"), IO.Network", "IO.NetConnect", "evil.com:443", "/");
  ("IO.Network", "IO.NetConnect", "evil.com:443", "/");
  (* names and prefixes *)
  ("IO.Mut(\"counter\")", "IO.Mut", "counter", "/");
  ("IO.Mut(\"counter\")", "IO.Mut", "counter2", "/");
  ("IO.Mut(\"a\", \"b\")", "IO.Mut", "b", "/");
  ("IO.Mut(\"a\", prefix(\"cache.\"))", "IO.Mut", "cache.users", "/");
  ("IO.Mut(\"a\", prefix(\"cache.\"))", "IO.Mut", "cache", "/");
  ("IO.Mut(prefix(\"w.\"))", "IO.Mut", "w.", "/");
  ("IO.Mut(prefix(\"w.\"))", "IO.Mut", "a", "/");
  ("IO.Registry(\"svc\")", "IO.Registry", "svc", "/");
  ("IO.Registry(\"svc\")", "IO.Mut", "svc", "/");
  ("IO.Registry(prefix(\"worker.\"))", "IO.Registry", "worker.7", "/");
  ("IO", "IO.Registry", "anything", "/");
  ("IO.Mut(\"a\"), IO.Mut", "IO.Mut", "zzz", "/");
]

(* ── OCaml reference verdict ─────────────────────────────────────────── *)

let parse_needs (text : string) : (string * string option) list =
  let src = Printf.sprintf "mod D do\n  needs %s\nend\n" text in
  let lexbuf = Lexing.from_string src in
  let m = March_parser.Parse.module_of_lexbuf lexbuf in
  List.concat_map
    (function
      | March_ast.Ast.DNeeds (caps, _) ->
        List.map
          (fun (path, sc) ->
             (String.concat "." (List.map (fun (n : March_ast.Ast.name) -> n.txt) path), sc))
          caps
      | _ -> [])
    m.March_ast.Ast.mod_decls

let resolve ~cwd p = if CS.is_absolute p then p else cwd ^ "/" ^ p

(* A path scope's strings: the first, then every further `name=` one. *)
let scope_paths (sc : string) : string list =
  match String.split_on_char ';' sc with
  | first :: rest ->
    first
    :: List.map
         (fun o ->
            if String.length o > 5 && String.sub o 0 5 = "name=" then
              String.sub o 5 (String.length o - 5)
            else o)
         rest
  | [] -> []

(* A port as Host_scope reads one: 1-5 digits, 1..65535; anything else 0. *)
let parse_port (s : string) : int =
  if s = "" || String.length s > 5 || not (String.for_all (fun c -> c >= '0' && c <= '9') s)
  then 0
  else
    let p = int_of_string s in
    if p >= 1 && p <= 65535 then p else 0

let split_target (t : string) : string * int =
  match String.rindex_opt t ':' with
  | None -> (t, 0)
  | Some i ->
    let h = String.sub t 0 i and p = String.sub t (i + 1) (String.length t - i - 1) in
    (h, parse_port p)

let entry_admits ~kind ~target ~cwd (cap, sc) =
  L.cap_subsumes cap kind
  &&
  match sc with
  | None -> true
  | Some sc ->
    if CS.is_scopable kind && not (CS.is_host_scopable kind || CS.is_name_scopable kind)
    then
      List.exists
        (fun s -> CS.within ~scope:(resolve ~cwd s) (resolve ~cwd target))
        (scope_paths sc)
    else if CS.is_host_scopable kind && CS.is_host_scopable cap then
      match HS.parse_decl (Some sc) with
      | Ok d ->
        let host, port = split_target target in
        HS.permits [ d ] ~host ~port
      | Error _ -> false
    else if CS.is_name_scopable kind then
      match NS.parse sc with Ok s -> NS.admits s target | Error _ -> false
    else false

let ocaml_verdict (text, kind, target, cwd) =
  List.exists (entry_admits ~kind ~target ~cwd) (parse_needs text)

(* ── March verdict ───────────────────────────────────────────────────── *)

let march_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let program () =
  let calls =
    List.map
      (fun (text, kind, target, cwd) ->
         Printf.sprintf "    row(%s, %s, %s, %s)" (march_string text) (march_string kind)
           (march_string target) (march_string cwd))
      rows
  in
  Printf.sprintf
    {|mod AuthorityDifferential do
  needs IO.Console
  fn row(text : String, kind : String, target : String, cwd : String) : () do
    match Authority.parse(text) do
    Ok(s) -> Authority.ignore(println(if Authority.admits(s, kind, target, cwd) do "1" else "0" end))
    Err(e) -> Authority.ignore(println("parse error: " ++ e))
    end
  end
  fn main(_c : Cap(IO.Console)) do
%s
  end
end
|}
    (String.concat "\n" calls)

let rec rm_rf p =
  if Sys.file_exists p then
    if Sys.is_directory p then begin
      Array.iter (fun f -> rm_rf (Filename.concat p f)) (Sys.readdir p);
      Sys.rmdir p
    end else Sys.remove p

let read_all ic =
  let b = Buffer.create 256 in
  (try
     while true do Buffer.add_channel b ic 1 done
   with End_of_file -> ());
  Buffer.contents b

let run_march src =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let dir = Filename.temp_dir "march-auth-diff" "" in
  let home = Filename.concat dir "home" in
  Unix.mkdir home 0o755;
  Unix.mkdir (Filename.concat home ".cache") 0o755;
  Fun.protect ~finally:(fun () -> try rm_rf dir with _ -> ()) (fun () ->
      let oc = open_out_bin (Filename.concat dir "diff.march") in
      output_string oc src;
      close_out oc;
      let cmd =
        Printf.sprintf "cd %s && HOME=%s %s diff.march 2>&1" (Filename.quote dir)
          (Filename.quote home) exe in
      let ic = Unix.open_process_in cmd in
      let out = read_all ic in
      ignore (Unix.close_process_in ic);
      out)

let test_agree () =
  let out = run_march (program ()) in
  let lines = List.filter (fun l -> l <> "") (String.split_on_char '\n' out) in
  if List.length lines <> List.length rows then
    Alcotest.failf "expected %d verdicts from the March program, got:\n%s"
      (List.length rows) out;
  List.iter2
    (fun ((text, kind, target, cwd) as row) got ->
       let want = if ocaml_verdict row then "1" else "0" in
       Alcotest.(check string)
         (Printf.sprintf "needs %s; %s(%S) in %s" text kind target cwd)
         want got)
    rows lines

(* The reference itself must not be vacuous: both verdicts occur, in each
   family of rows. *)
let test_reference_not_vacuous () =
  let verdicts = List.map ocaml_verdict rows in
  Alcotest.(check bool) "some row admits" true (List.mem true verdicts);
  Alcotest.(check bool) "some row refuses" true (List.mem false verdicts);
  Alcotest.(check bool) "about 60 rows" true (List.length rows >= 60)

(* ── launch_init and enter_fn, in every runtime ──────────────────────── *)

let have_node = lazy (Sys.command "command -v node >/dev/null 2>&1" = 0)

(* stdout of [cmd] in [dir] under [home], with "<exit N>" and stderr
   appended on a non-zero exit. *)
let sh ~dir ~home ?(env = "") cmd =
  let full =
    Printf.sprintf "cd %s && export HOME=%s; %s %s 2>stderr.txt" (Filename.quote dir)
      (Filename.quote home) env cmd in
  let ic = Unix.open_process_in full in
  let out = read_all ic in
  let code = match Unix.close_process_in ic with Unix.WEXITED c -> c | _ -> -1 in
  if code = 0 then out
  else
    let err =
      try
        let ic = open_in_bin (Filename.concat dir "stderr.txt") in
        let s = really_input_string ic (in_channel_length ic) in
        close_in ic; s
      with _ -> "" in
    Printf.sprintf "%s<exit %d>\n%s" out code err

(* [src] built once per mode and run under each env; one output per env. *)
let run_modes ~src ~envs : (string * string list) list =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let modes = [ "interp"; "compiled" ] @ (if Lazy.force have_node then [ "js" ] else []) in
  List.map (fun mode ->
      let dir = Filename.temp_dir "march-auth-launch" "" in
      let home = Filename.concat dir "home" in
      Unix.mkdir home 0o755;
      Unix.mkdir (Filename.concat home ".cache") 0o755;
      Fun.protect ~finally:(fun () -> try rm_rf dir with _ -> ()) (fun () ->
          let oc = open_out_bin (Filename.concat dir "launch.march") in
          output_string oc src;
          close_out oc;
          let outs =
            match mode with
            | "interp" ->
              List.map (fun env -> sh ~dir ~home ~env (exe ^ " --stdlib-source launch.march")) envs
            | "compiled" ->
              let b = sh ~dir ~home (exe ^ " --compile --opt 0 --stdlib-source launch.march -o ./prog") in
              if not (Sys.file_exists (Filename.concat dir "prog")) then List.map (fun _ -> b) envs
              else List.map (fun env -> sh ~dir ~home ~env "./prog") envs
            | _ ->
              let b = sh ~dir ~home (exe ^ " --target js --opt 0 --stdlib-source launch.march -o ./prog.mjs") in
              if not (Sys.file_exists (Filename.concat dir "prog.mjs")) then List.map (fun _ -> b) envs
              else List.map (fun env -> sh ~dir ~home ~env "node ./prog.mjs") envs
          in
          (mode, outs)))
    modes

let launch_src = {|mod LaunchFixture do
  needs IO
  fn show(r : Result((), CapError)) : String do
    match r do
    Ok(_) -> "ok"
    Err(e) -> Authority.describe(e)
    end
  end
  fn main(_c : Cap(IO)) do
    Authority.launch_init("IO.Console, IO.FileRead(\"/srv/\")", true)
    println(show(Authority.check("IO.FileRead", "/srv/a")))
    println(show(Authority.check("IO.FileRead", "/etc/a")))
    println(show(Authority.check("IO.Clock", "")))
    let r = Authority.enter_fn("f", "IO.FileRead(\"/srv/a/\")")
    let r2 = Authority.enter_fn("f", "IO.FileRead(\"/srv/a/\")")
    let n = List.length(cap_layers())
    let in_b = show(Authority.check("IO.FileRead", "/srv/b"))
    let in_ax = show(Authority.check("IO.FileRead", "/srv/a/x"))
    let in_con = show(Authority.check("IO.Console", "stdout"))
    cap_restore(r2)
    cap_restore(r)
    println("frame layers " ++ int_to_string(n))
    println(in_b)
    println(in_ax)
    println(in_con)
    println(show(Authority.check("IO.FileRead", "/srv/b")))
  end
end
|}

let test_launch () =
  let req = "IO.Console, IO.FileRead(\"/srv/\")" in
  let tail launch =
    [ "frame layers 2";
      "IO.FileRead(\"/srv/b\") refused by function f's needs (IO.FileRead(\"/srv/a/\"))";
      "ok";
      "IO.Console(\"stdout\") refused by function f's needs (IO.FileRead(\"/srv/a/\"))";
      launch ]
  in
  let lines l = String.concat "\n" l ^ "\n" in
  let cases =
    [ ("",
       lines
         ([ "ok";
            "IO.FileRead(\"/etc/a\") refused by the launch grant (" ^ req ^ ")";
            "IO.Clock refused by the launch grant (" ^ req ^ ")" ]
          @ tail "ok"));
      ("MARCH_GRANT='IO.Console, IO.FileRead(\"/srv/a/\")'",
       lines
         ([ "ok";
            "IO.FileRead(\"/etc/a\") refused by the launch grant (IO.Console, IO.FileRead(\"/srv/a/\"))";
            "IO.Clock refused by the launch grant (IO.Console, IO.FileRead(\"/srv/a/\"))" ]
          @ tail "IO.FileRead(\"/srv/b\") refused by the launch grant (IO.Console, IO.FileRead(\"/srv/a/\"))"));
      ("MARCH_GRANT='IO.Console('",
       "<exit 2>\nmarch: MARCH_GRANT is not a scope list: a scope is not closed: expected `)`\n");
      ("MARCH_GRANT='IO.FileRead(\"/etc/\")'",
       "<exit 2>\nmarch: MARCH_GRANT grants IO.FileRead(\"/etc\"), which main does not request (main requests: "
       ^ req ^ ")\n") ]
  in
  (* The JS target's print_stderr is console.error, which adds a newline of
     its own (pre-existing; the interpreter and native print the string as
     given), so a JS launch error ends in one extra blank line. *)
  let js_stderr got =
    let n = String.length got in
    if n >= 2 && String.sub got (n - 2) 2 = "\n\n" then String.sub got 0 (n - 1) else got in
  List.iter (fun (mode, outs) ->
      List.iter2 (fun (env, want) got ->
          let got = if mode = "js" then js_stderr got else got in
          Alcotest.(check string) (Printf.sprintf "%s [%s]" mode env) want got)
        cases outs)
    (run_modes ~src:launch_src ~envs:(List.map fst cases))

(* An unscoped request with MARCH_GRANT unset sets no launch layer, so the
   runtime keeps its fast path. *)
let unscoped_src = {|mod UnscopedFixture do
  needs IO
  fn main(_c : Cap(IO)) do
    Authority.launch_init("IO.Console, IO.Clock", false)
    println("layers " ++ int_to_string(List.length(cap_layers())) ++ " raw "
      ++ int_to_string(cap_check_raw("IO.Clock", "")))
  end
end
|}

let test_unscoped () =
  List.iter (fun (mode, outs) ->
      List.iter2 (fun (env, want) got ->
          Alcotest.(check string) (Printf.sprintf "%s [%s]" mode env) want got)
        [ ("", "layers 0 raw 0\n"); ("MARCH_GRANT=IO.Console", "layers 1 raw 1\n") ] outs)
    (run_modes ~src:unscoped_src ~envs:[ ""; "MARCH_GRANT=IO.Console" ])

(* A relative target, and a relative path scope, are resolved against the
   current directory (cap_cwd) in every runtime.  The fixture's cwd is a
   fresh temp dir, so the frame's scope is built from it at run time. *)
let cwd_src = {|mod CwdFixture do
  needs IO
  fn verdict(r : Result((), CapError)) : String do
    match r do
    Ok(_) -> "ok"
    Err(_) -> "refused"
    end
  end
  fn main(_c : Cap(IO)) do
    let here = process_cwd()
    let r = Authority.enter_fn("g", "IO.FileRead(\"" ++ here ++ "\")")
    let a = verdict(Authority.check("IO.FileRead", "x/y"))
    let b = verdict(Authority.check("IO.FileRead", "../x"))
    let c = verdict(Authority.check("IO.FileRead", here ++ "/z"))
    cap_restore(r)
    let r2 = Authority.enter_fn("h", "IO.FileRead(\"sub/\")")
    let d = verdict(Authority.check("IO.FileRead", "sub/y"))
    let e = verdict(Authority.check("IO.FileRead", here ++ "/sub/y"))
    let f = verdict(Authority.check("IO.FileRead", "/elsewhere/sub/y"))
    cap_restore(r2)
    println(a ++ " " ++ b ++ " " ++ c ++ " " ++ d ++ " " ++ e ++ " " ++ f)
  end
end
|}

let test_cwd () =
  List.iter (fun (mode, outs) ->
      List.iter (fun got ->
          Alcotest.(check string) mode "ok refused ok ok ok refused\n" got)
        outs)
    (run_modes ~src:cwd_src ~envs:[ "" ])

let tests =
  [ ( "authority_launch",
      [ Alcotest.test_case "launch_init, the grant, enter_fn and the layered check" `Quick
          test_launch;
        Alcotest.test_case "an unscoped launch with no grant sets nothing" `Quick
          test_unscoped;
        Alcotest.test_case "relative targets and scopes resolve against the cwd" `Quick
          test_cwd ] );
    ( "authority_differential",
      [ Alcotest.test_case "the reference admits and refuses" `Quick
          test_reference_not_vacuous;
        Alcotest.test_case "Authority.admits agrees with lib/caps row for row" `Quick
          test_agree ] ) ]
