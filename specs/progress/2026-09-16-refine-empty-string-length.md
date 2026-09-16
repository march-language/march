# `s == ""` establishes a length in the else-branch

**Landed 2026-09-16.** Plan: `specs/plans/2026-09-16-refinement-precision-plan.md`
(Part B, phase B3 — the cheap alternative the plan recommended over swapping
to z3's string theory).

## The gap

`String` is modelled as an uninterpreted sort with `len` as an uninterpreted
function constrained only by non-negativity. Distinctness from the empty
literal therefore said nothing about a length, so

```march
if s == "" do 0 else nonempty(s) end
```

skipped in the else-branch against `nonempty(s : {String | len(_) > 0})`. The
spec documented this as a real gap whose closure "needs an injectivity axiom
with a cost assessed as not worth it".

## The fix, and why it is not that axiom

Each declared string constant now carries the ground implication

```
c != "" -> $strlen(c) > 0
```

which is true of byte length: the empty string is the only string of length 0.
No string theory, no injectivity axiom, no quantifier — a ground implication
per constant, which matters because a quantified axiom is what once turned
every stdlib `Array` bounds check into a 1.5 s `unknown` and cost every
program's cold check 20 s.

It is registered from both sides (`declare_str_const` and `str_lit_const`),
since the empty literal and the variable can be minted in either order.

## What stays skipped, deliberately

- The THEN-branch. The fact is conditional on `s != ""`, so a call guarded the
  wrong way round proves nothing — pinned by its own fixture, because an
  unconditional implication would prove both branches and the else-branch
  fixture alone could not tell the difference.
- An unguarded string. The implication is a fact about strings, not a licence
  to assume non-emptiness.
- Prefix, suffix, contains, concatenation and regex reasoning: still outside
  the fragment, and the plan's recommendation against a full string-theory
  swap stands — zero stdlib string refinements exist, and CI's z3 is an
  unpinned distro build on a shared solver process.

## Measurements

- `test_refinecheck.exe`: 897/897. The fixture that previously pinned the
  limitation is rewritten to pin the new behaviour, plus two guards against
  over-claiming.
- Cold check: 0.38 s user, unchanged across three runs. (A first measurement
  read 1.81 s; that was another worktree's suite saturating the machine, not
  this change. Load makes timings lie — measure more than once.)
- `stdlib/list.march` unchanged at 42 proved / 42 skipped: no stdlib
  refinement mentions a string.
