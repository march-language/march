`[P2]` # `link` is implemented but unreachable; no exit signals, no trap-exit

## The gap

`lib/eval/eval.ml:4238` defines a `link` builtin (and `link_actors` /
`ai_links` machinery backs it), but **there is no entry in the typechecker's
builtin table**, so the function does not exist as far as typed March is
concerned:

```
    link(a, b)
         ^^^^
    I cannot find `link`.
```

(verified 2026-08-12 against a two-actor program). `unlink` is in the same
position. There is also no `trap_exit` / exit-signal propagation of any kind.

So the runtime carries half an implementation of a fault-propagation model that
no program can reach.

## Why it matters

Links + exit signals + trap-exit are BEAM's *core* fault model — they are how
supervisors are built and how "let it crash" composes beyond a single
supervision tree. March currently has monitors (one-directional, and see
`2026-08-12-monitor-down-carries-no-reason.md`) plus built-in supervisors, and
nothing else.

## The decision to make, deliberately

This is genuinely a design fork, not an obvious omission:

- **Akka** deliberately dropped links in favour of DeathWatch (monitor-style) +
  supervision strategies, and is none the worse for it.
- **BEAM** treats links as foundational.

Either answer is defensible. What is *not* defensible is the current state: an
accidental answer produced by an unreachable builtin. Pick one:

1. **Expose it** — type `link`/`unlink`, define exit-signal propagation
   (a linked actor's death kills its peer unless the peer traps exits), add
   `trap_exit` so a trapping actor receives an Exit message instead of dying.
2. **Remove it** — delete the interpreter builtin and `ai_links`, and state in
   `specs/lang/actors.md` that March's fault model is monitors + supervisors,
   Akka-style, so the absence is documented rather than discovered.

Option 2 is cheaper and loses nothing that supervisors + a reason-carrying
monitor do not already provide. Option 1 is the right call only if bidirectional
failure propagation between *peers* (not parent/child) turns out to be a real
need.

## Acceptance

Either `link` type-checks and its exit semantics are specified and tested, or
the builtin is gone and the actors chapter says why.
