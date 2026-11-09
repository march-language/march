`[P3]` Unbounded quantifiers in lemma conclusions, with explicit triggers, and a `forall` statement.

Large step 10 of `2026-11-06-verification-ladder-roadmap`; after `2026-11-06-bounded-quantifiers`.

## Wanted

- `@[lemma] fn sorted_tail(xs : List(Int)) : {Unit | forall i : Int {nth(xs, i)}, … }` where
  `{…}` is the trigger the user picks (Dafny `{:trigger}`). A conclusion without a trigger the
  compiler can derive is an error, not a guess.
- A `forall` statement that proves a universal fact from a proof for one arbitrary value:
  `forall i in 0..n ensures P(i) do … end`.
- `exists` in a conclusion with a witness: `exists k, P(k) by k0`.

## Why last

Unrestricted quantifiers are where SMT proofs become brittle (matching loops, timeouts that flip
with unrelated edits). The bounded forms cover most needs; this is for library-level laws.

## Done when

- An instantiation/resource budget prevents uncontrolled search and reports the trigger,
  available statistics and `not proved`. Diagnose a matching loop only with evidence of repeated
  term generation; a large instantiation count alone is not proof of one.
- A library law (e.g. `forall xs, ys: reverse(append(xs, ys)) == append(reverse(ys), reverse(xs))`
  stated once and used without a call) proves and is used at callers.

## Prefer explicit proof boundaries (2026-11-07)

[Refinement Reflection, POPL 2018](https://nikivazou.github.io/static/popl18/refinement-reflection.pdf)
motivates controlling definition instantiation. Keep ordinary lemma calls as the default:
instantiating a theorem at a supplied argument is more explicit than installing all theorems as
ambient quantified axioms. Automatic use of an unbounded law is opt-in and locally scoped.

Universal introduction uses a fresh arbitrary variable, with no hidden assumptions specific to
one witness. Existential introduction checks the supplied witness. Validate binder coverage and
scope for triggers; no-pattern or exhausted cases are unproved. Add a recursive self-triggering
law and mutually triggering laws as negative/resource controls. This feature has no general
completeness guarantee and does not inherit one from PLE.
