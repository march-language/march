# Cross-language benchmark refresh, 2026-09-25 (Linux x86_64 cloud VM)

Re-ran `bench/run_benchmarks.sh` (all seven benchmarks, all six languages, 10
runs each) and committed the output as
`bench/results/2026-09-25-x86_64-xeon-cloud.{txt,jsonl,svg}`. `bench/RESULTS.md`
now leads with this run, keeps the 2026-07-24 M3 run as "Previous run", and
compares March-to-Rust/OCaml ratios against the 2026-08-04 x86 run.

## Runner changes (`bench/run_benchmarks.sh`)

- **`MARCH=` is honoured.** The script resolved `MARCH` (and its header told
  users to override it) but always compiled the March rows with `dune exec`.
  An explicit `MARCH=/path/to/march` now builds them with that compiler, and
  the toolchain banner says the compiler is not this working tree. Unset, the
  behaviour is unchanged.
- **OCaml SIMD rows no longer need `ocamlfind`.** Without it the script links
  OCaml 5's bundled unix library with `ocamlopt -I +unix unix.cmxa`.

## How the run was provisioned

The container had no opam switch, and opam.ocaml.org was unreachable, so the
compiler could not be built from this tree. The March rows use the
`nightly-20260924` release binary (commit `59ecf17`); the seven benchmark
sources are byte-identical between that commit and this one. That nightly's
runtime links a system `libblake3`, which Ubuntu 24.04 does not package, so a
static `libblake3.a` was built from the repo's vendored
`runtime/third_party/blake3` portable sources. OCaml 5.3.0 was built from the
upstream git tag for the OCaml rows; Elixir 1.14 came from apt and NumPy 2.4.6
from PyPI.

## Findings

- binary-trees: March/Rust 4.39x to 2.92x, March/OCaml 20.1x to 13.3x, against
  the 2026-08-04 x86 run.
- simd-map2: bimodal March timing, filed as
  `specs/todos/2026-09-25-simd-map2-bimodal-timing.md`.
- The `nightly-20260924` binary needs a host `libblake3`, which stock Ubuntu
  24.04 lacks. Later commits vendor BLAKE3 into the runtime, which removes that
  dependency for future nightlies.
