# Interpreter env-lookup performance (phase 1 close)

Interpreter variable lookup was consuming 95% of interpreted runtime; the phase focused on eliminating redundant environment scans. Applied two primary optimizations: monomorphic comparison shortcut in the builtin scope (String.equal instead of generic `=`), and a hashed global tail to eliminate linear scan of top-level bindings. The apply-call debug-bookkeeping fast path was measured at ≤0.3% effect and dropped per plan.

## Measured speedup (same-box A/B interleaved, loaded system)

| change | fib(25) interp |
|--------|----------------|
| before phase | 16.6 s |
| String.equal scan (commit 486052de) | 5.1–6.1 s (ratio 0.306) |
| hashed global tail (commit 1f28c948) | 1.47 s (ratio vs prev 0.28) |
| apply fast path | dropped — ≤0.3% effect, under the 10% gate |

The apply-call invariant guarding the optimization opportunity (`test_apply_debug_depth_restored_on_exception` in `test/test_eval.ml`) was retained as a pinned test case for future reference, even though the rewrite itself was not shipped.

## Follow-up work

REPL-mode interpreter lookups were then patched across two commits (de3a95d7, d4288b86) to preserve performance across multi-prompt sessions — the hashed global scope is now refreshed at prompt restart, preventing stale bindings from shadowing fresh definitions.

Per `sample` profiling of large stdlib workloads, the next hot path in the interpreter is stdlib string machinery and Map operations, not variable lookup.
