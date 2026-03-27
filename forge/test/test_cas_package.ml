(** Tests for the package CAS — canonical archive, hashing, integrity. *)

open March_forge

(* ------------------------------------------------------------------ *)
(*  Helpers                                                            *)
(* ------------------------------------------------------------------ *)

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let mkdir path =
  try Unix.mkdir path 0o755
  with Unix.Unix_error (Unix.EEXIST, _, _) -> ()

let with_temp_dir f =
  let d = Filename.temp_dir "test_cas_" "" in
  Fun.protect ~finally:(fun () ->
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote d)) in ())
    (fun () -> f d)

(** Create a minimal package directory structure. *)
let make_package dir files =
  List.iter (fun (rel_path, content) ->
      let abs = Filename.concat dir rel_path in
      let abs_dir = Filename.dirname abs in
      let _ = Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote abs_dir)) in
      write_file abs content
    ) files

(* ------------------------------------------------------------------ *)
(*  Canonical archive                                                  *)
(* ------------------------------------------------------------------ *)

let test_collect_files_sorted () =
  with_temp_dir (fun d ->
      write_file (Filename.concat d "b.march") "mod B do end";
      write_file (Filename.concat d "a.march") "mod A do end";
      mkdir (Filename.concat d "lib");
      write_file (Filename.concat d "lib/c.march") "mod C do end";
      let files = Resolver_cas_package.collect_files d in
      (* Should be sorted: a.march, b.march, lib/c.march *)
      Alcotest.(check (list string)) "sorted lexicographic"
        ["a.march"; "b.march"; "lib/c.march"] files)

let test_collect_files_skips_git () =
  with_temp_dir (fun d ->
      write_file (Filename.concat d "main.march") "mod Main do end";
      mkdir (Filename.concat d ".git");
      write_file (Filename.concat d ".git/HEAD") "ref: refs/heads/main";
      let files = Resolver_cas_package.collect_files d in
      Alcotest.(check (list string)) "no .git files" ["main.march"] files)

let test_hash_deterministic () =
  with_temp_dir (fun d ->
      make_package d [
        ("lib/main.march", "mod Main do\nfn main() do IO.print \"hello\" end\nend");
        ("forge.toml", "[package]\nname = \"myapp\"\nversion = \"1.0.0\"\n");
      ];
      let h1 = Resolver_cas_package.hash_directory d in
      let h2 = Resolver_cas_package.hash_directory d in
      Alcotest.(check string) "deterministic" h1 h2;
      Alcotest.(check bool) "sha256 prefix"
        true (String.length h1 > 7 && String.sub h1 0 7 = "sha256:"))

let test_hash_changes_with_content () =
  with_temp_dir (fun d1 ->
      with_temp_dir (fun d2 ->
          make_package d1 [("main.march", "mod A do end")];
          make_package d2 [("main.march", "mod B do end")];
          let h1 = Resolver_cas_package.hash_directory d1 in
          let h2 = Resolver_cas_package.hash_directory d2 in
          Alcotest.(check bool) "different content → different hash" true (h1 <> h2)))

let test_hash_stable_across_order () =
  (* Add files in different order — same content = same hash *)
  with_temp_dir (fun d1 ->
      with_temp_dir (fun d2 ->
          make_package d1 [("a.march", "A"); ("b.march", "B")];
          make_package d2 [("b.march", "B"); ("a.march", "A")];
          (* Since we sort before hashing, both archives should be identical *)
          let h1 = Resolver_cas_package.hash_directory d1 in
          let h2 = Resolver_cas_package.hash_directory d2 in
          Alcotest.(check string) "sorted → same hash" h1 h2))

let test_hash_ignores_git_dir () =
  with_temp_dir (fun d ->
      make_package d [("lib/main.march", "mod Main do end")];
      let h1 = Resolver_cas_package.hash_directory d in
      (* Add a .git directory with junk *)
      mkdir (Filename.concat d ".git");
      write_file (Filename.concat d ".git/COMMIT_EDITMSG") "some commit message";
      let h2 = Resolver_cas_package.hash_directory d in
      Alcotest.(check string) ".git excluded from hash" h1 h2)

(* ------------------------------------------------------------------ *)
(*  CAS store / retrieve / verify                                      *)
(* ------------------------------------------------------------------ *)

