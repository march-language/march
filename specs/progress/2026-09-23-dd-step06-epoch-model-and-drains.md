# Distributed deploys, build step 6: the unified epoch model and drains

**DONE 2026-09-23.** Parent:
[../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
sections 6.1-6.3, II.4.1-II.4.8, D10-D13, D27-D33. Builds on #564
(`specs/progress/2026-09-21-hcr-migrate-order-and-snapshot-cap.md`) and closes its
remaining gap (`specs/progress/2026-09-23-dd-hcr-migration-bugs.md`). Step 5's
decision (Model B deferred, not required) is
`specs/progress/2026-09-23-dd-step05-model-b-deferred.md`. What was not built is
`specs/todos/2026-09-23-dd-step06-followups.md`.

## What landed

**Epochs and `enter_unit` (D33, II.4.1).** `march_proc.code_epoch` (atomic, on the
proc, never TLS), inherited at spawn from the spawning proc, else the current epoch.
`march_dispatch_enter_unit(id, out)` resolves to the newest live version at or
before the running proc's epoch; every compiled boundary call (base binary and
`.so`) and the actor loop use it. `@__march_hcr_epoch`/`__march_init` stay, unread.
The `publish_epoch` ordering bug was already fixed by #551; staging keeps it by
construction (the epoch is written while the version is not live).

**Pins and retirement (D32, II.4.2)** in `runtime/march_dispatch.c`: an 8-entry pin
table, one atomic word per entry (epoch + count), separate from per-call `refs`.
Every pin has a live holder: a proc (spawn to reap), a queued marker, or the
current epoch's role pin. Per-slot reclaim: version V (epoch e) is reclaimable iff
`refs == 0` and no pinned epoch lies in `[e, e_next)`. `MARCH_MAX_LIVE_VERSIONS` is
3. Staged publish (`stage`/`commit`/`unstage`/`can_stage`). When no slot is
reclaimable or the pin table is full, `march_hcr_activate` changes nothing and the
reload server answers `WAIT epoch:<E> pins:<n> deadline_ms:<t>`; a batch stays
staged. New verbs `PINS`, `DRAIN epoch:<E> [soft_ms:] [hard_ms:]`, `ACTIVATE5`.
`forge deploy hot` prints the wait and re-sends every second (`MARCH_DEPLOY_WAIT_S`,
600 s); `forge hot-reload status` prints the pin table and counters.

**Stamps and markers (D29, II.4.5-II.4.6).** `march_mbox_node` carries the sender's
epoch and a `marker` flag. A marker bypasses every overflow policy, never blocks,
does not count against `mbox_limit`, is invisible to nested `receive()` and to
`DROP_OLD` eviction, and holds a pin on its epoch until consumed or disposed (the
reap disposes it through a marker dtor). `march_hcr_activate`: stage all, commit
all, advance the current epoch, then mark every live actor, then arm a soft drain
of the older epochs. The #564 `hcr_marker_lost` fallback survives as
`hcr_lost_epoch`, reachable only on malloc failure; the test asserts it never
fired.

**The receive loop (II.4.6, D30).** Marker: advance, applying the state migration
of every deploy passed (from an activation log, in epoch order), or remember it as
pending while held. A message stamped newer than the actor, with a message-type
change in between: advance early (held: defer, replayed in order after the
advance). A message older than the actor's last message-type change:
`__migrate_msg_<Actor>`, else drop and count. Otherwise dispatch at the actor's
own epoch.

**`migrate_msg` and drains (II.4.7-II.4.8, 6.2).** `<actor>_migrate_msg(m : Old) :
Option(<Actor>.Msg)`, checked IO-free, one annotated parameter, `Option` return,
exhaustive; `<Actor>.Msg` is a typecheck alias of `<Actor>_Msg`. Desugar generates
a `(msg, none) -> msg` wrapper exported as `@__migrate_msg_<Actor>`. Handler
signatures and the old type's constructors go into `.schemas.json`; forge detects a
message-type change (bit 2 over `ACTIVATE5`), refuses a `migrate_msg` whose old type
differs from the running handlers, and `forge hot-reload migrate-msg-stub <Actor>`
writes a stub. Drains: soft deadline forces the marker for unheld actors; hard
deadline kills actors pinned there with `Crash("draining")` (every restart type
restarts; restarts spawn at the current epoch) and requests a stop on other procs.

