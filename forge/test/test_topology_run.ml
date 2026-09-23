(** `forge run` on a topology app (distributed-deploys plan, build step 3):
    examples/topology_app, two pools with no hand-written `main`.

    - `forge run --processes`: one process per pool, a local cluster; the
      front pool's hook initiates sessions of both roles the back pool
      serves; a Ctrl-C to forge (SIGINT) drains and stops every process,
      each exiting 0, and none is left running.
    - `forge topology export`: the derived caps come from the compiler.

    Hermetic like test_procs.ml: the just-built march and forge on a private
    PATH, an empty MARCH_HOME, the staged runtime and stdlib, a scratch copy
    of the example. *)

let getenv_abs v =
  match Sys.getenv_opt v with
  | None | Some "" ->
    Printf.eprintf "test_topology_run: %s is not set (see forge/test/dune)\n" v;
    exit 2
  | Some p -> if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p

let read_file path = try In_channel.with_open_bin path In_channel.input_all with Sys_error _ -> ""

let contains s sub =
  let n = String.length s and k = String.length sub in
  let rec go i = i + k <= n && (String.sub s i k = sub || go (i + 1)) in
  go 0

(** The environment every forge invocation runs in. *)
let hermetic_env = lazy (
  let march = getenv_abs "MARCH_TEST_BIN" and forge = getenv_abs "FORGE_TEST_BIN" in
  let bin = Filename.temp_dir "topology_run_bin_" "" in
  Unix.symlink march (Filename.concat bin "march");
  Unix.symlink forge (Filename.concat bin "forge");
  [ ("PATH", bin ^ ":" ^ Option.value ~default:"/usr/bin:/bin" (Sys.getenv_opt "PATH"));
    ("MARCH_HOME", Filename.temp_dir "topology_run_mh_" "");
    ("HOME", Filename.temp_dir "topology_run_home_" "");
    ("MARCH_RUNTIME_DIR", getenv_abs "MARCH_TEST_RUNTIME_DIR");
    ("MARCH_STDLIB", getenv_abs "MARCH_TEST_STDLIB_DIR") ])

(** A scratch copy of the example project. *)
let fresh_project () =
  let src = getenv_abs "TOPOLOGY_APP_DIR" in
  let dir = Filename.temp_dir "topology_app_" "" in
  let rc = Sys.command (Printf.sprintf "cp -R %s/. %s && rm -rf %s/.forge %s/.march"
                          (Filename.quote src) (Filename.quote dir) (Filename.quote dir) (Filename.quote dir)) in
  if rc <> 0 then Alcotest.failf "could not copy %s" src;
  dir

let environment extra =
  let env = Lazy.force hermetic_env @ extra in
  let keep kv = not (List.exists (fun (k, _) -> String.length kv > String.length k
                                                 && String.sub kv 0 (String.length k + 1) = k ^ "=") env) in
  Array.append (Array.of_list (List.map (fun (k, v) -> k ^ "=" ^ v) env))
    (Array.of_list (List.filter keep (Array.to_list (Unix.environment ()))))

(** Start forge in [dir] as the leader of its own process group (as a shell
    starts a foreground job), output to [out]. *)