let test_store_and_lookup () =
  (* Override HOME to an isolated tmp dir for CAS *)
  with_temp_dir (fun tmp_home ->
      let old_home = try Some (Sys.getenv "HOME") with Not_found -> None in
      Unix.putenv "HOME" tmp_home;
      Fun.protect ~finally:(fun () ->
          match old_home with
          | Some h -> Unix.putenv "HOME" h
          | None   -> ())
        (fun () ->
           with_temp_dir (fun pkg_dir ->
               make_package pkg_dir [("lib/main.march", "mod Pkg do end")];
               let hash = Resolver_cas_package.store_directory
                   ~name:"mypkg" ~source:"git:example.com/mypkg" pkg_dir in
               (* Should be findable *)
               Alcotest.(check bool) "lookup succeeds"
                 true (Resolver_cas_package.lookup hash <> None))))

let test_store_idempotent () =
  with_temp_dir (fun tmp_home ->
      let old_home = try Some (Sys.getenv "HOME") with Not_found -> None in
      Unix.putenv "HOME" tmp_home;
      Fun.protect ~finally:(fun () ->
          match old_home with
          | Some h -> Unix.putenv "HOME" h
          | None   -> ())
        (fun () ->
           with_temp_dir (fun pkg_dir ->
               make_package pkg_dir [("lib/main.march", "mod Pkg do end")];
               let h1 = Resolver_cas_package.store_directory pkg_dir in
               let h2 = Resolver_cas_package.store_directory pkg_dir in
               Alcotest.(check string) "idempotent hash" h1 h2)))

let test_verify_intact () =
  with_temp_dir (fun tmp_home ->
      let old_home = try Some (Sys.getenv "HOME") with Not_found -> None in
      Unix.putenv "HOME" tmp_home;
      Fun.protect ~finally:(fun () ->
          match old_home with
          | Some h -> Unix.putenv "HOME" h
          | None   -> ())
        (fun () ->
           with_temp_dir (fun pkg_dir ->
               make_package pkg_dir [("lib/main.march", "mod Pkg do end")];
               let hash = Resolver_cas_package.store_directory pkg_dir in
               match Resolver_cas_package.verify hash with
               | Ok ()   -> ()
               | Error e -> Alcotest.fail ("verify failed: " ^ e))))

let test_verify_detects_tampering () =
  with_temp_dir (fun tmp_home ->
      let old_home = try Some (Sys.getenv "HOME") with Not_found -> None in
      Unix.putenv "HOME" tmp_home;
      Fun.protect ~finally:(fun () ->
          match old_home with
          | Some h -> Unix.putenv "HOME" h
          | None   -> ())
        (fun () ->
           with_temp_dir (fun pkg_dir ->
               make_package pkg_dir [("lib/main.march", "mod Pkg do end")];
               let hash = Resolver_cas_package.store_directory pkg_dir in
               (* Tamper with the archive *)
               (match Resolver_cas_package.lookup hash with
                | None -> Alcotest.fail "package not found"
                | Some archive_path ->
                  (* Append junk to corrupt the archive *)
                  let oc = open_out_gen [Open_append; Open_binary] 0o644 archive_path in
                  output_string oc "TAMPERED";
                  close_out oc);
               match Resolver_cas_package.verify hash with
               | Error _ -> ()   (* expected: tampering detected *)
               | Ok ()   -> Alcotest.fail "expected verify to fail on tampered archive")))

(* ------------------------------------------------------------------ *)
(*  Suite                                                               *)
(* ------------------------------------------------------------------ *)

let () =
  Alcotest.run "forge-cas" [
    "canonical-archive", [
      Alcotest.test_case "files sorted lexicographically"  `Quick test_collect_files_sorted;
      Alcotest.test_case ".git directory excluded"         `Quick test_collect_files_skips_git;
      Alcotest.test_case "hash is deterministic"           `Quick test_hash_deterministic;
      Alcotest.test_case "different content → diff hash"   `Quick test_hash_changes_with_content;
      Alcotest.test_case "add order irrelevant (sorted)"   `Quick test_hash_stable_across_order;
      Alcotest.test_case ".git excluded from hash"         `Quick test_hash_ignores_git_dir;
    ];
    "cas-store", [
      Alcotest.test_case "store and lookup"                `Quick test_store_and_lookup;
      Alcotest.test_case "store is idempotent"             `Quick test_store_idempotent;
      Alcotest.test_case "verify intact archive"           `Quick test_verify_intact;
      Alcotest.test_case "verify detects tampering"        `Quick test_verify_detects_tampering;
    ];
  ]
