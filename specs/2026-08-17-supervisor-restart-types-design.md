# Supervisor restart types and child specs — design

**Date:** 2026-08-17
**Status:** design, not yet implemented
**Todo:** [`specs/todos/2026-08-12-supervisor-restart-types-and-child-specs.md`](todos/2026-08-12-supervisor-restart-types-and-child-specs.md)
**Decisions taken 2026-08-17:** labelled trailing modifier for the syntax;
`restart` implemented now with the grammar left extensible for `shutdown`.

---

## 1. The gap, restated against current code

**The todo overstates what remains.** It says `march_supervisor_notify` "fires
for **every** death of a supervised child". That was true when filed; it is not
true now. PR #284 threaded a `march_death_reason` through `do_actor_death`, and
the notify call is already guarded:

```c
/* runtime/march_runtime.c:3946 */
if (meta && meta->supervisor && reason != MARCH_DEATH_NORMAL) {
    march_supervisor_notify(meta->supervisor, meta);
}
```

So a child that returns from its actor loop normally (`MARCH_DEATH_NORMAL`,
raised at `:3019`) already does **not** restart. Verify this before building —
the guard is the whole reason this design is small.

What actually remains:

| Death path | Reason passed | Notifies today | Should notify |
|---|---|---|---|
| normal loop exit (`:3019`) | `MARCH_DEATH_NORMAL` | no | no, for every restart type |
| crash trap (`:2846`) | `MARCH_DEATH_CRASH` | yes | `permanent`, `transient` |
| `kill()` (`:3952`) | `MARCH_DEATH_KILLED` | **yes** | `permanent` only |
| batch sibling kill (`:3243`, `:3280`) | `MARCH_DEATH_KILLED` | no — the strategies null `cm->supervisor` first | unchanged |

**The live defect is one row:** `kill()` on a supervised child restarts it, with
no way to retire one deliberately. Everything else in this design is the
per-child policy needed to express that intent.

## 2. Semantics

Three restart types, `permanent` the default:

| Type | `MARCH_DEATH_CRASH` | `MARCH_DEATH_KILLED` | `MARCH_DEATH_NORMAL` |
|---|---|---|---|
| `permanent` (default) | restart | restart | **no restart** |
| `transient` | restart | no restart | no restart |
| `temporary` | no restart | no restart | no restart |

### The deliberate divergence from OTP — read this before implementing

OTP's `permanent` restarts a child **even on normal exit**. March's `permanent`
does not, because the `reason != MARCH_DEATH_NORMAL` guard already ships and the
todo's own acceptance criterion requires that "existing `supervise` blocks keep
working unchanged". Making `permanent` match OTP would silently change the
behaviour of every supervise block already written.

So March's `permanent` is OTP's `permanent` minus normal-exit restarts — closer
to OTP's `transient` than its `permanent`, with `kill()` counting as abnormal.
This must be stated in the actors chapter in exactly those terms; a reader
arriving from Erlang will otherwise assume OTP semantics and be wrong in a way
no error message will catch.

`transient` is then the genuinely new capability: **crash restarts it, `kill()`
retires it.** That is the job-worker case the todo names.

### Interaction with batch strategies

`one_for_all` and `rest_for_one` kill live siblings with `MARCH_DEATH_KILLED`
(`:3243`, `:3280`) as part of a restart pass. Those kills must **not** be
filtered by restart type — they are internal machinery, not a user retiring a
child, and the strategies already suppress recursive notify by nulling
`cm->supervisor` before the kill.

But the **respawn** side must honour the type: a `temporary` sibling caught in a
`one_for_all` sweep should be killed and *not* brought back. That check belongs
in `march_one_for_all_restart` / `march_rest_for_one_restart`'s respawn loop,
not in the notify filter. **This is the subtlest part of the change** — get it
wrong and a `temporary` child silently resurrects whenever a sibling crashes.

### Restart budget

