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
     as port 0), judged by [Host_scope.permits].  Under a host scope, a
     capability below IO.NetConnect with the host-neutral target `""` is
     admitted exactly when the static checker lets a host-scoped module
     call it: some builtin of that capability is [Net_dest.Neutral]
     (tls_client_ctx: "it also bounds the TLS connections built on it");
   - names: [Name_scope.admits].

   The March verdict comes from ONE interpreted program that prints
   [Authority.admits] for every row.  The C verdict comes from the same
   program compiled: a native binary calls the C runtime's copy of the policy
   (runtime/march_authority.c; lib/tir/auth_native.ml retargets
   [Authority.parse] / [Authority.admits] to it).  All three must agree row
   for row (ocap phase 4, Task 4b).  Further rows pin the parser's results and
   error texts, [Authority.subset] and the hand-built [Paths] / [Hosts] forms,
   interpreted against compiled. *)

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
  ("IO.NetConnect(\"*.x.com\", methods(get))", "IO.NetConnect.TLS", "", "/");
  ("IO.NetConnect(\"api.x.com\")", "IO.NetConnect.TLS", "api.x.com:443", "/");
  ("IO.NetConnect(\"api.x.com\")", "IO.NetConnect", "", "/");
  ("IO.FileRead(\"/\")", "IO.FileRead", "rel/x", "/home/u");
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

(* A capability the static checker lets a host-scoped module use without a
   host: one with a [Net_dest.Neutral] builtin in the compiler's own table. *)
let host_neutral_kind kind =
  List.exists
    (fun (b, c) ->
       c = kind && March_caps.Net_dest.builtin_dest b = Some March_caps.Net_dest.Neutral)
    March_typecheck.Typecheck_builtins.builtin_cap_table

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
    else if CS.is_host_scopable cap && not (CS.is_host_scopable kind) then
      target = "" && host_neutral_kind kind
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

let run_march ?(compiled = false) src =
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
        if compiled then
          Printf.sprintf "cd %s && HOME=%s %s --compile --opt 0 diff.march -o ./prog >build.txt 2>&1 && ./prog 2>&1 || cat build.txt"
            (Filename.quote dir) (Filename.quote home) exe
        else
          Printf.sprintf "cd %s && HOME=%s %s diff.march 2>&1" (Filename.quote dir)
            (Filename.quote home) exe in
      let ic = Unix.open_process_in cmd in
      let out = read_all ic in
      ignore (Unix.close_process_in ic);
      out)

let agree ~compiled () =
  let out = run_march ~compiled (program ()) in
  let lines = List.filter (fun l -> l <> "") (String.split_on_char '\n' out) in
  if List.length lines <> List.length rows then
    Alcotest.failf "expected %d verdicts from the %s program, got:\n%s"
      (List.length rows) (if compiled then "compiled (C)" else "March") out;
  List.iter2
    (fun ((text, kind, target, cwd) as row) got ->
       let want = if ocaml_verdict row then "1" else "0" in
       Alcotest.(check string)
         (Printf.sprintf "%s: needs %s; %s(%S) in %s"
            (if compiled then "C" else "March") text kind target cwd)
         want got)
    rows lines

let test_agree () = agree ~compiled:false ()

(* The same rows judged by the C policy: the program compiled. *)
let test_agree_c () = agree ~compiled:true ()

(* ── C against March: the parser, subset and the hand-built forms ────── *)

(* Scope texts, accepted and refused: each is parsed and its result written
   out constructor by constructor (or its error text), so the C parser must
   build the same values, field for field, and refuse with the same words. *)
let parse_rows : string list = [
  "()"; ""; "IO"; "IO.Console, IO.Clock"; "  IO.Console ,IO.Clock\n";
  "IO.FileRead(\"/srv/a/../b/./c//\")"; "IO.FileSystem(\"/\", \"/x\")";
  "IO.NetConnect(\"*.X.com:443/v1/\", methods(get, post), no_redirects)";
  "IO.NetConnect(\"API.x.com.\")"; "IO.NetConnect(\"[::1]:8080\")"; "IO.NetConnect(no_redirects)";
  "IO.NetConnect(methods(get))"; "IO.NetConnect(\"a.com\", methods(\"get\"))";
  "IO.NetConnect(\"a.com\", methods get)"; "IO.NetConnect(\"a.com\", methods(get)";
  "IO.Mut(\"a\", \"b\", prefix(\"c.\"))"; "IO.Registry(prefix(\"w.\"))";
  (* refused *)
  "IO.Console("; "IO.Console()"; "IO.Console IO.Clock"; "io.console"; "IO..Console"; "IO.Console,";
  ","; "IO.Console(\"x\")"; "IO.FileRead(\"rel/\")"; "IO.FileRead(\"\")"; "IO.FileRead(no_redirects)";
  "IO.FileRead(\"/a\" \"/b\")"; "IO.FileRead(\"/a\""; "IO.FileRead(\"/a\\\"";
  "IO.NetConnect(\"https://a.com\")"; "IO.NetConnect(\"user@a.com\")"; "IO.NetConnect(\"a.com:0\")";
  "IO.NetConnect(\"a.com:\")"; "IO.NetConnect(\"a.com:99999\")"; "IO.NetConnect(\"*\")";
  "IO.NetConnect(\"a.*.com\")"; "IO.NetConnect(\"a..com\")"; "IO.NetConnect(\"a_b.com\")";
  "IO.NetConnect(\"[zz]\")"; "IO.NetConnect(\"[::1\")"; "IO.NetConnect(\"/v1/\")";
  "IO.NetConnect(\"a.com//x\")"; "IO.NetConnect(\"a.com/../x\")"; "IO.NetConnect(\"a.com/a%20\")";
  "IO.NetConnect(\"a.com\", no_redirects, no_redirects)"; "IO.NetConnect(methods(get), methods(put))";
  "IO.NetConnect(methods(fetch))"; "IO.NetConnect(\"a.com\", bogus)"; "IO.NetConnect(\"a\", \"b\")";
  "IO.NetConnect(no_redirects, \"a.com\")"; "IO.NetConnect(path(\"x\"))"; "IO.NetConnect(methods(get, \"x\"))";
  "IO.Mut(\"\")"; "IO.Mut(\"a;b\")"; "IO.Mut(prefix(\"\"))"; "IO.Mut(other(\"x\"))"; "IO.Mut(prefix)";
  "IO.Mut(prefix(\"a\", \"b\"))"; "IO.Console@"; "IO.FileRead(\"/\xc3\xa9\")";
]

