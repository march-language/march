# Closure-capture release: a verdict per allocation site (what is left)

Follow-up to `specs/progress/2026-09-06-closure-environment-deep-drop.md`.

> **Re-checked 2026-11-09 on `c3cd49c76`.** Every concrete leak this file tracked is gone.
> The history is in git (`git log -p -- specs/todos/2026-09-06-closure-capture-release-widening.md`).
> Compiled `--opt 2`, 20,000 iterations, objects live at exit:
>
> - item 1, Perceus dups `$clo` at capture reads: landed 2026-09-13
>   (`specs/progress/2026-09-13-closure-environment-released.md`);
> - item 3, the outer release of a closure dropped without being applied: one closure in a
>   list never applied leaves 1 object in all, a dropped unapplied closure 0, and three
>   closures over one `String` 1. Fixed by `fedce40d4`
>   (`specs/progress/2026-10-05-dropped-closure-captures.md`);
> - item 4, `Array.set`'s trie path: 0 (it was 2.997 objects per update), and the tail path 0.
>   Fixed by `64091d1e3` (`specs/progress/2026-09-28-array-built-then-dropped-leaks-trie.md`);
> - item 5, `node_discovery`: resolved 2026-09-16.

## What is left: widen the gate (design, no known leak)

`owning_apply_fns` fails closed on any allocation shape it does not recognise, which is the
right default and also why it declines so many closure types. Two directions:

- Recognise more allocation shapes (an `EAlloc` in a tail, in an argument, in a field)
  instead of noting them `false`.
- Reach the verdict per ALLOCATION SITE rather than per closure TYPE, so one non-escaping
  site does not disqualify every other use of the same lambda. Perceus emits no RC op when a
  closure captures a borrowed alias (a field of a live record, an entry a map still owns), so
  such an environment owns nothing and must release nothing. A sound per-site verdict
  registers a closure type only when every allocation site took its own reference to every
  capture that needs one: an `inc_rc` immediately before the alloc, or a capture whose last
  use IS the alloc. Both are visible in the TIR at [Drop], which runs after RC insertion.

No measured leak depends on this today. It is a precision improvement to the gate.