A death that does not restart must not charge the restart budget or advance
`crash_streak`. Otherwise killing three `temporary` children in a row could
escalate and take down a healthy supervisor. The filter must therefore sit
**before** the leaf-lock section in `march_supervisor_notify` that does the
streak read-modify-write, not after.

## 3. Surface syntax

Current grammar (`lib/parser/parser.mly:637`):

```
supervise_child:
  | actor_type = upper_name; field_name = lower_name
    { (field_name, TyCon (actor_type, [])) }
```

New form — a labelled, optional trailing modifier, matching the block's existing
`max_restarts 3 within 60` keyword-value style:

```march
supervise do
  strategy one_for_one
  max_restarts 5 within 60
  Worker wa                      -- permanent (default, unchanged)
  Worker wb restart transient
  Reaper  wc restart temporary
end
```

Grammar:

```
supervise_child:
  | actor_type = upper_name; field_name = lower_name;
    r = option(child_restart)
    { (field_name, TyCon (actor_type, []), Option.value r ~default:Permanent) }

child_restart:
  | RESTART; t = restart_type_tok  { t }

restart_type_tok:
  | PERMANENT  { Permanent }
  | TRANSIENT  { Transient }
  | TEMPORARY  { Temporary }
```

**Why this shape.** It extends to `shutdown` with no grammar rework —
`Worker wb restart transient shutdown 5000` is another `option(...)` in the same
position. That satisfies the todo's "grow once" intent for the syntax, while
leaving `shutdown`'s *semantics* to the graceful-drain work
(`specs/todos/2026-08-12-graceful-shutdown-and-drain.md`), which does not exist
yet and cannot be faked.

**New keywords:** `restart`, `permanent`, `transient`, `temporary`. Check
whether these are already reserved — `march-lang`'s parser has a token filter and
this repo has a documented history of `init` being reserved and surprising
people. If any of the four collide with a common identifier, prefer
contextual keywords over reserving them outright, and say so in the report.

## 4. Implementation

### 4.1 AST (`lib/ast/ast.ml:291`)

```ocaml
and restart_type = Permanent | Transient | Temporary

and supervise_field = {
  sf_name    : name;
  sf_ty      : ty;
  sf_restart : restart_type;   (** NEW; Permanent when omitted *)
}
```

`sc_fields` already carries per-child records, so this is the natural home — no
parallel list, which would let the two drift out of order.

### 4.2 Lowering (`lib/tir/lower_actor.ml`)

`sc_fields` is consumed at `:316` and `:411`, and the strategy is already lowered
as an int literal at `:370` via `strategy_int`. Add the mirror: a
`restart_type_int` (`0`/`1`/`2`) emitted per child, threaded into the
`march_actor_register_child` call so the runtime learns each child's type at
registration.

### 4.3 Runtime ABI

`march_actor_register_child` gains a parameter:

```c
void march_actor_register_child(void *supervisor, void *child,
                                void *spawn_clo, int64_t word_idx,
                                int64_t restart_type);
```

This is an ABI change to a symbol that codegen emits. Update the declaration in
`runtime/march_runtime.h`, every `.ll` golden that declares it, and the
`test_codegen.ml` preamble strings. Grep for the symbol rather than trusting this
list.

`march_sup_child` (`:1783`) gains:

```c
    /* Restart policy for this child: 0 permanent, 1 transient, 2 temporary.
     * Set once at registration and never mutated, so unlike crash_streak /
     * last_crash_ms it needs no g_supervise_mu protection to read. */
    int32_t restart_type;
```

Note `sup_children` grows via `realloc`, which does **not** zero new memory —
`crash_streak` and `last_crash_ms` are set explicitly at registration for exactly
this reason (see their field comment). `restart_type` must be set explicitly too.

### 4.4 The filter

