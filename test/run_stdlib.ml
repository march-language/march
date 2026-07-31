(* Stdlib suites plus the compiled HTTP server's end-to-end suite.  The
   latter lives in its own module (test_http_native.ml) but rides this
   runner deliberately: run_stdlib.exe is executed by `dune runtest`, so
   CI's `test` job runs it on both macOS and Linux.  See the header of
   test/test_http_native.ml for why that wiring is the whole point. *)
let () =
  Alcotest.run "march-stdlib"
    (Test_stdlib_suite.stdlib_suites @ Test_http_native.suites)
