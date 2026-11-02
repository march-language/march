(* Under MARCH_CI_SKIP_OS_INDEPENDENT=1 (CI's macOS job) these groups run on
   Linux only; see [Test_helpers.drop_os_independent]. Measured 2026-11-02, ~60%
   of this suite's time. Two kinds:
   - never invoke clang or zig (logged with both shimmed): endpoints,
     tcenv_cli_cache, cap_scope, resolver, entry_mod_qual_erasure;
   - compile a program only as the vehicle for compiler or CAS logic, asserting
     on diagnostics, cache hits/misses or emitted JSON, never on how the
     linked binary behaves: alloc_contract, topology_flag, cap_ceiling, cas_b7,
     cas_report_bypass, march_query, post_tir_cache.
   Groups that test linking, the sandbox, the concurrent-compile race or the
   contents of a linked binary (link_deps, static_link, cap_sandbox_*,
   compile_ll_race, cap_strip, cap_markers, ...) stay on macOS. *)
let () =
  Alcotest.run "march-compiler"
    (Test_helpers.drop_os_independent
       (Test_compiler.compiler_suites @ Test_ctxesc.tests @ Test_stdlib_only.tests
        @ Test_hcr_stdlib_actors.tests @ Test_check_cas_cap_strict.tests)
       ~groups:
         [ "endpoints"; "tcenv_cli_cache"; "cap_scope"; "resolver";
           "entry_mod_qual_erasure"; "alloc_contract"; "topology_flag";
           "cap_ceiling"; "cas_b7"; "cas_report_bypass"; "march_query";
           "post_tir_cache" ])
