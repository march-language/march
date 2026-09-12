(** The dependency cache is VERSION-AWARE: two projects wanting different
    versions of one dependency must not share, or destroy, one directory.

    Before 2026-09-12 the cache was keyed by dep NAME alone
    ([~/.march/cas/deps/<name>]). For a git dep that caused thrash; for a
    REGISTRY dep it was destructive, because install did an unconditional
    `rm -rf` of the destination with no check at all — so installing
    `bastion 0.3.1` silently deleted the `bastion 0.2.0` another project was
    building against. The layout is now [deps/<name>/<coord>], where the
    coordinate is the resolved commit (git) or exact version (registry), read
    back out of forge.lock by [Project.dep_coords].

    These tests drive the RESOLUTION side against fixtures on a fake HOME,
    which is what a build actually depends on; they need no network. The
    installer's own `rm -rf` is covered by the layout: it can only ever target
    one coordinate directory, never a sibling. *)

open March_forge

let tmp_dir prefix =
  let base = Filename.get_temp_dir_name () in
  let rec attempt n =
    let path = Filename.concat base (Printf.sprintf "%s-%d-%d" prefix (Unix.getpid ()) n) in
    if Sys.file_exists path then attempt (n + 1)
    else (Unix.mkdir path 0o755; path)
  in
  attempt 0

let rec rm_rf path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Array.iter (fun n -> rm_rf (Filename.concat path n)) (Sys.readdir path);
      Unix.rmdir path
    end else Sys.remove path

