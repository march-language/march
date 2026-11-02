(* Under MARCH_CI_SKIP_OS_INDEPENDENT=1 (CI's macOS job) these groups run on
   Linux only; see [Test_helpers.drop_os_independent]. Measured 2026-11-02 with
   clang/zig shimmed to log their caller: neither group invokes the toolchain,
   and together they were ~30% of this suite's time. The IR validity gate
   verifies `--emit-llvm` text with opt; every test/native program is still
   compiled by clang on macOS, which rejects the same ill-formed IR. *)
let () =
  Alcotest.run "march-codegen"
    (Test_helpers.drop_os_independent Test_codegen.codegen_suites
       ~groups:[ "llvm_ir_validity_gate"; "check_diagnostic_determinism" ])
