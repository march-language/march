let () =
  Alcotest.run "march-compiler" (Test_compiler.compiler_suites @ Test_ctxesc.tests @ Test_stdlib_only.tests @ Test_hcr_stdlib_actors.tests @ Test_check_cas_cap_strict.tests)
