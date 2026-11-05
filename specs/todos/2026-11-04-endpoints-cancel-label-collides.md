`[P3]` `@[endpoints]`: a `choose` label named `cancel` (or `drain`) breaks the generated role module

Found 2026-11-04 while writing the protocol `--explain` pages (§F3 mechanism 6). A branch
`cancel -> …` gives the offer callback parameter `on_cancel`, which collides with the cancel
handler parameter of the generated `offer_…_or` function. The result is `duplicate_binder`,
`not_a_function` and `type_mismatch` errors inside generated code, with no message in protocol
terms. Either reject the label in `annotate` (`lib/desugar/desugar_endpoints.ml`) with an
`endpoints_label_invalid` saying why, as it already does for `msg_` labels, or rename the generated
handler parameters so no label can collide.
