(* The dependency set of a compiled program follows what it reaches
   (static-output design, Stage 2: specs/2026-09-23-static-compile-output-
   design.md §5.1, checks 1 and 8 of §6).  march_tls.o and march_compress.o
   link through an archive after the program's object, with --as-needed /
   -dead_strip_dylibs, so a program that never reaches TLS or Compress
   neither links those members nor records their libraries; before, every
   program loaded libssl, libcrypto, libz, libzstd and libbrotli.  A
   --hot-reload server still links the whole runtime: a patch .so resolves
   runtime symbols against it (design D6).

   MARCH_NO_RUNTIME_ARCHIVE=1 links every member loose (today's fallback
   when the archive cannot be built); the red check below uses it. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let read_file path =
  try
    let ic = open_in_bin path in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic; s
  with Sys_error _ -> ""

let uname_s () =
  try
    let ic = Unix.open_process_in "uname -s" in
    let s = try input_line ic with End_of_file -> "" in
    ignore (Unix.close_process_in ic); s
  with _ -> ""

let is_macos = uname_s () = "Darwin"
let is_linux = uname_s () = "Linux"

let rec rm_rf p =
  match Sys.is_directory p with
  | true ->
    Array.iter (fun c -> rm_rf (Filename.concat p c)) (Sys.readdir p);
    (try Unix.rmdir p with Unix.Unix_error _ -> ())
  | false -> (try Sys.remove p with Sys_error _ -> ())
  | exception Sys_error _ -> ()

let with_dir f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march_link_deps.%d.%d" (Unix.getpid ())
         (Hashtbl.hash (Unix.gettimeofday ()))) in
  Unix.mkdir dir 0o755;
  Unix.mkdir (Filename.concat dir "home") 0o755;
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () -> f dir)

let programs = [
  "hello",
  "mod Hello do\n  needs IO.Console\n  fn main(_c : Cap(IO.Console)) : Unit do\n    println(\"hi\")\n  end\nend\n",
  "hi";
  "tlsp",
  "mod Tlsp do\n  needs IO.Console\n  needs IO.NetConnect.TLS\n\
  \  fn main(_c : Cap(IO.Console), _t : Cap(IO.NetConnect.TLS)) : Unit do\n\
  \    match Tls.client_ctx(Tls.default_client_config()) do\n\
  \      Ok(_) -> println(\"tls ctx ok\")\n\
  \      Err(e) -> println(\"tls err \" ++ Tls.error_to_string(e))\n\
  \    end\n  end\nend\n",
  "tls ctx ok";
  "gz",
  "mod Gz do\n  needs IO.Console\n  fn main(_c : Cap(IO.Console)) : Unit do\n\
  \    match Compress.Gzip.encode(Bytes.from_string(\"hello hello\")) do\n\
  \      Ok(z) -> match Compress.Gzip.decode(z) do\n\
  \        Ok(x) -> println(\"gz \" ++ Bytes.to_string(x))\n\
  \        Err(_) -> println(\"gz decode err\")\n\
  \      end\n\
  \      Err(_) -> println(\"gz encode err\")\n\
  \    end\n  end\nend\n",
  "gz hello hello";
  "zs",
  "mod Zs do\n  needs IO.Console\n  fn main(_c : Cap(IO.Console)) : Unit do\n\
  \    match Compress.Zstd.encode(Bytes.from_string(\"zstd zstd\")) do\n\
  \      Ok(z) -> match Compress.Zstd.decode(z) do\n\
  \        Ok(x) -> println(\"zs \" ++ Bytes.to_string(x))\n\
  \        Err(_) -> println(\"zs decode err\")\n\
  \      end\n\
  \      Err(_) -> println(\"zs encode err\")\n\
  \    end\n  end\nend\n",
  "zs zstd zstd";
]

