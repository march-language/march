# Vendored notty (ocaml-dune fork)

Upstream: https://github.com/ocaml-dune/notty, commit 54b14f0dc25316a5b64206c55598442ec9d43325
(2025-09-16), the community fork of pqwy/notty proposed for adoption in
https://github.com/ocaml-community/meta/issues/46. Sources are unmodified.

Why vendored: opam's `notty` 0.2.3 (pqwy/notty) fails to compile on OCaml 5.4+ ("Some
record fields are undefined: out_width"); the fork carries the fix, but has no opam release.

Only `notty` and `notty.unix` are included; `notty.top`, `notty.lwt`, examples and
benchmarks are omitted. The two `dune` files are ours: `src/dune` drops `notty.top`
(avoids a `cppo` build dependency) and `src-unix/dune` uses `foreign_stubs` instead of
`c_flags`, which dune language >= 2.0 removed.

Delete this directory, and restore `notty` in `dune-project`, once a fixed release is
on opam.
