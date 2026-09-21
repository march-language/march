# `[P2]` A `linear` parameter's body is not checked for exactly one use

Filed 2026-09-21, split out of `2026-09-20-role-module-take-closed` when `take_closed`
shipped ([[2026-09-21-endpoints-take-closed]]). Item 1 of that todo is done; this is
item 2, untouched.

`pfn drop(linear p : a) : () do let _ = p; () end` typechecks: the checker does not look
inside a function to see what its `linear` parameter does, and the diagnostic for a
generic drop says to "mark it `linear` where it is defined", which is taken on trust. So
one such function, generic in its parameter, discards any linear value in the program.

The choreography guide and the `test/two_node/cluster_ap_hosted*` fixtures used to teach
exactly that function; they now call the generated `take_closed` instead, so no shipped
code depends on the hole. What remains is the decision:

- check a `linear` parameter's body for exactly one use, the way a linear local is
  checked, and report the same error inside the definition; or
- document `linear x : a` as an opt-in the caller trusts, and say so where the
  "mark it `linear` where it is defined" hint is emitted.

Whichever is chosen, a reject fixture should pin it.
