# `[P4]` Refinement checker: set-free VCs still pay for set element-sort resolution

Filed 2026-09-14, the last open item from the review of set refinements
(PR #452; see `specs/progress/2026-09-13-set-inclusion-refinements.md`).

Every call-site and postcondition VC runs `Refine_encode.resolve_set_sorts`
(two traversals of the goal and every assumption) and `set_preamble`
(`vc_set_elem_sorts`, another traversal) even when nothing in the VC is a set.
The result is correct, just unneeded work on the hot path of every obligation.

Direction: a cheap "mentions a set term or an `SSet` declaration" scan first,
returning the inputs unchanged when it is false. Measure before and after on
the stdlib refine sweep (`--refine-report` over the stdlib) rather than
assuming a win; the traversals are linear in the VC size.

## Closed 2026-09-14: measured, no win, not applied

Closed while landing Phase 1 of the set refinements strengthening
(`specs/plans/set-refinements-strengthening-plan.md` step 1.6), where
`resolve_set_sorts` became `Refine_encode.resolve_sorts`, which also settles
datatype instances and renames measures per instance.

The suggested fast path was built: a scan that returns the query unchanged
when it has no set term, no constructor or tester term, and no `Elem`,
placeholder or instance sort. The `--refine-report` sweep over every
`stdlib/*.march` file, run cold from an empty directory with z3 4.16, gave
byte-identical reports and no measurable difference in wall time:

| Build | Wall time |
| --- | --- |
| without the fast path | 176.9 s |
| with the fast path | 178.0 s |

Solver time dominates; the resolution traversals are linear in the query and
do not show. The fast path was reverted rather than kept as unmeasurable
complexity.
