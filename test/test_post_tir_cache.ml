(* A post-TIR CAS hit must stop after the cache lookup: no LLVM emission, no
   clang, no second "compiled" line.

   bin/main.ml's native compile path reads
     (if cached_ok then Printf.eprintf "compiled %s (cached)\n" out_bin
      else <emit IR; clang; store>)
   and from commit 21a0dd568 (--rc-trace site ids) until 2026-10-07 the else
   branch began with a bare `rc_checks := …;`.  `;` binds looser than
   if/else, so the else branch was only that assignment and the emission,
   clang link and artifact store ran on every compile, hits included: a hit
   printed "compiled out (cached)", then re-linked and printed "compiled out".
   The binary was right; the cache saving was gone
   (specs/progress/2026-10-07-post-tir-cache-hit-still-emits-and-links.md).

   A comment-only edit is the scenario that reaches this branch: the source
   digest changes, so the source-level early hit misses, but the TIR (and so
   every per-SCC impl hash) is unchanged.  The test asserts the second
   compile's `--timings` stamps reach `cas-hash` (it really got to the post-TIR
   lookup, not a source-level hit that would pass vacuously) and go no
   further. *)

(* Exe-relative, as in test_compile_ll_race.ml: a CWD-relative path returns
   127 under dune's test runner. *)
let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let src = {|mod PostTirCacheProbe do
  needs IO.Console

  fn main(_c : Cap(IO.Console)) : Unit do
    println("post-tir " ++ int_to_string(6 * 7))
  end
end
|}

let read_file path =
  try
    let ic = open_in_bin path in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic;
    s
  with Sys_error _ -> ""

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0

let count hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i acc =
    if i + m > n then acc
    else if String.sub hay i m = needle then go (i + m) (acc + 1)
    else go (i + 1) acc
  in
  if m = 0 then 0 else go 0 0

let rec rm_rf p =
  match Sys.is_directory p with
  | true ->
    Array.iter (fun c -> rm_rf (Filename.concat p c)) (Sys.readdir p);
    (try Unix.rmdir p with Unix.Unix_error _ -> ())
  | false -> (try Sys.remove p with Sys_error _ -> ())
  | exception Sys_error _ -> ()

(* A fresh project dir (the CAS store is <cwd>/.march/cas) and a private HOME
   (~/.cache/march is shared across worktrees). *)
let with_scratch f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
    (Printf.sprintf "march_post_tir_cache.%d.%d" (Unix.getpid ())
       (Hashtbl.hash (Unix.gettimeofday ()))) in
  Unix.mkdir dir 0o755;
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () -> f dir)

(* Redirect to a file, never a pipe: a piped `--compile` can hang. *)
let compile ~dir ~log =
  let cmd = Printf.sprintf "cd %s && env HOME=%s %s --compile --timings -o out m.march > %s 2>&1"
      (Filename.quote dir) (Filename.quote dir) (Filename.quote compiler_exe)
      (Filename.quote log) in
  let rc = Sys.command cmd in
  let out = read_file log in
  if rc <> 0 then Alcotest.failf "compile failed (rc=%d):\n%s" rc out;
  out

let test_comment_edit_hit_skips_emit_and_clang () =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe;
  with_scratch @@ fun dir ->
  let path = Filename.concat dir "m.march" in
  Out_channel.with_open_bin path (fun oc -> output_string oc src);
  let first = compile ~dir ~log:(Filename.concat dir "first.log") in
  Alcotest.(check bool) ("the first compile emits IR: " ^ first) true
    (contains first "llvm-emit");
  Out_channel.with_open_gen [ Open_append; Open_binary ] 0o644 path
    (fun oc -> output_string oc "-- a comment-only edit\n");
  let second = compile ~dir ~log:(Filename.concat dir "second.log") in
  let what s = Printf.sprintf "%s; second compile's log:\n%s" s second in
  Alcotest.(check bool) (what "the second compile reached the post-TIR lookup") true
    (contains second "cas-hash");
  Alcotest.(check bool) (what "the second compile is a cache hit") true
    (contains second "(cached)");
  Alcotest.(check bool) (what "a hit emits no LLVM IR") false
    (contains second "llvm-emit");
  Alcotest.(check bool) (what "a hit runs no clang") false
    (contains second "  clang");
  Alcotest.(check int) (what "a hit reports one compiled line") 1
    (count second "compiled ");
  let run_log = Filename.concat dir "run.log" in
  let rc = Sys.command (Printf.sprintf "%s > %s 2>&1"
      (Filename.quote (Filename.concat dir "out")) (Filename.quote run_log)) in
  Alcotest.(check int) "the cached binary exits 0" 0 rc;
  Alcotest.(check string) "the cached binary's output" "post-tir 42"
    (String.trim (read_file run_log))

let tests =
  [ Alcotest.test_case "comment-only edit: post-TIR hit skips llvm-emit and clang"
      `Slow test_comment_edit_hit_skips_emit_and_clang;
  ]
