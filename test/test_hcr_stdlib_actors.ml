(** Stdlib actors are not hot-reload slots (owner decision 2026-09-30,
    specs/todos/2026-09-25-hot-deploy-stalls-node-past-swim-timeout.md
    point 3).

    Every `*_dispatch` used to get a dispatch slot, the stdlib's own actors
    included (`ClusterNodeActor_dispatch`, which answers SWIM pings,
    `Endpoint_dispatch`, `Writer_dispatch`, ...), so a deploy could activate,
    pause or migrate them.  Now only an app actor's does, and "the stdlib's"
    is decided by LOADER PROVENANCE ([Hot_reload.is_slot_actor_dispatch]):
    a user file named like a stdlib file, or a user actor named like a
    stdlib actor, stays a slot.

    A slot shows in the emitted IR as an `@.hr_name<N>` constant: the name
    [march_dispatch_publish] registers.  In-process cases drive the pipeline
    on parsed sources whose spans name a chosen file; driver cases run the
    real compiler (and, for the manifests, a real `--compile-so`). *)

module TB = March_typecheck.Typecheck_builtins
module HR = March_tir.Hot_reload

(* ── helpers ───────────────────────────────────────────────────────────── *)

(** The names the IR publishes as dispatch slots. *)
let slot_names (ir : string) : string list =
  let re = Str.regexp {|@\.hr_name[0-9]+ = [^"]*c"\([^"\\]*\)\\00"|} in
  let rec go pos acc =
    match Str.search_forward re ir pos with
    | _ -> go (Str.match_end ()) (Str.matched_group 1 ir :: acc)
    | exception Not_found -> List.sort_uniq String.compare acc
  in
  go 0 []

let contains ~needle hay =
  let nl = String.length needle and hl = String.length hay in
  let rec scan i = i + nl <= hl && (String.sub hay i nl = needle || scan (i + 1)) in
  nl = 0 || scan 0

let check_slot what ~slots name expected =
  Alcotest.(check bool)
    (Printf.sprintf "%s: %s %s a slot (slots: %s)" what name
       (if expected then "is" else "is not") (String.concat ", " slots))
    expected (List.mem name slots)

(** Parse [src] as if read from [file]: every span names that file, which
    is what provenance looks at. *)
let parse_as ~file src : March_ast.Ast.module_ =
  let lexbuf = Lexing.from_string src in
  Lexing.set_filename lexbuf file;
  March_desugar.Desugar.desugar_module
    (March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)

(** Run [f] with [files] recorded as the stdlib's, the way a stdlib loader
    records what it read ([TB.note_stdlib_decls]); restored after. *)
let with_stdlib_files files f =
  let saved = !TB.stdlib_source_files in
  TB.stdlib_source_files := files @ saved;
  Fun.protect f ~finally:(fun () -> TB.stdlib_source_files := saved)

(** The in-process pipeline to IR, with `--hot-reload HrApp`. *)
let hot_reload_ir ?(cfg = HR.default_config "HrApp") (m : March_ast.Ast.module_) : string =
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map ~hot_reload:true m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  March_tir.Llvm_emit.emit_module ~hot_reload:(Some cfg) tir

let actor_src ~mod_name ~actor = Printf.sprintf {|mod %s do
  actor %s do
    state { n : Int }
    init { n: 0 }
    on Bump(k : Int) do { n: state.n + k } end
  end

  fn go() : Int do
    let a = spawn(%s)
    send(a, Bump(1))
    0
  end
end
|} mod_name actor actor

(* ── in-process: provenance, not names ─────────────────────────────────── *)

(** The same source, once as a user file and once as a file the stdlib
    loader read: only the provenance differs, and only it decides. *)
let test_provenance_decides () =
  let src = actor_src ~mod_name:"HrApp" ~actor:"Writer" in
  let user = hot_reload_ir (parse_as ~file:"/virtual/app/hr_app.march" src) in
  check_slot "user file" ~slots:(slot_names user) "Writer_dispatch" true;
  let file = "/virtual/stdlib/node_queue.march" in
  with_stdlib_files [ file ] (fun () ->
      let std = hot_reload_ir (parse_as ~file src) in
      Alcotest.(check bool) "the stdlib-provenance actor is still compiled" true
        (contains ~needle:"@Writer_dispatch(" std);
      check_slot "stdlib file" ~slots:(slot_names std) "Writer_dispatch" false)

(** A stdlib module and a user module in one program, the user's file
    named exactly like the stdlib's (basename `node_queue.march`), and the
    user's actor named like a stdlib actor (`Writer`): the user's stays a
    slot, the stdlib's (`Pump`) gets none. *)
let test_look_alikes_stay_slots () =
  let std_file = "/virtual/stdlib/node_queue.march" in
  let std = parse_as ~file:std_file (actor_src ~mod_name:"NodeQueue" ~actor:"Pump") in
  let user = parse_as ~file:"/virtual/app/node_queue.march" (actor_src ~mod_name:"HrApp" ~actor:"Writer") in
  let dmod (m : March_ast.Ast.module_) =
    March_ast.Ast.DMod (m.mod_name, March_ast.Ast.Public, m.mod_decls, March_ast.Ast.dummy_span) in
  let prog = { user with March_ast.Ast.mod_decls = dmod std :: user.mod_decls } in
  with_stdlib_files [ std_file ] (fun () ->
      let slots = slot_names (hot_reload_ir prog) in
      check_slot "look-alikes" ~slots "Writer_dispatch" true;
      check_slot "look-alikes" ~slots "Pump_dispatch" false)

(** A `--hot-reload` build whose only actor is the stdlib's has NO slot, and
    must still start its reload server: the start used to be emitted with the
    slot table and skipped at zero slots, which left such a binary (an app
    whose code all lives in the entry module) with no reload socket at all. *)
let test_zero_slots_still_serve () =
  let file = "/virtual/stdlib/node_queue.march" in
  with_stdlib_files [ file ] (fun () ->
      (* a `main`, so there is an @main to carry the setup *)
      let src = {|mod NodeQueue do
  actor Writer do
    state { n : Int }
    init { n: 0 }
    on Bump(k : Int) do { n: state.n + k } end
  end

  fn main() do
    let a = spawn(Writer)
    send(a, Bump(1))
  end
end
|} in
      let ir = hot_reload_ir (parse_as ~file src) in
      Alcotest.(check (list string)) "no slot at all" [] (slot_names ir);
      Alcotest.(check bool) "the reload server still starts" true
        (contains ~needle:"call void @march_reload_server_start(" ir))

(* ── the entry file's own top-level fns (2026-10-01) ────────────────────── *)

let entry_src = {|mod HrApp do
  actor Counter do
    state { n : Int }
    init { n: 0 }
    on Bump(k : Int) do { n: state.n + k } end
  end

  fn helper(x : Int) : Int do x + 1 end

  pfn quiet(x : Int) : Int do x * 2 end

  fn depth(n : Int) : Int do
    if n <= 0 do 0 else 1 + depth(n - 1) end
  end

  fn main() do
    let a = spawn(Counter)
    send(a, Bump(helper(quiet(depth(3)))))
  end
end
|}

(** What bin/topology_gen.ml splices into a `[control]` app's entry module,
    in miniature: declarations parsed under [HR.control_wiring_file]. *)
let control_decls () =
  (parse_as ~file:HR.control_wiring_file {|mod TopologyGenerated do
  actor CtlR do
    state { n : Int }
    init { n: 0 }
    on Tick(k : Int) do { n: state.n + k } end
  end

  pfn ctl_thing(x : Int) : Int do x + 3 end
end
|}).March_ast.Ast.mod_decls

(** Lowering names the entry file's top-level fns bare (`helper`, not
    `HrApp.helper`): with the prefix naming the entry module they are slots,
    found by provenance, and a call to one from `main` dispatches. `main`
    itself never is. Without [entry_top_level] (the prefix names some other
    module) they are not. *)
let test_entry_top_level_fns_are_slots () =
  let m = parse_as ~file:"/virtual/app/hr_app.march" entry_src in
  let on = { (HR.default_config "HrApp") with HR.entry_top_level = true } in
  let ir = hot_reload_ir ~cfg:on m in
  let slots = slot_names ir in
  Alcotest.(check (list string)) "the slots" [ "Counter_dispatch"; "depth"; "helper"; "quiet" ] slots;
  Alcotest.(check bool) "main calls helper through the dispatch table" true
    (contains ~needle:"call ptr @march_dispatch_enter_unit(" ir);
  (* `depth`'s non-tail self-call is direct (a running invocation finishes
     on its own version, as a self-tail-call's loop always did), so the
     only dispatching sites are main's calls: one per slot it calls. *)
  let body_of name =
    let start = Str.search_forward (Str.regexp_string ("define i64 @" ^ name ^ "(")) ir 0 in
    String.sub ir start (Str.search_forward (Str.regexp "^}") ir start - start) in
  Alcotest.(check bool) "depth calls itself directly" true (contains ~needle:"call i64 @depth(" (body_of "depth"));
  Alcotest.(check bool) "depth does not dispatch" false
    (contains ~needle:"@march_dispatch_enter_unit(" (body_of "depth"));
  let off = hot_reload_ir (parse_as ~file:"/virtual/app/hr_app.march" entry_src) in
  Alcotest.(check (list string)) "prefix not the entry module: actors only" [ "Counter_dispatch" ] (slot_names off)

(** The control plane's wiring is spliced into the entry module but is
    infrastructure: neither its functions nor its actors are slots. *)
let test_control_wiring_not_slots () =
  let m = parse_as ~file:"/virtual/app/hr_app.march" entry_src in
  let m = { m with March_ast.Ast.mod_decls = m.March_ast.Ast.mod_decls @ control_decls () } in
  let on = { (HR.default_config "HrApp") with HR.entry_top_level = true } in
  let ir = hot_reload_ir ~cfg:on m in
  Alcotest.(check bool) "the control actor is compiled" true (contains ~needle:"@CtlR_dispatch(" ir);
  Alcotest.(check (list string)) "the app's slots only" [ "Counter_dispatch"; "depth"; "helper"; "quiet" ] (slot_names ir)

(* ── driver: the real stdlib ───────────────────────────────────────────── *)

let compiler_exe =
  Filename.concat (Filename.dirname Sys.executable_name) "../bin/main.exe"

let staged_stdlib = Filename.concat (Filename.dirname Sys.executable_name) "../stdlib"

let fresh_dir tag =
  let d = Filename.temp_dir ("hcr_stdlib_" ^ tag ^ "_") "" in
  d

let read_file path = In_channel.with_open_bin path In_channel.input_all

let write_file path contents =
  Out_channel.with_open_bin path (fun oc -> output_string oc contents)

(** Run the compiler in [dir] (its CAS lands there) with a private HOME:
    [~/.cache/march] is shared across worktrees. *)
let run_compiler ?(env = []) ~dir ~home args =
  let out = Filename.concat dir "compiler.out" in
  let env = String.concat " " (List.map (fun (k, v) -> k ^ "=" ^ Filename.quote v) (("HOME", home) :: env)) in
  let cmd =
    Printf.sprintf "cd %s && %s %s %s > %s 2>&1" (Filename.quote dir) env (Filename.quote compiler_exe)
      (String.concat " " (List.map Filename.quote args)) (Filename.quote out)
  in
  let rc = Sys.command cmd in
  let text = read_file out in
  if rc <> 0 then Alcotest.failf "compiler exited %d in %s:\n%s" rc dir text

(* An app actor next to a stdlib actor (NodeQueue.start spawns the stdlib's
   Writer). Stdlib actors' glue is module-qualified since #726, so Writer's
   dispatch is NodeQueue__Writer_dispatch. *)
let app_src = {|mod HrApp do
  needs IO

  actor Counter do
    state { n : Int }
    init { n: 0 }
    on Bump(k : Int) do { n: state.n + k } end
  end

  fn main(cap : Cap(IO)) do
    let c = spawn(Counter)
    send(c, Bump(1))
    let _q = NodeQueue.start(-1, 1024)
    println("ok")
  end
end
|}

let emit_llvm ~file src =
  let dir = fresh_dir "emit" and home = fresh_dir "home" in
  write_file (Filename.concat dir file) src;
  run_compiler ~dir ~home [ "--emit-llvm"; "--hot-reload"; "HrApp"; file ];
  read_file (Filename.concat dir (Filename.remove_extension file ^ ".ll"))

let test_driver_stdlib_actor_no_slot () =
  if not (Sys.file_exists compiler_exe) then Alcotest.failf "compiler not found at %s" compiler_exe;
  let ir = emit_llvm ~file:"hr_app.march" app_src in
  Alcotest.(check bool) "the stdlib's Writer is in the program" true (contains ~needle:"@NodeQueue__Writer_dispatch(" ir);
  Alcotest.(check (list string)) "the only slot is the app actor's" [ "Counter_dispatch" ] (slot_names ir);
  (* a user entry file named like the stdlib file that declares Writer *)
  let ir = emit_llvm ~file:"node_queue.march" app_src in
  Alcotest.(check (list string)) "an entry named node_queue.march is still the app's"
    [ "Counter_dispatch" ] (slot_names ir)

(** The manifest diff of #663, and a stdlib-only change.

    v1 -> v2, a one-line edit in the app actor's handler, flags exactly that
    actor (its handler and its slot, whose hash folds the handler in) and no
    stdlib function.  v1 -> v3, the same app against a stdlib whose Writer
    handler changed: the app's only slot is unchanged, so `forge deploy hot`
    would find nothing to activate; the manifests' stdlib digests differ, and
    that is what forge turns into a restart. *)
let test_manifest_diff () =
  if not (Sys.file_exists compiler_exe) then Alcotest.failf "compiler not found at %s" compiler_exe;
  let home = fresh_dir "home" in
  let build ?(env = []) tag src =
    let dir = fresh_dir tag in
    write_file (Filename.concat dir "hr_app.march") src;
    let so = Filename.concat dir "p.so" in
    run_compiler ~env ~dir ~home
      [ "--compile"; "--compile-so"; "--hot-reload"; "HrApp"; "-o"; so; "hr_app.march" ];
    match March_forge.Cmd_deploy_hot.parse_manifest (so ^ ".hcr_manifest") with
    | Ok m -> m
    | Error e -> Alcotest.failf "%s: %s" tag e
  in
  let hashes (m : March_forge.Cmd_deploy_hot.manifest) =
    List.map (fun (f : March_forge.Cmd_deploy_hot.fn_manifest) -> (f.fn_name, f.fn_impl_hash)) m.functions in
  let changed a b =
    let hb = hashes b in
    List.filter_map (fun (n, h) ->
        match List.assoc_opt n hb with Some h' when h' <> h -> Some n | _ -> None) (hashes a)
    |> List.sort String.compare
  in
  let v1 = build "v1" app_src in
  let v2 = build "v2" (Str.global_replace (Str.regexp_string "state.n + k") "state.n + k + 1" app_src) in
  Alcotest.(check (list string)) "a one-line app edit flags exactly the app's actor"
    [ "Counter_Bump"; "Counter_dispatch" ] (changed v1 v2);
  Alcotest.(check bool) "the manifests record a stdlib digest" true (v1.stdlib_hash <> None);
  Alcotest.(check (option string)) "the same stdlib" v1.stdlib_hash v2.stdlib_hash;
  Alcotest.(check (option string)) "no stdlib change reported" None
    (March_forge.Cmd_deploy_hot.stdlib_change ~prior:v1 ~current:v2);
  (* v3: the stdlib's Writer handler changes, the app does not *)
  let std = fresh_dir "stdlib" in
  if Sys.command (Printf.sprintf "cp -R %s/. %s && chmod -R u+w %s" (Filename.quote staged_stdlib)
                    (Filename.quote std) (Filename.quote std)) <> 0 then Alcotest.fail "copying the stdlib";
  let nq = Filename.concat std "node_queue.march" in
  let before = "    on Credit(total : Int) do\n      grant(state, total)" in
  let text = read_file nq in
  if not (contains ~needle:before text) then Alcotest.failf "the Writer.Credit handler moved: update this fixture";
  write_file nq (Str.global_replace (Str.regexp_string before)
                   "    on Credit(total : Int) do\n      grant(state, if total < 0 do 0 else total end)" text);
  let v3 = build ~env:[ ("MARCH_STDLIB", std) ] "v3" app_src in
  let ch = changed v1 v3 in
  Alcotest.(check bool) "the stdlib actor's code changed" true (List.mem "NodeQueue__Writer_Credit" ch);
  Alcotest.(check bool) "the app's slot did not" false (List.mem "Counter_dispatch" ch);
  Alcotest.(check bool) "the stdlib digests differ" true (v1.stdlib_hash <> v3.stdlib_hash);
  Alcotest.(check bool) "forge sees a stdlib change" true
    (March_forge.Cmd_deploy_hot.stdlib_change ~prior:v1 ~current:v3 <> None)

let tests =
  [ ("hcr stdlib actors",
     [ Alcotest.test_case "provenance, not the name, takes the slot" `Quick test_provenance_decides;
       Alcotest.test_case "a look-alike file and actor stay slots" `Quick test_look_alikes_stay_slots;
       Alcotest.test_case "zero slots: the reload server still starts" `Quick test_zero_slots_still_serve;
       Alcotest.test_case "the entry file's top-level fns are slots, main is not" `Quick test_entry_top_level_fns_are_slots;
       Alcotest.test_case "the spliced control plane gets no slot" `Quick test_control_wiring_not_slots;
       Alcotest.test_case "driver: a stdlib actor gets no slot" `Quick test_driver_stdlib_actor_no_slot;
       Alcotest.test_case "driver: manifest diff, app edit vs stdlib edit" `Slow test_manifest_diff ]) ]
