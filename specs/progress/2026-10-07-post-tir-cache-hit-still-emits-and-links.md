`[P2]` A post-TIR CAS hit still runs LLVM emission and clang

**Found:** 2026-10-07, re-running B0 (`scripts/compile-time-bench.sh`) for
`specs/plans/incremental-codegen-cas-baseline-2.md`. Every `comment` row, which was a
`tir-hit` on 2026-10-05, now reports `miss`.

**What happens.** In `bin/main.ml`'s native compile path, the post-TIR cache branch reads:

```ocaml
(if cached_ok then
  Printf.eprintf "compiled %s (cached)\n" out_bin
else
  March_tir.Llvm_toplevel.rc_checks := sanitize_mode () <> None;
  let ir = March_tir.Llvm_emit.emit_module ... in
  ...)
```

`;` binds looser than `if … then … else`, so the `else` branch is only the `rc_checks`
assignment. The `let ir = …` emission, the clang link and the artifact store that follow run
on **every** compile that reaches the lookup, hit or miss. On a hit the compiler prints
`compiled out (cached)`, then emits, links over the copied artifact, and prints `compiled
out` again. The output is correct; the cache saving is gone. A comment-only edit of
`examples/topology_app` at `--opt 2` pays the whole ~10 s back end again instead of
stopping after `cas-hash`.

The line came in with commit `21a0dd568` (`--rc-trace` site ids, A3). Misses are unaffected:
they run the pipeline once.

**Fix.** Wrap the else branch (`else begin … end`, or put the assignment inside the
`let`). Add a regression check that a second compile of a comment-edited source prints
no `[timings] … llvm-emit` stamp; `scripts/compile-time-bench.sh`'s `comment` rows going
back to `tir-hit` is the end-to-end signal.

**Fixed** 2026-10-07. The else branch now opens with
`let () = March_tir.Llvm_toplevel.rc_checks := … in`, so the emission, clang link and
artifact store are inside it. Regression test:
`test/test_post_tir_cache.ml` (compiler suite, `Slow`) compiles a program in a fresh
project dir with a private `HOME`, appends a comment, compiles again with `--timings`,
and asserts the second compile reaches the `cas-hash` stamp, reports `(cached)`, prints
no `llvm-emit` or `clang` stamp and only one `compiled` line, and that the cached
binary runs. Reverting the fix turns it RED ("a hit emits no LLVM IR"). End to end,
`scripts/compile-time-bench.sh --corpus small --runs 1` reports the `comment` row as
`tir-hit` again (2.3 s, no back-end bucket, against 11.3 s cold).
