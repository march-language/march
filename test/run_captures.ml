(* Capture sets (ocap phase 8a, specs/plans/2026-11-24-ocap-p8a-capture-sets-plan.md):
   the set algebra, the inference tests and the golden `--dump-captures`
   corpus (test/captures/).  Its own runner: the `compiler` and `rest` CI
   shards are near their step timeout. *)
let () = Alcotest.run "march-captures" (Test_capture_set.tests @ Test_captures.tests @ Test_capture_golden.tests @ Test_capture_oracle.tests)