(* (a, b): is every entry of scope list [a] covered by one of [b]? *)
let subset_rows : (string * string) list = [
  ("IO.FileRead(\"/srv/a\")", "IO.FileSystem(\"/srv\")");
  ("IO.FileRead(\"/srv\")", "IO.FileSystem(\"/srv/a\")");
  ("IO.FileRead", "IO.FileRead(\"/\")");
  ("IO.FileRead(\"/x\")", "IO.FileRead");
  ("IO.FileRead(\"/x\"), IO.Console", "IO");
  ("IO.Console, IO.Clock", "IO.Console");
  ("()", "()");
  ("IO.Mut(\"a\", prefix(\"c.x\"))", "IO.Mut(prefix(\"c.\"), \"a\")");
  ("IO.Mut(prefix(\"c\"))", "IO.Mut(prefix(\"c.\"))");
  ("IO.NetConnect(\"a.x.com\")", "IO.NetConnect(\"*.x.com\")");
  ("IO.NetConnect(\"*.x.com\")", "IO.NetConnect(\"*.x.com\")");
  ("IO.NetConnect(\"*.x.com\")", "IO.NetConnect(\"a.x.com\")");
  ("IO.NetConnect(\"x.com:443\")", "IO.NetConnect(\"x.com\")");
  ("IO.NetConnect(\"x.com\")", "IO.NetConnect(\"x.com:443\")");
  ("IO.NetConnect(\"x.com/v1/a/\")", "IO.NetConnect(\"x.com/v1/\")");
  ("IO.NetConnect(\"x.com\")", "IO.NetConnect(\"x.com/v1/\")");
  ("IO.NetConnect(\"x.com\", methods(get))", "IO.NetConnect(\"x.com\", methods(get, post))");
  ("IO.NetConnect(\"x.com\")", "IO.NetConnect(\"x.com\", methods(get))");
  ("IO.NetConnect(\"x.com\")", "IO.NetConnect(no_redirects)");
  ("IO.NetConnect(\"x.com\", no_redirects)", "IO.NetConnect(no_redirects)");
  ("IO.NetConnect(\"x.com\")", "IO.NetConnect");
  ("IO.NetConnect", "IO.NetConnect(\"x.com\")");
  ("IO.Database", "IO.NetConnect");
  ("IO.NetConnect(\"x.com\")", "IO.Network");
]

