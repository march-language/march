(* `march caps <files...>` — package-level capability computation.

   Package-level rather than per-file because per-file does not work: most
   files in a real package reference sibling modules and fail standalone
   (measured on real packages: conduit 9/43, depot 14/32, forgepm 15/60), and
   a union over whatever happened to typecheck UNDER-reports.  For a
   capability record that is the dangerous direction — it certifies a package
   as needing less than it does.  Measured concretely on depot: per-file found
   {IO.Console, IO.NetConnect, IO.Random}; whole-package additionally found
   IO.Foreign and IO.Spawn. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let with_pkg files f =
  let dir = Filename.temp_file "cap_pkg" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o755;
  let paths =
    List.map
      (fun (name, src) ->
        let p = Filename.concat dir name in
        let oc = open_out p in
        output_string oc src;
        close_out oc;
        p)
      files
  in
  let r = f dir paths in
  List.iter (fun p -> try Sys.remove p with Sys_error _ -> ()) paths;
  (try Unix.rmdir dir with Unix.Unix_error _ -> ());
  r

let run_caps dir paths =
  let out = Filename.temp_file "cap_pkg_out" ".txt" in
  let err = Filename.temp_file "cap_pkg_err" ".txt" in
  let rc =
    Sys.command
      (Printf.sprintf "MARCH_LIB_PATH=%s %s caps %s > %s 2> %s"
         (Filename.quote dir) (Filename.quote compiler_exe)
         (String.concat " " (List.map Filename.quote paths))
         (Filename.quote out) (Filename.quote err))
  in
  let read p =
    let ic = open_in p in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic;
    Sys.remove p;
    s
  in
  (rc, read out, read err)

let contains hay needle =
  let n = String.length needle and l = String.length hay in
  let rec go i = i + n <= l && (String.sub hay i n = needle || go (i + 1)) in
  n = 0 || go 0

(* A helper module used by the entry file: the entry alone cannot be analyzed,
   which is exactly why per-file analysis under-reports. *)
let helper_src =
  {|
mod PkgHelper do
  fn fetch(host : String) : Bool do
    match tcp_connect(host, 80) do
      Ok(_)  -> true
      Err(_) -> false
    end
  end
end
|}

let entry_src =
  {|
mod PkgEntry do
  fn main() : () do
    if PkgHelper.fetch("example.com") do
      println("y")
    else
      println("n")
    end
  end
end
|}

let test_package_union_includes_sibling_caps () =
  with_pkg
    [ ("pkg_helper.march", helper_src); ("pkg_entry.march", entry_src) ]
    (fun dir paths ->
      let rc, out, err = run_caps dir paths in
      if rc <> 0 then Alcotest.failf "march caps failed (rc=%d):\n%s" rc err;
      (* IO.NetConnect lives in the HELPER, not the entry: a per-file union
         that could not analyze the helper would miss it entirely. *)
      Alcotest.(check bool) "sibling's IO.NetConnect is in the package set" true
        (contains out "IO.NetConnect");
      Alcotest.(check bool) "entry's IO.Console is in the package set" true
        (contains out "IO.Console"))

let broken_src =
  {|
mod PkgBroken do
  fn main() : () do
    this_function_does_not_exist()
  end
end
|}

let test_unanalyzable_package_fails_loudly () =
  (* The property that matters: a package that does not typecheck must yield
     NO capability set at all.  Emitting a partial one would certify the
     package as needing less than it does. *)
  with_pkg
    [ ("pkg_broken.march", broken_src) ]
    (fun dir paths ->
      let rc, out, err = run_caps dir paths in
      Alcotest.(check bool) "exits nonzero" true (rc <> 0);
      Alcotest.(check string) "emits NO capability set" "" (String.trim out);
      Alcotest.(check bool) "says why" true (contains err "march caps:"))

let tests =
  [
    Alcotest.test_case "package union includes sibling capabilities" `Slow
      test_package_union_includes_sibling_caps;
    Alcotest.test_case "unanalyzable package fails loudly" `Slow
      test_unanalyzable_package_fails_loudly;
  ]
