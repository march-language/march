(* `march FILE --args a b` seeds the interpreted program's own argv.

   Without it, the process_argv builtin (lib/eval/eval_builtins.ml) returns the
   COMPILER process's Sys.argv, and march rejects a second positional outright
   ("Usage: march [options] [file.march]"), so an interpreted script has no way
   at all to see its own arguments.  `forge run f.march -- a b` depends on this.

   Exe-relative compiler path, for the same reason as test_cap_strip.ml: a
   CWD-relative path returns 127 under dune's test runner. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

(* Prints its argv, comma-joined.  The explicit caps are required: a `main` with
   no capability parameter is rejected outright ("performs IO but declares no
   grant"), and IO.Process is what System.argv() itself needs. *)
let probe_src = {|
mod ArgvProbe do
  needs IO.Console
  needs IO.Process
  fn main(_c : Cap(IO.Console), _p : Cap(IO.Process)) : () do
    println(String.join(System.argv(), ","))
  end
end
|}

(* Returns (exit_code, trimmed_stdout_and_stderr, path_of_the_probe_file). *)
let run_probe extra =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf
      "compiler not found at %s — test/dune must declare bin/main.exe as a dep \
       of run_compiler.exe" compiler_exe;
  let src = Filename.temp_file "prog_argv" ".march" in
  let oc = open_out src in
  output_string oc probe_src;
  close_out oc;
  let out = Filename.temp_file "prog_argv_out" ".txt" in
  let rc =
    Sys.command
      (Printf.sprintf "%s %s%s > %s 2>&1"
         (Filename.quote compiler_exe) (Filename.quote src) extra
         (Filename.quote out))
  in
  let ic = open_in out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  (try Sys.remove src with Sys_error _ -> ());
  (try Sys.remove out with Sys_error _ -> ());
  (rc, String.trim s, src)

let test_args_seeds_argv () =
  let (rc, out, src) = run_probe " --args alpha beta" in
  Alcotest.(check int) "exit 0" 0 rc;
  Alcotest.(check string) "argv is the script then its arguments"
    (src ^ ",alpha,beta") out

let test_args_with_nothing_after_is_script_only () =
  (* Arg.Rest_all fires with the empty list, which must still take precedence
     over Sys.argv — otherwise `--args` with no arguments would leak the
     compiler's own command line into the program. *)
  let (rc, out, src) = run_probe " --args" in
  Alcotest.(check int) "exit 0" 0 rc;
  Alcotest.(check string) "argv is just the script" src out

let test_without_args_flag_behaviour_is_unchanged () =
  let (rc, out, src) = run_probe "" in
  Alcotest.(check int) "exit 0" 0 rc;
  Alcotest.(check string) "still the compiler's own Sys.argv"
    (compiler_exe ^ "," ^ src) out

let test_bare_positional_still_rejected () =
  (* Program arguments must go through --args; a second positional stays an
     error, so nothing silently changes meaning for existing callers. *)
  let (rc, _out, _src) = run_probe " alpha" in
  Alcotest.(check bool) "second positional is still an error" true (rc <> 0)

let tests =
  [ Alcotest.test_case "--args becomes the program's argv" `Quick
      test_args_seeds_argv;
    Alcotest.test_case "--args with nothing after it is script-only" `Quick
      test_args_with_nothing_after_is_script_only;
    Alcotest.test_case "no --args keeps the old Sys.argv behaviour" `Quick
      test_without_args_flag_behaviour_is_unchanged;
    Alcotest.test_case "a bare second positional is still rejected" `Quick
      test_bare_positional_still_rejected ]
