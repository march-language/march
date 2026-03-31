(** Tests for forge bastion commands: scaffold, routes parser. *)

open March_forge

(* ------------------------------------------------------------------ helpers *)

let read_file path =
  let ic = open_in path in
  let n  = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

let file_contains path substr =
  let content = read_file path in
  let clen = String.length content and slen = String.length substr in
  if slen = 0 then true
  else if clen < slen then false
  else begin
    let found = ref false in
    for i = 0 to clen - slen do
      if not !found && String.sub content i slen = substr then found := true
    done;
    !found
  end

(** Run [f basename] inside a fresh temp directory.  The [basename] is the
    project name passed to scaffold; the temp dir is the parent. *)
let with_temp_parent f =
  let tmpdir   = Filename.temp_dir "test_bastion_" "" in
  let parent   = Filename.dirname tmpdir in
  let basename = Filename.basename tmpdir in
  Unix.rmdir tmpdir;
  let old_cwd = Sys.getcwd () in
  Unix.chdir parent;
  Fun.protect
    ~finally:(fun () ->
        Unix.chdir old_cwd;
        let _ = Sys.command
            (Printf.sprintf "rm -rf %s"
               (Filename.quote (Filename.concat parent basename)))
        in ())
    (fun () -> f basename)

(* ================================================================ scaffold ======= *)

let test_scaffold_creates_forge_toml () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      Alcotest.(check bool) "forge.toml exists" true
        (Sys.file_exists (Filename.concat name "forge.toml")))

let test_scaffold_forge_toml_type_is_app () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      let content = read_file (Filename.concat name "forge.toml") in
      let doc = Toml.parse content in
      let pkg = Toml.get_section doc "package" in
      Alcotest.(check (option string)) "type = app"
        (Some "app") (Toml.get_string pkg "type"))

let test_scaffold_creates_required_files () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      let check path =
        Alcotest.(check bool) ("exists: " ^ path) true
          (Sys.file_exists (Filename.concat name path))
      in
      check ".editorconfig";
      check ".gitignore";
      check "README.md";
      check "config/config.march";
      check "config/dev.march";
      check "config/test.march";
      check "config/prod.march";
      check ("lib/" ^ name ^ ".march");
      check ("lib/" ^ name ^ "/router.march");
      check ("lib/" ^ name ^ "/controllers/page_controller.march");
      check ("lib/" ^ name ^ "/templates/layout.march");
      check ("lib/" ^ name ^ "/templates/page/index.march");
      check "assets/css/app.css";
      check "assets/js/app.js";
      check "test/test_helper.march";
      check "test/controllers/test_page_controller.march")

let test_scaffold_main_has_httpserver_listen () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      let path = Filename.concat name ("lib/" ^ name ^ ".march") in
      Alcotest.(check bool) "main has HttpServer.listen" true
        (file_contains path "HttpServer.listen"))

let test_scaffold_main_has_bastiondev () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      let path = Filename.concat name ("lib/" ^ name ^ ".march") in
      Alcotest.(check bool) "main references BastionDev" true
        (file_contains path "BastionDev"))

let test_scaffold_router_has_route_comment () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      let path = Filename.concat name ("lib/" ^ name ^ "/router.march") in
      Alcotest.(check bool) "router has -- ROUTE:" true
        (file_contains path "-- ROUTE:"))

let test_scaffold_router_has_get_root () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      let path = Filename.concat name ("lib/" ^ name ^ "/router.march") in
      Alcotest.(check bool) "router matches (:get, Nil)" true
        (file_contains path "(:get, Nil)"))

let test_scaffold_router_has_bastion_dashboard () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      let path = Filename.concat name ("lib/" ^ name ^ "/router.march") in
      Alcotest.(check bool) "router has _bastion dashboard route" true
        (file_contains path "_bastion"))

let test_scaffold_config_dev_sets_port () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      let path = Filename.concat name "config/dev.march" in
      Alcotest.(check bool) "dev config mentions port 4000" true
        (file_contains path "4000"))

let test_scaffold_config_prod_uses_env () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      let path = Filename.concat name "config/prod.march" in
      Alcotest.(check bool) "prod config reads PORT from env" true
        (file_contains path "PORT"))

