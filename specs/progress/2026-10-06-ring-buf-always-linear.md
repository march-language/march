# `RingBuf` is `always_linear`, with a consume-and-return API and an rc-neutral builtin contract (Part C, Phase C2)

**Landed 2026-10-06.** Phase C2 of
`specs/plans/2026-09-25-send-data-race-freedom-plan.md`; semantics in
`specs/2026-10-06-linear-ringbuf-and-sendable-arrays-design.md` §3 and §4.
Depends on C0 (`2026-10-06-sole-ownership-checks-acquire-and-march-free-destructor.md`)
for `march_free`. The todo
`specs/todos/2026-09-25-send-marker-and-closure-capture-checks.md` stays open
until C5.

## What was wrong

`RingBuf` mutated in place with no ownership check, so every alias saw every
push; the only thing keeping a buffer on one thread was `check_sendable`'s
denylist, which ran on actor-message payloads alone. Phase 0 confirmed eight
routes around it (H1–H8): a `Task.async` closure, a closure in a message, a
user ADT wrapping the buffer, a generic `dup`, an HTTP handler closure, a
module-level `let`, `Vault.set`, and a `Task` returning a buffer. Copy-on-write
was rejected for `RingBuf` (design spec §3.1): the documented use keeps the
buffer in actor state, where the state record still holds it while the handler
pushes, so every push would have copied.

## What changed

**Typechecker.**
- `typecheck_env.ml` seeds `always_linear_types` with `"RingBuf"`. No wrapper
  type: `is_linear_ty` and `field_linearity` consult `resolves_always_linear`
  on any bare `TCon`, so a binding, record field or actor-state field of type
  `RingBuf(a)` (or `Option(RingBuf(a))`, via `holds_linear`) is linear with no
  annotation.
- `typecheck_builtins.ml`: every `ring_buf_*` builtin consumes the buffer.
  `push`/`clear` return it; `pop`/`get`/`peek_*`/`size`/`cap` return
  `(answer, RingBuf(a))`; new `ring_buf_snapshot : RingBuf(a) -> (List(a),
  RingBuf(a))` and `ring_buf_drop : RingBuf(a) -> Unit`; `to_list` ends the
  buffer. Elements stay unrestricted (the generics do not opt in), so a buffer
  of linear elements is rejected by the generic-parameter rule.
- **New rule (H6), `typecheck.ml`'s `DLet` arm:** an `always_linear` type, or a
  type that holds one (`contains_linear` on the solved RHS type), cannot be a
  module-level `let`: `` `rb` has the linear type `RingBuf(Int)`, so it cannot
  be a module-level `let`: … ``. Covers `Handle` and `LinearMap` too, which were
  silently accepted at module level.
- `non_sendable_types` is now `[]`: a linear send is the one consuming use, and
  a moved buffer has exactly one owner on either side. The empty list stays as
  C5's enforcement point.

**The reference-count contract** (plan C2, full table there). A live cell has
`rc == 1` from `make` to its terminator and no Perceus-emitted RC op touches
it: Perceus emits no inc/dec for a `Lin` variable, `let (v, rb2) = …` moves
the pair's fields out and frees only the shell, and a linear send hands the
single reference to the mailbox. Per builtin: `make` → fresh cell (rc 1);
`push`/`clear` → the same cell, rc untouched; every reader → the same cell
inside a fresh 2-tuple (tuple slots use the uniform convention, so `size`/`cap`
store `(n << 1) | 1`); `to_list`/`drop` → `march_decrc(cell)`, destructor runs.
Two alternatives were rejected: borrow-plus-`incrc` on return (leaks every
buffer at rc 2, since Perceus never decs a `Lin` variable) and a fresh cell per
operation (allocates on every push).

Edited in all five places the plan names: `lib/tir/borrow.ml` (the ten
entries leave `extern_borrow_table`; all eleven buffer-taking builtins are in
`extern_owned_builtins` with the contract in a comment),
`typecheck_builtins.ml`, `lib/eval/eval_builtins.ml` (the OCaml record is
still mutated in place and handed back; `drop` is a no-op; `ring_to_list` moved
to `eval_runtime.ml`), `runtime/march_runtime.c` (`ring_pair`; header comment
rewritten), `lib/tir/llvm_builtins.ml` (rows and `PDeclare`s), plus
`lib/tir/defun.ml`'s builtin list and `test/test_codegen.ml`'s golden
`declare` block. `ring_buf_push` stays impure (`purity.ml`'s `ring_buf_`
prefix).

**Stdlib, tests, fixtures, bench.**
- `stdlib/ring_buf.march` rewritten to the threaded API (`is_empty`/`is_full`
  thread through `size`/`cap`); header states the ownership contract.
- `test/stdlib/test_ring_buf.march` and `test/native/ring_buf_ops.march`
  rewritten; the two backends print the same facts.
- `test/native/ring_buf_record_leak_probe.march`: a `RingBuf` in a user record
  updated with `{ r with buf: RingBuf.push(r.buf, x) }` for 400 rounds, plus
  make/push/peek/to_list churn and string-element overwrite/snapshot/drop, all
  `live_allocs()`-flat. This is the one path where the borrow-table change is
  load-bearing. Added to `specs/lang/golden/sanitize.sh`'s curated native list
  so CI runs it under ASan (this box lacks the compiler-rt headers to run
  `MARCH_SANITIZE=1` locally).
- Corpus: `accept/t296`–`t299` (actor-state idiom with `spawn`, `snapshot`
  and a moving send; a buffer in a user record; `Parallel.pmap` over a lambda
  capturing an immutable `Map`; a message closure over immutable values) and
  `reject/t300`–`t307` (H1–H8). `reject/t159`–`t163` lost their witness with
  the empty denylist and now move a buffer through each send path and use it
  again (pulled forward from C4 so the corpus stays green). **Two-repo rule:**
  `march-lean` must mirror the eight new rejects and the five rewritten
  `EXPECT-ERROR` lines.
- `bench/ring_buf.march` (push/pop loop, 20M pushes, 1024 slots; in the bench
  gate with its checksum anchored). Compiled at `--opt 2` on this x86-64 box it
  runs in about 250 ms; the reader's 32-byte pair is the cost the design spec's
  open question 2 (unboxed pairs) would remove if it ever shows.

## What Phase 0 and C2 found about the spec

- H7 holds (the generic-parameter rule fires for `Vault.set` and `vault_set`).
- H8 is rejected at `Task.async`, not at the second `await`: `task_spawn` is
  generic in its closure's result. The spec row was rewritten in Phase 0.
- H1 likewise: a `Task.async` closure that *returns* the buffer hits the
  generic-parameter rule first; the fixture's closures end with `drop` so the
  witnessed error is the closure-capture one the spec names.
- The `always_affine` question (design spec §8.1) is open: the rewritten tests
  needed a `drop` in every reader-only test, which is the noise the question
  asks about. Nothing here decides it.
