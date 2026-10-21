(* `march --compile --static` (static-output design, Stages 4 and 6:
   specs/2026-09-23-static-compile-output-design.md §5, decisions D4/D5).

   macOS ("self-contained"): every load command under /usr/lib or /System;
   OpenSSL, zstd and brotli come from their static archives.  Linux: musl
   only; a glibc host is refused, so CI's Ubuntu legs pin the refusal and
   the musl link itself is exercised by the release workflow's Alpine legs
   (.github/workflows/build.yml), which run the binary in an empty
   container.  Helpers are Test_link_deps'. *)

open Test_link_deps

let has hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  go 0

(* Compile with [args], expecting failure; returns the output. *)
let compile_fails ?(env = "") ~dir ~args name src =
  let f = Filename.concat dir (name ^ ".march") in
  Out_channel.with_open_bin f (fun oc -> output_string oc src);
  let log = Filename.concat dir (name ^ ".fail.log") in
  let rc = Sys.command (Printf.sprintf "cd %s && env HOME=%s %s %s --compile %s -o %s %s > %s 2>&1"
      (Filename.quote dir) (Filename.quote (Filename.concat dir "home")) env
      (Filename.quote compiler_exe) args (Filename.quote (Filename.concat dir (name ^ "_x")))
      (Filename.quote f) (Filename.quote log)) in
  let out = read_file log in
  Alcotest.(check bool) ("the build fails\n" ^ out) true (rc <> 0);
  out

let prog n = let (_, src, out) = List.find (fun (m, _, _) -> m = n) programs in (src, out)

let test_macos_self_contained () =
  if not is_macos then Alcotest.skip ();
  with_dir @@ fun dir ->
  List.iter (fun n ->
      let src, expect = prog n in
      let bin = compile ~extra:"--static" ~dir n src in
      Alcotest.(check string) (n ^ " runs") expect (run bin);
      let d = deps bin in
      (* zlib is the system's /usr/lib/libz: allowed, and filtered here only
         from the non-system view deps gives, so check it is the system one. *)
      Alcotest.(check bool) (n ^ " loads nothing but the system's libraries " ^ show d) true
        (List.for_all (fun l -> l = "z") d))
    [ "hello"; "tlsp"; "gz"; "zs" ]

let test_macos_missing_archive () =
  if not is_macos then Alcotest.skip ();
  with_dir @@ fun dir ->
  let src, _ = prog "tlsp" in
  let out = compile_fails ~dir ~args:"--static"
      ~env:("MARCH_TEST_LIBPROBE_ROOT=" ^ Filename.quote (Filename.concat dir "no-such-root"))
      "tlsp" src in
  Alcotest.(check bool) ("names libssl.a and the formula\n" ^ out) true
    (has out "TLS is used, but libssl.a was not found (brew install openssl@3)");
  Alcotest.(check bool) ("before any compile or link\n" ^ out) false
    (has out "error:" || has out "undefined")

let test_macos_dylib_refused () =
  if not is_macos then Alcotest.skip ();
  let dylib = "/opt/homebrew/opt/zstd/lib/libzstd.dylib" in
  if not (Sys.file_exists dylib) then Alcotest.skip ();
  with_dir @@ fun dir ->
  let src, _ = prog "hello" in
  let out = compile_fails ~dir ~args:("--static --ffi-link " ^ dylib) "hello" src in
  Alcotest.(check bool) ("the self-check names the dylib\n" ^ out) true
    (has out "is not self-contained" && has out "libzstd");
  Alcotest.(check bool) "and leaves no binary" false
    (Sys.file_exists (Filename.concat dir "hello_x"))

let test_glibc_refused () =
  if not is_linux then Alcotest.skip ();
  let musl = Sys.command "ldd --version 2>&1 | grep -qi musl" = 0 in
  if musl then Alcotest.skip ();
  with_dir @@ fun dir ->
  let src, _ = prog "hello" in
  let out = compile_fails ~dir ~args:"--static" "hello" src in
  Alcotest.(check bool) ("refused on glibc, naming the Alpine route\n" ^ out) true
    (has out "links against musl" && has out "Alpine")

let test_hot_reload_refused () =
  if not (is_macos || is_linux) then Alcotest.skip ();
  with_dir @@ fun dir ->
  let src, _ = prog "hello" in
  let out = compile_fails ~dir ~args:"--static --hot-reload Hello" "hello" src in
  Alcotest.(check bool) ("--static --hot-reload is refused\n" ^ out) true
    (has out "--static: a --hot-reload build")

let tests = [
  Alcotest.test_case "macos: --static loads only system libraries, and runs" `Slow test_macos_self_contained;
  Alcotest.test_case "macos: --static names a missing archive and its formula" `Slow test_macos_missing_archive;
  Alcotest.test_case "macos: --static refuses a binary that loads a non-system dylib" `Slow test_macos_dylib_refused;
  Alcotest.test_case "linux glibc: --static is refused, naming the Alpine route" `Slow test_glibc_refused;
  Alcotest.test_case "--static with --hot-reload is refused" `Slow test_hot_reload_refused;
]
