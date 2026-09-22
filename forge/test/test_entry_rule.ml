(** One entry-file rule ([Project.entry], G5 of
    specs/plans/2026-09-21-distributed-deploys-groundwork-plan.md).

    Before it, `forge build`/`check`/`run` looked for lib/<name>.march and the
    hot-deploy build step looked for src/<name>.march, so a project that built
    could not be hot-deployed ("no such file"), and the other way round. Each
    layout below is driven through all four consumers — [Cmd_check.check],
    [Cmd_build.build] (whose binary is run, so we see WHICH file it compiled),
    [Cmd_run.resolve_entry] and [Cmd_deploy_hot.build_so] — and they must
    pick the same file.

    Hermetic: shells out to the just-built compiler with the staged runtime
    and stdlib (see forge/test/dune). *)

open March_forge

let setup_hermetic_toolchain () =
  let resolve env_var =
    match Sys.getenv_opt env_var with
    | None | Some "" ->
      Printf.eprintf
        "test_entry_rule: %s is not set. The dune rule must pass it (see \
         forge/test/dune); refusing to fall back to an ambient toolchain.\n"
        env_var;
      exit 2
    | Some rel ->
      if Filename.is_relative rel then Filename.concat (Sys.getcwd ()) rel else rel
  in
  let march_abs = resolve "MARCH_TEST_BIN" in
  let runtime_dir_abs = resolve "MARCH_TEST_RUNTIME_DIR" in
  let stdlib_dir_abs = resolve "MARCH_TEST_STDLIB_DIR" in
  List.iter (fun abs ->
      if not (Sys.file_exists abs) then begin
        Printf.eprintf "test_entry_rule: %s does not exist\n" abs;
        exit 2
      end)
    [ march_abs; runtime_dir_abs; stdlib_dir_abs ];
  let bindir = Filename.temp_dir "march_hermetic_bin_" "" in
  Unix.symlink march_abs (Filename.concat bindir "march");
  let old_path = Option.value (Sys.getenv_opt "PATH") ~default:"" in
  Unix.putenv "PATH" (bindir ^ ":" ^ old_path);
  Unix.putenv "MARCH_HOME" (Filename.temp_dir "march_hermetic_home_" "");
  Unix.putenv "HOME" (Filename.temp_dir "march_hermetic_userhome_" "");
  Unix.putenv "MARCH_RUNTIME_DIR" runtime_dir_abs;
  Unix.putenv "MARCH_STDLIB" stdlib_dir_abs

let write_file path content =
  let rec mkdir_p d =
    if not (Sys.file_exists d) then begin
      mkdir_p (Filename.dirname d);
      Unix.mkdir d 0o755
    end
  in
  mkdir_p (Filename.dirname path);
  Out_channel.with_open_text path (fun oc -> output_string oc content)

let contains s sub =
  let n = String.length s and k = String.length sub in
  let rec go i = i + k <= n && (String.sub s i k = sub || go (i + 1)) in
  go 0

let name = "entryapp"

(* A program that prints [tag], so the built binary says which file it came
   from. *)
let program tag =
  Printf.sprintf
    "mod Entryapp do\n  needs IO.Console\n  fn main(_c : Cap(IO.Console)) : () do\n    println(\"%s\")\n  end\nend\n"
    tag

(* Picking this file is a type error, so a consumer that chose it fails. *)
let broken =
  "mod Entryapp do\n  needs IO.Console\n  fn main(_c : Cap(IO.Console)) : () do\n    println(1 ++ \"x\")\n  end\nend\n"

let with_project ?entrypoint (files : (string * string) list) f =
  let root = Unix.realpath (Filename.temp_dir "forge_entry_rule_" "") in
  let ep = match entrypoint with
    | Some e -> Printf.sprintf "entrypoint = \"%s\"\n" e
    | None -> "" in
  write_file (Filename.concat root "forge.toml")
    (Printf.sprintf "[package]\nname = \"%s\"\nversion = \"0.1.0\"\ntype = \"app\"\n%s"
       name ep);
  List.iter (fun (rel, src) -> write_file (Filename.concat root rel) src) files;
  let old = Sys.getcwd () in
  Unix.chdir root;
  Fun.protect
    ~finally:(fun () ->
        Unix.chdir old;
        ignore (Sys.command ("rm -rf " ^ Filename.quote root)))
    (fun () -> f root)