let spawn_forge ~dir ~out args =
  let env = environment [] in
  match Unix.fork () with
  | 0 ->
    (try
       ignore (Unix.setsid ());
       Unix.chdir dir;
       let fd = Unix.openfile out [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
       Unix.dup2 fd Unix.stdout;
       Unix.dup2 fd Unix.stderr;
       Unix.execve (Filename.concat (List.assoc "PATH" (Lazy.force hermetic_env) |> String.split_on_char ':' |> List.hd) "forge")
         (Array.of_list ("forge" :: args)) env
     with _ -> Unix._exit 127)
  | pid -> pid

let wait_for_line ~out ~pid line timeout =
  let t0 = Unix.gettimeofday () in
  let rec go () =
    if contains (read_file out) line then true
    else if Unix.gettimeofday () -. t0 > timeout then false
    else match Unix.waitpid [ Unix.WNOHANG ] pid with
      | (0, _) -> Unix.sleepf 0.25; go ()
      | _ -> contains (read_file out) line
  in
  go ()

let wait_exit pid timeout =
  let t0 = Unix.gettimeofday () in
  let rec go () =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | (0, _) -> if Unix.gettimeofday () -. t0 > timeout then None else (Unix.sleepf 0.1; go ())
    | (_, st) -> Some st
  in
  go ()

(** Processes whose command line names [dir] (the built binaries live under it). *)
let leftovers dir =
  let tmp = Filename.temp_file "pgrep" ".txt" in
  ignore (Sys.command (Printf.sprintf "pgrep -f %s > %s 2>/dev/null" (Filename.quote dir) (Filename.quote tmp)));
  let s = String.trim (read_file tmp) in
  if s = "" then [] else String.split_on_char '\n' s

let cleanup pid =
  (try Unix.kill (- pid) Sys.sigkill with Unix.Unix_error _ -> ());
  ignore (wait_exit pid 5.)

(** Run forge [args] until [ready] appears, send [signal] to [target] (forge
    alone, or its whole process group as a terminal's Ctrl-C does), and
    return forge's exit status and output. *)
let run_until ~dir ~ready ~group args =
  let out = Filename.concat dir "forge.out" in
  let pid = spawn_forge ~dir ~out args in
  let ok = wait_for_line ~out ~pid ready 300. in
  if not ok then begin
    cleanup pid;
    Alcotest.failf "never saw %S; forge printed:\n%s" ready (read_file out)
  end;
  Unix.kill (if group then - pid else pid) Sys.sigint;
  match wait_exit pid 60. with
  | None -> cleanup pid; Alcotest.failf "forge did not exit after SIGINT:\n%s" (read_file out)
  | Some st -> (st, read_file out)

let test_processes () =
  let dir = fresh_project () in
  let (st, out) = run_until ~dir ~ready:"front: done" ~group:false [ "run"; "--processes" ] in
  let expect s = if not (contains out s) then Alcotest.failf "expected %S in:\n%s" s out in
  expect "forge run: starting back-1 (pool back";
  expect "forge run: starting front-1 (pool front";
  expect "[back-1] back: hook ran";
  (* Echo.Server is a function body (factor 10 from the hook's Env);
     Count.Counter an actor whose total survives across sessions. *)
  expect "[front-1] front: echo 40, totals 1 then 3";
  expect "[back-1] topology: drained back-1";
  expect "[front-1] topology: drained front-1";
  expect "forge run: back-1 exited 0";
  expect "forge run: front-1 exited 0";
  (match st with
   | Unix.WEXITED 0 -> ()
   | _ -> Alcotest.failf "forge ended %s:\n%s" (March_forge.Procs.string_of_status st) out);
  Alcotest.(check (list string)) "no process left running" [] (leftovers dir)

let test_export_caps_from_compiler () =
  let dir = fresh_project () in
  let out = Filename.concat dir "export.json" in
  let env = environment [] in
  let pid =
    Unix.create_process_env "sh" [| "sh"; "-c"; Printf.sprintf "cd %s && forge topology export > %s 2>/dev/null"
                                                    (Filename.quote dir) (Filename.quote out) |] env
      Unix.stdin Unix.stdout Unix.stderr
  in
  ignore (Unix.waitpid [] pid);
  let j = Yojson.Safe.from_string (read_file out) in
  let open Yojson.Safe.Util in
  let d = j |> member "derived" in
  let strs p k = d |> member p |> member k |> to_list |> List.map to_string in
  Alcotest.(check (list string)) "back's caps, from the compiler" [ "IO.Console" ] (strs "back" "caps");
  Alcotest.(check (list string)) "front initiates both clients" [ "Count.Client"; "Echo.Client" ] (strs "front" "initiates");
  Alcotest.(check string) "source" "compiler" (d |> member "back" |> member "source" |> to_string)

let () =
  Alcotest.run "topology-run" [
    ("forge run", [
        Alcotest.test_case "--processes: one process per pool; SIGINT drains and stops all" `Slow test_processes;
        Alcotest.test_case "topology export: derived caps from the compiler" `Slow test_export_caps_from_compiler;
      ]);
  ]
