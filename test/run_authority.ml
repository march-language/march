(* The run-time authority suites (ocap phase 4): the slot and frame runtime,
   the March/C/OCaml policy differential, and frames and captures in every
   runtime. Split from run_compiler, whose CI shard they took past its
   75-minute step timeout; see the run_authority stanza in test/dune.

   None of these groups depends on the OS, so under
   MARCH_CI_SKIP_OS_INDEPENDENT=1 (CI's macOS job) none of them runs; they run
   on Linux.

   Every case waits on a compile or a run, so one process kept one core busy:
   32 min on main's `rest` shard and 43 on a slow runner, most of it after the
   other suites had finished (November 2026). run_groups fans the groups out
   over MARCH_TEST_PROCS processes; unset, it is Alcotest.run. *)
let () =
  Test_helpers.run_groups "march-authority"
    (Test_helpers.keep_os_sensitive
       (Test_cap_runtime_slot.tests @ Test_scope_value.tests @ Test_authority_differential.tests @ Test_auth_rt.tests)
       ~groups:[])
