# DONE 2026-09-21: both findings of the runtime lock-free audit are fixed

The audit (original text below) found two bugs and certified everything else
clean. Both are fixed; the clean inventory was not re-audited.

## 1. HCR dispatch ring: dlclose ran before the retire store

`runtime/march_dispatch.c`, `publish_impl` (the reclaim branch). New order:
refs==0 filter -> store `live=0` -> re-check `refs==0` -> only then
`slot_dlclose`. If the re-check sees a pin, publish returns -1 (the existing
"caller must purge" result), the version stays retired, and its handle stays
open until a later publish reclaims it once the pin drains.

Two things the audit did not spell out, both fixed in the same change:

- **The retire/re-check is a store-buffering (Dekker) pair** with the reader's
  pin/re-validate (`live` store then `refs` load, vs `refs` RMW then `live`
  load). Release/acquire allows both loads to read stale values, so all four
  accesses are now seq_cst. Reader-side cost is nil on x86 (`lock xadd`, plain
  load) and AArch64 (`ldaddal`, `ldar`).
- **The reclaim also did a plain `refs = 0` store** after retiring. A reader
  mid-back-out (pinned, about to see `live==0` and `fetch_sub`) would have its
  increment erased and then wrap `refs` to UINT64_MAX, pinning the slot forever.
  The store is gone: refs is 0 on a fresh slot (calloc) and verified 0 on reclaim.
- Adjacent: `march_dispatch_publish_epoch` stamped `epoch` AFTER the slot's
  `live=1` publication, so `enter_gen` could select a fresh version by its
  previous occupant's epoch. It is now stamped before the release store, and
  the field is a relaxed atomic (the scan reads it before pinning, concurrently
  with a reclaim).
- The stale "acceptable under a cooperative green-thread scheduler" rationale
  is deleted. Epoch/grace reclamation (the full fix) is still not built.

Test seam: `march_dispatch_set_close_hook` makes reclaim call a hook instead of
`dlclose`. Two new cases in `test/test_dispatch.c` (`test_dispatch_runner`,
`runtest`):

- `test_reclaim_retires_before_dlclose` — deterministic: from inside the close
  hook, i.e. while "dlclose" is in flight, an `enter_gen` aimed at the closing
  version's epoch must not be handed its fn_ptr.
- `test_reclaim_race_threads` — 4 reader threads aim `enter_gen` at the next
  reclaim candidate and hold the pin briefly; the publisher cycles publishes;
  a pin that overlaps its version's close is counted. Also asserts the race was
  exercised (>= 10k pins, some publishes blocked). First CI run (macos-15)
  caught that guard firing: a fixed 50k publishes finished before any reader
  was scheduled (`pins=0`). Readers now signal they are running before the
  publisher starts, and the publisher runs until the race has been exercised
  (>= 20k publishes, capped at 1M or 10 s). The guards are skipped, with a
  printed SKIP, when only one CPU is online: there the race cannot be
  exercised at all (measured in Docker pinned to one core: `blocked=0`).

Red control (scratch copy with only the reclaim order reverted to
dlclose -> live=0):

| build | where | result |
|---|---|---|
| red | macOS arm64 | both new cases FAIL; `overlap=13049` |
| red | Docker ubuntu arm64, 3 CPUs (reworked test) | both FAIL; `overlap=5172` |
| red | Docker ubuntu arm64, TSAN | both FAIL; `overlap=28692`; 1 TSAN data race (reclaim rewrite vs pinned reader) |
| fix | macOS arm64, x3 | PASS, `overlap=0` |
| fix | Docker ubuntu arm64, TSAN | PASS, `overlap=0`, 0 TSAN warnings |
| fix | Docker ubuntu arm64, ASAN | PASS (ASAN adds little here: the handles are fake, nothing is unmapped) |

## 2. Signal.watch registration could erase a delivery

`runtime/march_runtime.c`, `march_signal_watch`: `pending`/`seen` are now
cleared BEFORE the watcher is published (the `g_signal_handlers` exchange),
then the OS handler is installed. Only a re-watch was exposed (the OS handler
is already `march_signal_dispatch`); a first watch still has the previous
disposition until `signal()` runs. Deliveries that precede the call are still
discarded, as before.

The window is a few instructions, so the test lands a signal in it through a
second seam, `march_signal_watch_test_hook` (called right after the watcher is
published). `test/test_signal_watch.c` (`test_signal_watch_runner`, `runtest`):
watch A, re-watch B with the hook raising SIGHUP, drain, expect B ran once.

| build | where | result |
|---|---|---|
| red (old order) | macOS arm64; Docker ubuntu arm64 plain + ASAN | FAIL: the delivery is erased |
| fix | same three | PASS |

Distinct from the quarantined `signal_term_suppress` torn-output race
(`specs/todos/2026-07-23-ci-infra-2026-07-23.md`), which this does not touch.

## Housekeeping

The todo carried a stray trailing section ("Root causes (updated 2026-07-24)",
the nightly quarantine lane) about the CI quarantine, not this audit, which
exists nowhere else in the tree. It is preserved verbatim at the end of this
file rather than dropped.

---

## Original audit (filed 2026-07-24)

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

**FINDINGS — two, both filed here, both fixed 2026-09-21 (see top):**

- [x] **HCR dispatch ring: `dlclose` runs BEFORE the `live=0` retire store**
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
- [x] **Signal.watch registration window can erase a delivery**
  (`runtime/march_runtime.c` watch/unwatch): registration stores the handler
  FIRST, then clears `pending`/`seen` — a signal arriving between the two has
  its `pending=1` wiped by the trailing clear, silently dropping that one
  delivery. Clear-then-install would close it. Adjacent to (but distinct
  from) the still-quarantined `signal_term_suppress` torn-output race.

---

## Stray section carried by the todo (unrelated to this audit; kept verbatim)

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
