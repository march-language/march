(** Regression tests for the REPL's stdlib typecheck-env disk cache
    ([lib/repl/repl.ml]'s [save_cached_tc_env] / [load_cached_tc_env]).

    The cache save had been failing silently on every REPL start since the
    import tracker gained its [ie_matches : string -> bool] closure: a
    [Marshal] of the env record raises [Invalid_argument "output_value:
    functional value"], the `with _ -> ()` swallowed it, and the pid-suffixed
    temp file it had already created was never unlinked — 1132 zero-byte
    orphans in ~/.cache/march, and a full stdlib typecheck on every start. *)

module Tc = March_typecheck.Typecheck
module Repl = March_repl.Repl

let with_temp_home f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
    (Printf.sprintf "march_repl_cache_test.%d.%d" (Unix.getpid ())
       (Hashtbl.hash (Sys.time ()))) in
  (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  (* The cache code mkdirs ~/.cache/march but not ~/.cache, so give it the
     parent a real home always has. *)
  (try Unix.mkdir (Filename.concat dir ".cache") 0o755
   with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let old_home = try Some (Sys.getenv "HOME") with Not_found -> None in
  Unix.putenv "HOME" dir;
  Fun.protect
    ~finally:(fun () ->
      (match old_home with Some h -> Unix.putenv "HOME" h | None -> ());
      let cache = Filename.concat dir ".cache/march" in
      (try Array.iter (fun f -> try Sys.remove (Filename.concat cache f)
                                with _ -> ()) (Sys.readdir cache)
       with _ -> ());
      (try Unix.rmdir cache with _ -> ());
      (try Unix.rmdir (Filename.concat dir ".cache") with _ -> ());
      (try Unix.rmdir dir with _ -> ()))
    (fun () -> f dir)

let cache_files home =
  let cache = Filename.concat home ".cache/march" in
  try Array.to_list (Sys.readdir cache) with _ -> []

let ends_with suffix s =
  let ls = String.length s and lf = String.length suffix in
  ls >= lf && String.sub s (ls - lf) lf = suffix

(* An env whose import tracker holds a real entry — i.e. exactly what the REPL
   hands [save_cached_tc_env] after folding stdlib through [check_decl]. The
   entry's [ie_matches] field is the functional value that made the whole
   record unmarshalable. *)
let env_with_import_entry () =
  let env = Tc.make_env (March_errors.Errors.create ()) (Hashtbl.create 16) in
  let entry = {
    Tc.ie_span = March_ast.Ast.dummy_span;
    ie_desc = "unused import `List`";
    ie_matches = (fun n -> n = "List");
    ie_used = ref false;
    ie_used_names = Hashtbl.create 4;
  } in
  env.Tc.import_tracker := [entry];
  Tc.import_index_add_exact env.Tc.import_idx "List" entry;
  { env with Tc.vars = Tc.StrMap.add "marker" (Tc.Mono (Tc.TCon ("Int", []))) env.Tc.vars }

let test_save_writes_loadable_blob () =
  with_temp_home (fun home ->
    let env = env_with_import_entry () in
    Repl.save_cached_tc_env ~content_hash:(String.make 32 'a') env;
    let files = cache_files home in
    let tmps = List.filter (ends_with ".tmp") files in
    let bins = List.filter (ends_with ".bin") files in
    Alcotest.(check (list string)) "no orphaned temp file left behind" [] tmps;
    Alcotest.(check int) "one cache blob written" 1 (List.length bins);
    List.iter (fun b ->
      let path = Filename.concat (Filename.concat home ".cache/march") b in
      Alcotest.(check bool) "blob is non-empty" true
        ((Unix.stat path).Unix.st_size > 0)) bins;
    (* And it must read back: a blob that only *exists* is worthless if the
       loader rejects it, which is how a silent save failure would look from
       the next REPL start's point of view. *)
    let loaded =
      Repl.load_cached_tc_env ~content_hash:(String.make 32 'a')
        ~type_map:(Hashtbl.create 16) in
    match loaded with
    | None -> Alcotest.fail "cached env did not load back"
    | Some tc ->
      Alcotest.(check bool) "loaded env carries the saved bindings" true
        (Tc.StrMap.mem "marker" tc.Tc.vars);
      Alcotest.(check (list string)) "import tracker comes back empty" []
        (List.map (fun (e : Tc.import_entry) -> e.Tc.ie_desc) !(tc.Tc.import_tracker)))

let test_sweeps_stale_temp_files () =
  with_temp_home (fun home ->
    let cache = Filename.concat home ".cache/march" in
    (try Unix.mkdir (Filename.concat home ".cache") 0o755 with _ -> ());
    (try Unix.mkdir cache 0o755 with _ -> ());
    (* A dead pid's leftover, and a live one (our own) that must survive. *)
    let dead = Filename.concat cache "stdlib_tcenv_deadbeef_0123.bin.999999.tmp" in
    let live = Filename.concat cache
      (Printf.sprintf "stdlib_tcenv_deadbeef_0123.bin.%d.tmp" (Unix.getpid ())) in
    close_out (open_out dead);
    close_out (open_out live);
    ignore (Repl.load_cached_tc_env ~content_hash:(String.make 32 'b')
              ~type_map:(Hashtbl.create 4));
    Alcotest.(check bool) "dead-pid temp swept" false (Sys.file_exists dead);
    Alcotest.(check bool) "live-pid temp kept" true (Sys.file_exists live);
    (try Sys.remove live with _ -> ()))

let tests = [
  Alcotest.test_case "save writes a loadable non-empty blob" `Quick
    test_save_writes_loadable_blob;
  Alcotest.test_case "stale pid-suffixed temps are swept" `Quick
    test_sweeps_stale_temp_files;
]
