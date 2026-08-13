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
