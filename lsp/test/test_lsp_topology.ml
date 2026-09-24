(** The topology file in the editor (build step 7 of the distributed-deploys
    plan): [March_lsp_lib.Topology_doc] over a scratch project on disk.

    The parity tests compute forge's own answer ([Topology.load] +
    [Topology.index_project] + [Topology.check], exactly what
    [forge topology check] runs) over the same files and require the LSP's
    diagnostics to carry the same messages on the same lines, so the two
    cannot drift apart silently. *)

open Test_lsp_harness

module TD = March_lsp_lib.Topology_doc
module T = March_forge.Topology

(* ------------------------------------------------------------------ fixture *)

let shop_march = {|mod Shop do
  needs IO
  needs Session.Live

  @[endpoints]
  protocol Checkout do
    role Ledger needs IO.FileWrite
    order: Client -> Ledger : Int
    receipt: Ledger -> Client : Int
  end

  @[endpoints]
  protocol Thumbs do
    Edge -> Render : Int
    Render -> Edge : Int
  end

  @[endpoints]
  protocol Quotes do
    ask: Client -> Server : Int
    reply: Server -> Client : Int
  end

  mod Ledger do
    fn serve_one(env, s, st) do 0 end
  end

  mod Render do
    fn render_one(env, s, st) do 0 end
  end

  mod Edge do
    fn start(c, node) do 1 end
  end

  actor ServerActor do
    state { n : Int }
    init { n: 0 }
  end

  fn main(c : Cap(IO)) do 0 end
end
|}

let base_toml = {|[roles]
"Checkout.Ledger" = { body = "Shop.Ledger.serve_one", capacity = 64 }
"Thumbs.Render"   = { body = "Shop.Render.render_one", place = { on = "gpu", count = 2 } }
"Quotes.Server"   = { actor = "Shop.ServerActor" }

[pool.edge]
start  = "Shop.Edge.start"
public = [443]

[pool.ledger]
serves = ["Checkout.Ledger", "Quotes.Server"]

[pool.imaging]
serves  = ["Thumbs.Render"]
isolate = true
|}

let prod_toml = {|[pool.imaging]
hosts = [{ host = "root@render-1", labels = ["gpu"] }, "root@render-2"]

[pool.ledger]
hosts = ["root@db-1"]
|}

let write path content =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

(** A scratch project with lib/shop.march and the topology files. The
    LSP's buffer tables are cleared before and after, so one test's open
    documents never leak into the next. *)
let with_project ?(base = base_toml) ?(prod = Some prod_toml) f =
  let root = Filename.temp_dir "lsp_topology_" "" in
  let reset () =
    Hashtbl.reset TD.open_docs;
    Hashtbl.reset TD.march_buffers
  in
  reset ();
  Fun.protect
    ~finally:(fun () ->
        reset ();
        ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote root))))
    (fun () ->
       write (Filename.concat root "forge.toml")
         "[package]\nname = \"shop\"\nversion = \"0.1.0\"\ntype = \"app\"\n";
       Sys.mkdir (Filename.concat root "lib") 0o755;
       write (Filename.concat root "lib/shop.march") shop_march;
       write (Filename.concat root "topology.toml") base;
       (match prod with
        | Some p -> write (Filename.concat root "topology.prod.toml") p
        | None -> ());
       f root)

let base_path root = Filename.concat root "topology.toml"
let prod_path root = Filename.concat root "topology.prod.toml"
let shop_path root = Filename.concat root "lib/shop.march"

(** forge's answer, as [forge topology check [--env]] computes it:
    [(file basename, line, is_error, message)]. *)
let forge_diags ?env root =
  let ds =
    match T.load ~root ?env () with
    | Error ds -> ds
    | Ok t -> T.check ~index:(T.index_project ~root) t
  in
  List.map (fun (d : T.diag) ->
      (Filename.basename d.T.loc.T.file, d.T.loc.T.line, d.T.severity = T.Error, d.T.msg))
    ds

