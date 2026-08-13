# Supervisor restart backoff: constants are not tunable from March

Filed alongside Task 16 of the actor-system-hardening plan
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`), which added
exponential restart backoff with jitter to `march_supervisor_notify`
(`runtime/march_runtime.c`).

## What's fixed today

The backoff curve is hardcoded in C: `delay = min(5000, 25 << min(streak-1,
7))` ms, `±25%` jitter, streak resets after a full `supervisor_window_secs`
window survived. There is no way for a `supervise do ... end` block to
choose a different base delay, cap, jitter fraction, or to opt out of
backoff entirely (beyond crashing only once, which always takes the
zero-delay synchronous path regardless).

## Why it's out of scope for Task 16

Task 16's brief locked in the exact constants above so every existing
supervision golden (`examples/supervision_strategies.march`, the native
supervision tests, which each crash a child exactly once) stays
byte-identical. Making the curve configurable means threading new syntax
through the parser/typecheck/lower pipeline for the `supervise` block
(alongside the existing `strategy` / `max_restarts N within S` clauses),
plus deciding sensible defaults and validating them — a feature-sized
change, not a fit for a hardening task whose job was "stop the crash-storm
CPU burn without changing observable behavior for the common case."

## Suggested shape for a follow-up

Extend the `supervise` block grammar with an optional clause, e.g.:

```
supervise do
  strategy one_for_one
  max_restarts 100 within 60
  backoff base 25 cap 5000 jitter 25%   -- new, optional
  Fragile child
end
```

parsed into `sup_meta` fields (`backoff_base_ms`, `backoff_cap_ms`,
`backoff_jitter_pct`) alongside the existing `supervisor_max_restarts` /
`supervisor_window_secs`, defaulting to today's hardcoded values
(25/5000/25) when the clause is absent so existing programs (and the
goldens) are unaffected. `march_supervisor_notify`'s delay computation
would read from `sup_meta` instead of the literals.