(* Compile [name] in [dir] (private HOME, so no other build's cache serves
   it); returns the binary's path. *)
let compile ?(env = "") ?(extra = "") ~dir name src =
  let f = Filename.concat dir (name ^ ".march") in
  Out_channel.with_open_bin f (fun oc -> output_string oc src);
  let bin = Filename.concat dir (name ^ extra |> String.map (fun c -> if c = ' ' || c = '-' then '_' else c)) in
  let log = bin ^ ".log" in
  let cmd = Printf.sprintf "cd %s && env HOME=%s %s %s --compile %s -o %s %s > %s 2>&1"
      (Filename.quote dir) (Filename.quote (Filename.concat dir "home")) env
      (Filename.quote compiler_exe) extra (Filename.quote bin) (Filename.quote f)
      (Filename.quote log) in
  if Sys.command cmd <> 0 then Alcotest.failf "compile of %s failed:\n%s" name (read_file log);
  bin

let run bin =
  let out = bin ^ ".out" in
  ignore (Sys.command (Printf.sprintf "%s > %s 2>&1" (Filename.quote bin) (Filename.quote out)));
  String.trim (read_file out)

(* The non-system libraries [bin] loads, as stems: "ssl", "crypto", "z",
   "zstd", "brotlienc", ... *)
let deps bin =
  let cmd =
    if is_macos then Printf.sprintf "otool -L %s | tail -n +2" (Filename.quote bin)
    else Printf.sprintf "readelf -d %s | grep NEEDED" (Filename.quote bin) in
  let ic = Unix.open_process_in cmd in
  let rec lines acc = match input_line ic with
    | l -> lines (l :: acc) | exception End_of_file -> List.rev acc in
  let ls = lines [] in
  ignore (Unix.close_process_in ic);
  let stem l =
    (* otool: "\t/path/libssl.3.dylib (compat...)"; readelf: "... [libssl.so.3]" *)
    let l = String.trim l in
    let path =
      match String.index_opt l '[' with
      | Some i -> String.sub l (i + 1) (String.index_from l i ']' - i - 1)
      | None -> (match String.index_opt l ' ' with Some i -> String.sub l 0 i | None -> l) in
    let base = Filename.basename path in
    let base = if String.length base > 3 && String.sub base 0 3 = "lib"
      then String.sub base 3 (String.length base - 3) else base in
    match String.index_opt base '.' with Some i -> String.sub base 0 i | None -> base in
  List.map stem ls
  |> List.filter (fun s -> not (List.mem s
         [ "c"; "m"; "System"; "ucontext"; "dl"; "pthread"; "rt"; "ld-linux-aarch64";
           "ld-linux-x86-64"; "c.musl-aarch64"; "c.musl-x86_64" ]))
  |> List.sort_uniq compare

let show l = "[" ^ String.concat "," l ^ "]"

let test_deps_follow_reach () =
  if not (is_macos || is_linux) then Alcotest.skip ();
  with_dir @@ fun dir ->
  List.iter (fun (name, src, expect_out) ->
      let bin = compile ~dir name src in
      Alcotest.(check string) (name ^ " runs") expect_out (run bin);
      let d = deps bin in
      match name with
      | "hello" ->
        Alcotest.(check string) "hello loads no library beyond libc" "[]" (show d)
      | "tlsp" ->
        Alcotest.(check string) "tlsp loads OpenSSL and nothing else" "[crypto,ssl]" (show d)
      | "gz" ->
        (* One archive member per codec (Stage 3): gzip is zlib alone. *)
        Alcotest.(check string) "gz loads zlib and nothing else" "[z]" (show d)
      | _ ->
        Alcotest.(check string) "zs loads libzstd and nothing else" "[zstd]" (show d))
    programs

(* Red half: with every member loose (the old link), hello loads OpenSSL. *)
let test_loose_members_load_everything () =
  if not (is_macos || is_linux) then Alcotest.skip ();
  with_dir @@ fun dir ->
  let (name, src, _) = List.hd programs in
  let bin = compile ~env:"MARCH_NO_RUNTIME_ARCHIVE=1" ~dir name src in
  let d = deps bin in
  Alcotest.(check bool) ("the loose link loads OpenSSL " ^ show d) true
    (List.mem "ssl" d && List.mem "crypto" d)

let test_hot_reload_keeps_runtime () =
  if not (is_macos || is_linux) then Alcotest.skip ();
  with_dir @@ fun dir ->
  let (name, src, _) = List.hd programs in
  let bin = compile ~extra:"--hot-reload Hello" ~dir name src in
  let ic = Unix.open_process_in
      (Printf.sprintf "nm -g %s 2>/dev/null | grep -c 'T _*march_tls_client_ctx$'" (Filename.quote bin)) in
  let n = try int_of_string (String.trim (input_line ic)) with _ -> 0 in
  ignore (Unix.close_process_in ic);
  Alcotest.(check bool) "a --hot-reload build still defines march_tls_client_ctx for patches"
    true (n >= 1)

(* A program that reaches a codec this host lacks is refused at compile time,
   naming the package (design D3 and check 5); before Stage 3 it compiled and
   its binary answered Err("Compress.Zstd: libzstd not available") at run
   time.  MARCH_TEST_LIBPROBE_ROOT (bin/main.ml) makes the probe find no
   library without touching the host. *)
let test_missing_codec_refused () =
  if not (is_macos || is_linux) then Alcotest.skip ();
  with_dir @@ fun dir ->
  let (name, src, _) = List.nth programs 3 in
  let f = Filename.concat dir (name ^ ".march") in
  Out_channel.with_open_bin f (fun oc -> output_string oc src);
  let log = Filename.concat dir "refused.log" in
  let rc = Sys.command (Printf.sprintf
      "cd %s && env HOME=%s MARCH_TEST_LIBPROBE_ROOT=%s %s --compile -o zs %s > %s 2>&1"
      (Filename.quote dir) (Filename.quote (Filename.concat dir "home"))
      (Filename.quote (Filename.concat dir "no-such-root"))
      (Filename.quote compiler_exe) (Filename.quote f) (Filename.quote log)) in
  let out = read_file log in
  let has needle =
    let n = String.length out and m = String.length needle in
    let rec go i = i + m <= n && (String.sub out i m = needle || go (i + 1)) in go 0 in
  Alcotest.(check bool) ("the build fails\n" ^ out) true (rc <> 0);
  Alcotest.(check bool) ("naming Compress.Zstd and libzstd\n" ^ out) true
    (has "Compress.Zstd is used, but libzstd was not found");
  Alcotest.(check bool) ("with the packages\n" ^ out) true (has "apt install libzstd-dev");
  Alcotest.(check bool) ("before any C is compiled or linked\n" ^ out) false
    (has "undefined" || has "error:")

let tests = [
  Alcotest.test_case "a codec this host lacks is a compile error naming the package" `Slow test_missing_codec_refused;
  Alcotest.test_case "dependency set follows what the program reaches" `Slow test_deps_follow_reach;
  Alcotest.test_case "every member loose (old link): hello loads OpenSSL" `Slow test_loose_members_load_everything;
  Alcotest.test_case "--hot-reload keeps the whole runtime" `Slow test_hot_reload_keeps_runtime;
]
