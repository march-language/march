# Diagnosing the `solver-undecided` bucket

Filed 2026-09-01.  Status: LANDED 2026-09-01 (branch
`claude/refinement-errors-improvement-de2bdc`).  Implementation notes, and every
deviation from this document, are in
`specs/progress/2026-09-01-refinement-solver-undecided-diagnosis.md`; measured
results are in `specs/2026-09-01-refinement-error-diagnosis-measurements.md`.
Note in particular that the fourth cause proposed below, `Nonlinear_goal`, was
CUT as unreachable — three diagnosed causes shipped.

## Problem

The refinement diagnostics March *emits* are good.  Counterexample surfacing
(#383) gave return-contract failures a concrete failing input, dual spans and a
plain-English requirement line:

```
`clamp` does not satisfy its return type constraint on all code paths.
The return type requires:  _ >= 0
but clamp(0) returns -1.
```

The problem is one step away from those cases.  Sampling `--check
--refine-report` over six stdlib modules (`list`, `enum`, `map`, `string`,
`json`, `uri`) gives 34 skipped obligations, **32 of them `solver-undecided`** —
a single undifferentiated bucket whose entire user-facing text is a canned
paragraph of March's philosophy and nothing about the call in front of them:

```
precondition `_ > 0` on `Enum.chunk_every` was NOT verified here.
reason: solver-undecided — the solver proved neither the predicate nor its negation
note: March reports only definite failures, so a contract it cannot decide
is accepted in silence.  Add `cap verified` to this module to make every
unverifiable obligation an error instead; `--refine-report` lists them all.
```

Two measured examples of how coarse that is.

**One `let` degrades a definite violation into the bucket.**

```march
Enum.chunk_every(xs, 0)   -- ERROR: precise, argument-level span, "guard the call"
let n = 0
Enum.chunk_every(xs, n)   -- HINT: solver-undecided
```

**The stdlib's flagship refined function cannot verify its own recursive call.**
`stdlib/list.march:128`:

```march
fn last(xs : {List(a) | len(_) > 0}) : a do
  match xs do
  Nil          -> panic("List.last: empty list")
  Cons(x, Nil) -> x
  Cons(_, t)   -> last(t)   -- HINT: solver-undecided on len(_) > 0
  end
end
```

The needed fact is in the match: the previous arm ruled out the singleton, so
`t` is a `Cons`.  A human decides this at a glance and is told the solver was
unsure.

This design does **not** close the precision gaps that cause those skips.  It
splits the bucket so the reader learns *which* thing went wrong and what to do,
and it promotes the one sub-case that can be proven a real failure.

### Dropped during implementation: `Nonlinear_goal`

A fourth variant, for a goal multiplying two unknowns, was specified and then
cut: it is unreachable.  `smt_of` (`lib/refinecheck/refine_scope.ml:143`)
returns `None` for a product of two non-literals, so such a predicate never
reflects at all and the obligation is filed `unreflectable-predicate` long
before `check_call`'s fall-through.  `Smt.Mul` is built only by
`division_safety` and `return_infer`, neither of which feeds that ledger.
Making it reachable would require extending reflection — a precision change,
which §Non-goals rules out.  Recorded here so it is not re-proposed.

## Non-goals

- No new facts are derived.  Let-bound constants are still not propagated;
  match-arm exclusions are still not derived.  Those are a separate project,
  and this one is deliberately sized to be independent of it.
- No change to what is *accepted*, except the promotion in §2.

## 1. Split the bucket

`Obligation.reason` gains four variants; `Solver_undecided` survives as the
honest residual.  Diagnosis runs lazily at the fall-through
(`lib/refinecheck/refine_call.ml:1919`), reached only when we are already
committed to not proving, so a proved obligation pays nothing.

| Variant | Detection | Cost |
|---|---|---|
| `Unconstrained_subject of string` | the subject's SMT symbol appears in zero assumptions of the built `vc` | syntactic, free |
| `Partial_conjunct of { held : string list; missing : string list }` | goal is an `And`; discharge each conjunct separately | *n* extra Z3 queries, off the happy path only |
| `Nonlinear_goal` | goal contains `*` / `/` / `%` over two non-constant symbols | syntactic, free |
| `Opaque_application of string` | goal names a function symbol the VC preamble never declared | syntactic, free |
| `Solver_undecided` | none of the above | — |

`reason_name` gains three slugs and `reason_detail` one clause each.  The slug
split is the deliverable for `--refine-report`: it stops saying "32
solver-undecided" and starts saying which 32.

Note this cuts against the existing comment on `reason_name`, which
deliberately does *not* interpolate a spelling into the `alias-withdrawn` slug
to avoid splitting one cause into as many buckets as there are names.  That
reasoning is sound and still applies: the variants here are distinct *causes*,
not several spellings of one, and `Unconstrained_subject` /
`Opaque_application` carry their name in the detail rather than the slug for
exactly that reason.

Target messages:

```
-- HINT --
precondition `_ >= 0 && _ < len(xs)` on `List.nth` was NOT verified here.
`i >= 0` is established here.  `i < len(xs)` is not — nothing in scope
relates `i` to the length of `xs`.
```

```
-- HINT --
precondition `_ > 0` on `Enum.chunk_every` was NOT verified here.
Nothing in scope constrains `n`.
```

## 2. Promote confirmed, executed panics

### The unsound version, and why it is unsound

The only difference between today's `Violated` path and the undecided
fall-through is which discharge came back `Verified`.  On the undecided path
`first` is often `Sat` and carries a model, and `Witness.confirm_precond`
already exists to decode a model, execute it and confirm a violation.  Wiring
it straight in would be wrong.

`confirm_precond`'s `ok` predicate (`lib/refinecheck/witness.ml:837`) validates
a candidate against the scope refinements, **the recorded path facts**, and the
predicate.  Under `Violated` that is sound — the solver already proved the
negation from those same assumptions, so the witness is illustrative decoration
on a settled verdict.  In the undecided bucket the witness becomes load-bearing,
and it is unsound exactly where the bucket is most populated: **when the reason
for undecidedness is a missing fact, that fact is by definition not in `path`,
so a candidate violating it sails through `ok`.**

`List.last` is the worked example.  `t = Nil` satisfies every *recorded* path
fact; the arm exclusion that rules it out is precisely the fact the checker
never derived.  A naive promotion reports a confirmed failing input for a
provably correct function — the one thing #383 measured itself against and won
on (zero new diagnostics over 298 fixtures).

### The gate: execute the enclosing function from its entry

When `first` is `Sat`:

1. Take the model and keep only assignments to the **enclosing function's own
   parameters**.  A subject that is a match binder or a `let`-bound
   intermediate contributes nothing here.
2. Check those arguments admissible against the enclosing function's own
   refinements — this is the `sc` check that `ok` already performs.
3. Run the enclosing function from its entry under the existing fuel limit and
   effect veto.
4. Promote **only** if it actually panics, and quote the panic.

Reachability is never assumed; it is demonstrated.  Both cases fall out without
special-casing:

- `fn caller(ys : List(Int)) = head_of(ys)` — model assigns `ys = []`, which is
  an admissible argument to `caller`, execution panics.  Promoted.
- `last`'s recursive `last(t)` — the model assigns the match binder `t`, not a
  parameter.  `last`'s only parameter `xs` is constrained by its own
  `{List(a) | len(_) > 0}`, so no admissible `xs` reaches that call with
  `t = Nil`.  Nothing to execute, nothing promoted.

The second is not a special case being added.  It is what executing from the
entry does on its own, and it is why this gate is preferred over a syntactic
completeness proxy: a proxy would need widening every time the checker's
precision improves, and would be silently wrong in between.

Candidates decline (no promotion, fall back to §1's diagnosis) whenever the
enclosing function is not interpreter-runnable — effectful, capability-
requiring, non-terminating under fuel — or its parameters cannot be decoded.

### Severity and the fix

`Warning` by default; `Error` under `cap verified`.

This differs from #383, which made a some-input *return-contract* violation an
`Error`, and the asymmetry is deliberate.  A return-contract violation breaks a
promise the function made itself.  A call-site precondition failure on an
unrefined parameter means the function made no promise at all — it silently
propagates someone else's requirement.  Nearly every unrefined wrapper around a
panicking stdlib function is in that category, so the blast radius is much
larger, and "propagates an undeclared requirement" is a design choice a user is
allowed to make.  `cap verified` is already the established opt-in for turning
unverifiable obligations into errors, so escalation there needs no new concept.

On promotion only, call `precond_infer` for that one function and attach its
result as the diagnostic's `fix`.  `precond_infer` is assume-and-recheck against
the real checker, so a suggestion is correct by construction; it costs tens of
re-checks, which is affordable precisely because promotion is rare.  The message
then ends in the signature to write rather than the panic to fear:

```
-- WARNING --
`caller` propagates a requirement it doesn't declare.

`head_of` requires  len(_) > 0
but caller([]) panics at r1.march:11 — "List.head: empty list"

help: declare what `caller` actually needs —
        fn caller(ys : {List(Int) | len(_) > 0}) : Int
`forge fix` can apply this.
```

## 3. Testing

**The test that matters most is a negative one.**  `List.last` must not be
promoted, asserted as *silence at that span*.  An accept-only fixture passes
whether the promotion is correctly declining or the whole promotion path is
dead — the same trap that hid five bugs behind five `| _ -> ()` capability
walks, caught only by tests asserting a specific negative.

- One fixture per new reason variant, pinning *which* variant fires.
- Promotion fixtures on both sides: `caller(ys)` promoted with a quoted panic,
  `last` silent.
- Fixtures for the decline paths: effectful enclosing function, undecodable
  parameter.

## 4. Measurement

Two numbers, over the real corpus rather than the six-module sample:

1. **Bucket distribution across all 116 stdlib modules plus `test/native`,
   before and after.**  "94% of skips are one bucket" becomes a table naming
   the split.  This also tells us whether the three variants are the right three,
   or whether the residual is still the largest slice — in which case the
   taxonomy is wrong and should be revised before shipping.
   Two caveats established during implementation, which any quoted number
   must carry: (a) a promotion is recorded as `Obligation.Violated`, the same
   verdict the solver uses for "can never hold" — `refine_post` already did
   this for some-input return failures — so `--refine-report`'s `violated`
   total conflates the two shapes; (b) promotion is not attempted for spans in
   `stdlib_files`, whose diagnostics are filtered from output, because doing
   so produced an unexplained `violated` count and paid the interpreter cost
   for nothing (four true-but-invisible sites in `stdlib/stats.march`).

2. **Promotion count, hand-audited line by line.**  This number should be
   small.  If it is large, the reachability gate is wrong; stop rather than
   ship.

Plus `--check` wall time on a trivial program against the pre-change compiler.
#383 recorded 1.08s → 1.17s and that budget is not infinite.

## 5. Oracle protocol

`refine-oracle` will legitimately move: hint text changes on nearly every skip,
report slugs regroup, promotions add lines.  That makes it useless as a
pass/fail gate here, and running it as one would be self-deception.  Instead:

1. Prove it RED-capable on a deliberate verdict perturbation **first**.
2. Diff baseline against check and justify every moved line by category —
   expected text change, expected regroup, intended promotion.
3. Any line fitting none of those three is a bug.

Three caches produce vacuous green and are handled up front:

- `.march/cas/artifacts-v2` — a compile-path CAS hit short-circuits before
  `--refine-report` prints anything.
- `.march/cas/vc` — cleared **once** before the run, never during it.
- `~/.cache/march` — shared across worktrees; its marshalled stdlib spans carry
  the populating worktree's absolute paths.  Run under a private `HOME`.

Ordinary gates: full `scripts/run-tests.sh`, and `@types-check` **with
`--force`**, asserting on the log contents — without `--force` it exits 0 with
a zero-byte log and proves nothing, and these new messages are exactly the kind
of diagnostic text it pins.

## 6. Cost summary

Everything added is off the happy path.  Conjunct splitting runs only after the
positive discharge failed.  Interpreter execution runs only when there is a
`Sat` model and the enclosing function is runnable.  `precond_infer` runs only
on a confirmed promotion.  A proved obligation pays nothing new.
