let () =
  Alcotest.run "march-compiler" (Test_compiler.compiler_suites @ Test_ctxesc.tests @ Test_stdlib_only.tests @ Test_check_cas_cap_strict.tests)
