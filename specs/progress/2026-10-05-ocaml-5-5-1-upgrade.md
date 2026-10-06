# Build against OCaml 5.5.1

**Date:** 2026-10-05

Moved CI, the CI Docker images (`ci/Dockerfile.ubuntu`, `ci/Dockerfile.two-node`,
`scripts/two-node-docker.sh`), the `march-setup` action default and the install docs from
OCaml 5.3.0 to 5.5.1. The declared floor (`ocaml >= 5.3.0`) is unchanged and 5.3.0 still builds.

## What blocked it (all dependencies; no March source change)

- **`notty` 0.2.3** declares `ocaml < 5.4` and fails to compile on 5.4+: OCaml 5.4 added
  `out_width` to `Format.formatter_out_functions`. pqwy/notty master is unfixed; the community
  fork (ocaml-dune/notty, ocaml-community/meta#46) fixes it with a `{ base with ... }` copy
  but has no opam release. Vendored at `vendor/notty/` (commit 54b14f0d, sources unmodified;
  see `vendor/notty/VENDORED.md`). `dune` gained `(vendored_dirs vendor)`, and `march.opam` now
  depends on `uutf` instead of `notty`.
- **`js_of_ocaml < 6.4.0`** cap (added 2026-06-23 for an assertion in `js_variable_coalescing.ml`
  when compiling `march_eval.cma`). 6.3.2 does not compile on 5.5 (`Const_base` is gone from
  compiler-libs). 6.4.1 builds `js/march_browser.bc.js` on 5.5.1 with no assertion, so the cap is
  lifted.

## Verification

Local switch `march55` (`ocaml-base-compiler.5.5.1`): compiler, LSP and JS bundle build clean;
`scripts/run-tests.sh` suites compiler, eval, codegen, stdlib, stdlib_march, test_jit and the five
LSP suites all passed. `test_refinecheck` (z3) was not run. The vendored notty also builds on 5.3.0.

Speed: no gain. Same-box A/B of the resulting `main.exe`, medians of 7 alternating runs: interpreted
`fib(30)` -1%, typecheck of `dataframe.march`/`session_node.march` +1..2%, `--emit-llvm` +2..3%,
clean `dune build bin/main.exe` about +5% (noise at load 7-12). The upgrade is for toolchain
currency, not speed.

## Not verified locally

The GitHub Actions legs (macOS, both Alpine static Linux legs, the Docker two-node image) were
edited but cannot be exercised from a workstation; first CI run is the check.
