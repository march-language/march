# `[P3]` A role grant naming a non-IO capability fails inside generated code with unusable errors

Filed 2026-09-24 by the distributed-deploys review (step 4, PR #596).

## Defect

`check_role_needs` (`lib/typecheck/typecheck.ml:5229`) only checks that the
name is a known capability. `role Cons needs ClusterNode.Live` (or
`Session.Live`) gives about 8 repeats of "cap_narrow cannot produce …",
pointing at generated code with no excerpt. `role Cons needs LibC` gives 19
errors ("I cannot find `LibC`" and widening errors). All are rejected, so this
is not a hole, but nothing points at the grant line.

## Confirmed

By running `--check` on the three spellings.

## Fix I would make

In `check_role_needs`, refuse any path not under `IO`, with one diagnostic at
the grant line.

## Fixed 2026-09-24

`check_role_needs` refuses any path `Cap_lattice.cap_subsumes "IO"` does not cover, once,
at the path's span: "`role Cons needs ClusterNode.Live` names a capability that is not
under `IO`. A role's grant is narrowed by the runner from `main`'s `Cap(IO)`, so it can
name IO capabilities only; ... help: take `ClusterNode.Live` out of the grant. The session
capability is passed to every body already". The grant is not recorded, so the walk does
not run against it.

The generator had to change too, minimally (`lib/desugar/desugar_endpoints.ml`, owned by
the D27 session): `grants_of` now keeps only the paths under `IO`, so no `cap_narrow(io)`
is emitted for a non-IO path and the generated code produces no error of its own. Without
that filter the typechecker's one error would sit among the 8 (or 19) generated ones the
finding describes. Measured: `ClusterNode.Live` 9 errors → 1 at the grant line (plus the
program's own follow-on errors from a body written for the dropped parameter),
`Session.Live` 9 → 1, `LibC` 20 → 1. Witness: `cli_role_needs_non_io` asserts exactly one
`-- ERROR` and no "in code generated for this file" for all three spellings.