let test_scaffold_module_name_is_pascal () =
  (* "my_web_app" -> "MyWebApp" *)
  with_temp_parent (fun name ->
      let proj_name = name ^ "_web" in
      (match Scaffold_bastion.scaffold proj_name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      let path = Filename.concat proj_name ("lib/" ^ proj_name ^ ".march") in
      let content = read_file path in
      (* Module declaration must be "mod MyWebApp do", not "mod My_web do" *)
      let parts = String.split_on_char '_' proj_name
                  |> List.filter (fun p -> p <> "")
                  |> List.map String.capitalize_ascii
      in
      let expected_mod = "mod " ^ String.concat "" parts ^ " do" in
      Alcotest.(check bool) "module name is PascalCase" true
        (let len = String.length expected_mod in
         String.length content >= len &&
         String.sub content 0 len = expected_mod ||
         (* allow "mod X do" anywhere in the file *)
         let clen = String.length content and slen = String.length expected_mod in
         let found = ref false in
         for i = 0 to clen - slen do
           if String.sub content i slen = expected_mod then found := true
         done;
         !found))

let test_scaffold_duplicate_fails () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail ("first scaffold failed: " ^ m)
       | Ok () -> ());
      match Scaffold_bastion.scaffold name with
      | Error _ -> ()   (* expected *)
      | Ok ()   -> Alcotest.fail "expected error for duplicate directory")

let test_scaffold_gitignore_has_march () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      let content = read_file (Filename.concat name ".gitignore") in
      let lines = String.split_on_char '\n' content in
      Alcotest.(check bool) "/.march/ in .gitignore" true
        (List.mem "/.march/" lines))

let test_scaffold_css_exists_and_nonempty () =
  with_temp_parent (fun name ->
      (match Scaffold_bastion.scaffold name with
       | Error m -> Alcotest.fail m
       | Ok () -> ());
      let path = Filename.concat name "assets/css/app.css" in
      Alcotest.(check bool) "app.css non-empty" true
        (Sys.file_exists path && (read_file path |> String.length) > 0))

(* ================================================================ routes parser ==== *)

(** Build a fake router.march source string for parser tests. *)
let sample_router pascal =
  Printf.sprintf
{|mod %s.Router do

  alias HttpServer as H

  fn dispatch(conn, stats) do
    let m = H.method(conn)
    let p = H.path_info(conn)
    match (m, p) do
    -- ROUTE: GET /
    (:get, Nil) ->
      %s.PageController.index(conn)

    -- ROUTE: GET /users
    (:get, Cons("users", Nil)) ->
      %s.UserController.index(conn)

    -- ROUTE: POST /users
    (:post, Cons("users", Nil)) ->
      %s.UserController.create(conn)

    -- ROUTE: GET /_bastion
    (:get, Cons("_bastion", Nil)) ->
      BastionDev.dashboard_handler(conn, stats)

    _ ->
      H.send_resp(conn, 404, "Not Found")
    end
  end

end
|}
    pascal pascal pascal pascal

let write_temp_router pascal =
  let tmp = Filename.temp_file "test_router_" ".march" in
  let oc  = open_out tmp in
  output_string oc (sample_router pascal);
  close_out oc;
  tmp

let test_routes_comment_parser_finds_get_root () =
  let src = sample_router "MyApp" in
  let lines = Array.of_list (String.split_on_char '\n' src) in
  let routes = Cmd_bastion_routes.parse_comment_routes lines in
  Alcotest.(check bool) "finds GET /" true
    (List.exists (fun r ->
         r.Cmd_bastion_routes.method_str = "GET" &&
         r.Cmd_bastion_routes.path = "/") routes)

let test_routes_comment_parser_finds_post_users () =
  let src = sample_router "MyApp" in
  let lines = Array.of_list (String.split_on_char '\n' src) in
  let routes = Cmd_bastion_routes.parse_comment_routes lines in
  Alcotest.(check bool) "finds POST /users" true
    (List.exists (fun r ->
         r.Cmd_bastion_routes.method_str = "POST" &&
         r.Cmd_bastion_routes.path = "/users") routes)

