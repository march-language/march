# [P2] Mutable stdlib types can cross threads: `RingBuf` is shared mutable state, and the sendability check has holes

**Logged:** 2026-09-25
**Plan:** `specs/plans/2026-09-25-send-data-race-freedom-plan.md`

## Symptom

`check_sendable` (`lib/typecheck/typecheck_exhaustive.ml:823`) is meant to keep
`RingBuf` and the `Native*Arr` types on one thread. It runs only on
actor-message constructor arguments. Found by reading the code, and confirmed
against a built compiler on 2026-10-06 (Phase 0 results below):

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

## Phase 0 results (2026-10-06, `march --check` at `262fea07`)

Every hole program type-checks today. The programs are staged under
`specs/lang/types/staging/` (`h1`–`h8`, plus the `a1`–`a4` accept fixtures)
and move to `reject/` / `accept/` in the phase that changes their verdict
(C2 for `h1`–`h8`), so the corpus INDEX counts stay honest until then.

| # | Program | Today |
|---|---|---|
| H1 | `h1_task_captures_ring_buf` (two `Task.async` closures over one buffer) | accepted |
| H2 | `h2_closure_in_message_captures_ring_buf` | accepted |
| H3 | `h3_user_adt_hides_ring_buf` (`type Wrap = Wrap(RingBuf(Int))`) | accepted |
| H4 | `h4_generic_dup_aliases_ring_buf` (`fn dup(x) do (x, x) end`) | accepted |
| H5 | `h5_http_handler_captures_ring_buf` (`HttpServer.plug` closure) | accepted |
| H6 | `h6_module_level_ring_buf` (module-level `let`, read by two functions) | accepted |
| H7 | `h7_vault_set_ring_buf` (`Vault.set`, then `Vault.get` aliases it) | accepted |
| H8 | `h8_task_await_twice_ring_buf` (`Task.await` twice on one `Task(RingBuf)`) | accepted |

The design spec's two §3.5 assumptions, probed with an existing
`always_linear type S1 = S1(Int)` (RingBuf is not linear yet):

- **H7 holds.** `Vault.set(t, "k", s)` and the raw builtin `vault_set(t, "k", s)`
  are both rejected with the generic-parameter error (`` `S1` is linear, but
  `Vault.set` is generic in a parameter of that type ``), so the rule reaches
  stdlib wrappers and builtin generics alike.
- **H8 is moot, and the spec row was wrong.** `Task.async(fn () -> S1(1))` is
  rejected at the `Task.async` call by the same generic-parameter rule (the
  closure's result type is a consumed position of `task_spawn`), so a
  `Task(RingBuf)` cannot be created and `Task.await` is never reached. The
  "container holding a linear value" rule does not reach the opaque `Task`
  (`contains_linear` excludes opaque handles on purpose), but it does not need
  to. The spec now says so.
- **H6 confirmed on an existing linear type too:** a module-level
  `let shared = S1(1)` read by two calls is accepted today, which is the gap
  the new module-level rule closes for `Handle` and `LinearMap` as well.

Two items on the plan's Phase 0 accept list did not land here: "a native
array sent in a message" is rejected today (`reject/t164`) and lands with C1;
"a closure capturing a `RingBuf` used only on its own thread" is rejected
under C2 (closures cannot capture a linear value), so it is not an accept
fixture at all.

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
