(* The `--check` early CAS short-circuit (bin/main.ml, `~target:"check"`)
   caches a clean verdict keyed on the source digest.  `--no-cap-strict`
   changes that verdict: [Typecheck.cap_strict_ceiling] is set from
   [cap_strict] on the --check path, so a stdlib-mediated capability use
   that plain `--check` rejects is accepted with the flag.  Until 2026-09-24
   the flag was not part of the key, so `march --check --no-cap-strict f`
   exiting 0 made the next plain `march --check f` of the same source exit 0
   silently on a warm CAS.  The key now carries "capstrict", the same
   spelling as the compile path's build_cas_key.

   Driver-level on purpose (subprocess against bin/main.exe, the way
   test_tcenv_cli_cache.ml does it): the short-circuit lives in the driver,
   above the typechecker, so an in-process typecheck can never see it.  The
   CAS lives under the compiler's CWD, so each case runs in its own scratch
   directory and never touches the repo's `.march/cas`. *)

(* Plain `--check` rejects this (`Inner` reaches IO.FileWrite through
   `File.write` and declares no `needs IO.FileWrite`); `--no-cap-strict`
   accepts it.  Same program as test_cap_ceiling's [undeclared_stdlib_write_src]. *)
let src = {|
mod CeilOptOut do
  needs IO.Console
  needs IO.FileWrite
  mod Inner do
    needs IO.Console
    fn go() : () do
      match File.write("/tmp/cap_ceiling_optout", "d") do
        Ok(_)  -> println("ok")
        Err(_) -> println("e")
      end
    end
  end
  fn main(_cap_console : Cap(IO.Console), _cap_filewrite : Cap(IO.FileWrite)) : () do
    Inner.go()
  end
end
|}

let expected_error = "does not declare `needs IO.FileWrite`"

let contains s sub =
  match Str.search_forward (Str.regexp_string sub) s 0 with
  | _ -> true
  | exception Not_found -> false

let fresh_dir prefix =
  let d = Filename.temp_file prefix "" in
  Sys.remove d;
  Sys.mkdir d 0o755;
  d

let write_file path text =
  let oc = open_out path in
  output_string oc text;
  close_out oc

let read_file path =
  let ic = open_in path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

(* Run `main.exe --check <flags> <file>` with [cwd] as its working directory
   (so its `.march/cas` lands there) and a private HOME (so the shared
   ~/.cache/march is not involved either).  Returns (exit code, output). *)
let run_check ~cwd ~home ~flags main_exe march_file =
  let out = Filename.concat cwd "check.out" in
  let cmd =
    Printf.sprintf "cd %s && HOME=%s %s --check %s %s > %s 2>&1"
      (Filename.quote cwd) (Filename.quote home) (Filename.quote main_exe)
      flags (Filename.quote march_file) (Filename.quote out)
  in
  let rc = Sys.command cmd in
  (rc, read_file out)

let test_relaxed_verdict_does_not_satisfy_strict_check () =
  let main_exe = Test_helpers.find_main_exe () in
  let cwd = fresh_dir "check_cas_capstrict_cwd" in
  let home = fresh_dir "check_cas_capstrict_home" in
  let march_file = Filename.concat cwd "ceil.march" in
  write_file march_file src;
  (* Control: on a cold CAS the plain check rejects the program.  Without
     this the two asserts below could pass vacuously on a program the
     ceiling never rejected. *)
  let (rc0, out0) = run_check ~cwd ~home ~flags:"" main_exe march_file in
  if rc0 = 0 then
    Alcotest.failf "control: plain --check should reject on a cold CAS:\n%s" out0;
  if not (contains out0 expected_error) then
    Alcotest.failf "control: plain --check rejected, but not for the ceiling:\n%s" out0;
  (* Seed the CAS with the relaxed verdict. *)
  let (rc1, out1) = run_check ~cwd ~home ~flags:"--no-cap-strict" main_exe march_file in
  if rc1 <> 0 then
    Alcotest.failf "--check --no-cap-strict should accept the program:\n%s" out1;
  (* Warm CAS: the plain check must still reject, with the same diagnostic.
     Before the fix this exited 0 and printed nothing. *)
  let (rc2, out2) = run_check ~cwd ~home ~flags:"" main_exe march_file in
  if rc2 <> 1 then
    Alcotest.failf
      "plain --check after a --no-cap-strict run exited %d (expected 1) — the \
       relaxed verdict satisfied the strict check:\n%s" rc2 out2;
  if not (contains out2 expected_error) then
    Alcotest.failf "plain --check on a warm CAS did not print the capability error:\n%s" out2

let tests =
  [ ("--check CAS key vs --no-cap-strict",
     [ Alcotest.test_case "relaxed verdict does not satisfy the strict check" `Quick
         test_relaxed_verdict_does_not_satisfy_strict_check ]) ]
