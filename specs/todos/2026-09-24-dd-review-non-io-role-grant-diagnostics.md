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
