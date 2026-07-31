# Memory-ordering audit of the runtime's lock-free paths (2026-07-24, post-deadlock-fix)


After the `task_await` store-buffering bug, every atomic site in `runtime/` was
audited for the same class: a lock-free **store followed by a load of a
DIFFERENT atomic location** whose correctness argument assumes sequential
consistency (Dekker pairs), plus lifecycle check-then-act races. Method: full
inventory of `atomic_*` sites per file (scheduler 78, runtime 48, dispatch 31,
deque 15, http 17, message 6, reload/ffi 4), then per-protocol classification.

**CLEAN — verified sound:**
- `march_deque.h` — textbook Lê-et-al C11 Chase-Lev: `pop` carries the seq_cst
  fence between its bottom-store and top-load (the exact SB shape that bit
  `task_wait_done`), `steal` fences between its two loads, CASes seq_cst. Even
  documents the TSan-vs-standalone-fence subtlety.
- Global runq — mutex-protected push/pop; the lock-free empty fast path has
  bounded staleness (re-polled every dispatch iteration) and its "a queued
  proc still counts as live" shutdown argument checks out against the
  `g_live_procs` decrement site (only on PROC_DEAD).
- `sched_loop` idle/shutdown — all flag reads are POLLS inside a 1ms-sleep
  loop, never parked waits, so staleness is bounded and no wake can be lost.
- Actor mailbox (`march_sched_send`/`recv`) — check-and-transition on both
  sides runs under `mbox_lock`; lock ordering substitutes for SC.
- `march_message.c` inbox — Treiber stack (single-location CAS push,
  exchange drain).
- RC ops — single-location `fetch_add/sub` with the documented returned-value
  ABA guard. HTTP date double-buffer — correct single-writer publish (reader
  keys on the flag stored LAST). FFI blocking-call `done` flag — same-location
  release/acquire message passing. Wake/park — the seq_cst + wake-permit
  protocol landed with the deadlock fix.

**FINDINGS — two, both filed, neither fixed here:**

- [ ] **HCR dispatch ring: `dlclose` runs BEFORE the `live=0` retire store**
  (`runtime/march_dispatch.c`, `march_dispatch_publish` reclaim path). The
  reader (`march_dispatch_enter`) does live-check -> pin (`refs` fetch_add) ->
  re-validate live, which is the right pattern — but the reclaimer's order is
  refs==0 check -> `slot_dlclose()` -> ... -> `live=0`. A reader that passed
  its live-check just before the refs check can pin and re-validate while
  dlclose is mid-flight; re-validation passes because `live=0` has not been
  stored yet, and the reader then calls a fn_ptr into an unloading `.so`.
  Plain TOCTOU (no weak memory needed). The in-code rationale — "acceptable
  under March's cooperative green-thread scheduler" — predates the
  multi-scheduler runtime and is stale. Cheap hardening: store `live=0`
  FIRST, then re-check `refs==0` (a pinned reader is now visible), and only
  then dlclose; full fix is the epoch/grace reclamation the comment already
  anticipates. Low urgency: HCR publish is an admin-path operation.
- [ ] **Signal.watch registration window can erase a delivery**
  (`runtime/march_runtime.c` watch/unwatch): registration stores the handler
  FIRST, then clears `pending`/`seen` — a signal arriving between the two has
  its `pending=1` wiped by the trailing clear, silently dropping that one
  delivery. Clear-then-install would close it. Adjacent to (but distinct
  from) the still-quarantined `signal_term_suppress` torn-output race.

Root causes (updated 2026-07-24):
- **the scheduler missed-wakeup deadlock** — FIXED (store-buffering memory-ordering
  bug + a residual wake-while-RUNNING drop). `task_burst_await` is back on `runtest`;
  the three node tests remain quarantined only on the shared-host port-collision
  verification blocker described in the table;
- **the `Signal.watch` dispatch race** (one test) — see its entry below. Note this one
  is NOT merely an ordering flake: the dominant failure shape is *torn* output, so an
  order-insensitive golden does not fix it.

`forge`'s is a separate, unrelated cause and is the only one of the five that is not a race.

**How you find out these are fixable:** `.github/workflows/nightly.yml`'s `quarantined`
job runs all six aliases every night, `continue-on-error`, purely as a signal — a green
run is the cue to un-quarantine (restore `(alias runtest)` in `test/dune`, or re-add
`test_build_check` to forge's `tests` stanza). **That lane reports; it does not fix, and
it does not gate anything.** Nothing else in CI runs these. Keep its alias list in sync
with the table above — before it existed, these tests ran in no workflow at all, which
makes a quarantine indistinguishable from a deletion.

---