**Holds (D28, II.4.4).** `epoch_hold()`/`epoch_release()` builtins, stdlib-only.
`SessionNode.party()` makes its Endpoint actor hold (it inherits the caller's epoch
and runs the callbacks); `finish` releases. The generated hosted API holds per
started endpoint (`take_idle`, released by `finish`/`cancel`) through
`Session.hold_epoch`/`release_epoch`. A hosted session whose host a hard drain
kills ends as `Err(Left("draining"))`.

## Deviations from II.4, each deliberate

1. **Activation order: commit, advance, THEN mark** (II.4.6 marks before flipping
   live/current). With the plan's order an actor can reach its marker, migrate its
   state and dispatch before the new version is live, so the migrated state runs on
   the old code; and an actor spawned from an old parent during the walk gets no
   marker. Flipping first is safe because every pinned unit resolves at or below its
   own epoch; only unpinned units (main) see the new versions at once.
2. **Markers go to every live actor, not only HCR actors, and an actor spawned at an
   epoch older than current gets one at spawn.** Otherwise non-HCR actors (stdlib
   actors, actors in non-reloadable modules) pin their spawn epoch for ever, blocking
   retirement, and the tasks they spawn run old code.
3. **The compiled `main` is unpinned (`code_epoch` 0, follows current).** It runs for
   the process lifetime and has no marker; pinned, it would keep its epoch alive for
   ever. II.4.1's "epoch 0 falls back to current" is kept, and the base epoch is
   `MARCH_EPOCH_BASE` = 1 so every other unit is pinned from the start.
4. **A deploy's runtime epoch is `max(client epoch, current + 1)`**: two activations
   never share an epoch (a later activation at an epoch an actor already reached
   would run new code with no marker).
