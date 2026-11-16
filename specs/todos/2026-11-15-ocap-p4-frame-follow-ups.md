# ocap phase 4: function-frame follow-ups

Open items left by Task 4 (run-time frames, lib/tir/auth_rt.ml):

- Mutually tail-recursive framed fns grow the stack by one wrapper per hop
  (decision 7). Only self calls are retargeted to `f$auth`.
- Interface impl methods and REPL-shell (`Lower` resumable path) fns with a
  `needs` clause get no frame, in either backend (no `note_fn_needs` there).
- Until closure capture (Task 5) lands, a function value created outside a
  frame and called inside it runs under the frame. The interpreter frames
  every fn with a `needs` clause, so it is exposed to this more often than
  compiled code.
- The interpreter skips the frame of any fn named `main`; compiled code
  skips only the entry `main` (`Tir_names.entry_main_of_names`). A scoped
  clause on a non-entry `Mod.main` therefore differs.
- A path check still normalizes the target once per layer that has a path
  scope; hoisting it to once per check would shave ~100 ns per extra layer.
