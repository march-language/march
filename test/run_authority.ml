(* The run-time authority suites (ocap phase 4): the slot and frame runtime,
   the March/C/OCaml policy differential, and frames and captures in every
   runtime. Split from run_compiler, whose CI shard they took past its
   75-minute step timeout; see the run_authority stanza in test/dune.

   None of these groups depends on the OS, so under
   MARCH_CI_SKIP_OS_INDEPENDENT=1 (CI's macOS job) none of them runs; they run
   on Linux. *)
let () =
  Alcotest.run "march-authority"
    (Test_helpers.keep_os_sensitive
       (Test_cap_runtime_slot.tests @ Test_scope_value.tests @ Test_authority_differential.tests @ Test_auth_rt.tests)
       ~groups:[])
