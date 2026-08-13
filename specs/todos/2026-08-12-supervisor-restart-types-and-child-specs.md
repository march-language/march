`[P1]` # No restart types: a supervised child can never be retired

## The gap

`march_kill` → `do_actor_death` → `march_supervisor_notify` fires for **every**
death of a supervised child, with no way to distinguish "this child crashed"
from "this child was deliberately stopped". Every child is therefore
`permanent` in OTP's vocabulary, and:

**`kill(pid)` on a supervised child restarts it.** There is no way to
deliberately retire one. A worker that finishes its assignment and stops is
brought back, forever, until the restart budget escalates and takes down the
supervisor.

## What OTP child specs carry that March's `supervise` block does not

| Field | OTP values | March today |
|---|---|---|
| `restart` | `permanent` \| `transient` (restart only on *abnormal* exit) \| `temporary` (never) | always permanent |
| `shutdown` | `brutal_kill` \| timeout ms \| `infinity` | always brutal |
| `type` | `worker` \| `supervisor` | n/a (nesting works, but untyped) |
| `significant` | bool | n/a |

`transient` is the common case this blocks: a job worker that exits normally
when its work is done, and is restarted only when it dies badly.

## Sketch

The runtime already distinguishes the two death paths — `march_kill` (explicit)
vs the crash trap in `actor_green_thread` (panic) — it simply collapses them at
the notify call. Thread a reason through `do_actor_death` (shared with
`2026-08-12-monitor-down-carries-no-reason.md`, which needs exactly the same
information) and consult the child's restart type before notifying.

Surface syntax is the open design question: `supervise` blocks name children as
`Name = spawn(Actor)`, with no slot for per-child options. Options include a
trailing modifier (`child = spawn(W) restart transient`) or an options record.
Decide alongside the `shutdown` field so the child spec grows once, not twice.

## Acceptance

`kill()` on a `transient`/`temporary` child stops it for good; a crash still
restarts a `transient` child; existing `supervise` blocks keep working
unchanged (permanent stays the default).