let render_program () =
  let q = march_string in
  Printf.sprintf
    {|mod AuthorityRender do
  needs IO.Console
  fn arg_text(a : Authority.Arg) : String do
    match a do
    Authority.Any -> "Any"
    Authority.Paths(ps) -> "Paths[" ++ String.join(ps, "|") ++ "]"
    Authority.Hosts(s) -> "Hosts[" ++ s ++ "]"
    Authority.Names(ns, pre) -> "Names[" ++ String.join(ns, "|") ++ ";" ++ String.join(pre, "|") ++ "]"
    Authority.HostAt(s, h, w, p) ->
      "HostAt[" ++ s ++ "," ++ h ++ "," ++ (if w do "wild" else "exact" end) ++ "," ++ int_to_string(p) ++ "]"
    Authority.PathsAt(ps) -> "PathsAt[" ++ String.join(ps, "|") ++ "]"
    end
  end
  fn scope_text(s : Authority.CapEntry) : String do
    match s do
    Authority.CapEntry(k, a) -> k ++ "=" ++ arg_text(a)
    end
  end
  fn parsed(text : String) : List(Authority.CapEntry) do
    match Authority.parse(text) do
    Ok(s) -> s
    Err(_) -> Nil
    end
  end
  fn p(text : String) : () do
    match Authority.parse(text) do
    Ok(ss) -> Authority.ignore(println("ok " ++ int_to_string(List.length(ss)) ++ " " ++ String.join(List.map(ss, scope_text), " ")))
    Err(e) -> Authority.ignore(println("error " ++ e))
    end
  end
  fn sub(a : String, b : String) : () do
    Authority.ignore(println(if Authority.subset(parsed(a), parsed(b)) do "subset" else "not" end))
  end
  fn adm(ss : List(Authority.CapEntry), kind : String, target : String, cwd : String) : () do
    Authority.ignore(println(if Authority.admits(ss, kind, target, cwd) do "admits" else "refuses" end))
  end
  fn main() do
%s
%s
    let paths = [Authority.CapEntry("IO.FileSystem", Authority.Paths(["/srv/./a/", "rel/x"]))]
    adm(paths, "IO.FileRead", "/srv/a/b", "/")
    adm(paths, "IO.FileRead", "/srv/ab", "/")
    adm(paths, "IO.FileRead", "rel/x/y", "/")
    adm(paths, "IO.FileRead", "x/y", "/home")
    adm(paths, "IO.FileRead", "x/y", "")
    adm(paths, "IO.Console", "", "/")
    let hosts = [Authority.CapEntry("IO.NetConnect", Authority.Hosts("*.x.com:443/v1/;methods=get"))]
    adm(hosts, "IO.NetConnect", "a.x.com:443", "/")
    adm(hosts, "IO.NetConnect", "a.x.com:80", "/")
    adm(hosts, "IO.NetConnect", "x.com:443", "/")
    adm(hosts, "IO.NetConnect.TLS", "", "/")
    adm(hosts, "IO.Database", "a.x.com:443", "/")
    adm([Authority.CapEntry("IO.NetConnect", Authority.Hosts(";no_redirects"))], "IO.NetConnect", "e.org:1", "/")
    adm([Authority.CapEntry("IO.NetConnect", Authority.Hosts("bad host"))], "IO.NetConnect", "e.org:1", "/")
    sub("IO.FileRead(\"/srv/a\")", "IO.FileRead(\"/srv\")")
    Authority.ignore(println(if Authority.subset([Authority.CapEntry("IO.FileRead", Authority.Paths(["/srv/a/../b"]))], [Authority.CapEntry("IO.FileRead", Authority.Paths(["/srv/b"]))]) do "subset" else "not" end))
    Authority.ignore(println(if Authority.subset([Authority.CapEntry("IO.NetConnect", Authority.Hosts("a.x.com"))], [Authority.CapEntry("IO.NetConnect", Authority.Hosts("*.x.com"))]) do "subset" else "not" end))
    Authority.ignore(println(if Authority.subset([Authority.CapEntry("IO.NetConnect", Authority.Hosts(""))], [Authority.CapEntry("IO.NetConnect", Authority.Hosts(""))]) do "subset" else "not" end))
  end
end
|}
    (String.concat "
" (List.map (fun t -> Printf.sprintf "    p(%s)" (q t)) parse_rows))
    (String.concat "
" (List.map (fun (a, b) -> Printf.sprintf "    sub(%s, %s)" (q a) (q b)) subset_rows))

let test_render () =
  let src = render_program () in
  let march = run_march src and c = run_march ~compiled:true src in
  let ml = String.split_on_char '\n' march and cl = String.split_on_char '\n' c in
  let want = List.length parse_rows + List.length subset_rows + 17 + 1 in
  if List.length ml <> want then
    Alcotest.failf "expected %d lines from the interpreted program, got:\n%s" want march;
  if List.length cl <> want then
    Alcotest.failf "expected %d lines from the compiled program, got:\n%s" want c;
  let labels =
    List.map (fun t -> "parse " ^ t) parse_rows
    @ List.map (fun (a, b) -> Printf.sprintf "subset %s <= %s" a b) subset_rows
    @ List.init 18 (fun i -> Printf.sprintf "hand-built row %d" (i + 1)) in
  List.iteri (fun i (m, cc) ->
      Alcotest.(check string) (Printf.sprintf "C = March: %s" (List.nth labels i)) m cc)
    (List.combine ml cl);
  (* Not vacuous: both verdicts and both parse outcomes occur. *)
  let has sub = List.exists (fun l -> l = sub) ml in
  let starts pre = List.exists (fun l -> String.length l >= String.length pre
                                         && String.sub l 0 (String.length pre) = pre) ml in
  Alcotest.(check bool) "some parse succeeds" true (starts "ok ");
  Alcotest.(check bool) "some parse fails" true (starts "error ");
  Alcotest.(check bool) "some subset holds" true (has "subset");
  Alcotest.(check bool) "some subset fails" true (has "not");
  Alcotest.(check bool) "some admits" true (has "admits");
  Alcotest.(check bool) "some refuses" true (has "refuses")

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
  let modes = [ "interp"; "jit"; "compiled" ] @ (if Lazy.force have_node then [ "js" ] else []) in
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
            | "jit" ->
              List.map (fun env -> sh ~dir ~home ~env (exe ^ " --jit --stdlib-source launch.march")) envs
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
  -- main's needs clause is the launch request (decision 3): the program
  -- entry calls Authority.launch_init with it before any user code.
  fn main() needs IO.Console, IO.FileRead("/srv/") do
    println(show(Authority.check("IO.FileRead", "/srv/a")))
    println(show(Authority.check("IO.FileRead", "/etc/a")))
    println(show(Authority.check("IO.Clock", "")))
    let r = Authority.enter_fn(Authority.frame_layer("f", "IO.FileRead(\"/srv/a/\")"))
    let r2 = Authority.enter_fn(Authority.frame_layer("f", "IO.FileRead(\"/srv/a/\")"))
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
      ("MARCH_GRANT='IO.FileRead(\"data/\")'",
       "<exit 2>\nmarch: MARCH_GRANT is not a scope list: the scope `data/` on `IO.FileRead` is a relative path; give an absolute path, one starting with `/`\n");
      ("MARCH_GRANT='IO.FileRead(\"/etc/\")'",
       "<exit 2>\nmarch: MARCH_GRANT grants IO.FileRead(\"/etc\"), which main does not request (main requests: "
       ^ req ^ ")\n") ]
  in
  List.iter (fun (mode, outs) ->
      List.iter2 (fun (env, want) got ->
          Alcotest.(check string) (Printf.sprintf "%s [%s]" mode env) want got)
        cases outs)
    (run_modes ~src:launch_src ~envs:(List.map fst cases))

(* An unscoped request with MARCH_GRANT unset sets no launch layer, so the
   runtime keeps its fast path. *)
let unscoped_src = {|mod UnscopedFixture do
  needs IO
  fn main() needs IO.Console, IO.Clock do
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

(* ocap phase 6: a dependency grant's frame (Authority.enter_grant) is not
   pushed again while the same grant (limit and text) is anywhere in the
   layer list, so recursion in and out of a granted package keeps the list
   bounded; any other grant is pushed. Every runtime gives the same answer. *)
let grant_src = {|mod GrantFixture do
  needs IO
  fn show(r : Result((), CapError)) : String do
    match r do
    Ok(_) -> "ok"
    Err(e) -> Authority.describe(e)
    end
  end
  fn n() : String do int_to_string(List.length(cap_layers())) end
  fn main() needs IO.Console do
    let n0 = n()
    let r1 = Authority.enter_grant(Authority.grant_layer("weather", "IO.Console"))
    let n1 = n()
    let r2 = Authority.enter_fn(Authority.frame_layer("Weather.get", "IO"))
    let r3 = Authority.enter_fn(Authority.frame_layer("App.cb", "IO.Console, IO.Clock"))
    let n3 = n()
    let r4 = Authority.enter_grant(Authority.grant_layer("weather", "IO.Console"))
    let n4 = n()
    let clock = show(Authority.check("IO.Clock", ""))
    let r5 = Authority.enter_grant(Authority.grant_layer("weather", "IO.Clock"))
    let n5 = n()
    cap_restore(r5)
    cap_restore(r4)
    let n4b = n()
    cap_restore(r3)
    cap_restore(r2)
    cap_restore(r1)
    println(n0 ++ " " ++ n1 ++ " " ++ n3 ++ " " ++ n4 ++ " " ++ n5 ++ " " ++ n4b ++ " " ++ n())
    println(clock)
    println(show(Authority.check("IO.Clock", "")))
  end
end
|}

let test_enter_grant () =
  List.iter (fun (mode, outs) ->
      List.iter (fun got ->
          Alcotest.(check string) mode
            "0 1 3 3 4 3 0\nIO.Clock refused by the grant to package weather (IO.Console)\nok\n" got)
        outs)
    (run_modes ~src:grant_src ~envs:[ "" ])

(* ocap phase 7: a mock layer (Authority.mock_layer, ByMock(id)) never
   refuses; one covering an operation (an entry of exactly its kind that
   admits the target) admits it past the layers outside; a restrict inside
   it still refuses; mock_for finds the innermost covering mock unless a
   layer inside it refuses first; check_unmocked ignores mocks.  The same in
   the March policy (interp, JS) and the C port (jit, compiled). *)
let mock_src = {|mod MockLayerFixture do
  needs IO
  fn show(r : Result((), CapError)) : String do
    match r do
    Ok(_) -> "ok"
    Err(e) -> Authority.describe(e)
    end
  end
  fn opt(o : Option(Int)) : String do
    match o do
    Some(i) -> "some " ++ int_to_string(i)
    None -> "none"
    end
  end
  fn main() needs IO.Console do
    let r0 = Authority.enter_fn(Authority.frame_layer("T.f", "IO.Console"))
    let a = show(Authority.check("IO.Clock", ""))
    let r1 = cap_push(Authority.mock_layer(7, "IO.Clock"))
    let b = show(Authority.check("IO.Clock", ""))
    let c = opt(Authority.mock_for("IO.Clock", ""))
    let d = show(Authority.check_unmocked("IO.Clock", ""))
    let e = opt(Authority.mock_for("IO.Console", "stdout"))
    let f = show(Authority.check("IO.Console", "stdout"))
    let r2 = cap_push(Authority.restrict_layer("t:1", "IO.Console"))
    let g = show(Authority.check("IO.Clock", ""))
    let h = opt(Authority.mock_for("IO.Clock", ""))
    cap_restore(r2)
    let r3 = cap_push(Authority.mock_layer(8, "IO.FileRead(\"/srv/\")"))
    let i = opt(Authority.mock_for("IO.FileRead", "/srv/x"))
    let j = opt(Authority.mock_for("IO.FileRead", "/etc/x"))
    let k = opt(Authority.mock_for("IO.FileSystem", "/srv/x"))
    let k2 = opt(Authority.mock_for("IO.Clock", ""))
    let l = show(Authority.check("IO.FileRead", "/srv/x"))
    let m = show(Authority.check("IO.FileRead", "/etc/x"))
    cap_restore(r3)
    cap_restore(r1)
    let n = show(Authority.check("IO.Clock", ""))
    cap_restore(r0)
    println(a)
    println(b ++ " | " ++ c ++ " | " ++ d ++ " | " ++ e ++ " | " ++ f)
    println(g ++ " | " ++ h)
    println(i ++ " | " ++ j ++ " | " ++ k ++ " | " ++ k2 ++ " | " ++ l ++ " | " ++ m)
    println(n)
    println(show(Authority.check("IO.Clock", "")))
  end
end
|}

let test_mock_layer () =
  let refused = "IO.Clock refused by function T.f's needs (IO.Console)" in
  List.iter (fun (mode, outs) ->
      List.iter (fun got ->
          Alcotest.(check string) mode
            (String.concat "\n"
               [ refused;
                 "ok | some 7 | " ^ refused ^ " | none | ok";
                 "IO.Clock refused by the restrict at t:1 (IO.Console) | none";
                 "some 8 | none | none | some 7 | ok | IO.FileRead(\"/etc/x\") refused by function T.f's needs (IO.Console)";
                 refused;
                 "ok"; "" ])
            got)
        outs)
    (run_modes ~src:mock_src ~envs:[ "" ])

(* A relative target is resolved against the current directory (cap_cwd)
   in every runtime.  The fixture's cwd is a
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
    let r = Authority.enter_fn(Authority.frame_layer("g", "IO.FileRead(\"" ++ here ++ "\")"))
    let a = verdict(Authority.check("IO.FileRead", "x/y"))
    let b = verdict(Authority.check("IO.FileRead", "../x"))
    let c = verdict(Authority.check("IO.FileRead", here ++ "/z"))
    cap_restore(r)
    let r2 = Authority.enter_fn(Authority.frame_layer("h", "IO.FileRead(\"" ++ here ++ "/sub/\")"))
    let d = verdict(Authority.check("IO.FileRead", "sub/y"))
    let e = verdict(Authority.check("IO.FileRead", "sub/../y"))
    let f = verdict(Authority.check("IO.FileRead", "/elsewhere/sub/y"))
    cap_restore(r2)
    println(a ++ " " ++ b ++ " " ++ c ++ " " ++ d ++ " " ++ e ++ " " ++ f)
  end
end
|}

let test_cwd () =
  List.iter (fun (mode, outs) ->
      List.iter (fun got ->
          Alcotest.(check string) mode "ok refused ok ok refused refused\n" got)
        outs)
    (run_modes ~src:cwd_src ~envs:[ "" ])

(* When the current directory cannot be read (here: it was removed), cap_cwd
   is "" in every runtime and a relative target is refused, never resolved
   against "/".  Each mode's program is built in a live dir and then run
   from a removed one.  Not the interpreter: its driver cannot start in a
   removed cwd at all (refine_check reads the cwd and raises Sys_error,
   pre-existing), so its cap_cwd (Sys_error -> "") is covered only by the
   admits(.., "") unit cases in test/stdlib/test_authority.march. *)
let gone_src = {|mod GoneFixture do
  needs IO
  fn verdict(r : Result((), CapError)) : String do
    match r do
    Ok(_) -> "ok"
    Err(_) -> "refused"
    end
  end
  fn main(_c : Cap(IO)) do
    let r = Authority.enter_fn(Authority.frame_layer("g", "IO.FileRead(\"/\")"))
    let a = verdict(Authority.check("IO.FileRead", "srv/x"))
    let b = verdict(Authority.check("IO.FileRead", "/srv/x"))
    cap_restore(r)
    println(a ++ " " ++ b)
  end
end
|}

let test_gone_cwd () =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let modes = [ "compiled" ] @ (if Lazy.force have_node then [ "js" ] else []) in
  List.iter (fun mode ->
      let dir = Filename.temp_dir "march-auth-gone" "" in
      let home = Filename.concat dir "home" in
      Unix.mkdir home 0o755;
      Unix.mkdir (Filename.concat home ".cache") 0o755;
      Fun.protect ~finally:(fun () -> try rm_rf dir with _ -> ()) (fun () ->
          let src = Filename.concat dir "gone.march" in
          let oc = open_out_bin src in
          output_string oc gone_src;
          close_out oc;
          let run_cmd =
            match mode with
            | "compiled" ->
              ignore (sh ~dir ~home (exe ^ " --compile --opt 0 --stdlib-source gone.march -o ./prog"));
              Some (Filename.quote (Filename.concat dir "prog"))
            | _ ->
              ignore (sh ~dir ~home (exe ^ " --target js --opt 0 --stdlib-source gone.march -o ./prog.mjs"));
              Some ("node " ^ Filename.quote (Filename.concat dir "prog.mjs"))
          in
          match run_cmd with
          | None -> ()
          | Some cmd ->
            let gone = Filename.concat dir "gone" in
            let full =
              Printf.sprintf "mkdir %s && cd %s && rmdir %s && HOME=%s %s 2>&1"
                (Filename.quote gone) (Filename.quote gone) (Filename.quote gone)
                (Filename.quote home) cmd in
            let ic = Unix.open_process_in full in
            let out = read_all ic in
            ignore (Unix.close_process_in ic);
            Alcotest.(check string) (mode ^ " in a removed cwd") "refused ok\n" out))
    modes

(* ── The program entry (ocap phase 4, Task 3) ──────────────────────────
   Every entry calls Authority.launch_init exactly once, before module-level
   code: a top-level `let` that prints runs after the launch, so a launch
   error leaves no "init" line, and a good launch prints it once. *)
let entry_src = {|mod EntryFixture do
  needs IO
  let banner = println("init")
  fn verdict(r : Result((), CapError)) : String do
    match r do
    Ok(_) -> "ok"
    Err(_) -> "refused"
    end
  end
  fn main() needs IO.Console, IO.FileRead("/srv/") do
    println(verdict(Authority.check("IO.FileRead", "/srv/a")) ++ " "
      ++ verdict(Authority.check("IO.FileRead", "/etc/a")) ++ " layers "
      ++ int_to_string(List.length(cap_layers())))
  end
end
|}

let test_entry_order () =
  let req = "IO.Console, IO.FileRead(\"/srv/\")" in
  let cases =
    [ ("", "init\nok refused layers 1\n");
      ("MARCH_GRANT='IO.Console'", "init\nrefused refused layers 1\n");
      ("MARCH_GRANT='IO.FileRead(\"/etc/\")'",
       "<exit 2>\nmarch: MARCH_GRANT grants IO.FileRead(\"/etc\"), which main does not request (main requests: "
       ^ req ^ ")\n") ]
  in
  List.iter (fun (mode, outs) ->
      List.iter2 (fun (env, want) got ->
          Alcotest.(check string) (Printf.sprintf "%s [%s]" mode env) want got)
        cases outs)
    (run_modes ~src:entry_src ~envs:(List.map fst cases))

(* A pure program (no capability operation, no needs) launches too: its
   request is empty, so any grant is wider than it. *)
let pure_src = {|mod PureFixture do
  fn main() do
    let _x = 1 + 2
    ()
  end
end
|}

let test_entry_pure () =
  let cases =
    [ ("", "");
      ("MARCH_GRANT='IO.Console('",
       "<exit 2>\nmarch: MARCH_GRANT is not a scope list: a scope is not closed: expected `)`\n") ]
  in
  List.iter (fun (mode, outs) ->
      List.iter2 (fun (env, want) got ->
          Alcotest.(check string) (Printf.sprintf "%s [%s]" mode env) want got)
        cases outs)
    (run_modes ~src:pure_src ~envs:(List.map fst cases))

(* A test file's request is its module's needs line (design §21), in each
   test runner: `march test`, a compiled --test binary and a JS --test
   module.  The runner output is reduced to its verdict line. *)
let test_file_src = {|mod LaunchTestFile do
  needs IO.Console, IO.FileRead("/srv/")
  fn verdict(r : Result((), CapError)) : String do
    match r do
    Ok(_) -> "ok"
    Err(_) -> "refused"
    end
  end
  test "the launch request is the module needs line" do
    assert(verdict(Authority.check("IO.FileRead", "/srv/a")) == "ok")
    assert(verdict(Authority.check("IO.FileRead", "/etc/a")) == "refused")
  end
end
|}

let test_entry_test_runners () =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let modes = [ "march test"; "compiled --test" ] @ (if Lazy.force have_node then [ "js --test" ] else []) in
  List.iter (fun mode ->
      let dir = Filename.temp_dir "march-auth-tests" "" in
      let home = Filename.concat dir "home" in
      Unix.mkdir home 0o755;
      Unix.mkdir (Filename.concat home ".cache") 0o755;
      Fun.protect ~finally:(fun () -> try rm_rf dir with _ -> ()) (fun () ->
          let oc = open_out_bin (Filename.concat dir "launch_test.march") in
          output_string oc test_file_src;
          close_out oc;
          let run env =
            match mode with
            | "march test" -> sh ~dir ~home ~env (exe ^ " test launch_test.march")
            | "compiled --test" ->
              ignore (sh ~dir ~home (exe ^ " --compile --test --opt 0 launch_test.march -o ./prog"));
              sh ~dir ~home ~env "./prog"
            | _ ->
              ignore (sh ~dir ~home (exe ^ " --target js --test --opt 0 launch_test.march -o ./prog.mjs"));
              sh ~dir ~home ~env "node ./prog.mjs"
          in
          let ok = run "" in
          (* A runner exits non-zero on a failing test, which [sh] reports
             as "<exit N>". *)
          let contains sub str =
            try ignore (Str.search_forward (Str.regexp_string sub) str 0); true
            with Not_found -> false in
          Alcotest.(check bool) (mode ^ ": the test passes under the module's request\n" ^ ok) true
            (not (contains "<exit" ok) && contains "." ok);
          let bad = run "MARCH_GRANT='IO.Clock'" in
          Alcotest.(check bool) (mode ^ ": a wider grant exits 2 before any test\n" ^ bad) true
            (try
               ignore (Str.search_forward (Str.regexp_string
                 "<exit 2>\nmarch: MARCH_GRANT grants IO.Clock, which main does not request (main requests: IO.Console, IO.FileRead(\"/srv/\"))") bad 0);
               true
             with Not_found -> false)))
    modes

(* The REPL launches with the full authority ("IO", unscoped), which a grant
   narrows; a bad grant exits 2 before the first prompt.  Both engines: the
   JIT (the default) and the interpreter. *)
let test_entry_repl () =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let dir = Filename.temp_dir "march-auth-repl" "" in
  let home = Filename.concat dir "home" in
  Unix.mkdir home 0o755;
  Unix.mkdir (Filename.concat home ".cache") 0o755;
  Fun.protect ~finally:(fun () -> try rm_rf dir with _ -> ()) (fun () ->
      let oc = open_out_bin (Filename.concat dir "in.txt") in
      output_string oc "Authority.check(\"IO.FileRead\", \"/etc/a\")\n:quit\n";
      close_out oc;
      let refused out =
        try ignore (Str.search_forward (Str.regexp_string
            "= Err(CapError(\"IO.FileRead\", \"/etc/a\", ByLaunch, \"IO.Console\"))") out 0); true
        with Not_found -> false in
      List.iter (fun (engine, env0) ->
          let full = sh ~dir ~home ~env:env0 (exe ^ " < in.txt") in
          Alcotest.(check bool) (engine ^ ": no grant, nothing refused\n" ^ full) false (refused full);
          let narrowed = sh ~dir ~home ~env:(env0 ^ " MARCH_GRANT=IO.Console") (exe ^ " < in.txt") in
          Alcotest.(check bool) (engine ^ ": the grant narrows the REPL\n" ^ narrowed) true (refused narrowed);
          let bad = sh ~dir ~home ~env:(env0 ^ " MARCH_GRANT='IO.Console('") (exe ^ " < in.txt") in
          (* stderr also carries the REPL's [timing] lines, so the exit and
             the launch line are matched separately. *)
          let has sub = try ignore (Str.search_forward (Str.regexp_string sub) bad 0); true
            with Not_found -> false in
          Alcotest.(check bool) (engine ^ ": a malformed grant exits 2\n" ^ bad) true
            (has "<exit 2>\n" && has "\nmarch: MARCH_GRANT is not a scope list"))
        [ ("jit", ""); ("interp", "MARCH_REPL_INTERP=1") ])

(* Fix round 1, I2: an entry that lowers to `App.main` (the file's own
   module wraps a nested one) launches in every runtime, with App.main's
   request, not the outer module's needs line. *)
let nested_src = {|mod Outer do
  needs IO.Console, IO.Clock
  mod App do
    needs IO.Console
    fn main() do
      println("hi")
    end
  end
end
|}

let test_entry_nested () =
  let cases =
    [ ("", "hi\n");
      ("MARCH_GRANT=IO.Clock",
       "<exit 2>\nmarch: MARCH_GRANT grants IO.Clock, which main does not request (main requests: IO.Console)\n") ]
  in
  List.iter (fun (mode, outs) ->
      List.iter2 (fun (env, want) got ->
          Alcotest.(check string) (Printf.sprintf "%s [%s]" mode env) want got)
        cases outs)
    (run_modes ~src:nested_src ~envs:(List.map fst cases))

(* Gap 3: `needs ()` on main is a clause that requests nothing; the
   module's needs line is not the fallback. *)
let unit_needs_src = {|mod UnitNeeds do
  needs IO.Console
  fn main() needs () do
    let _x = 1 + 2
    ()
  end
end
|}

let test_entry_unit_needs () =
  let cases =
    [ ("", "");
      ("MARCH_GRANT=IO.Console",
       "<exit 2>\nmarch: MARCH_GRANT grants IO.Console, which main does not request (main requests: )\n") ]
  in
  List.iter (fun (mode, outs) ->
      List.iter2 (fun (env, want) got ->
          Alcotest.(check string) (Printf.sprintf "%s [%s]" mode env) want got)
        cases outs)
    (run_modes ~src:unit_needs_src ~envs:(List.map fst cases))

(* Fix round 1, I1: the launch precedes a MARCH_LIB_PATH dependency's
   module-level code in the interpreter as in a compiled binary.  (With no
   grant the two differ, as before: the interpreter evaluates a library's
   top-level lets eagerly, a compiled binary on first use.) *)
let test_entry_lib_dep () =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let dir = Filename.temp_dir "march-auth-libdep" "" in
  let home = Filename.concat dir "home" in
  Unix.mkdir home 0o755;
  Unix.mkdir (Filename.concat home ".cache") 0o755;
  Unix.mkdir (Filename.concat dir "lib") 0o755;
  Fun.protect ~finally:(fun () -> try rm_rf dir with _ -> ()) (fun () ->
      let write name src =
        let oc = open_out_bin (Filename.concat dir name) in
        output_string oc src; close_out oc in
      write "lib/dep.march" {|mod Dep do
  needs IO.Console
  let banner = println("dep-init")
  fn hello() do
    println("dep-hello")
  end
end
|};
      write "main.march" {|mod Main do
  needs IO.Console, IO.Clock
  fn main() do
    match Dep.hello() do
      Ok(_) -> ()
      Err(_) -> ()
    end
  end
end
|};
      let lib = "MARCH_LIB_PATH=" ^ Filename.quote (Filename.concat dir "lib") in
      ignore (sh ~dir ~home ~env:lib (exe ^ " --compile --opt 0 main.march -o ./prog"));
      List.iter (fun (env, want) ->
          Alcotest.(check string) ("interp [" ^ env ^ "]") want
            (sh ~dir ~home ~env:(lib ^ " " ^ env) (exe ^ " main.march"));
          Alcotest.(check string) ("compiled [" ^ env ^ "]") want
            (sh ~dir ~home ~env:(lib ^ " " ^ env) "./prog"))
        [ ("MARCH_GRANT=IO.Clock", "");
          ("MARCH_GRANT=IO.Process",
           "<exit 2>\nmarch: MARCH_GRANT grants IO.Process, which main does not request (main requests: IO.Console, IO.Clock)\n") ])

(* `--grant SCOPES` is MARCH_GRANT for the run (interpreter, --jit,
   `march test`). *)
let test_grant_flag () =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let dir = Filename.temp_dir "march-auth-grant" "" in
  let home = Filename.concat dir "home" in
  Unix.mkdir home 0o755;
  Unix.mkdir (Filename.concat home ".cache") 0o755;
  Fun.protect ~finally:(fun () -> try rm_rf dir with _ -> ()) (fun () ->
      let write name src =
        let oc = open_out_bin (Filename.concat dir name) in
        output_string oc src; close_out oc in
      write "entry.march" entry_src;
      write "launch_test.march" test_file_src;
      let flag = " --grant 'IO.Console'" in
      Alcotest.(check string) "interp --grant" "init\nrefused refused layers 1\n"
        (sh ~dir ~home (exe ^ flag ^ " --stdlib-source entry.march"));
      Alcotest.(check string) "--jit --grant" "init\nrefused refused layers 1\n"
        (sh ~dir ~home (exe ^ flag ^ " --jit --stdlib-source entry.march"));
      let t = sh ~dir ~home (exe ^ " test --grant IO.Clock launch_test.march") in
      Alcotest.(check bool) ("march test --grant\n" ^ t) true
        (try ignore (Str.search_forward (Str.regexp_string
            "<exit 2>\nmarch: MARCH_GRANT grants IO.Clock") t 0); true
         with Not_found -> false))

(* ── Size: a printing program links no March matcher (Task 4b) ─────────
   Hello world (`needs IO.Console` + println), compiled --opt 2: the IR
   defines at most 13 functions (the pre-phase-4 baseline was 10), none of
   them an Authority policy function other than `check`, and launches through
   the C runtime.  The binary's size is printed for the record (the Task 4b
   target, <= 274 KB on macOS arm64, is measured by hand: see
   specs/progress/2026-11-15-ocap-p4-native-authority-in-c.md). *)
let hello_src = {|mod Hello do
  needs IO.Console
  fn main() do
    println("Hello, world!")
  end
end
|}

let test_hello_size () =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let dir = Filename.temp_dir "march-auth-size" "" in
  let home = Filename.concat dir "home" in
  Unix.mkdir home 0o755;
  Unix.mkdir (Filename.concat home ".cache") 0o755;
  Fun.protect ~finally:(fun () -> try rm_rf dir with _ -> ()) (fun () ->
      let oc = open_out_bin (Filename.concat dir "hello.march") in
      output_string oc hello_src;
      close_out oc;
      ignore (sh ~dir ~home (exe ^ " --emit-llvm --opt 2 hello.march"));
      ignore (sh ~dir ~home (exe ^ " --compile --opt 2 hello.march -o ./hello"));
      let ll =
        let ic = open_in_bin (Filename.concat dir "hello.ll") in
        let s = really_input_string ic (in_channel_length ic) in
        close_in ic; s in
      let defines =
        List.filter (fun l -> String.length l > 7 && String.sub l 0 7 = "define ")
          (String.split_on_char '\n' ll) in
      let names = String.concat "\n" defines in
      Alcotest.(check bool) (Printf.sprintf "at most 13 defined functions, got %d:\n%s"
                               (List.length defines) names) true (List.length defines <= 13);
      List.iter (fun l ->
          let contains sub = try ignore (Str.search_forward (Str.regexp_string sub) l 0); true
            with Not_found -> false in
          if contains "@Authority." && not (contains "@Authority.check(") then
            Alcotest.failf "hello world defines an Authority policy function: %s" l)
        defines;
      Alcotest.(check bool) "the entry launches through the C runtime" true
        (try ignore (Str.search_forward (Str.regexp_string "@march_cap_rt_launch_init(") ll 0); true
         with Not_found -> false);
      Alcotest.(check string) "it still prints" "Hello, world!\n" (sh ~dir ~home "./hello");
      (* The binary's size is reported, not gated: it is page-rounded
         (16 KB __TEXT pages on macOS arm64) and depends on the toolchain, so
         an absolute bound would go red for unrelated runtime growth.  The
         gate is the IR above, which is the compiler's own output: with the
         March matcher linked back in, hello world defines 118 functions. *)
      let size = (Unix.stat (Filename.concat dir "hello")).Unix.st_size in
      let text =
        let ic = Unix.open_process_in
            (Printf.sprintf "size -m %s 2>/dev/null | awk '/Section __text:/ {print $3; exit}'"
               (Filename.quote (Filename.concat dir "hello"))) in
        let s = try input_line ic with End_of_file -> "?" in
        ignore (Unix.close_process_in ic);
        s in
      Printf.printf "hello world --opt 2: binary %d B, __text %s B, .ll %d B, %d defines\n%!"
        size text (String.length ll) (List.length defines))

let tests =
  [ ( "authority_launch",
      [ Alcotest.test_case "launch_init, the grant, enter_fn and the layered check" `Quick
          test_launch;
        Alcotest.test_case "an unscoped launch with no grant sets nothing" `Quick
          test_unscoped;
        Alcotest.test_case "relative targets resolve against the cwd" `Quick test_cwd;
        Alcotest.test_case "enter_grant pushes a grant once" `Quick test_enter_grant;
        Alcotest.test_case "a mock layer admits what it covers and never refuses" `Quick
          test_mock_layer;
        Alcotest.test_case "an unreadable cwd refuses a relative target" `Quick
          test_gone_cwd ] );
    ( "launch_entry",
      [ Alcotest.test_case "every runtime launches before module-level code" `Quick
          test_entry_order;
        Alcotest.test_case "a pure program launches too" `Quick test_entry_pure;
        Alcotest.test_case "test runners launch with the module's needs line" `Quick
          test_entry_test_runners;
        Alcotest.test_case "the REPL launches with IO, narrowed by a grant" `Quick
          test_entry_repl;
        Alcotest.test_case "--grant sets MARCH_GRANT for the run" `Quick test_grant_flag;
        Alcotest.test_case "a nested App.main entry launches everywhere" `Quick test_entry_nested;
        Alcotest.test_case "needs () on main requests nothing" `Quick test_entry_unit_needs;
        Alcotest.test_case "a library's top-level lets run after the launch" `Quick
          test_entry_lib_dep ] );
    ( "authority_differential",
      [ Alcotest.test_case "the reference admits and refuses" `Quick
          test_reference_not_vacuous;
        Alcotest.test_case "Authority.admits agrees with lib/caps row for row" `Quick
          test_agree;
        Alcotest.test_case "the C policy (compiled) agrees with lib/caps row for row" `Quick
          test_agree_c;
        Alcotest.test_case "the C parser, subset and hand-built forms agree with March" `Quick
          test_render ] );
    ( "authority_size",
      [ Alcotest.test_case "hello world links no March matcher" `Quick test_hello_size ] ) ]
