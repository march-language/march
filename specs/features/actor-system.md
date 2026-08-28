# March Actor System: Moved

This file was split. The language-reference content (actor declaration syntax,
`spawn`/`send`/`kill`/`receive`, mailbox semantics, the capability model,
linear-typed messages, session-type integration) is now the canonical chapter
**[../lang/actors.md](../lang/actors.md)**; see the reference umbrella
**[specs/lang/index.md](../lang/index.md)**.

The compiler-internals content (scheduler architecture, mailbox
implementation, TIR lowering) will be indexed by the implementation reference
**`specs/impl/index.md`** (pending, Task 5); until that lands, see
`runtime/march_scheduler.c`, `runtime/march_runtime.c`, and
`lib/tir/lower_actor.ml` directly, plus `specs/actor-lowering.md` for the
original lowering design.

The full prior text of this file is available in git history
(`git log --follow -- specs/features/actor-system.md`).
