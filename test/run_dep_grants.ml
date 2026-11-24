(* The dependency-grants loader and package membership (ocap phase 6):
   test/test_dep_grants.ml.  Its own runner, run by CI's `forge` shard (see
   the run_dep_grants stanza in test/dune). *)
let () = Alcotest.run "march-dep-grants" Test_dep_grants.tests
