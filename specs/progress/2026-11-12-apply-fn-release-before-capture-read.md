# An apply function holds its environment until its last capture read (done 2026-11-12)

On `main` at 07b58d065 the compiled `test/native/native_arr_pmap_capture.march`
(`--compile --opt 2`) died with SIGSEGV in about a third of its runs on macOS
arm64 (`fatal SIGSEGV si_code=2 ... sched=-1 pid=-1`), so a full
`dune build --root .` failed intermittently. Found while merging main into
the ocap phase-2 PR (#1245).

## Cause

Not NativeArray. The same program capturing a plain `List(Int)` crashed just
as often; with no capture it never did. The crash was heap corruption
noticed later, in mimalloc's `_mi_page_free_collect` when a scheduler thread
exited (`_mi_thread_done`) or in `mi_malloc`.

`Drop.rewrite_apply_clo_drop` (`lib/tir/drop.ml`) kept the apply function's
release of its environment, `march_decrc_freed($clo)`, where Perceus spliced
it: straight after the prefix that loads the captures. It deferred only the
capture releases (on the freeing path) to the tails. The captures are
borrowed from the environment, so every read after the splice point relied
on someone else still holding the environment. `Parallel.pmap` calls ONE
closure (`fn i -> NativeArray.get_int(arr, i) * 2`) from several workers:

1. Worker A loads `arr`, releases the environment: not the last reference.
2. Worker B does the same; its release frees the environment, and at its
   tail it drops `arr`.
3. A is still reading `arr`.

Sequential code never interleaves those steps, which is why only parallel
callers (and, in principle, a green-thread switch or a deep `$clodrop$` of
the closure value) could hit it.

## What changed

The environment's own release moves to every tail, after the last read of a
capture (`tail_release` in `rewrite_apply_clo_drop`):

- a tail that reads no capture: release in front of it (tail calls stay tail
  calls, llvm_tco still folds self-recursive apply functions);
- a tail call that reads a capture it owns (covered by the `inc_rc` run in
  front of it) or that is a self-call through `$clo` or its self-binding
  alias: release in front of it, as before;
- any other tail reading a capture (a builtin, or a module function that
  borrows it): `let r = tail in (release; r)`.

A self-alias's release (`dec_rc go`) stays in place: this frame still holds
`$clo` there.

The doc comment's old note, that a move to the tails had made
`test/native/node_discovery.march` recurse without bound, is about a release
placed after a self tail call; this placement never does that.

## Tests

- `test/native/pmap_shared_closure_capture.march` (dune rule, `--opt 2`):
  1000 rounds of `Parallel.pmap` over a lambda reading a captured list, and
  one tail-calling a module function with it. Crashed in 29 of 30 runs
  before, 0 of 100 after.
- `closure_field_tail` / "apply fn holds its environment until the last
  capture read" (`test/test_codegen.ml`): on post-Drop TIR, no release of
  `$clo` precedes a call reading a capture, for a non-tail read, a borrowing
  module-call tail and a builtin tail.
- `native_arr_pmap_capture`: 100 of 100 runs clean (was about 1 in 3
  crashing).
