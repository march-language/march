# Float-boxing erasure boundary: the two Task-trampoline sites are still open

Filed 2026-08-12. **Narrowed 2026-08-20**: this item originally tracked two
sites. The apply-wrapper/uniform-ABI half is now tracked separately in
`specs/todos/2026-08-20-float-box-uniform-abi-per-call-leak.md` (still open — a
fix was attempted and reverted; that file records both failed approaches and
their measurements). A third, previously unnamed site was found during that
work and is added below. What remains **here** is the Task-trampoline pair, and
both are currently **unreachable** — see Blocker.

Background on the shared root (the Stage 2 float-boxing design never gave
`march_alloc_float`/`march_unbox_float` an ownership story):
`specs/progress/2026-08-12-float-boxing-case-merge-leak-fix.md`.

## Remaining sites

1. **Task/closure trampoline return** — `lib/tir/llvm_emit.ml`, the
   `inner_ty = "double"` arm of the `task_await_unwrap` path (~line 2239,
   `march_unbox_float` on the pointer recovered from `task[3]`). The closure's
   apply fn boxed its `double` result before handing it to the trampoline; the
   awaiting side unboxes with no free.
2. **`task_await` Result-path float unbox** — same file, the `inner_ty =
   "double"` arm of the `task_await` builtin (~line 2298). **This site was not
   named in the original item**; it was found on 2026-08-20 by reading the two
   `march_unbox_float` call sites in that file. Same shape as site 1: the
   `Ok(v)` payload is unboxed in place with no free.

Both look like the same "provably sole owner, safe to free immediately after
unbox" shape as the landed case-merge fix — the box exists only to smuggle a
double through `task[3]` and is consumed exactly once — but that has **not been
verified by measurement**, for the reason below.

## Blocker — these sites cannot currently be reached

`Task.async` with a **Float-returning thunk does not compile at all**: the
emitted IR is rejected by clang (`'%ldN' defined with type 'double' but
expected 'i64'`). Filed as
`specs/todos/2026-08-20-task-async-float-thunk-compiled-build-break.md`.

Consequence: there is no way to construct a `Task(Float)` in compiled code
today, so neither site can be executed, leak-probed, or regression-tested. Any
"fix" applied to them now would be unverifiable dead code — precisely the
mistake the original item's "why the naive fix is wrong" section warned
against.

**Do the build break first.** Then write the probe, watch it go RED, then fix.

## Suggested approach, once unblocked

Mirror the landed call-site fix rather than the callee-side one: confirm the
box is created immediately upstream in the same call path and that nothing else
can observe it before the unbox reads it, then `march_decrc_local` immediately
after the unbox. Probe shape: `Task.await` / `Task.await_unwrap` on a
Float-returning task in a loop, asserting a `live_allocs()` delta (NOT RSS —
see `test/native/native_arr_fold_leak_probe.march` for why), alongside an
Int-returning control leg. `test/native/native_arr_fold_acc_leak_probe.march`
is the closest existing template for the probe + dune-rule shape, and the probe
source in `specs/todos/2026-08-20-float-box-uniform-abi-per-call-leak.md` is the
closest one for the closure-call loop itself.

## Read this before proposing a fix

The apply-wrapper sibling (now
`specs/todos/2026-08-20-float-box-uniform-abi-per-call-leak.md`) has had TWO
fixes attempted and both were unsound, each in an instructive way:

* a callee-side `march_decrc_local` after the entry unbox — the shape this item
  originally proposed — **double-frees** against `native_float_arr_fold`'s own
  `march_decrc(elem)`;
* a call-site release keyed off the caller's declared param type — **use after
  free**, because the caller's `TFn` type and the callee's actual (possibly
  still generic `ptr`) param type can disagree, and a generic param RETAINS the
  box. Measured as a SIGBUS in `bench/array_numeric.march`.

So do not assume an unbox site may free what it unboxed. Establish who owns the
box first. For sites 1 and 2 that question is genuinely easier — the box exists
only to smuggle a double through `task[3]` — but it still has to be answered
with a measurement, not by analogy.