`march_supervisor_notify` currently takes `(supervisor, crashed_meta)`. The
reason is already reachable — `do_actor_death` sets `meta->terminal_reason`
(`:3815`) under `g_tbl_mu` before the notify call at `:3946`, guarded by
`terminal_set`. Prefer reading `crashed_meta->terminal_reason` over widening the
signature; confirm `terminal_set` is 1 on every path that reaches notify.

Filter early — before the leaf-lock section, so a suppressed death charges
nothing:

```c
    march_sup_child *child = &sup_meta->sup_children[child_idx];
    march_death_reason r = crashed_meta->terminal_set
        ? crashed_meta->terminal_reason : MARCH_DEATH_CRASH;
    int should_restart =
          child->restart_type == 0 ? (r != MARCH_DEATH_NORMAL)
        : child->restart_type == 1 ? (r == MARCH_DEATH_CRASH)
        : 0;
    if (!should_restart) return;
```

The `MARCH_DEATH_CRASH` fallback when `terminal_set` is 0 is deliberately
conservative: an unknown reason restarts a `permanent` child, preserving today's
behaviour rather than silently retiring something.

### 4.5 Batch respawn

In `march_one_for_all_restart` and `march_rest_for_one_restart`, skip the respawn
of any child whose `restart_type == 2` (`temporary`). Leave the kill itself
alone. See §2 — this is the easiest part to miss.

### 4.6 Interpreter parity

`lib/eval/eval.ml`'s `notify_supervisor` (`:2496`) and its caller (`:2573`) need
the same filter, reading the same reason the interpreter already computes for
`Down` messages. Both backends must agree: the registry work established that
identical source behaving differently across backends is its own bug class, and
`test/native/*.march` goldens run compiled while much of the supervision suite
runs interpreted.

## 5. Testing

**Unlike the concurrency fixes, this IS deterministically testable** — it is
single-threaded policy, not a race. There is no excuse for shipping it without
tests, and the acceptance criteria map one-to-one onto native goldens:

| Fixture | Asserts |
|---|---|
| `supervisor_restart_transient_kill.march` | `kill()` on a `transient` child retires it; supervisor stays up |
| `supervisor_restart_transient_crash.march` | a `panic()` in a `transient` child still restarts it |
| `supervisor_restart_temporary.march` | neither crash nor `kill()` restarts a `temporary` child |
| `supervisor_restart_permanent_default.march` | a child with no modifier behaves exactly as today |
| `supervisor_restart_batch_temporary.march` | a `temporary` sibling swept by `one_for_all` is killed and **not** respawned |
| `supervisor_restart_budget_unspent.march` | retiring N `temporary` children does not escalate the budget |

Run each **both compiled and interpreted** and diff against the same `.expected`,
following the pattern `interp_actor_registry_restart` established.

The existing three supervision goldens must byte-match unchanged — that is the
regression proof for "existing blocks keep working".

## 6. Risks

1. **Silently changing `permanent`.** If the notify filter is written as OTP
   semantics rather than the table in §2, every existing supervise block changes
   behaviour. The unchanged goldens are the guard.
2. **The batch respawn path (§4.5).** Missed, a `temporary` child resurrects
   whenever a sibling crashes — and no single-child test catches it.
3. **Budget accounting (§2).** Filtering after the streak update lets retirements
   escalate a healthy supervisor toward its `max_restarts` ceiling.
4. **ABI drift.** `march_actor_register_child` is emitted by codegen; a missed
   `.ll` golden or preamble string fails only in CI, and the sandbox stages only
   declared deps.
5. **Keyword collisions.** Four new keywords in a language where `init` is
   already reserved and has surprised people.

## 7. Out of scope

- `shutdown` timeouts — needs `2026-08-12-graceful-shutdown-and-drain`. The
  grammar accommodates it; the semantics wait.
- OTP's `type` (`worker`/`supervisor`) and `significant`. Nesting already works
  untyped, and `significant` has no consumer without shutdown semantics.
- Changing `permanent` to OTP's restart-on-normal-exit. That is a breaking
  change and should be its own decision if ever wanted.
