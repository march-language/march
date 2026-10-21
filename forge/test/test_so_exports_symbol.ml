(* Cmd_deploy_hot.so_exports_symbol: how `forge deploy hot` decides that a
   patch carries an actor's migrate_state (`__migrate_<Actor>`).  It used
   `nm -D`, which reads an ELF's dynamic symbol table and prints nothing for a
   Mach-O image, so on macOS every deploy that changed an actor's state was
   refused for want of the migration it carried.
   specs/progress/2026-09-21-hcr-spawn-site-state-layout.md *)

let with_so (f : string -> unit) =
  let dir = Filename.temp_dir "so_exports" "" in
  let c = Filename.concat dir "m.c" and so = Filename.concat dir "m.so" in
  let oc = open_out c in
  output_string oc
    "void *__migrate_Counter(void *s) { return s; }\n\
     static int helper(void) { return 1; }\n\
     int uses_helper(void) { return helper(); }\n";
  close_out oc;
  let rc =
    Sys.command
      (Printf.sprintf "cc -shared -fPIC -o %s %s 2>/dev/null"
         (Filename.quote so) (Filename.quote c))
  in
  if rc <> 0 then Alcotest.skip ();
  Fun.protect
    ~finally:(fun () ->
        ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir))))
    (fun () -> f so)

let exported () =
  with_so (fun so ->
      Alcotest.(check bool) "an exported migrate symbol is found" true
        (March_forge.Cmd_deploy_hot.so_exports_symbol so "__migrate_Counter"))

let absent () =
  with_so (fun so ->
      Alcotest.(check bool) "a symbol the image lacks is not" false
        (March_forge.Cmd_deploy_hot.so_exports_symbol so "__migrate_Gauge");
      Alcotest.(check bool) "a static (local) function is not exported" false
        (March_forge.Cmd_deploy_hot.so_exports_symbol so "helper");
      Alcotest.(check bool) "a prefix of an exported name is not a match" false
        (March_forge.Cmd_deploy_hot.so_exports_symbol so "__migrate_Count"))

let () =
  Alcotest.run "so_exports_symbol"
    [ ("so_exports_symbol",
       [ Alcotest.test_case "exported symbol" `Quick exported;
         Alcotest.test_case "absent symbols" `Quick absent ]) ]
