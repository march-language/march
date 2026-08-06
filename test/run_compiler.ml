let () =
  Alcotest.run "march-compiler" (Test_compiler.compiler_suites @ Test_ctxesc.tests)
