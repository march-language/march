# Compiler bug — multi-head fn recurses infinitely under --target js (filed, not fixed, 2026-07-10)


- ❌ **A multi-head function mixing a literal-Int pattern in one argument
  position with a plain-variable pattern in another loses its base case
  under `--target js` and recurses infinitely** (stack overflow, not just
  missing TCO — confirmed via a minimal repro with only 2 levels of true
  recursion depth, far too shallow to be a real stack-depth issue):
  ```march
  mod MultiHeadTest do
    fn rotate_n(cells, 0) do cells end
    fn rotate_n(cells, n) do rotate_n(cells, n - 1) end

    fn main() : Unit do
      println(int_to_string(List.length(rotate_n([1,2,3], 2))))
    end
  end
  ```
  Native (`march file.march`) prints `3` correctly. `--target js` throws
  `RangeError: Maximum call stack size exceeded` immediately — the emitted
  JS recurses through a join-point apply wrapper
  (`rotate_n$List_Int$Int` ↔ `$jpNNNNN$apply$NNNN`) that never resolves the
  `n == 0` base case, so it truly never terminates rather than just
  overflowing a deep-but-finite native stack.
- **Workaround (used in `demo_app/tetris/lib/tetris.march`'s `rotate_n`):**
  rewrite as a single function body with an internal `match n do 0 -> ...
  | _ -> recurse end` instead of two `fn rotate_n(cells, 0) do ... end` /
  `fn rotate_n(cells, n) do ... end` clauses — same minimal repro shape with
  this rewrite compiles and runs correctly under `--target js` (prints `3`).
- **Scope narrowed:** single-arg multi-head (`fn fib(0) do 0 end` / `fn
  fib(1) do 1 end` / `fn fib(n) do ... end`, `examples/pattern_matching.march`'s
  existing style) compiles and runs correctly under `--target js` (prints
  `55` for `fib(10)`, no stack overflow) — the bug is specific to
  **multi-argument multi-head where only one parameter position varies by
  pattern across clauses** (`rotate_n(cells, 0)` / `rotate_n(cells, n)`: the
  first position is a plain variable in every clause, only the second
  differs). Not investigated further: whether this is in the TIR
  join-points pass specifically (the emitted symbol names —
  `rotate_n$List_Int$Int` ↔ `$jpNNNNN$apply$NNNN` — suggest that's where the
  base case gets lost) or `lib/tir/js_emit.ml`'s tail-call handling for the
  resulting match-desugared shape.
