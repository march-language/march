# Refinement probe queries declare a z3 constant named `_`

Logged 2026-11-09 (found while timing stage B of the Map/Set proofs, #1211).

Checking a trivial program with the stdlib's Set proofs in place starts two
`z3 -in` processes even when every verdict is cached. Each sends six
validity/satisfiability probes (`(assert (not P))` and `(assert (not (not P)))`)
over a return refinement that mentions `elts`, and each declares the
refinement's binder verbatim:

```
(declare-const _ M_List)
(assert (not (= ($elts$M_List _) ((as const MSet$Elem) false))))
(check-sat)
```

z3 rejects `_` ("invalid constant declaration, symbol expected"; "unknown
constant _"), then answers `sat` for the unconstrained remainder. Every probe
reads as satisfiable whatever the predicate, so whatever pass runs them never
fires on these refinements, and the queries are not served from the verdict
cache.

To do: find the probe (a vacuity/tautology check on `{T | P(_)}` that encodes
the binder without renaming it, as the obligation encoder does), rename `_` to
a fresh symbol, and add a test whose predicate is a tautology so the probe's
verdict is visible. Capture the traffic with a `z3` wrapper on `PATH` that tees
stdin when it is called with `-in`.
