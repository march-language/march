- ✅ **P0: RC underflow (double-free) when the SAME scrutinee is re-matched inside a sibling arm's sub-path (`lib/tir/perceus.ml`, 2026-07-02)** — found during Wave 2 Task 4's TIR snapshot audit (`test/snapshots/perceus/scrutinee_borrowed_conservatism.expected`), fixed here. Minimal repro (compiled, `xs = Nil`):
  ```march
  mod MinimalScrutDbl do
    fn f(xs : List(Int), flag : Bool) : Int do
      match xs do
        Cons(h, t) ->
          if flag do
            h
          else
            match xs do
              Cons(h2, _) -> h2
              Nil -> 0
            end
          end
        Nil -> -1
      end
    end
    fn main() do println(f(Nil, true)) end
  end
  ```
  aborted with `march: RC underflow (rc was 0) at 0x... — aborting` (exit 134) when compiled; the interpreter printed `-1` correctly (compiled-only). Root cause (`lib/tir/perceus.ml`'s `ECase` handling, `insert_rc_expr`): the `Cons` arm re-matches the SAME scrutinee `xs` inside its `else` sub-path, so the documented "scrutinee-borrowed conservatism" (~line 1058-1080; a deliberately path-INSENSITIVE approximation the comment calls "memory-safe, minor leak") marks `xs` borrowed for the `Cons` arm and re-adds it to that arm's `live_before_br`. `add_cross_decrcs` (~line 1146-1182) then unions `live_before_br` across ALL sibling arms and emits a `dec_rc` at the head of any arm where a variable is "dead here, live elsewhere" — so the `Nil` arm (and the synthesized non-exhaustive-match `_` default) each got a cross-branch `dec_rc xs` **in addition to** the normal `add_scrutinee_free_for` scrutinee-free every arm already receives when the scrutinee is dead-after-case (~line 984-1017), producing two `dec_rc xs` on the same reference. **Fix:** `add_cross_decrcs`'s `dead_here` computation now excludes the scrutinee's own variable name (derived from the `ECase`'s atom) from the cross-branch liveness set — the scrutinee's fate is exclusively owned by `add_scrutinee_free_for`, which already correctly decides per-arm whether to free it, so it must never be treated as ordinary cross-branch "dead here, live elsewhere" liveness (that liveness was itself only an artifact of the scrutinee-borrowed re-add, not a real use by the sibling arm). The Case-2 "leak, not crash" conservatism (single sub-path scrutinee use, no re-match) is untouched; niche/newtype scrutinee-free skip and the `$fbip$` arity-marker encoding are unmodified. `MARCH_DEBUG_PERCEUS=1` confirms exactly 60 fewer `dec_rc` insertions module-wide (14766→14706), `inc`/`cancelled`/`reuse` unchanged; the repro now exits 0 printing `-1`, matching the interpreter. Snapshot regenerated (`UPDATE_SNAPSHOTS=1 ./run_snapshots.exe`): `test/snapshots/perceus/scrutinee_borrowed_conservatism.expected` loses exactly the two redundant `dec_rc xs;` lines — audited byte-for-byte; no other snapshot in the 29-test corpus churned. New regression test `test/test_codegen.ml`'s `scrutinee_borrowed_cross_branch_dec_codegen` suite (compiled + interpreter parity, exit 0). **All six runners green: 384 compiler / 230 eval / 347 codegen (+1) / 791 stdlib / 53 stdlib_march / 29 snapshots.** RC benchmarks unaffected (tree_transform/list_ops/binary_trees/mutual_recursion all correct output, timings within noise). Bonus re-test of the known pre-existing `bench/heapsort.march` crash: still crashes both before and after this fix (same call site, `Sort.heap_merge_h`, confirmed via `lldb`), but the exit code/signal changed (134 RC-underflow → 139 SIGSEGV) because this fix shifted the binary's memory layout — the underlying bug is a separate, deeper, pre-existing RC issue in `heap_merge_h` unrelated to this fix (a small hand-reduced repro of the same merge shape does not crash; only the full 10,000-element heapsort volume triggers it), not introduced by this change.