5. **`DRAIN epoch:<E>` drains every epoch <= E**, and every activation arms a drain of
   the older epochs automatically: soft `MARCH_HCR_DRAIN_MS` (5000, the #564 knob),
   hard `MARCH_HCR_HARD_DRAIN_MS` (off by default). With no hard deadline armed a WAIT
   can last until someone sends `DRAIN` with one; forge gives up after
   `MARCH_DEPLOY_WAIT_S`.
6. **Past the soft deadline, messages whose format did not change run on the new code
   against the migrated state**; only old-format ones are converted or dropped. This
   follows II.4.6's rules; #564 dropped every remaining pre-marker message.
7. **Legacy verbs (ACTIVATE..ACTIVATE4) carry no message-type bit**, so their deploys
   count as message-compatible.
8. **`migrate_msg` converts across ONE message-type change**: an old message two
   changes behind is dropped and counted (the older conversion's `.so` may be gone).
9. **No `DELIVERY_FAILED` for remote deliveries dropped in the receive loop.** A
   remote delivery is a plain local send from a route closure in `cluster_node`, so
   the loop has no handle on the connection; such drops are counted with the rest.
   Follow-up todo.
10. **Hosted holds are per started endpoint** (`take_idle` to `finish`/`cancel`), not
    per `await_*`: same count of holds, one hold/release pair per session instead of
    per step.
11. **Only hosted sessions end as `Left("draining")`.** A party whose held Endpoint is
    killed at a hard deadline ends through the existing dead-endpoint paths. D27
    loop-boundary session drains (SessionNode reading the draining flag) are not
    built: `march_hcr_epoch_draining` exists in C with no builtin yet. Follow-up todo.
12. **Hard deadline, non-actor procs: `stop_requested`**, which ends a blocking receive;
    a task computing without receiving runs on (the scheduler is cooperative). Tasks
    are not cancelled through their handles.
13. **Nested `receive()` inside a handler skips markers and applies no epoch rules.**
14. **The activation log is never freed** (a few dozen bytes per deploy): an old-stamped
    message can outlive every unit of its epoch and must still see the type change.
15. **A version carrying a migration is also kept while any older epoch is pinned**, on
    top of the reclaim condition, so an actor several deploys behind can still run it.
16. **The stub generator is `forge hot-reload migrate-msg-stub`**, not a `forge deploy
    --plan` step (the task allowed this minimal form).
17. **Commits**: items 1-4 share `march_runtime.c`/`march_scheduler.c`, so they landed
    as three commits by layer (dispatch+codegen, runtime+server, forge) rather than one
    per item.
18. **Step 3 had not landed** when item 6 merged origin/main, so its loopback and
    `Topology.drain_on_signal` hard deadline are not wired to the drain API.

## Tests

- `test/test_dispatch.c`: 13 cases. The wrong-reclaim case (a unit at epoch 5 calling
  a function last changed at epoch 2, epoch 2 unpinned) goes RED on exactly its
  checks under the "own epoch retired" rule; tie-break, staging invisibility, pin
  table.
- `test/test_hcr_migrate_order.c`: 60 checks over real actor green threads: queued
  messages on the pinned version; 2100 actors; soft deadline (same-format and
  old-format); a second deploy while draining; a held proc defers its marker and a
  newer-format message; D30 early advance keeps FIFO; `migrate_msg` converts; a full
  `DROP_NEW` mailbox; a hard-deadline kill; counters; no leaked marker. 12/12 green at
  load 15-18. Perturbations, each RED on its checks: marker obeys the overflow policy
  (3), no early advance (6), holds ignored at the marker (6), hard kill disabled (2).
- `test/test_reload_activate4.c`: end to end over the socket with a real patch
  (`test/hcr_stub_so.c`): ACTIVATE5 bitmask validation, WAIT on the oldest pinned
  epoch, PINS, DRAIN, a staged batch waiting, then a successful retry.
- Compiler: five `migrate_msg`/`<Actor>.Msg` typecheck cases; `test_hot_reload`
  asserts the `enter_unit` call form in base and `.so` builds; `test_endpoints` pins
  the hosted holds; `test_stdlib_only` the two gated names. Forge: WAIT parsing,
  ACTIVATE5, schema handlers, message diff, stub text.
- Suite and ASAN results: see "Results" below.

## A bug the ASAN leg found

Built with `-fsanitize=address -O1` in the Linux container, `test_hcr_migrate_order`
died with SIGSEGV in the hard-deadline case on every run; the `origin/main` harness
was clean. Bisected: the kill was irrelevant (a hard-deadline thread that only slept
still crashed); the trigger was `march_hcr_drain` calling `pthread_create` from a
green thread. The hard-deadline timer is now a green proc parked until the deadline
(`march_sched_spawn_daemon_unpinned`: a daemon with `code_epoch` 0, so it neither
keeps the process alive nor holds an epoch). The cold `hcr_*` helpers are also
`noinline`, keeping their locals off the actor loop's frame.

## Results

`scripts/run-tests.sh` (full, including `test_jit`) at the final runtime, load
14-25 on the 14-core Mac:

| suite | tests | result |
|---|---:|---|
| compiler | 1248 | pass (rerun at final HEAD after the ratchet fix below) |
| eval | 282 | pass |
| codegen | 626 | pass |
| stdlib | 886 | pass |
| stdlib_march | 71 | pass |
| test_jit | 24 | pass |
| LSP (lsp, utf16, jsonrpc, incremental, query_cli) | 361, 5, 36, 10, 7 | pass |
| refinecheck | 959 | pass |

The first full run failed one compiler case: the stdlib internal-error ratchet
counted 5 unresolved constructors in `session_node.march` against 3 expected
(`HostWatch` is declared before the Endpoint actor, and the hold commit added two
references to its constructors). Fixed by keeping one reference
(`HostDown(p, ep, why)`); the group and then the whole compiler suite pass.

`dune build --root . @test/runtest` (every dune rule under `test/`, the native
programs included): rc 0. It prints one `march_sched: failed to allocate process stack`
from `test_reload_activate4`: that process runs the reload server with no scheduler,
so the `DRAIN` case's hard-deadline timer proc cannot be spawned (and is not needed).
Every compiled program runs a scheduler.

Dune-rule tests run directly: `test_dispatch`, `test_scheduler`,
`test_broadcast_migrate_leak`, `test_hcr_migrate_order`, `test_reload_activate4` (both
modes). `scripts/check-actor-rc-stores.sh`, `scripts/check-runtime-sources.sh` and
`scripts/check-docs.sh` pass.

**ASAN** (Linux container from `ci/Dockerfile.ubuntu`, arm64): `test_hcr_migrate_order`
60/60 and `test_dispatch` clean under `-fsanitize=address`; `sanitize.sh` 119 programs
clean (47 golden, 32 native, 40 two-node; 2 two-node scenarios skipped, need root).

**Benchmarks** (compiled `--opt 2`, same-box A/B against an origin/main compiler,
median of 5 interleaved rounds at load 14-16):

| benchmark | mode | origin/main | step 6 |
|---|---|---:|---:|
| actor_ping | plain | 3.200 s | 3.126 s (-2.3%) |
| actor_ping | --hot-reload | 1.525 s | 1.559 s (+2.2%, ranges overlap) |
| list_ops_nested | plain | 0.105 s | 0.106 s (+0.7%) |
| list_ops_nested | --hot-reload | 0.103 s | 0.103 s (+0.3%) |
