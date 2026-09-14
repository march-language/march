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
