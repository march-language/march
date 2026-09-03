# Refinement coverage audit

Status: designed 2026-09-03. Not landed.

## The problem

The obligation ledger made *filed* obligations countable. It cannot make
*unfiled* ones countable. A refinement the checker never recognises produces no
proof, no violation, and no skip. It is absent from every count, so every
existing guard rail reports success.

Two live examples, both confirmed on `dc3361f9`:

```march
fn f() : {String | _ == "a"} do "b" end          -- exits 0, ledger empty
```

```march
type Box = { v : {Int | _ > 0} }
fn f(b : Box) : Int do b.v end
fn main() : Int do f({ v: 0 }) end                -- exits 0, ledger empty
```

Both print `0 proved, 0 violated, 0 skipped` for user code. Under `cap verified`,
which promises that every obligation is discharged, both pass. The promise is
kept vacuously because no obligation was ever created.

Neither hole was found by a test. Both surfaced by accident, when someone wrote a
fixture that landed nowhere and noticed. The CI ratchet cannot see them either:
it enforces a skip ceiling and a proof floor, and an unfiled obligation moves
neither number.

## What the audit asserts

Not "every declared refinement produces an obligation". That is false by design.
A precondition is filed once per call site, so a refined parameter on an uncalled
function legitimately has zero obligations, and an audit built on that assertion
would drown in true zeros.

The assertion is instead:

> Every declared refinement occurrence has a known disposition.

The audit enumerates every `TyRefine` occurrence in a module and puts each into
exactly one bucket:

| bucket | meaning |
|---|---|
| `enforced` | the position is checked, and the checker's own extractor accepts this type |
| `inert-warned` | the position is deliberately not checked, and a warning already says so |
| `unenforced` | neither of the above: declared, silent, and nothing tells the user |

`unenforced` is the bug bucket. It is the thing no existing apparatus can see.

## Why this shape rather than a ledger join

The obvious design is to join the ledger back to declaration sites and report the
sites with no obligation. Three problems kill it:

- An obligation carries no declaration identity. It has a span, a callee string,
  a rendered predicate string, and a kind. For a precondition the span is the
  *call site*, not the declaration. The only join key is `(callee, predicate)`,
  which collides across same-named parameters and across same-named functions in
  different modules, and degrades to nothing whenever the predicate renders as
  the `<predicate>` placeholder.
- Fixing that means adding a declaration back-link to the obligation record,
  which touches a type the whole checker and its printers depend on, including a
  span-keyed index whose meaning must not change.
- Even with a perfect join, the uncalled-function case makes a zero
  uninterpretable without a call graph.

The audit avoids all three by never joining. It asks a different question, one
the compiler can answer locally at each declaration: *would the checker recognise
this refinement if it got here?* It answers by calling the checker's own
extractors, the same functions the real walk uses, on the declared type. An
uncalled refined parameter is `enforced` under this rule, correctly, because the
extractor accepts it and the absence of obligations is the absence of calls.

This also means the audit tracks the checker automatically. When an extractor
learns a new base type, sites move from `unenforced` to `enforced` with no audit
change.

## What it will find on day one

The audit goes red immediately, and that is the point. Expected populations:

- Return refinements whose base is neither Int, Bool, Float, a record, nor a
  single-clause unguarded ADT. String is the known one.
- Every refinement below the outermost position of a type: a record field, a type
  argument, an arrow domain, a linear wrapper.
- Refinements on positions the walk never reaches: a block-level `fn` return, an
  actor handler parameter.

The first release records the truth. It does not fix it. Two of these already
have todo files; the rest become todo files with a measured count behind them.

## Shape of the deliverable

A compiler flag, `--refine-audit`, mirroring `--refine-report`. It prints one
line per `unenforced` site with a span and a reason, then a summary table of the
three buckets. It changes no verdict and emits no diagnostic. Under `cap
verified` it stays silent, because turning a hole into an error is a separate
decision that should be made after the number is known, not before.

A committed baseline makes it a ratchet. The audit runs over the fixture corpus,
its output is compared to a checked-in file, and a human regenerates that file on
purpose when a change is intended. This follows the TIR snapshot pattern rather
than the refinement oracle, whose baseline lives in a temporary directory and is
not committed, so it cannot catch a regression that arrives between refactors.

## Where it hooks in

`Refine_check.check_module` ends by running the whole-type traversal that emits
the declared-but-inert warnings. At that point the module's declarations and the
completed ledger are both in scope. The audit is a further step there, after the
walk and before any printer, on the same side of the fence as the report with
respect to the inference probes that reset the ledger.

The site enumerator is a fork of that existing traversal, which already recurses
through every type constructor and already reaches lambda parameters, `let`
annotations, and annotations on expressions. It needs two additions the warning
walk does not have, both of which are holes in their own right: type definitions,
whose fields the walk skips on the stated ground that a refinement in a type
definition is checked where it is used, which is exactly the claim the nested
todo falsifies; and actor handler parameters.

## Risks

**The audit becomes a second source of truth that drifts.** Mitigated by calling
the checker's extractors rather than reimplementing their rules. Any
reimplementation would eventually disagree with the checker, and a coverage tool
that disagrees is worse than none. Where an extractor cannot be called directly,
the audit must say so rather than guess.

**A large `unenforced` count trains people to ignore it.** Mitigated by the
ratchet: the number is allowed to fall and never to rise, and each entry is
attributable to a position kind, so a new hole in a previously clean position is
visible even while the total is large.

**Cost.** The audit is a traversal over declarations plus extractor calls. No
solver work. It runs only under its flag.

## Not in scope

Fixing any hole the audit finds. Making `unenforced` an error under `cap
verified`. Cross-module coverage, which the per-module ledger reset makes
meaningless today.
