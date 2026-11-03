(* Under MARCH_CI_SKIP_OS_INDEPENDENT=1 (CI's macOS job) only these groups run;
   the rest run on Linux only. See [Test_helpers.keep_os_sensitive].

   Kept because they exercise the platform: linking (link_deps, static_link),
   the capability sandbox (seatbelt on macOS), what ends up in a linked
   binary (cap_strip, cap_markers), the concurrent-compile race on the IR file
   (first seen as a macOS link error), hot reload and sessions (dlopen), the
   compiled lowering of builtins, and program argv.

   The rest is typechecking, capability rules, diagnostics and CAS/cache logic;
   where it compiles a program, it asserts on the compiler's answer, not the
   binary's. None of it failed on macOS alone in Oct 2026. *)
let () =
  Alcotest.run "march-compiler"
    (Test_helpers.keep_os_sensitive
       (Test_compiler.compiler_suites @ Test_ctxesc.tests @ Test_stdlib_only.tests
        @ Test_hcr_stdlib_actors.tests @ Test_check_cas_cap_strict.tests)
       ~groups:
         [ "link_deps"; "static_link"; "cap_sandbox_runtime"; "cap_sandbox_profile";
           "cap_strip"; "cap_markers"; "compile_ll_race"; "hcr_closure_codegen";
           "hcr stdlib actors"; "session_compile"; "builtin_compiled_lowering";
           "prog_argv" ])