let mkdir_p dir =
  let rec go d =
    if not (Sys.file_exists d) then begin
      go (Filename.dirname d);
      (try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
    end
  in go dir

let write_file path content =
  mkdir_p (Filename.dirname path);
  let oc = open_out path in output_string oc content; close_out oc

let with_fake_home f =
  let home = tmp_dir "dep-cache-home" in
  let prev = Sys.getenv_opt "HOME" in
  Unix.putenv "HOME" home;
  Fun.protect
    ~finally:(fun () ->
        (match prev with Some h -> Unix.putenv "HOME" h | None -> ());
        rm_rf home)
    (fun () -> f home)

let deps_root home =
  Filename.concat home
    (Filename.concat ".march" (Filename.concat "cas" "deps"))

(** Install a fake package tree for [name] at coordinate [coord], with a
    marker file inside lib/ naming the version so a test can tell which
    version it resolved to. *)
let install_fake ~home ~name ~coord ~marker =
  let dir = Filename.concat (Filename.concat (deps_root home) name) coord in
  write_file (Filename.concat dir "forge.toml")
    (Printf.sprintf "[package]\nname = %S\n" name);
  write_file (Filename.concat (Filename.concat dir "lib") "m.march") marker;
  dir

let lockfile ~root entries =
  let path = Filename.concat root "forge.lock" in
  Resolver_lockfile.write path entries ~manifest_hash:"sha256:test";
  path

(* ------------------------------------------------------------------ *)

(** The headline property: two versions coexist, and each project's lockfile
    selects its own. Under the old name-keyed layout only one could exist at
    all, so this is unrepresentable there. *)
let test_two_versions_coexist () =
  with_fake_home (fun home ->
      let d1 = install_fake ~home ~name:"bastion" ~coord:"0.2.0" ~marker:"v020" in
      let d2 = install_fake ~home ~name:"bastion" ~coord:"0.3.1" ~marker:"v031" in
      Alcotest.(check bool) "0.2.0 tree still present" true (Sys.file_exists d1);
      Alcotest.(check bool) "0.3.1 tree still present" true (Sys.file_exists d2);

      let proj_a = tmp_dir "dep-cache-a" and proj_b = tmp_dir "dep-cache-b" in
      Fun.protect ~finally:(fun () -> rm_rf proj_a; rm_rf proj_b) (fun () ->
          ignore (lockfile ~root:proj_a [
              Resolver_lockfile.{ name = "bastion"; version = Some "0.2.0";
                                  source = "registry:forge"; commit = None;
                                  hash = "sha256:aa"; checksum = Some "sha256:bb" } ]);
          ignore (lockfile ~root:proj_b [
              Resolver_lockfile.{ name = "bastion"; version = Some "0.3.1";
                                  source = "registry:forge"; commit = None;
                                  hash = "sha256:cc"; checksum = Some "sha256:dd" } ]);
          let resolve root =
            let coords = Project.dep_coords ~project_root:root in
            match Project.git_dep_lib_path ~coords "bastion" with
            | None -> Alcotest.fail "dep did not resolve"
            | Some lib ->
              let ic = open_in (Filename.concat lib "m.march") in
              Fun.protect ~finally:(fun () -> close_in_noerr ic)
                (fun () -> input_line ic)
          in
          Alcotest.(check string) "project A gets 0.2.0" "v020" (resolve proj_a);
          Alcotest.(check string) "project B gets 0.3.1" "v031" (resolve proj_b)))

(** A git dep is keyed by COMMIT, so a tag that moves does not alias. *)
let test_git_dep_keyed_by_commit () =
  with_fake_home (fun home ->
      ignore (install_fake ~home ~name:"depot" ~coord:"aaaa1111" ~marker:"old");
      ignore (install_fake ~home ~name:"depot" ~coord:"bbbb2222" ~marker:"new");
      let proj = tmp_dir "dep-cache-git" in
      Fun.protect ~finally:(fun () -> rm_rf proj) (fun () ->
          ignore (lockfile ~root:proj [
              Resolver_lockfile.{ name = "depot"; version = Some "1.0.0";
                                  source = "git:https://example.com/depot.git";
                                  commit = Some "bbbb2222";
                                  hash = "sha256:ee"; checksum = None } ]);
          let coords = Project.dep_coords ~project_root:proj in
          match Project.git_dep_lib_path ~coords "depot" with
          | None -> Alcotest.fail "git dep did not resolve"
          | Some lib ->
            Alcotest.(check bool) "resolved to the locked commit, not the other" true
              (String.length lib > 8
               && Filename.basename (Filename.dirname (Filename.dirname lib)) = "depot")
            ;
            let ic = open_in (Filename.concat lib "m.march") in
            let line = Fun.protect ~finally:(fun () -> close_in_noerr ic)
                (fun () -> input_line ic) in
            Alcotest.(check string) "content is the locked commit's" "new" line))

(** A legacy FLAT install (the pre-2026-09-12 layout) still resolves, so an
    upgrade does not break a build before `forge deps` migrates it. *)
let test_legacy_flat_install_still_resolves () =
  with_fake_home (fun home ->
      let flat = Filename.concat (deps_root home) "widget" in
      write_file (Filename.concat flat "forge.toml") "[package]\nname = \"widget\"\n";
      write_file (Filename.concat (Filename.concat flat "lib") "m.march") "flat";
      let proj = tmp_dir "dep-cache-legacy" in
      Fun.protect ~finally:(fun () -> rm_rf proj) (fun () ->
          let coords = Project.dep_coords ~project_root:proj in
          match Project.git_dep_lib_path ~coords "widget" with
          | None -> Alcotest.fail "legacy flat install stopped resolving"
          | Some lib ->
            Alcotest.(check string) "legacy lib dir"
              (Filename.concat flat "lib") lib))

(** With no lockfile entry and exactly ONE cached version, resolution is
    unambiguous and succeeds. *)
let test_single_version_resolves_without_lockfile () =
  with_fake_home (fun home ->
      ignore (install_fake ~home ~name:"solo" ~coord:"1.2.3" ~marker:"only");
      let proj = tmp_dir "dep-cache-solo" in
      Fun.protect ~finally:(fun () -> rm_rf proj) (fun () ->
          match Project.git_dep_lib_path "solo" with
          | None -> Alcotest.fail "single cached version should resolve"
          | Some lib ->
            let ic = open_in (Filename.concat lib "m.march") in
            let line = Fun.protect ~finally:(fun () -> close_in_noerr ic)
                (fun () -> input_line ic) in
            Alcotest.(check string) "resolved the only version" "only" line))

(** With no lockfile entry and SEVERAL cached versions, resolution must refuse
    rather than guess. Guessing which version a project wanted is the mistake
    the version-aware layout exists to prevent. *)
let test_ambiguous_without_lockfile_refuses () =
  with_fake_home (fun home ->
      ignore (install_fake ~home ~name:"ambig" ~coord:"1.0.0" ~marker:"a");
      ignore (install_fake ~home ~name:"ambig" ~coord:"2.0.0" ~marker:"b");
      Alcotest.(check bool) "two cached versions with no lockfile do not resolve"
        true (Project.git_dep_lib_path "ambig" = None))

(** [dep_coords] must ignore entries that name no coordinate: a path dep has
    neither commit nor registry version, and must not be looked up in the CAS. *)
let test_path_dep_contributes_no_coordinate () =
  let proj = tmp_dir "dep-cache-path" in
  Fun.protect ~finally:(fun () -> rm_rf proj) (fun () ->
      ignore (lockfile ~root:proj [
          Resolver_lockfile.{ name = "local"; version = None;
                              source = "path:../local"; commit = None;
                              hash = "sha256:ff"; checksum = None } ]);
      let coords = Project.dep_coords ~project_root:proj in
      Alcotest.(check bool) "path dep absent from the coordinate table"
        false (Hashtbl.mem coords "local"))

let () =
  Alcotest.run "forge-dep-cache-versions"
    [ ( "version-aware cache",
        [ Alcotest.test_case "two versions of one dep coexist" `Quick
            test_two_versions_coexist;
          Alcotest.test_case "git dep keyed by commit" `Quick
            test_git_dep_keyed_by_commit;
          Alcotest.test_case "legacy flat install still resolves" `Quick
            test_legacy_flat_install_still_resolves;
          Alcotest.test_case "single version resolves without a lockfile" `Quick
            test_single_version_resolves_without_lockfile;
          Alcotest.test_case "ambiguous without a lockfile refuses" `Quick
            test_ambiguous_without_lockfile_refuses;
          Alcotest.test_case "path dep contributes no coordinate" `Quick
            test_path_dep_contributes_no_coordinate ] ) ]
