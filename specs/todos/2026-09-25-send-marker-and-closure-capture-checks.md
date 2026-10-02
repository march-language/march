# [P2] Mutable stdlib types can cross threads: `RingBuf` is shared mutable state, and the sendability check has holes

**Logged:** 2026-09-25
**Plan:** `specs/plans/2026-09-25-send-data-race-freedom-plan.md`

## Symptom

`check_sendable` (`lib/typecheck/typecheck_exhaustive.ml:823`) is meant to keep
`RingBuf` and the `Native*Arr` types on one thread. It runs only on
actor-message constructor arguments. Found by reading the code; not yet
reproduced with a built compiler (Phase 0 of the plan does that):

- **H1:** `task_spawn`, `Task.*` and `Parallel.*` never check what their
  closure captures, so two tasks can mutate one `RingBuf` at once.
- **H2:** a closure's captures are invisible to the type walk
  (`send(s, Run(fn x -> RingBuf.push(rb, x)))` passes).
- **H3:** a user ADT hides its fields (`type Wrap = Wrap(RingBuf(Int))`).
- **H4:** type variables are skipped.
- **H5:** the HTTP server shares one handler closure across connection
  threads, and nothing checks its captures.
- **H6–H8** (added 2026-10-01): a module-level `let` of a `RingBuf` is a
  shared global with no linearity check at all; `Vault.set` of one; and a
  double `Task.await` of a `Task(RingBuf)`.

## What the stdlib audit found

- **`RingBuf`** is the only type that really is shared mutable state. It has no
  users outside its own module and tests.
- **The five `Native*Arr` types** are copy-on-write values: every in-place
  write is gated on `rc == 1`. They were listed as non-sendable by analogy.
- **Sole-ownership checks** use relaxed loads (`monotonic` in LLVM, plain
  loads in C). They should be `acquire` to pair with `march_decrc`'s release.
  This affects FBIP everywhere, and native arrays already cross threads via
  task captures.
- **`march_free` skips resource destructors**, so a dead linear buffer, once
  one can exist, leaks its store and elements.
- **The `ring_buf_*` builtins borrow the buffer** (`lib/tir/borrow.ml:240`);
  the linear API needs them owned and rc-neutral (the plan's C2 contract).

## Done when

Part C of the plan has landed:
- the acquire fix;
- native arrays sendable;
- `RingBuf` `always_linear`, with the rc-neutral builtin contract and the
  module-level `let` rule (`LiveProcess` is deferred: the registry fix removed
  its safety case);
- the `t159`–`t163` fixtures rewritten;
- the C5 rule written down, with `is_send` as its guard.

H1–H8 each have a `reject/` fixture in `specs/lang/types/`. Parts A (Phase 2)
and B stay deferred until the C5 rule is waived; if that happens, file them as
their own todo.

Related, fixed since: `specs/progress/2026-09-28-live-process-registry-unsynchronised.md`.
