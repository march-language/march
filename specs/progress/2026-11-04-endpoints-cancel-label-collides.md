`[P3]` `@[endpoints]`: a `choose` label named `cancel` (or `drain`) breaks the generated role module

Found 2026-11-04 while writing the protocol `--explain` pages (§F3 mechanism 6). A branch
`cancel -> …` gives the offer callback parameter `on_cancel`, which collides with the cancel
handler parameter of the generated `offer_…_or` function. The result is `duplicate_binder`,
`not_a_function` and `type_mismatch` errors inside generated code, with no message in protocol
terms. Either reject the label in `annotate` (`lib/desugar/desugar_endpoints.ml`) with an
`endpoints_label_invalid` saying why, as it already does for `msg_` labels, or rename the generated
handler parameters so no label can collide.

## Fixed 2026-11-06

Generated offer branch callbacks now use `on_branch_<label>` consistently in
parameters and dispatch arms, separate from `on_cancel`, `on_drain`, and
`on_crash`. Public function names, argument positions and types stay unchanged.
No protocol labels are newly reserved. The crash-aware offer uses the same naming.

The endpoints regression typechecks a protocol with `cancel`, `drain`, and
`branch_cancel` branches and callers of both `_or` and `_or_drain`. Before the fix
it reported duplicate on_cancel/on_drain binders; the distinct branch payload
types also exercise callback wiring.

Validation: all 133 endpoints tests pass, including the new regression and
existing crash-aware offer cases. The compiler and forge binaries build, and
`cert_order` passes using the generated endpoint code in three native processes.
The additional quick compiler-suite run was stopped after nine minutes with no
failures reported; it did not complete and is not counted as passing validation.