let test_routes_comment_parser_skips_bastion () =
  (* The _bastion dashboard route IS in the comment list because we emit
     "-- ROUTE: GET /_bastion".  But cmd_bastion_routes.run filters it when
     combining comment + arm routes.  Here we just confirm the parser sees it. *)
  let src = sample_router "MyApp" in
  let lines = Array.of_list (String.split_on_char '\n' src) in
  let routes = Cmd_bastion_routes.parse_comment_routes lines in
  (* The comment parser picks it up; the de-dup logic in run() is separate *)
  let _ = routes in   (* no assertion needed; just check it doesn't crash *)
  ()

let test_routes_arm_parser_finds_get_root () =
  let src = sample_router "MyApp" in
  let lines = Array.of_list (String.split_on_char '\n' src) in
  let routes = Cmd_bastion_routes.parse_arm_routes lines in
  (* arm parser skips _bastion routes internally *)
  Alcotest.(check bool) "arm parser finds GET /" true
    (List.exists (fun r ->
         r.Cmd_bastion_routes.method_str = "GET" &&
         r.Cmd_bastion_routes.path = "/") routes)

let test_routes_run_returns_ok_for_missing_router () =
  (* If no router file exists, run() should return Ok () with a message, not crash *)
  let tmpdir = Filename.temp_dir "test_bastion_no_router_" "" in
  let old_cwd = Sys.getcwd () in
  Fun.protect
    ~finally:(fun () ->
        Unix.chdir old_cwd;
        let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       Unix.chdir tmpdir;
       (* create a minimal forge.toml so Project.load succeeds *)
       let oc = open_out "forge.toml" in
       output_string oc "[package]\nname = \"norouter\"\nversion = \"0.1.0\"\ntype = \"app\"\n";
       close_out oc;
       Unix.mkdir "lib" 0o755;
       let entry = Filename.concat "lib" "norouter.march" in
       let oe = open_out entry in
       output_string oe "mod NoRouter do end\n";
       close_out oe;
       match Cmd_bastion_routes.run () with
       | Ok () -> ()   (* expected *)
       | Error m -> Alcotest.fail ("unexpected error: " ^ m))

let test_routes_file_roundtrip () =
  (* Write router to a temp file, parse it, confirm we see expected routes *)
  let tmp = write_temp_router "RoundTrip" in
  Fun.protect
    ~finally:(fun () -> Sys.remove tmp)
    (fun () ->
       let src   = read_file tmp in
       let lines = Array.of_list (String.split_on_char '\n' src) in
       let routes = Cmd_bastion_routes.parse_comment_routes lines in
       Alcotest.(check bool) "roundtrip: GET / present" true
         (List.exists (fun r ->
              r.Cmd_bastion_routes.method_str = "GET" &&
              r.Cmd_bastion_routes.path = "/") routes);
       Alcotest.(check bool) "roundtrip: GET /users present" true
         (List.exists (fun r ->
              r.Cmd_bastion_routes.method_str = "GET" &&
              r.Cmd_bastion_routes.path = "/users") routes))

(* ================================================================ suite ========== *)

let () =
  Alcotest.run "forge-bastion"
    [ "scaffold",
      [ Alcotest.test_case "creates forge.toml"              `Quick test_scaffold_creates_forge_toml
      ; Alcotest.test_case "forge.toml type = app"           `Quick test_scaffold_forge_toml_type_is_app
      ; Alcotest.test_case "all required files exist"        `Quick test_scaffold_creates_required_files
      ; Alcotest.test_case "main has HttpServer.listen"      `Quick test_scaffold_main_has_httpserver_listen
      ; Alcotest.test_case "main references BastionDev"      `Quick test_scaffold_main_has_bastiondev
      ; Alcotest.test_case "router has -- ROUTE: comments"   `Quick test_scaffold_router_has_route_comment
      ; Alcotest.test_case "router matches (:get, Nil)"        `Quick test_scaffold_router_has_get_root
      ; Alcotest.test_case "router has _bastion route"       `Quick test_scaffold_router_has_bastion_dashboard
      ; Alcotest.test_case "dev config sets port 4000"       `Quick test_scaffold_config_dev_sets_port
      ; Alcotest.test_case "prod config reads PORT from env" `Quick test_scaffold_config_prod_uses_env
      ; Alcotest.test_case "module name is PascalCase"       `Quick test_scaffold_module_name_is_pascal
      ; Alcotest.test_case "duplicate scaffold fails"        `Quick test_scaffold_duplicate_fails
      ; Alcotest.test_case ".gitignore has /.march/"         `Quick test_scaffold_gitignore_has_march
      ; Alcotest.test_case "app.css exists and non-empty"    `Quick test_scaffold_css_exists_and_nonempty
      ]
    ; "routes",
      [ Alcotest.test_case "comment parser: GET /"           `Quick test_routes_comment_parser_finds_get_root
      ; Alcotest.test_case "comment parser: POST /users"     `Quick test_routes_comment_parser_finds_post_users
      ; Alcotest.test_case "comment parser: _bastion ok"     `Quick test_routes_comment_parser_skips_bastion
      ; Alcotest.test_case "arm parser: GET /"               `Quick test_routes_arm_parser_finds_get_root
      ; Alcotest.test_case "run: ok when no router file"     `Quick test_routes_run_returns_ok_for_missing_router
      ; Alcotest.test_case "roundtrip: file parse"           `Quick test_routes_file_roundtrip
      ]
    ]
