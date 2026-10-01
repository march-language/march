# `process_spawn_lines`: leaked intermediates and a String typed as a Seq (fixed 2026-09-30)

**Reproduced on origin/main (b931328e5, and again on 771430bf3).**

- *Wrong payload.* `test/native/process_run_stream.march` (`Process.run_stream`
  consumed with `Seq.to_list`/`Seq.fold`): the interpreter prints the lines;
  the compiled binary dies with `panic: non-exhaustive pattern match`, because
  `Ok(<raw stdout String>)` was being matched as `Ok(Seq(fold_closure))`.
- *Leak.* Calling the builtin 40 times in a loop, `--compile --opt 2`:
  `live_allocs()` delta **120** (3 objects per call), against **0** for
  `process_spawn_sync` in the same harness.

## Decision: the builtin returns the raw stdout String; `run_stream` builds the Seq

`Process.run_stream` is documented, typed, and (interpreted) implemented as
`Result(Seq(String), String)`, so that is the API type and it does not change.
What changed is where the Seq is built. A `Seq` is a church-encoded closure
(`Seq(fn(acc, f) -> ...)`), and constructing one from C would mean hand-building
a closure with the erased-`i64` accumulator convention of a polymorphic fold, a
representation the runtime does not otherwise construct. So the builtin's
payload is now the plain captured stdout String on BOTH backends:

- `lib/typecheck/typecheck_builtins.ml`: `process_spawn_lines` is
  `String -> List(String) -> Result(String, String)` (was `Result(Seq(a), String)`).
- `lib/eval/eval_builtins.ml`: returns `Ok(<whole stdout>)` (was a `Seq` value
  of a line fold); `lib/tir/llvm_builtins.ml`'s `ret_ty` follows.
- `stdlib/process.march`: `run_stream` maps the `Ok(out)` through the existing
  `Seq.from_string_lines` (a single trailing newline adds no empty element).

The builtin name is now a misnomer (it returns a String, not lines); it is
kept because renaming it touches every builtin table (nine sites) and a JS
backend table for no behavioural gain.

## Ownership fix (`runtime/march_runtime.c`, `march_process_spawn_lines`)

`march_decrc` is SHALLOW (frees the cell, never walks fields), so the three
objects `march_process_spawn_sync` handed back are released by hand: the stderr
String, the ProcessResult cell and the outer Ok cell. The stdout String's one
reference MOVES from the ProcessResult into the fresh `Ok` returned. (A first
attempt that incref'd stdout and `decrc`'d the outer Result freed only the Ok
cell and left the delta at 120: the todo's "release ... and take a ref on
stdout" wording assumes a deep release.) Builds on #704's borrow classification
(`borrow.ml`: both args borrowed), which was already correct.

## Verification

- `test/native/process_handle_leak_probe.march` gains a `process_spawn_lines`
  leg calling the builtin directly: delta 120 -> 0 (`flat: true`). It calls the
  builtin rather than `run_stream` on purpose, see below.
- `test/native/process_run_stream.march`: parity golden. `.expected` is the
  interpreter's output; both backends are diffed against it (native rule + an
  `interp_process_run_stream` rule). Covers blank lines in the middle, a missing
  trailing newline, empty output, and a `Seq.fold` over the result. RED:
  compiled `panic: non-exhaustive pattern match`; GREEN: identical.

- Re-verified on 771430bf3: compiled `process_run_stream` exits 1 with
  `panic: non-exhaustive pattern match` on origin/main and matches the
  `.expected` on the branch (native and interpreted); the leak leg, run on
  origin/main with a payload-agnostic `Ok(_)` arm (the String payload does not
  typecheck there), reads `process_spawn_lines = 40, flat: false`, and
  `flat: true` on the branch.
- `run_stream`'s doc now says the command runs to completion and its stdout is
  read in full before the Seq is returned (it is not a live stream).

## Not fixed, filed separately

`Seq.count(Seq.from_list(["a"]))` in a loop leaks 3 objects per iteration and
`Seq.from_string_lines` 5, independent of processes:
`specs/todos/2026-09-30-seq-constructors-leak-their-closure.md`. That is why the
leak leg does not go through `run_stream`.
