# ocap phase 4: run-time frames for function `needs` clauses

Plan: specs/plans/2026-11-15-ocap-p4-runtime-plan.md, Task 4.

- `lib/tir/auth_rt.ml` (`Auth_rt.frames`) runs right after lowering in every
  compiled pipeline (bin/main.ml native and JS, `lib/jit/repl_jit.ml`,
  `lib/driver/js_pipeline.ml`). A fn whose `needs` clause carries a scope, or
  that reaches an actor spawn through direct calls, becomes a wrapper that
  enters the frame around `f$auth` (the original body; self calls retargeted,
  so a self tail call stays a loop). The entry `main` is never framed. With
  nothing to frame the module is returned physically unchanged.
- The frame's layer comes from `f$auth_layer()` =
  `Authority.frame_layer(name, text)`: the LLVM emitter turns its call into
  `march_cap_layer_once(cell, fn)` (parsed on first entry, made immortal,
  shared), the JS emitter memoises it, and the inliners never inline it
  (`Inline.never_inline`). `Authority.enter_fn(layer)` no longer parses; its
  re-entry check is two string compares (decision 6).
- `Lower.fn_needs_tbl` carries each fn's clause (canonical text via
  `Cap_request.request_of_entries`, scoped flag, and the module-qualified
  source name the frame reports, the same name the interpreter uses).
- The interpreter frames every fn with a `needs` clause except `main`
  (`Eval.framed_call`), parsing the layer once per definition.
- Slow-path perf: `Arg` gained `HostAt` (host pattern decoded at parse time)
  and `PathsAt` (paths normalized at parse time, matched by string compare);
  the lattice chain of the checked kind is walked once per check. The C
  release walk handles tags 4 and 5. Microbench (--opt 2): host check
  1.16 µs -> 0.36 µs (1 layer), 1.89 µs -> 0.60 µs (2 layers); path check
  0.63 -> 0.45 / 1.00 -> 0.80 µs; frame enter+leave 1.29 µs -> 37 ns.
- Tests: `test/test_auth_rt.ml` (run_compiler groups `auth_rt`,
  `auth_rt_runtime`), TIR snapshot `auth_frame`, stdlib `test_authority.march`.
