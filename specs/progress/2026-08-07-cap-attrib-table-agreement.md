# The ceiling's "indirect calls" false positive was two tables disagreeing

Landed 2026-08-07.

## The symptom, and why it misled

`--cap-strict` rejected correct programs:

```
$ march --compile --cap-strict -o /tmp/x bench/par_fib.march
-- CAPABILITY CEILING --
`IO.Spawn` is used but cannot be attributed to any module — it is reached only
through indirect calls, whose callee is not statically known
```

`bench/par_fib.march` calls `task_spawn` **directly in its own body** (lines
37–38) and declares `needs IO.Spawn` **on line 24**. Nothing about it is
indirect, and no amount of declaring fixes it — the author already declared it.

Measured before the fix: **4 of a 24-program sample** failed this way, all of
them parallel code. That made defaulting `--cap-strict` impossible, because the
diagnostic told users to do something that could not work.

## The cause: two capability tables, keyed differently

March has two, both load-bearing:

| table | key | drives |
|---|---|---|
| `Typecheck.builtin_cap_table` | March name (`task_spawn`) | source-level checks — Check 1b, and the severity flip |
| `Cap_symbols` | C symbol (`march_task_spawn_thunk`) | `Cap_attrib.attribute`, which the ceiling reads |

`Cap_attrib.cap_of_call` bridged them with
`Cap_symbols.cap_of_symbol (c_symbol_of_march_name name)`. That function returns
its argument **unchanged** when a builtin has no `c_name` — a trampoline-lowered
one like `task_spawn` — and the bare March name is not a key in `Cap_symbols`.
So the lookup returned `None`, attribution recorded nothing, and the capability
arrived in the ceiling's flat set with no owner.

`Cap_ceiling.Unattributed` then reported it with the only explanation it had.

## The fix

`cap_of_call` consults `builtin_cap_table` (March name) first and falls back to
`Cap_symbols` (C symbol). The fallback is still required: `Cap_symbols` also
keys synthesized post-lowering symbols (`march_task_spawn_thunk`) that never
appear as a March name.

No table was duplicated — `march_tir` already depends on `march_typecheck`, so
attribution now reads the *same* table typecheck does.

## The test is the deliverable

`test/test_cap_attrib_agreement.ml` asserts that every capability-bearing
builtin in `builtin_cap_table` resolves to the *same* capability through
attribution's path.

**It found more than I did.** My source grep for `c_name = None` predicted 3
affected builtins; the test found **10** — every one of `IO.Clock`'s,
`IO.Signal`'s and `IO.Spawn`'s:

```
unix_time_ms, uuid_v7            IO.Clock
signal_watch, signal_unwatch,
  signal_raise_self              IO.Signal
task_spawn, task_spawn_link,
  task_spawn_steal,
  task_spawn_with_cancel,
  get_work_pool                  IO.Spawn
```

Three whole capability families were invisible to the ceiling. A grep-based
estimate would have shipped a fix for a third of the problem and left the rest
to be rediscovered.

## Result

`examples/` + `bench/`, all 72 programs, `--compile --cap-strict`:

| | before | after |
|---|---|---|
| unattributed (false positives) | ~17% of sample | **1 of 72** |
| undeclared (genuine violations) | — | 12 |

The 12 undeclared are the ceiling working as intended — stdlib-mediated uses the
module really has not declared. They are the migration that a future
`--cap-strict`-by-default change has to do, and they are actionable: the
diagnostic names the module and the capability.

## What is left, and it is a different bug

The single remaining false positive is `examples/capabilities.march`, and it is
**not** the indirect-call gap despite the message saying so: a capability that
appears only in a SIGNATURE (`fn demo_narrowing(cap : Cap(IO))`) is counted as
used by the typecheck side and can never be attributed by the emitted-code side.
Filed as
`specs/todos/2026-08-07-ceiling-counts-signature-only-capabilities-as-used.md`,
with a note not to "fix" it by treating declared-anywhere as attributed, which
would defeat the fail-closed rule.

That todo also records the meta-lesson: `Cap_ceiling.describe` has one
`Unattributed` constructor that always blames indirect calls, so it
misdescribed its own cause for the entire `task_spawn` investigation and would
do so again. Carrying a reason on the constructor is cheap.

## Verification

corpus 277/277, compiler 799, eval 256, stdlib 833, codegen 546.
