# Drop `vendor/notty/` once a fixed `notty` is on opam

`vendor/notty/` carries the ocaml-dune/notty fork because opam's `notty` 0.2.3 does not compile
on OCaml 5.4+ (`out_width`). When a release containing the fix is on opam (watch
ocaml-community/meta#46), delete `vendor/notty/`, the `(vendored_dirs vendor)` stanza in the root
`dune`, and put `(notty (>= <fixed version>))` back in `dune-project` (regenerating `march.opam`;
`uutf` can then go, notty pulls it in).
