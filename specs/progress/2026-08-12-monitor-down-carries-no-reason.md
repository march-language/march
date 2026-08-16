`[P1]` # A local monitor delivers a COUNT, not a Down message with a reason

## The gap

`march_monitor` (`runtime/march_runtime.c`) registers the watcher on the
target's `monitor_head`; when the target dies, `do_actor_death` walks that list
and does nothing but `atomic_fetch_add(&watcher_meta->down_count, 1)`. The
watcher can learn only *how many* monitored actors have died — never **which**
one, under which monitor ref, or **why**.

`march_mailbox_size` returns `queue depth + down_count`, which is the only way
the count surfaces at all.

## Why it matters

- A watcher cannot distinguish a normal stop from a crash from a kill, so
  user-written supervision-like logic (retry on crash, accept a normal exit)
  is impossible to write correctly.
- `Actor.call` cannot tell "the actor died" from "the deadline passed" — both
  surface as the same timeout `Err`, which the 2026-08-12 hardening documented
  but could not fix for want of a reason channel.

## The inconsistency to close

The **distributed** plane already models this properly:
`stdlib/dist_link.march` defines `DownReason = Normal | Killed | Crash(String)
| NodeDown` and delivers `Down(ref, pid, reason)`. So a cross-node monitor is
strictly more informative than a local one. Close the gap in the *local*
direction — reuse `DownReason` rather than inventing a second vocabulary.

## Sketch

Deliver a real message into the watcher's mailbox instead of bumping a counter:
`do_actor_death` already knows the reason it was called with (explicit
`march_kill` vs the crash trap in `actor_green_thread` vs normal loop exit), so
the information exists at the call site and is currently discarded. Monitor
nodes already carry `mon_ref`, so the ref is available too.

Interacts with the mailbox work: a Down message is an ordinary message and must
respect the target's queue limit — decide deliberately whether a Down is
control-plane traffic that bypasses the limit (cf. the scheduler-stack bypass
in `march_sched_send`) or ordinary traffic that can be dropped.

## Acceptance

A watcher receives a `Down` carrying the monitor ref, the dead Pid, and a
reason that distinguishes normal / killed / crashed, on both backends.

## Completed 2026-08-15

Implemented by the local-monitor runtime/compiler work and documented here.
The delivered shape is `Down(ref, target_pid, reason)`, with local reasons
`Normal`, `Killed`, and `Crash(String)`. Delivery is control-plane traffic and
bypasses the watcher's mailbox limit. The interpreter and compiled backends
have matching local payload and reason behavior; the distributed protocol
retains the same shape and adds `NodeDown`.

Files documented: `docs/actors.md`, `specs/lang/actors.md`, and `CHANGELOG.md`.
The native monitor witness is `test/native/actor_monitor_down_reason.march`.

Verification (completed 2026-08-15 on a quiet box, load avg ~9.5, after the
initial run was terminated mid-flight under a load-250 episode):

| suite / gate | result |
|---|---|
| `run_compiler` | 915 tests, 0 failures |
| `run_eval` | 256 tests, 0 failures |
| `run_codegen` | 583 tests, 0 failures |
| `run_stdlib` | 863 tests, 0 failures |
| `test_stdlib_march` | 59 tests, 0 failures |
| TIR snapshots | 33 tests, 0 failures; `git diff test/snapshots/` empty |
| `@types-check` (CI-only, `--force`) | 293 passed, 0 failed |
| `@grammar-check` (CI-only, `--force`) | 46 passed, 0 failed |
| `scripts/check-docs.sh` | passed |

The four `run_stdlib` failures recorded in the first attempt (HCR versioned
dispatch, HCR manifest capabilities, `MARCH_SANITIZE` clean exit, and
string-statistics bytes-copied) were **environmental, not caused by this
change**: the same suite that recorded them now passes in full, and
`test_stdlib_march`, which never started, passes too. They were not assumed to
be flakes — this change reallocates constructor tags (reserved range
`0x7f00_0000+`) and HCR dispatch is tag-sensitive, so a genuine regression was
plausible and had to be ruled out by re-running rather than by inspection.

The TIR snapshots were run deliberately rather than skipped: this change edits
`lower.ml`, `lower_match.ml`, `lower_state.ml` and `lower_actor.ml` while
updating no `.expected` file, which is the profile of a stale-snapshot failure.
They pass, and the snapshot diff is genuinely empty — the monitor lowering does
not perturb the pinned corpus.

Both CI-only gates were run with `--force`; without it `@types-check` exits 0
with a zero-byte log and proves nothing.

The native monitor witness is `test/native/actor_monitor_down_reason.march`.
