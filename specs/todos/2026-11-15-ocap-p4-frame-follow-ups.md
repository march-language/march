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

Left by Task 4b (the native slow path in C, runtime/march_authority.c):

- Hello world's macOS arm64 binary (272,184 B) sits about 190 B under a 16 KB `__TEXT` page
  boundary. Any runtime growth that a printing program links pushes it to about 289 KB, past
  the 274 KB target. `authority_size` prints the size but does not gate on it. Task 7, which
  removes the MARCH_TEST_REFUSE hook, frees a little. A real margin needs a smaller C parser, or
  `first_outside` run over the C-side scopes so the launch links no release walk.
- The C policy and the March policy are two implementations of one policy. Only the
  differential test (`authority_differential`) keeps them in step. A rule changed in
  `stdlib/authority.march` must be changed in `runtime/march_authority.c` in the same commit.
- A program that declares a type named `Layer`, `Scope`, `Arg`, `CapLimit`, `CapError`,
  `Result` or `List` keeps the March policy natively (`Auth_native.applicable`), which links
  the matcher again. This is correct, but larger.
