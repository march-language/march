`[P3]` **An interface method name is not module-qualifiable at all.**

`Bar.greet(1)` never resolves — for a nested module or the entry module alike —
because a method resolves through interface dispatch rather than module member
lookup. So entry-level `Foo.greet(1)` failing is consistent rather than a
stripping gap, but it is still a spelling an author will reasonably write.

Making it work needs interface methods to become qualifiable in general (a
dispatch-side change), not a classification tweak: folding the method names into
`collect_direct_names` (`lib/desugar/desugar.ml`) was **measured** to regress
working code, because the same list feeds `qualify_module_refs`, which then
rewrites the bare `greet(1)` inside the declaring module into `Bar.greet(1)`.

## Before closing this, read: it will silently re-vacuate `accept/t126` and `accept/t127`

Those witnesses pin `stdlib_member_defs_ok`'s entry-module walk start, and they
currently do it with an `interface`/`impl` competitor *because*
`strip_entry_self_qual` does not rewrite method names. They were rewritten into
that shape on 2026-07-30 precisely because the `extern` competitor they used
before stopped working the moment that task taught the walk about externs — the
witnesses went vacuous and passed whatever the gate did.

The obvious way to close this residual puts them straight back in that state:
the entry module's `List.length(ys)` gets stripped to bare `length(ys)`, the
alias is never consulted, and both pass regardless of the walk start. Whoever
closes this must **re-verify t126/t127 by mutation** (revert the walk start to
`go false` and confirm each is still rejected with the false `len(_) > 0`
violation) and re-home them onto a competitor form that survives.

Related: `lib/refinecheck/refine_check.ml`'s member scan counts interface/impl
methods as a deliberate over-approximation and says so — do not "correct" it by
deleting those arms, which t126/t127 now depend on.
