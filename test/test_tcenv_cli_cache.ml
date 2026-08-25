(** Regression tests for the `march file.march` file-run stdlib
    typecheck-env disk cache ([bin/main.ml]'s [get_stdlib_tc_env],
    `~/.cache/march/stdlib_tcenv_cli_*.bin`).

    Fix-round-1 context: the cache was wired into [bin/main.ml]'s shared
    typecheck call (both `--compile` and interpreted `march file.march` go
    through it) without mirroring [run_check_cmd]'s `no_shadowing` guard —
    so a project that shadows a stdlib module name (a `MARCH_LIB_PATH`
    dependency, or the entry module itself, reusing a stdlib module's name)
    would seed pass 1 from — and CACHE — a typecheck env built by checking
    the shadow-filtered stdlib ALONE, with a hole where the shadowed module
    used to be. Any error that hole produced in an unrelated, unshadowed
    stdlib module was silently discarded before caching, and the resulting
    degraded env was written to disk for potential reuse by a later,
    unrelated (differently-shadowed or unshadowed) run whose content hash
    happened to coincide.

    These tests exercise `bin/main.exe` directly (not the OCaml
    [Typecheck]/[get_stdlib_tc_env] functions) because the bug lives in
    `bin/main.ml`'s wiring, which only exists in the compiled executable —
    same reason [test_missing_needs_dedup_no_orphan_hint] above shells out
    rather than calling `March_typecheck.Typecheck` in-process. *)

let with_temp_home f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
    (Printf.sprintf "march_tcenv_cli_cache_test.%d.%d" (Unix.getpid ())
       (Hashtbl.hash (Sys.time ()))) in
  (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  (try Unix.mkdir (Filename.concat dir ".cache") 0o755
   with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let old_home = try Some (Sys.getenv "HOME") with Not_found -> None in
  Unix.putenv "HOME" dir;
  Fun.protect
    ~finally:(fun () ->
      (match old_home with Some h -> Unix.putenv "HOME" h | None -> ());
      let rec rm_rf p =
        if Sys.file_exists p then begin
          if Sys.is_directory p then begin
            Array.iter (fun c -> rm_rf (Filename.concat p c)) (Sys.readdir p);
            (try Unix.rmdir p with _ -> ())
          end else (try Sys.remove p with _ -> ())
        end
      in
      rm_rf dir)
    (fun () -> f dir)

let cache_dir home = Filename.concat home ".cache/march"

let cli_cache_files home =
  try
    Sys.readdir (cache_dir home)
    |> Array.to_list
    |> List.filter (fun f ->
        String.length f >= 16 && String.sub f 0 16 = "stdlib_tcenv_cli")
  with Sys_error _ -> []

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

(* A stdlib-heavy program: exercises List, String and a `needs`-gated
   println so real capability + type inference machinery from several
   different stdlib modules is exercised, not just trivial arithmetic. *)
let stdlib_heavy_src =
  "mod StdlibHeavy do\n\
  \  needs IO.Console\n\
  \n\
  \  fn main(_cap : Cap(IO.Console)) do\n\
  \    let xs = List.map([1, 2, 3, 4, 5], fn x -> x * 2)\n\
  \    let s = List.fold_left(xs, 0, fn (acc, x) -> acc + x)\n\
  \    let joined = String.join([\"a\", \"b\", \"c\"], \",\")\n\
  \    println(int_to_string(s))\n\
  \    println(joined)\n\
  \  end\n\
   end"

let run_emit_llvm ~home ?(lib_path : string option) ~march_file main_exe =
  let out = march_file ^ ".compile_out" in
  let env_prefix =
    match lib_path with
    | None -> ""
    | Some p -> Printf.sprintf "MARCH_LIB_PATH=%s " (Filename.quote p)
  in
  let cmd =
    Printf.sprintf "%sHOME=%s %s --emit-llvm %s > %s 2>&1"
      env_prefix (Filename.quote home) (Filename.quote main_exe)
      (Filename.quote march_file) (Filename.quote out)
  in
  let rc = Sys.command cmd in
  let out_text = try read_file out with Sys_error _ -> "" in
  (try Sys.remove out with Sys_error _ -> ());
  (rc, out_text)

let ll_path_of march_file = Filename.remove_extension march_file ^ ".ll"

(* ── Test 1: cold vs warm cache produces byte-identical IR ──────────────── *)
let test_ir_identical_cold_vs_warm_cache () =
  let main_exe = Test_helpers.find_main_exe () in
  with_temp_home (fun home ->
    let src = Filename.temp_file "tcenv_cli_ir" ".march" in
    let oc = open_out src in
    output_string oc stdlib_heavy_src;
    close_out oc;
    (* Cold: no cache in this fresh HOME yet. *)
    let (rc1, out1) = run_emit_llvm ~home ~march_file:src main_exe in
    Alcotest.(check int) "cold --emit-llvm exits 0" 0 rc1;
    let ll = ll_path_of src in
    let cold_ir = read_file ll in
    Alcotest.(check bool) "cold run populated the cli tcenv cache" true
      (cli_cache_files home <> []);
    (* Warm: same HOME, cache now populated. *)
    let (rc2, out2) = run_emit_llvm ~home ~march_file:src main_exe in
    Alcotest.(check int) "warm --emit-llvm exits 0" 0 rc2;
    let warm_ir = read_file ll in
    Alcotest.(check string) "cold/warm stdout+stderr identical" out1 out2;
    Alcotest.(check string) "cold/warm emitted LLVM IR byte-identical"
      cold_ir warm_ir;
    List.iter (fun f -> try Sys.remove f with Sys_error _ -> ()) [src; ll])

(* ── Test 2 (fix round 1 regression): a shadowed stdlib module bypasses
   the cli cache entirely — no read, no write.  Fails on the pre-fix
   binary, which unconditionally called [get_stdlib_tc_env] (and so wrote
   a `stdlib_tcenv_cli_*` blob built from a stdlib set with a
   shadowed-module-shaped hole in it) regardless of shadowing. ────────── *)
let test_shadowed_run_bypasses_cli_cache () =
  let main_exe = Test_helpers.find_main_exe () in
  with_temp_home (fun home ->
    let lib_dir = Filename.concat home "shadow_lib" in
    (try Unix.mkdir lib_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
    let json_shadow = Filename.concat lib_dir "json.march" in
    let oc = open_out json_shadow in
    output_string oc
      "mod Json do\n\
      \  fn greet() do\n\
      \    \"shadow json\"\n\
      \  end\n\
       end";
    close_out oc;
    let entry = Filename.temp_file "tcenv_cli_shadow" ".march" in
    let oc2 = open_out entry in
    output_string oc2
      "mod ShadowEntry do\n\
      \  needs IO.Console\n\
      \n\
      \  fn main(_cap : Cap(IO.Console)) do\n\
      \    println(Json.greet())\n\
      \  end\n\
       end";
    close_out oc2;
    (* Run A: completely empty cache dir. *)
    let (rcA, outA) =
      run_emit_llvm ~home ~lib_path:lib_dir ~march_file:entry main_exe in
    Alcotest.(check int) "shadowed --emit-llvm exits 0" 0 rcA;
    let llA = read_file (ll_path_of entry) in
    Alcotest.(check (list string))
      "a shadowed run writes NO stdlib_tcenv_cli_* cache entry"
      [] (cli_cache_files home);
    (* Pre-populate the cache with an UNRELATED, unshadowed run's entry —
       simulates a real machine where `march file.march` has already run
       on some other, non-shadowing project sharing this HOME. *)
    let unrelated = Filename.temp_file "tcenv_cli_unrelated" ".march" in
    let oc3 = open_out unrelated in
    output_string oc3 stdlib_heavy_src;
    close_out oc3;
    let (rcU, _) = run_emit_llvm ~home ~march_file:unrelated main_exe in
    Alcotest.(check int) "unrelated warm-up run exits 0" 0 rcU;
    Alcotest.(check bool) "unrelated run DID populate the cli cache" true
      (cli_cache_files home <> []);
    List.iter (fun f -> try Sys.remove f with Sys_error _ -> ())
      [unrelated; ll_path_of unrelated];
    (* Run B: same shadowed program, cache dir now non-empty (but keyed
       under the unshadowed stdlib's content hash, never the shadowed
       one) — output must be identical to Run A regardless. *)
    let (rcB, outB) =
      run_emit_llvm ~home ~lib_path:lib_dir ~march_file:entry main_exe in
    Alcotest.(check int) "shadowed run (cache present) exits 0" 0 rcB;
    let llB = read_file (ll_path_of entry) in
    Alcotest.(check string)
      "shadowed run: stdout+stderr identical whether the (unrelated) cache is empty or populated"
      outA outB;
    Alcotest.(check string)
      "shadowed run: emitted LLVM IR identical whether the (unrelated) cache is empty or populated"
      llA llB;
    List.iter (fun f -> try Sys.remove f with Sys_error _ -> ())
      [entry; ll_path_of entry; json_shadow])

let tests = [
  Alcotest.test_case "cold/warm cli tcenv cache: IR byte-identical" `Quick
    test_ir_identical_cold_vs_warm_cache;
  Alcotest.test_case "shadowed stdlib module bypasses the cli tcenv cache" `Quick
    test_shadowed_run_bypasses_cli_cache;
]
