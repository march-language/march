# `cap_grant_exceeded`'s fix can be invalid syntax (2026-11-19)

Found by the ocap phase 4 PR B final review ("Declined to judge"; pre-existing,
identical on the PR A head, but users hit it more now that every capability
operation goes through a stdlib entry point and reports `cap_grant_exceeded`).

When `main` has no parameters and its grant is the module's `needs` line, the
machine fix inserts a `Cap` parameter after a comma that has nothing before it:
`fn main(, _cap_clock : Cap(IO.Clock))`. The accompanying text says declaring
`needs` does not raise the grant, which is wrong in that case: the module's
`needs` line IS `main`'s grant, and adding the kind there is the fix.

What to do: when `main` takes no parameters, emit `fn main(_cap_clock :
Cap(IO.Clock))` (no leading comma); when `main` has no grant of its own, offer
the module `needs` edit instead and word the text for that case. Add a
`test/errors` case for each shape and check the fix is machine-applicable.