let load () =
  match Project.load () with
  | Ok p -> p
  | Error e -> Alcotest.failf "forge.toml did not load: %s" e

let run_capture exe =
  let ic = Unix.open_process_in (Filename.quote exe ^ " 2>&1") in
  let out = In_channel.input_all ic in
  ignore (Unix.close_process_in ic);
  String.trim out

(* All four consumers resolve [expected] and the build runs [tag]'s program. *)
let agree ~expected ~tag root =
  let proj = load () in
  let expected = Filename.concat root expected in
  Alcotest.(check (result string string)) "Project.entry" (Ok expected)
    (Project.entry proj);
  (match Cmd_run.resolve_entry () with
   | Ok (e, _) -> Alcotest.(check string) "forge run's entry" expected e
   | Error e -> Alcotest.failf "forge run: %s" e);
  (match Cmd_check.check () with
   | Ok _ -> ()
   | Error e -> Alcotest.failf "forge check: %s" e);
  (match Cmd_build.build ~release:false () with
   | Ok binary ->
     Alcotest.(check string) "forge build compiled the same file" tag
       (run_capture binary)
   | Error e -> Alcotest.failf "forge build: %s" e);
  match Cmd_deploy_hot.build_so ~proj ~output:(Filename.concat root "hot") with
  | Ok _ -> ()
  | Error e -> Alcotest.failf "deploy build step: %s" e

let test_lib_layout () =
  with_project [ ("lib/entryapp.march", program "lib") ]
    (agree ~expected:"lib/entryapp.march" ~tag:"lib")

let test_src_layout () =
  with_project [ ("src/entryapp.march", program "src") ]
    (agree ~expected:"src/entryapp.march" ~tag:"src")

let test_lib_wins_over_src () =
  with_project
    [ ("lib/entryapp.march", program "lib"); ("src/entryapp.march", broken) ]
    (agree ~expected:"lib/entryapp.march" ~tag:"lib")

let test_entrypoint_wins () =
  with_project ~entrypoint:"app/main.march"
    [ ("app/main.march", program "ep"); ("src/entryapp.march", broken) ]
    (agree ~expected:"app/main.march" ~tag:"ep")

let test_no_entry_is_one_error () =
  with_project [ ("README.md", "no code\n") ] (fun _root ->
      let proj = load () in
      let names_both e =
        contains e "lib/entryapp.march" && contains e "src/entryapp.march" in
      (match Project.entry proj with
       | Ok e -> Alcotest.failf "unexpected entry %s" e
       | Error e -> Alcotest.(check bool) ("Project.entry names both: " ^ e) true (names_both e));
      (match Cmd_run.resolve_entry () with
       | Ok _ -> Alcotest.fail "forge run found an entry"
       | Error e -> Alcotest.(check bool) ("forge run names both: " ^ e) true (names_both e));
      match Cmd_deploy_hot.build_so ~proj ~output:"hot" with
      | Ok _ -> Alcotest.fail "the deploy build step found an entry"
      | Error e -> Alcotest.(check bool) ("deploy names both: " ^ e) true (names_both e))

let () =
  setup_hermetic_toolchain ();
  Alcotest.run "entry_rule"
    [ ("entry rule",
       [ Alcotest.test_case "lib/<name>.march" `Slow test_lib_layout;
         Alcotest.test_case "src/<name>.march" `Slow test_src_layout;
         Alcotest.test_case "lib/ wins over src/" `Slow test_lib_wins_over_src;
         Alcotest.test_case "[package] entrypoint wins" `Slow test_entrypoint_wins;
         Alcotest.test_case "no entry: every consumer says so" `Quick
           test_no_entry_is_one_error ]) ]