(** The LSP's diagnostics for [path]: [(line (1-based), is_error, message, source)]. *)
let lsp_diags path =
  List.map (fun (d : Lsp.Types.Diagnostic.t) ->
      ( d.range.start.line + 1,
        d.severity = Some Lsp.Types.DiagnosticSeverity.Error,
        (match d.message with `String s -> s | _ -> ""),
        Option.value ~default:"" d.source ))
    (TD.diagnostics_for path)

let show_forge ds =
  String.concat "\n" (List.map (fun (f, l, e, m) -> Printf.sprintf "%s:%d:%s %s" f l (if e then "" else " warning:") m) ds)

let show_lsp ds =
  String.concat "\n" (List.map (fun (l, e, m, s) -> Printf.sprintf "%d:%s %s [%s]" l (if e then "" else " warning:") m s) ds)

let has_msg ~sub ds = List.exists (fun (_, _, m, _) -> str_contains ~sub m) ds

(** Every forge diagnostic that points into [file] is on the LSP's list for
    that document, same line, same severity, same text. *)
let check_parity ~what ~file forge lsp =
  List.iter (fun (f, l, e, m) ->
      if f = Filename.basename file && l > 0 then
        if not (List.exists (fun (l', e', m', _) -> l = l' && e = e' && m = m') lsp) then
          Alcotest.failf "%s: forge reports %s:%d: %s\nbut the LSP has:\n%s\n(forge: %s)"
            what f l m (show_lsp lsp) (show_forge forge))
    forge

(** The diagnostic with [sub] in its message, or fail. *)
let find_diag ~sub path =
  match List.find_opt (fun (d : Lsp.Types.Diagnostic.t) ->
      match d.message with `String s -> str_contains ~sub s | _ -> false)
      (TD.diagnostics_for path) with
  | Some d -> d
  | None -> Alcotest.failf "no diagnostic containing %S:\n%s" sub (show_lsp (lsp_diags path))

(** (line, utf16 char) of the first occurrence of [sub] in [text], plus [off]. *)
let at text sub ?(off = 0) () =
  let (l, c) = pos_of text sub in
  (l, c + off)

(* -------------------------------------------------------------- recognition *)

let test_recognises_topology_paths () =
  let k p = match TD.kind_of_path p with
    | Some TD.Base -> "base" | Some (TD.Overlay e) -> "overlay:" ^ e | None -> "no" in
  Alcotest.(check string) "base" "base" (k "/p/topology.toml");
  Alcotest.(check string) "overlay" "overlay:prod" (k "/p/topology.prod.toml");
  Alcotest.(check string) "overlay with dash" "overlay:eu-west" (k "/p/topology.eu-west.toml");
  Alcotest.(check string) "forge.toml" "no" (k "/p/forge.toml");
  Alcotest.(check string) "empty env" "no" (k "/p/topology..toml");
  Alcotest.(check string) "march" "no" (k "/p/topology.march")

(* ---------------------------------------------------------------- diagnostics *)

let test_clean_topology_has_no_errors () =
  let prod = "[pool.imaging]\nhosts = [{ host = \"root@r-1\", labels = [\"gpu\"] }, { host = \"root@r-2\", labels = [\"gpu\"] }]\n" in
  with_project ~prod:(Some prod) (fun root ->
      TD.set_open (base_path root) base_toml;
      let ds = lsp_diags (base_path root) in
      if List.exists (fun (_, e, _, _) -> e) ds then
        Alcotest.failf "unexpected errors:\n%s" (show_lsp ds))

let test_unknown_key_matches_forge () =
  let base = base_toml ^ "\n[pool.extra]\nstart = \"Shop.Edge.start\"\nreplica = 2\n" in
  with_project ~base (fun root ->
      TD.set_open (base_path root) base;
      let forge = forge_diags root and lsp = lsp_diags (base_path root) in
      check_parity ~what:"unknown key" ~file:(base_path root) forge lsp;
      if not (has_msg ~sub:"unknown key 'replica' in [pool.extra]" lsp) then
        Alcotest.failf "unknown key not reported:\n%s" (show_lsp lsp);
      (* forge's line: the key's own line. *)
      let d = find_diag ~sub:"unknown key 'replica'" (base_path root) in
      let (kl, kc) = pos_of base "replica = 2" in
      Alcotest.(check int) "line" kl d.range.start.line;
      Alcotest.(check int) "covers the written text from its first column" kc d.range.start.character;
      Alcotest.(check int) "to its end" (kc + String.length "replica = 2") d.range.end_.character)

let test_unbound_served_role_matches_forge () =
  let base = base_toml ^ "\n[pool.more]\nserves = [\"Checkout.Client\"]\n" in
  with_project ~base (fun root ->
      TD.set_open (base_path root) base;
      let forge = forge_diags root and lsp = lsp_diags (base_path root) in
      check_parity ~what:"unbound served role" ~file:(base_path root) forge lsp;
      if not (has_msg ~sub:"serves \"Checkout.Client\", which has no binding in [roles]" lsp) then
        Alcotest.failf "unbound served role not reported:\n%s" (show_lsp lsp))

let test_unknown_label_under_overlay () =
  (* The base asks for `on = "gpu"`; an overlay whose hosts carry no such
     label makes it an error, reported by `--env prod` at the ROLE's line in
     the base file. *)
  let prod = "[pool.imaging]\nhosts = [\"root@render-1\", \"root@render-2\"]\n\n[pool.ledger]\nhosts = [\"root@db-1\"]\n" in
  with_project ~prod:(Some prod) (fun root ->
      TD.set_open (base_path root) base_toml;
      let forge = forge_diags ~env:"prod" root and lsp = lsp_diags (base_path root) in
      check_parity ~what:"unknown label" ~file:(base_path root) forge lsp;
      let sub = "place.on = \"gpu\", but no host of [pool.imaging] carries that label" in
      if not (has_msg ~sub lsp) then Alcotest.failf "unknown label not reported:\n%s" (show_lsp lsp);
      let (_, _, _, src) = List.find (fun (_, _, m, _) -> str_contains ~sub m) lsp in
      Alcotest.(check string) "says which overlay raised it" "forge topology --env prod" src;
      (* The base alone has no hosts, so forge without --env is silent. *)
      if List.exists (fun (_, _, _, m) -> str_contains ~sub m) (forge_diags root) then
        Alcotest.fail "fixture: the base alone should not raise the label error")

let test_count_above_hosts_under_overlay () =
  (* count = 2 on "gpu", and prod has one gpu host. *)
  with_project (fun root ->
      TD.set_open (base_path root) base_toml;
      let forge = forge_diags ~env:"prod" root and lsp = lsp_diags (base_path root) in
      check_parity ~what:"count" ~file:(base_path root) forge lsp;
      let sub = "place.count = 2, but only 1 host carries the label \"gpu\"" in
      if not (has_msg ~sub lsp) then Alcotest.failf "count not reported:\n%s" (show_lsp lsp);
      let (l, _, _, _) = List.find (fun (_, _, m, _) -> str_contains ~sub m) lsp in
      Alcotest.(check int) "at the role's line" (fst (pos_of base_toml "\"Thumbs.Render\"") + 1) l)

let test_unlabelled_steps_warning () =
  with_project (fun root ->
      TD.set_open (base_path root) base_toml;
      let forge = forge_diags root and lsp = lsp_diags (base_path root) in
      check_parity ~what:"D25" ~file:(base_path root) forge lsp;
      let sub = "protocol 'Thumbs' has 2 unlabelled steps" in
      match List.find_opt (fun (_, _, m, _) -> str_contains ~sub m) lsp with
      | None -> Alcotest.failf "D25 warning missing:\n%s" (show_lsp lsp)
      | Some (_, is_err, _, _) -> Alcotest.(check bool) "a warning" false is_err)

let test_overlay_shows_its_own_diagnostics () =
  let prod = prod_toml ^ "\n[pool.edge]\nhosts = [{ host = \"root@web-1\", label = [\"x\"] }]\n" in
  with_project ~prod:(Some prod) (fun root ->
      TD.set_open (prod_path root) prod;
      let forge = forge_diags ~env:"prod" root and lsp = lsp_diags (prod_path root) in
      check_parity ~what:"overlay" ~file:(prod_path root) forge lsp;
      if not (has_msg ~sub:"unknown key 'label' in [pool.edge] hosts" lsp) then
        Alcotest.failf "overlay key error not on the overlay:\n%s" (show_lsp lsp);
      (* ...and only the overlay's: nothing that forge places in the base. *)
      if has_msg ~sub:"unlabelled" lsp then
        Alcotest.failf "the base's warning leaked onto the overlay:\n%s" (show_lsp lsp))

let test_malformed_toml_line () =
  let base = base_toml ^ "\n[pool.bad\n" in
  with_project ~base (fun root ->
      TD.set_open (base_path root) base;
      let forge = forge_diags root and lsp = lsp_diags (base_path root) in
      check_parity ~what:"parse error" ~file:(base_path root) forge lsp;
      if not (has_msg ~sub:"unterminated section header" lsp) then
        Alcotest.failf "parse error missing:\n%s" (show_lsp lsp))

(** The acceptance test for "the diagnostics follow the code": the topology
    document is untouched, the `.march` buffer changes, and the topology's
    diagnostics change with it, then change back. *)
let test_march_edit_updates_topology_diagnostics () =
  with_project (fun root ->
      TD.set_open (base_path root) base_toml;
      let sub = "body 'Shop.Ledger.serve_one' is not a function declared in the project" in
      if has_msg ~sub (lsp_diags (base_path root)) then Alcotest.fail "error before the edit";
      (* Rename the function in the editor buffer only; the disk still has it. *)
      let edited = Str.global_replace (Str.regexp_string "fn serve_one") "fn serve_two" shop_march in
      TD.set_march_buffer (shop_path root) edited;
      Alcotest.(check (list string)) "the edited buffer's file depends on it"
        [ base_path root ] (TD.dependents_of (shop_path root));
      let d = find_diag ~sub (base_path root) in
      Alcotest.(check int) "at the role's line" (fst (pos_of base_toml "\"Checkout.Ledger\"")) d.range.start.line;
      (* Undo in the buffer: gone again. *)
      TD.set_march_buffer (shop_path root) shop_march;
      if has_msg ~sub (lsp_diags (base_path root)) then Alcotest.fail "error survived the undo";
      (* A buffer that no longer parses: forge's warning, on the first line. *)
      TD.set_march_buffer (shop_path root) "mod Shop do\n  fn (\n";
      if not (has_msg ~sub:"could not parse shop.march" (lsp_diags (base_path root))) then
        Alcotest.failf "parse warning missing:\n%s" (show_lsp (lsp_diags (base_path root)));
      (* Closing the buffer goes back to the disk. *)
      TD.close_march_buffer (shop_path root);
      if has_msg ~sub:"could not parse" (lsp_diags (base_path root)) then
        Alcotest.fail "closed buffer still read")

(* ---------------------------------------------------------------- definition *)

let def_line path text sub ?off () =
  let (line, utf16_char) = at text sub ?off () in
  match TD.definition_at ~path ~line ~utf16_char with
  | None -> Alcotest.failf "no definition for %S" sub
  | Some (l : Lsp.Types.Location.t) ->
    (Lsp.Types.DocumentUri.to_path l.uri, l.range.start.line, l.range.start.character)

let check_def ~what ~root (file, line, col) expected_sub =
  Alcotest.(check string) (what ^ ": file") (shop_path root) file;
  let (el, ec) = pos_of shop_march expected_sub in
  Alcotest.(check (pair int int)) (what ^ ": position") (el, ec) (line, col)

let test_definition_on_bindings () =
  with_project (fun root ->
      let p = base_path root in
      TD.set_open p base_toml;
      check_def ~what:"body" ~root (def_line p base_toml "Shop.Ledger.serve_one" ~off:3 ()) "serve_one";
      check_def ~what:"actor" ~root (def_line p base_toml "Shop.ServerActor" ~off:6 ()) "ServerActor";
      check_def ~what:"start" ~root (def_line p base_toml "Shop.Edge.start" ~off:12 ()) "start(c, node)")

let test_definition_on_role_strings () =
  with_project (fun root ->
      let p = base_path root in
      TD.set_open p base_toml;
      (* serves = ["Checkout.Ledger", ...]: the protocol part, then the role part. *)
      let serves_line = "serves = [\"Checkout.Ledger\"" in
      check_def ~what:"protocol part" ~root
        (def_line p base_toml serves_line ~off:(String.length "serves = [\"Chec") ())
        "Checkout do";
      check_def ~what:"role part (its grant line)" ~root
        (def_line p base_toml serves_line ~off:(String.length "serves = [\"Checkout.Led") ())
        "Ledger needs";
      (* A [roles] key, and a role with no grant line: its first message. *)
      check_def ~what:"roles key, ungranted role" ~root
        (def_line p base_toml "\"Quotes.Server\"" ~off:10 ())
        "Server : Int")

(* ---------------------------------------------------------------- completion *)

let labels_at path text sub ?off () =
  let (line, utf16_char) = at text sub ?off () in
  List.map (fun (i : Lsp.Types.CompletionItem.t) -> i.label)
    (TD.completions_at ~path ~line ~utf16_char)

let check_mem ~what x xs =
  if not (List.mem x xs) then
    Alcotest.failf "%s: %S not among [%s]" what x (String.concat "; " xs)

let check_not_mem ~what x xs =
  if List.mem x xs then Alcotest.failf "%s: %S should not be offered" what x

let test_completion_in_strings () =
  let text = {|[roles]
"Checkout.Ledger" = { body = "Shop.Led", capacity = 64 }
"Quotes.Server"   = { actor = "" }
"Thumbs.Render"   = { body = "Shop.Render.render_one", place = { on = "" } }

[pool.edge]
start = "
serves = ["Checkout.Ledger", ""]
initiates = [""]
hosts = [{ host = "h", labels = ["gpu"] }]
|} in
  with_project ~base:text (fun root ->
      let p = base_path root in
      TD.set_open p text;
      let body = labels_at p text "\"Shop.Led\"" ~off:9 () in
      check_mem ~what:"body" "Shop.Ledger.serve_one" body;
      check_not_mem ~what:"body offers functions, not actors" "Shop.ServerActor" body;
      let actor = labels_at p text "actor = \"\"" ~off:9 () in
      check_mem ~what:"actor" "Shop.ServerActor" actor;
      check_not_mem ~what:"actor offers actors" "Shop.Ledger.serve_one" actor;
      check_mem ~what:"start (unclosed string)" "Shop.Edge.start" (labels_at p text "start = \"" ~off:9 ());
      let serves = labels_at p text ", \"\"]" ~off:3 () in
      check_mem ~what:"serves" "Checkout.Ledger" serves;
      check_mem ~what:"serves" "Thumbs.Edge" serves;
      check_mem ~what:"initiates" "Quotes.Client" (labels_at p text "initiates = [\"" ~off:14 ());
      check_mem ~what:"place.on offers host labels" "gpu" (labels_at p text "on = \"\"" ~off:6 ());
      (* The edit replaces the whole string content, dots and all. *)
      let (line, utf16_char) = at text "\"Shop.Led\"" ~off:9 () in
      let it = List.find (fun (i : Lsp.Types.CompletionItem.t) -> i.label = "Shop.Ledger.serve_one")
          (TD.completions_at ~path:p ~line ~utf16_char) in
      (match it.textEdit with
       | Some (`TextEdit e) ->
         let (_, c0) = pos_of text "Shop.Led" in
         Alcotest.(check (pair int int)) "replaces from the opening quote" (line, c0)
           (e.range.start.line, e.range.start.character);
         Alcotest.(check int) "to the closing quote" (c0 + 8) e.range.end_.character;
         Alcotest.(check string) "inserts the name" "Shop.Ledger.serve_one" e.newText
       | _ -> Alcotest.fail "expected a TextEdit"))

let test_completion_of_keys () =
  let text = {|[roles]
"Checkout.Ledger" = { body = "Shop.Ledger.serve_one", c }
"Thumbs.Render" = { body = "Shop.Render.render_one", place = { o } }


[pool.edge]
se

[pool.imaging]
hosts = [{ ho }]

[drain]
s
|} in
  with_project ~base:text (fun root ->
      let p = base_path root in
      TD.set_open p text;
      let role_keys = labels_at p text ", c }" ~off:3 () in
      check_mem ~what:"role keys" "capacity" role_keys;
      check_mem ~what:"role keys" "actor" role_keys;
      check_not_mem ~what:"role keys are not pool keys" "serves" role_keys;
      check_mem ~what:"place keys" "count" (labels_at p text "{ o }" ~off:3 ());
      let pool = labels_at p text "\nse\n" ~off:3 () in
      check_mem ~what:"pool keys" "serves" pool;
      check_mem ~what:"pool keys" "hosts" pool;
      check_mem ~what:"host keys" "labels" (labels_at p text "{ ho }" ~off:4 ());
      check_mem ~what:"drain keys" "soft_ms" (labels_at p text "\ns\n" ~off:2 ());
      (* The empty line after the roles: a new role key, quoted. *)
      let (l, _) = pos_of text "[pool.edge]" in
      let items = TD.completions_at ~path:p ~line:(l - 2) ~utf16_char:0 in
      match List.find_opt (fun (i : Lsp.Types.CompletionItem.t) -> i.label = "Quotes.Server") items with
      | Some { textEdit = Some (`TextEdit e); _ } ->
        Alcotest.(check string) "a role key is inserted quoted" "\"Quotes.Server\"" e.newText
      | _ -> Alcotest.fail "no role-name completion at a new [roles] line")

let test_completion_of_pool_names_in_overlay () =
  let overlay = "[pool.\n" in
  with_project ~prod:(Some overlay) (fun root ->
      let p = prod_path root in
      TD.set_open p overlay;
      let got = labels_at p overlay "[pool." ~off:6 () in
      List.iter (fun n -> check_mem ~what:"pool names from the base" n got)
        [ "pool.edge"; "pool.ledger"; "pool.imaging" ])

(* --------------------------------------------------------------------- hover *)

let hover_text path text sub ?off () =
  let (line, utf16_char) = at text sub ?off () in
  match TD.hover_at ~path ~line ~utf16_char with
  | Some { contents = `MarkupContent m; _ } -> m.value
  | _ -> Alcotest.failf "no hover for %S" sub

let test_hover_on_role () =
  with_project (fun root ->
      let p = base_path root in
      TD.set_open p base_toml;
      let h = hover_text p base_toml "\"Checkout.Ledger\"" ~off:3 () in
      List.iter (fun sub ->
          if not (str_contains ~sub h) then Alcotest.failf "hover lacks %S:\n%s" sub h)
        [ "role Ledger needs IO.FileWrite";
          "(Cap(Session.Live), Cap(IO.FileWrite), Checkout_Ledger.Entry) -> Checkout_Ledger.Yield";
          "protocol `Shop.Checkout`" ];
      (* A serves entry hovers the same way; an ungranted role says so. *)
      let h2 = hover_text p base_toml "\"Quotes.Server\"]" ~off:3 () in
      List.iter (fun sub ->
          if not (str_contains ~sub h2) then Alcotest.failf "hover lacks %S:\n%s" sub h2)
        [ "No `role Server needs ...` grant";
          "(Cap(Session.Live), Quotes_Server.Entry) -> Quotes_Server.Yield" ];
      (* Not a role string: nothing. *)
      let (line, utf16_char) = at base_toml "Shop.Edge.start" ~off:2 () in
      Alcotest.(check bool) "no hover on a start string" true
        (TD.hover_at ~path:p ~line ~utf16_char = None))

let tests = [
  "recognises topology.toml and overlays", `Quick, test_recognises_topology_paths;
  "clean topology has no errors",          `Quick, test_clean_topology_has_no_errors;
  "unknown key: forge's text and line",    `Quick, test_unknown_key_matches_forge;
  "unbound served role matches forge",     `Quick, test_unbound_served_role_matches_forge;
  "unknown label under an overlay",        `Quick, test_unknown_label_under_overlay;
  "count above host count",                `Quick, test_count_above_hosts_under_overlay;
  "unlabelled-step warning",               `Quick, test_unlabelled_steps_warning;
  "overlay shows its own diagnostics",     `Quick, test_overlay_shows_its_own_diagnostics;
  "malformed TOML line",                   `Quick, test_malformed_toml_line;
  ".march edit updates topology diags",    `Quick, test_march_edit_updates_topology_diagnostics;
  "definition: body, actor, start",        `Quick, test_definition_on_bindings;
  "definition: Protocol.Role strings",     `Quick, test_definition_on_role_strings;
  "completion inside strings",             `Quick, test_completion_in_strings;
  "completion of keys per section",        `Quick, test_completion_of_keys;
  "completion of pool names in overlay",   `Quick, test_completion_of_pool_names_in_overlay;
  "hover on a role string",                `Quick, test_hover_on_role;
]
