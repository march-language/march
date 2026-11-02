(* Under MARCH_CI_SKIP_OS_INDEPENDENT=1 (CI's macOS job) only these groups run;
   the rest run on Linux only. See [Test_helpers.keep_os_sensitive].

   Kept because the answer can depend on the OS or on arm64 (the macOS runner
   is CI's only arm64 test host): the REPL JIT (dlopen), debug info
   (provenance: Mach-O vs ELF), the RC trace runtime, SIMD (vectorize_check,
   fast_math), struct and extern ABIs (unboxed_aggregates, blocking_extern),
   float codegen, signals, time, and the linux/amd64 cross link.

   Everything else here asserts on TIR/LLVM IR or compiles a regression
   program whose behaviour is fixed by the IR; it never failed on macOS alone
   (Oct 2026), and test/native's compile-and-run fixtures still run there.
   Before this list the suite was the macOS job's long pole (40 min). *)
let () =
  Alcotest.run "march-codegen"
    (Test_helpers.keep_os_sensitive Test_codegen.codegen_suites
       ~groups:
         [ "repl_jit_cross_line"; "repl_jit_regression"; "provenance"; "rc_trace";
           "vectorize_check"; "fast_math"; "unboxed_aggregates"; "blocking_extern";
           "float_lit_match_codegen"; "interp_signal"; "unix_time_ms";
           "cross_compile" ])
