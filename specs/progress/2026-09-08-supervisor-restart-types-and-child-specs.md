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

---

## Landed 2026-09-08

Design: [`specs/2026-09-08-supervise-child-spec-design.md`](../2026-09-08-supervise-child-spec-design.md),
which decides the surface for `restart`, `shutdown` and `backoff` together so
the child spec grows once (trailing labelled modifiers per child; block-level
`backoff`; no new reserved words).

The *syntax* for `restart` had already landed on 2026-08-17's design — AST
field, parser rule, soft keyword, lowering, the fifth `register_child` ABI
parameter, and a `march_sup_child.restart_type` slot. What had NOT landed was
any reader: `grep restart_type runtime/march_runtime.c` found the declaration,
the parameter and the store, and no load. The policy was parsed, typed, lowered
and stored, then ignored, so the P1's actual defect was live in full.

What this change adds:

- `march_child_should_restart` / `march_meta_death_reason` in the runtime, and
  the matching `child_should_restart` / `child_restart_policy` in
  `lib/eval/eval_runtime.ml` — one table, implemented twice, because the two
  backends must agree on identical source.
- The filter sits **before** `march_supervisor_notify`'s `g_supervise_mu`
  section (and before the interpreter's per-strategy budget debit), so a death
  that does not restart charges nothing against `max_restarts`.
- Both batch strategies skip the *respawn* of a `temporary` child while still
  killing it, on both backends. This is the part no single-child test sees.
- `notify_supervisor` / `notify_dyn_supervisor` now take the death reason; the
  dynamic supervisor honours `transient` as well as `temporary`.

Fixtures (each runs compiled AND interpreted against one `.expected`, and each
was checked to be non-vacuous by deleting the `restart` modifier and confirming
a printed line flips on both backends):
`test/native/supervisor_restart_transient.march`,
`supervisor_restart_temporary.march` (which doubles as the budget assertion —
`max_restarts 1`, so a charged retirement would kill the supervisor),
`supervisor_restart_batch_temporary.march`.

`shutdown` is deliberately NOT parsed yet: the design fixes its surface, but a
parsed-and-ignored modifier would recreate exactly the trap described above.
It lands with the drain that reads it.
