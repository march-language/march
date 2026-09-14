# `[P3]` Contract `Array.get` / `set` / `pop` with a bounds precondition

Filed 2026-09-13, when the blocker was removed
(`specs/progress/2026-09-13-measure-over-scalar-ctor-field.md`): a
`@[measure]` over `PVec`'s count field now reflects concretely on a literal
and is decided by a guard over `Array.length(v)` on an opaque value, which
is the `List.nth` treatment's precondition shape.

What is left is the contract itself and its consequences:

- tag `Array.length` `@[measure]` (it passes the M-b gate: total,
  terminating, pure) and give `Array.get` / `set` / `pop` a precondition
  `{Int | _ >= 0 && _ < Array.length(v)}` (`pop`: `Array.length(v) > 0`);
- add them to `Panic_surface_by_proof`'s covered set, which is fail-closed:
  every call under `cap no_panic` must then either prove its bound or be
  rejected, so an unguarded `Array.get(v, i)` in existing `cap no_panic`
  code becomes an error;
- run a full stdlib + ecosystem `--refine-report` sweep BEFORE landing and
  review every obligation that moves to VIOLATED: each is a real bug or a
  real false positive, and either blocks the change until understood.

Design: `specs/2026-09-13-refinement-p3-designs.md` §4, last paragraph.
